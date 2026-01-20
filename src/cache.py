"""
SQLite caching layer for Go Strategy Analysis Tool.

Stores analyzed board positions to avoid redundant KataGo calculations.
Includes metadata for future data review and merging.
"""

import json
import sqlite3
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from .config import AppConfig, get_db_path


# ============================================================================
# Data Classes
# ============================================================================

@dataclass
class MoveCandidate:
    """A candidate move with analysis statistics."""
    move: str           # GTP coordinate, e.g., "Q16"
    winrate: float      # Win rate as decimal, e.g., 0.523
    score_lead: float   # Score lead (positive = ahead)
    visits: int         # Number of visits for this move
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return asdict(self)
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'MoveCandidate':
        """Create from dictionary."""
        return cls(
            move=data['move'],
            winrate=data['winrate'],
            score_lead=data['score_lead'],
            visits=data['visits'],
        )
    
    def __repr__(self) -> str:
        return (
            f"MoveCandidate({self.move}, "
            f"wr={self.winrate:.1%}, "
            f"lead={self.score_lead:+.1f}, "
            f"visits={self.visits})"
        )


@dataclass
class AnalysisResult:
    """Complete analysis result for a board position."""
    board_hash: str
    board_size: int
    komi: float
    moves_sequence: str
    top_moves: List[MoveCandidate]
    engine_visits: int
    model_name: str
    from_cache: bool = False
    timestamp: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            'board_hash': self.board_hash,
            'board_size': self.board_size,
            'komi': self.komi,
            'moves_sequence': self.moves_sequence,
            'top_moves': [m.to_dict() for m in self.top_moves],
            'engine_visits': self.engine_visits,
            'model_name': self.model_name,
            'from_cache': self.from_cache,
            'timestamp': self.timestamp,
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'AnalysisResult':
        """Create from dictionary."""
        return cls(
            board_hash=data['board_hash'],
            board_size=data['board_size'],
            komi=data['komi'],
            moves_sequence=data['moves_sequence'],
            top_moves=[MoveCandidate.from_dict(m) for m in data['top_moves']],
            engine_visits=data['engine_visits'],
            model_name=data['model_name'],
            from_cache=data.get('from_cache', False),
            timestamp=data.get('timestamp'),
        )


# ============================================================================
# Database Schema
# ============================================================================

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS analysis_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    board_hash TEXT UNIQUE NOT NULL,
    moves_sequence TEXT,
    board_size INTEGER NOT NULL,
    komi REAL NOT NULL,
    analysis_result TEXT NOT NULL,
    engine_visits INTEGER NOT NULL,
    model_name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"""

CREATE_INDEX_SQL = """
CREATE INDEX IF NOT EXISTS idx_board_hash ON analysis_cache(board_hash);
"""


# ============================================================================
# Cache Class
# ============================================================================

class AnalysisCache:
    """
    SQLite-based cache for board position analysis results.
    
    Usage:
        cache = AnalysisCache(config)
        
        # Check cache
        result = cache.get(board_hash)
        if result:
            print("Cache hit!")
        else:
            # Run analysis...
            cache.put(board_hash, moves_seq, result, visits, model)
    """
    
    def __init__(self, config: Optional[AppConfig] = None, db_path: Optional[str] = None):
        """
        Initialize the cache.
        
        Args:
            config: Application configuration (used to get db path)
            db_path: Direct path to database file (overrides config)
        """
        if db_path:
            self.db_path = Path(db_path)
        elif config:
            self.db_path = get_db_path(config)
        else:
            raise ValueError("Either config or db_path must be provided")
        
        # Ensure parent directory exists
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        
        # Initialize database
        self._init_db()
    
    def _init_db(self) -> None:
        """Initialize database schema."""
        with self._get_connection() as conn:
            conn.execute(CREATE_TABLE_SQL)
            conn.execute(CREATE_INDEX_SQL)
            conn.commit()
    
    def _get_connection(self) -> sqlite3.Connection:
        """Get a database connection."""
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        return conn
    
    def get(self, board_hash: str) -> Optional[AnalysisResult]:
        """
        Retrieve cached analysis result by board hash.
        
        Args:
            board_hash: Zobrist hash of the board position
            
        Returns:
            AnalysisResult if found, None otherwise
        """
        query = """
            SELECT board_hash, moves_sequence, board_size, komi,
                   analysis_result, engine_visits, model_name, created_at
            FROM analysis_cache
            WHERE board_hash = ?
        """
        
        with self._get_connection() as conn:
            cursor = conn.execute(query, (board_hash,))
            row = cursor.fetchone()
        
        if row is None:
            return None
        
        # Parse the stored JSON
        try:
            result_data = json.loads(row['analysis_result'])
            top_moves = [MoveCandidate.from_dict(m) for m in result_data]
        except (json.JSONDecodeError, KeyError) as e:
            # Invalid data in cache, treat as miss
            return None
        
        return AnalysisResult(
            board_hash=row['board_hash'],
            board_size=row['board_size'],
            komi=row['komi'],
            moves_sequence=row['moves_sequence'] or "",
            top_moves=top_moves,
            engine_visits=row['engine_visits'],
            model_name=row['model_name'],
            from_cache=True,
            timestamp=row['created_at'],
        )
    
    def put(
        self,
        board_hash: str,
        moves_sequence: str,
        board_size: int,
        komi: float,
        top_moves: List[MoveCandidate],
        engine_visits: int,
        model_name: str,
    ) -> None:
        """
        Store analysis result in cache.
        
        Args:
            board_hash: Zobrist hash of the board position
            moves_sequence: String representation of moves (for reference)
            board_size: Size of the board (9, 13, or 19)
            komi: Komi value
            top_moves: List of candidate moves with statistics
            engine_visits: Number of visits used for analysis
            model_name: Name of the neural network model used
        """
        # Serialize top_moves to JSON
        result_json = json.dumps([m.to_dict() for m in top_moves])
        
        query = """
            INSERT OR REPLACE INTO analysis_cache 
            (board_hash, moves_sequence, board_size, komi, 
             analysis_result, engine_visits, model_name, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        with self._get_connection() as conn:
            conn.execute(query, (
                board_hash,
                moves_sequence,
                board_size,
                komi,
                result_json,
                engine_visits,
                model_name,
                datetime.now().isoformat(),
            ))
            conn.commit()
    
    def delete(self, board_hash: str) -> bool:
        """
        Delete a cached entry.
        
        Args:
            board_hash: Zobrist hash of the position to delete
            
        Returns:
            True if entry was deleted, False if not found
        """
        query = "DELETE FROM analysis_cache WHERE board_hash = ?"
        
        with self._get_connection() as conn:
            cursor = conn.execute(query, (board_hash,))
            conn.commit()
            return cursor.rowcount > 0
    
    def count(self) -> int:
        """Get the total number of cached entries."""
        query = "SELECT COUNT(*) FROM analysis_cache"
        
        with self._get_connection() as conn:
            cursor = conn.execute(query)
            return cursor.fetchone()[0]
    
    def clear(self) -> int:
        """
        Clear all cached entries.
        
        Returns:
            Number of entries deleted
        """
        query = "DELETE FROM analysis_cache"
        
        with self._get_connection() as conn:
            cursor = conn.execute(query)
            conn.commit()
            return cursor.rowcount
    
    def get_stats(self) -> Dict[str, Any]:
        """
        Get cache statistics.
        
        Returns:
            Dictionary with cache statistics
        """
        with self._get_connection() as conn:
            # Total count
            count = conn.execute("SELECT COUNT(*) FROM analysis_cache").fetchone()[0]
            
            # Count by board size
            size_query = """
                SELECT board_size, COUNT(*) as cnt 
                FROM analysis_cache 
                GROUP BY board_size
            """
            size_counts = {
                row['board_size']: row['cnt'] 
                for row in conn.execute(size_query)
            }
            
            # Count by model
            model_query = """
                SELECT model_name, COUNT(*) as cnt 
                FROM analysis_cache 
                GROUP BY model_name
            """
            model_counts = {
                row['model_name']: row['cnt'] 
                for row in conn.execute(model_query)
            }
            
            # Database file size
            db_size = self.db_path.stat().st_size if self.db_path.exists() else 0
        
        return {
            'total_entries': count,
            'by_board_size': size_counts,
            'by_model': model_counts,
            'db_size_bytes': db_size,
            'db_path': str(self.db_path),
        }
    
    def __repr__(self) -> str:
        return f"AnalysisCache(db_path={self.db_path}, entries={self.count()})"
