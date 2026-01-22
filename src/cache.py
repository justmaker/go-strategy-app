"""
SQLite caching layer for Go Strategy Analysis Tool.

Stores analyzed board positions to avoid redundant KataGo calculations.
Includes metadata for future data review and merging.
"""

import json
import sqlite3
from dataclasses import dataclass, asdict, field
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
    # New fields for Phase 3 partial calculation support
    calculation_duration: Optional[float] = None  # Time taken in seconds
    stopped_by_limit: Optional[bool] = None  # True if stopped by limit, False if converged
    limit_setting: Optional[str] = None  # e.g., "5s", "100v"
    ownership: Optional[List[float]] = None  # -1.0 to 1.0 for each intersection
    prisoners: Dict[str, int] = field(default_factory=lambda: {'B': 0, 'W': 0})
    
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
            'calculation_duration': self.calculation_duration,
            'stopped_by_limit': self.stopped_by_limit,
            'limit_setting': self.limit_setting,
            'ownership': self.ownership,
            'prisoners': self.prisoners,
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
            calculation_duration=data.get('calculation_duration'),
            stopped_by_limit=data.get('stopped_by_limit'),
            limit_setting=data.get('limit_setting'),
            ownership=data.get('ownership'),
            prisoners=data.get('prisoners', {'B': 0, 'W': 0}),
        )


# ============================================================================
# Database Schema
# ============================================================================

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS analysis_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    board_hash TEXT NOT NULL,
    moves_sequence TEXT,
    board_size INTEGER NOT NULL,
    komi REAL NOT NULL,
    analysis_result TEXT NOT NULL,
    engine_visits INTEGER NOT NULL,
    model_name TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    calculation_duration REAL,
    stopped_by_limit INTEGER,
    limit_setting TEXT
);
"""

CREATE_INDEX_SQL = """
CREATE INDEX IF NOT EXISTS idx_board_hash ON analysis_cache(board_hash);
"""

CREATE_UNIQUE_INDEX_SQL = """
CREATE UNIQUE INDEX IF NOT EXISTS idx_board_hash_visits_komi ON analysis_cache(board_hash, engine_visits, komi);
"""

CREATE_META_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS opening_book_meta (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    board_size INTEGER NOT NULL,
    komi REAL NOT NULL,
    handicap INTEGER NOT NULL,
    visits INTEGER NOT NULL,
    depth INTEGER NOT NULL,
    completed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT
);
"""

CREATE_META_UNIQUE_INDEX_SQL = """
CREATE UNIQUE INDEX IF NOT EXISTS idx_opening_book_meta ON opening_book_meta(board_size, komi, handicap, visits);
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
        """Initialize database schema and perform migrations."""
        # Check if DB existed before connection (which creates it)
        db_existed = self.db_path.exists() and self.db_path.stat().st_size > 0
        
        with self._get_connection() as conn:
            # Check for migration needs (old schema has UNIQUE constraint on board_hash)
            needs_migration = False
            try:
                # Check if board_hash is unique in the current schema
                cursor = conn.execute("PRAGMA index_list('analysis_cache')")
                for row in cursor:
                    # Look for the auto-created unique index or explicit one on board_hash
                    # In SQLite, a UNIQUE column creates a unique index
                    if row['unique'] and row['origin'] in ('c', 'u'):
                        # Check which columns this index covers
                        idx_name = row['name']
                        cols = conn.execute(f"PRAGMA index_info('{idx_name}')").fetchall()
                        if len(cols) == 1 and cols[0]['name'] == 'board_hash':
                            needs_migration = True
                            break
            except Exception:
                # Table might not exist yet
                pass

            if needs_migration:
                print("Migrating database to support multiple visit counts...")
                try:
                    conn.execute("ALTER TABLE analysis_cache RENAME TO analysis_cache_old")
                    conn.execute(CREATE_TABLE_SQL)
                    conn.execute(CREATE_INDEX_SQL)
                    conn.execute(CREATE_UNIQUE_INDEX_SQL)
                    # Copy data
                    conn.execute("""
                        INSERT INTO analysis_cache 
                        (board_hash, moves_sequence, board_size, komi, analysis_result, engine_visits, model_name, created_at)
                        SELECT board_hash, moves_sequence, board_size, komi, analysis_result, engine_visits, model_name, created_at
                        FROM analysis_cache_old
                    """)
                    conn.execute("DROP TABLE analysis_cache_old")
                    print("Migration successful.")
                except Exception as e:
                    print(f"Migration failed: {e}")
                    # Try to restore? For now just raise
                    raise

            # Standard Init
            conn.execute(CREATE_TABLE_SQL)
            conn.execute(CREATE_INDEX_SQL)
            conn.execute(CREATE_UNIQUE_INDEX_SQL)
            conn.execute(CREATE_META_TABLE_SQL)
            conn.execute(CREATE_META_UNIQUE_INDEX_SQL)
            
            # Seed if new database
            if not db_existed and not needs_migration:
                seed_path = Path(__file__).parent / "assets" / "seed_data.sql"
                if seed_path.exists():
                    try:
                        with open(seed_path, 'r', encoding='utf-8') as f:
                            conn.executescript(f.read())
                            
                        # Post-seed migration check: 
                        # If the seed file had the old schema, we need to migrate it NOW.
                        # (Checking the same condition again)
                        cursor = conn.execute("PRAGMA index_list('analysis_cache')")
                        seed_needs_migration = False
                        for row in cursor:
                            if row['unique']:
                                idx_name = row['name']
                                cols = conn.execute(f"PRAGMA index_info('{idx_name}')").fetchall()
                                if len(cols) == 1 and cols[0]['name'] == 'board_hash':
                                    seed_needs_migration = True
                                    break
                                    
                        if seed_needs_migration:
                            print("Migrating seeded database...")
                            conn.execute("ALTER TABLE analysis_cache RENAME TO analysis_cache_old")
                            conn.execute(CREATE_TABLE_SQL)
                            conn.execute(CREATE_INDEX_SQL)
                            conn.execute(CREATE_UNIQUE_INDEX_SQL)
                            conn.execute("""
                                INSERT INTO analysis_cache 
                                (board_hash, moves_sequence, board_size, komi, analysis_result, engine_visits, model_name, created_at)
                                SELECT board_hash, moves_sequence, board_size, komi, analysis_result, engine_visits, model_name, created_at
                                FROM analysis_cache_old
                            """)
                            conn.execute("DROP TABLE analysis_cache_old")

                    except Exception as e:
                        print(f"Warning: Failed to seed/migrate database: {e}")
            
            # Check for migration to include Komi in unique index
            needs_komi_migration = False
            try:
                # Check if current unique index includes komi
                cursor = conn.execute("PRAGMA index_list('analysis_cache')")
                for row in cursor:
                    if row['unique']:
                        idx_name = row['name']
                        cols = conn.execute(f"PRAGMA index_info('{idx_name}')").fetchall()
                        col_names = [c['name'] for c in cols]
                        if 'board_hash' in col_names and 'engine_visits' in col_names:
                             if 'komi' not in col_names:
                                 needs_komi_migration = True
                                 break
            except Exception:
                pass
            
            if needs_komi_migration:
                print("Migrating database to support Komi in unique index...")
                try:
                    conn.execute("DROP INDEX IF EXISTS idx_board_hash_visits")
                    conn.execute(CREATE_UNIQUE_INDEX_SQL)
                    print("Index migration successful.")
                except Exception as e:
                    print(f"Index migration failed: {e}")

            # Migration for Phase 3: Add partial calculation columns
            try:
                # Check if new columns exist
                cursor = conn.execute("PRAGMA table_info(analysis_cache)")
                existing_cols = {row['name'] for row in cursor}
                
                new_columns = [
                    ("calculation_duration", "REAL"),
                    ("stopped_by_limit", "INTEGER"),
                    ("limit_setting", "TEXT"),
                ]
                
                for col_name, col_type in new_columns:
                    if col_name not in existing_cols:
                        print(f"Adding column {col_name} to analysis_cache...")
                        conn.execute(f"ALTER TABLE analysis_cache ADD COLUMN {col_name} {col_type}")
                        
            except Exception as e:
                print(f"Warning: Failed to add partial calculation columns: {e}")

            conn.commit()
    
    def _get_connection(self) -> sqlite3.Connection:
        """Get a database connection."""
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        return conn
    
    def get(self, board_hash: str, komi: float, required_visits: Optional[int] = None) -> Optional[AnalysisResult]:
        """
        Retrieve cached analysis result.
        
        Args:
            board_hash: Zobrist hash of the board position
            komi: Komi value to match
            required_visits: If specified, match this exact visit count.
                           If None, return the result with the highest visit count.
            
        Returns:
            AnalysisResult if found, None otherwise
        """
        if required_visits is not None:
             query = """
                SELECT board_hash, moves_sequence, board_size, komi,
                       analysis_result, engine_visits, model_name, created_at,
                       calculation_duration, stopped_by_limit, limit_setting
                FROM analysis_cache
                WHERE board_hash = ? AND komi = ? AND engine_visits = ?
            """
             params = (board_hash, komi, required_visits)
        else:
            # Get the one with highest visits
            query = """
                SELECT board_hash, moves_sequence, board_size, komi,
                       analysis_result, engine_visits, model_name, created_at,
                       calculation_duration, stopped_by_limit, limit_setting
                FROM analysis_cache
                WHERE board_hash = ? AND komi = ?
                ORDER BY engine_visits DESC
                LIMIT 1
            """
            params = (board_hash, komi)
        
        with self._get_connection() as conn:
            cursor = conn.execute(query, params)
            row = cursor.fetchone()
        
        if row is None:
            return None
        
        # Parse the stored JSON
        try:
            result_data = json.loads(row['analysis_result'])
            top_moves = [MoveCandidate.from_dict(m) for m in result_data]
        except (json.JSONDecodeError, KeyError) as e:
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
            calculation_duration=row['calculation_duration'],
            stopped_by_limit=bool(row['stopped_by_limit']) if row['stopped_by_limit'] is not None else None,
            limit_setting=row['limit_setting'],
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
        calculation_duration: Optional[float] = None,
        stopped_by_limit: Optional[bool] = None,
        limit_setting: Optional[str] = None,
    ) -> None:
        """
        Store analysis result in cache with intelligent merge logic.
        
        Merge Rules (in priority order):
        1. Completeness: Complete (stopped_by_limit=False) always overwrites Partial (True)
        2. Depth/Effort: If same completeness, prefer higher visits or longer duration
        3. Recency: If similar effort, prefer newer data
        
        Args:
            board_hash: Zobrist hash of the board position
            moves_sequence: String representation of moves (for reference)
            board_size: Size of the board (9, 13, or 19)
            komi: Komi value
            top_moves: List of candidate moves with statistics
            engine_visits: Number of visits used for analysis
            model_name: Name of the neural network model used
            calculation_duration: Time taken for this calculation (seconds)
            stopped_by_limit: True if stopped by limit, False if converged naturally
            limit_setting: Description of limit used, e.g., "5s", "100v"
        """
        # Serialize top_moves to JSON
        result_json = json.dumps([m.to_dict() for m in top_moves])
        
        with self._get_connection() as conn:
            # Check for existing entry with same (board_hash, engine_visits, komi)
            existing = conn.execute("""
                SELECT calculation_duration, stopped_by_limit, limit_setting, created_at
                FROM analysis_cache
                WHERE board_hash = ? AND engine_visits = ? AND komi = ?
            """, (board_hash, engine_visits, komi)).fetchone()
            
            should_update = True
            
            if existing:
                # Apply intelligent merge logic
                existing_stopped = existing['stopped_by_limit']
                existing_duration = existing['calculation_duration']
                
                # Convert SQLite INTEGER to bool (None stays None)
                existing_stopped_bool = bool(existing_stopped) if existing_stopped is not None else None
                
                # Rule 1: Completeness - Complete always beats Partial
                if existing_stopped_bool is False and stopped_by_limit is True:
                    # Existing is complete, new is partial - keep existing
                    should_update = False
                elif existing_stopped_bool is True and stopped_by_limit is False:
                    # Existing is partial, new is complete - update
                    should_update = True
                elif existing_stopped_bool == stopped_by_limit:
                    # Same completeness - Rule 2: Prefer longer duration (more effort)
                    if existing_duration is not None and calculation_duration is not None:
                        if existing_duration > calculation_duration * 1.1:  # 10% threshold
                            should_update = False
                    # Rule 3: If similar effort or unknown, prefer newer (should_update stays True)
            
            if should_update:
                query = """
                    INSERT OR REPLACE INTO analysis_cache 
                    (board_hash, moves_sequence, board_size, komi, 
                     analysis_result, engine_visits, model_name, created_at,
                     calculation_duration, stopped_by_limit, limit_setting)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
                conn.execute(query, (
                    board_hash,
                    moves_sequence,
                    board_size,
                    komi,
                    result_json,
                    engine_visits,
                    model_name,
                    datetime.now().isoformat(),
                    calculation_duration,
                    1 if stopped_by_limit else (0 if stopped_by_limit is False else None),
                    limit_setting,
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
    
    def get_visit_counts(self, board_size: int, komi: float) -> Dict[int, int]:
        """
        Get count of entries for each visit count, for a specific board size and komi.
        
        Args:
            board_size: The board size to filter by
            komi: The komi value to filter by
            
        Returns:
            Dictionary mapping counts {visit_count: number_of_entries}
        """
        query = """
            SELECT engine_visits, COUNT(*) as cnt
            FROM analysis_cache
            WHERE board_size = ? AND komi = ?
            GROUP BY engine_visits
            ORDER BY cnt DESC
        """
        
        counts = {}
        with self._get_connection() as conn:
            cursor = conn.execute(query, (board_size, komi))
            for row in cursor:
                counts[row['engine_visits']] = row['cnt']
                
        return counts

    def has_opening_book(self, board_size: int, komi: float, handicap: int, min_visits: int = 300) -> bool:
        """
        Check if a complete opening book exists for the given configuration.
        
        Args:
            board_size: Board size
            komi: Komi
            handicap: Handicap stones count
            min_visits: Minimum visits required
            
        Returns:
            True if an opening book record exists
        """
        query = """
            SELECT 1 FROM opening_book_meta 
            WHERE board_size = ? AND komi = ? AND handicap = ? AND visits >= ?
            LIMIT 1
        """
        try:
            with self._get_connection() as conn:
                cursor = conn.execute(query, (board_size, komi, handicap, min_visits))
                return cursor.fetchone() is not None
        except Exception:
            # If table doesn't exist yet or other error
            return False

    def get_opening_book_visits(self, board_size: int, komi: float, handicap: int) -> int:
        """
        Get the visits count of the highest quality opening book if it exists, or 0.
        
        Args:
            board_size: Board size
            komi: Komi
            handicap: Handicap stones
            
        Returns:
            Visits count (e.g. 300) or 0 if not found
        """
        query = """
            SELECT MAX(visits) as max_visits FROM opening_book_meta 
            WHERE board_size = ? AND komi = ? AND handicap = ?
        """
        try:
            with self._get_connection() as conn:
                cursor = conn.execute(query, (board_size, komi, handicap))
                row = cursor.fetchone()
                return row['max_visits'] if row and row['max_visits'] else 0
        except Exception:
            return 0


    def merge_database(self, source_db_path: str) -> Dict[str, int]:
        """
        Merge another SQLite database into this one.
        Logic:
          - If (hash, visits) matches:
             - Parse stats from both.
             - Average winrate and score_lead for matching moves.
             - Update local entry.
          - If not matches:
             - Insert new entry.
             
        Args:
            source_db_path: Path to the source database file.
            
        Returns:
            Dict with stats: {'inserted': int, 'merged': int, 'errors': int}
        """
        stats = {'inserted': 0, 'merged': 0, 'errors': 0}
        
        try:
            # Connect to source database
            with sqlite3.connect(source_db_path) as source_conn:
                source_conn.row_factory = sqlite3.Row
                
                # Iterate over all entries in source
                query = "SELECT * FROM analysis_cache"
                cursor = source_conn.execute(query)
                
                for row in cursor:
                    try:
                        # Check if exists in local DB
                        existing = self.get(row['board_hash'], komi=row['komi'], required_visits=row['engine_visits'])
                        
                        source_moves = json.loads(row['analysis_result'])
                        top_moves = [MoveCandidate.from_dict(m) for m in source_moves]
                        
                        if existing:
                            # Merge logic: Average stats for matching moves
                            merged_moves = []
                            existing_map = {m.move: m for m in existing.top_moves}
                            
                            for new_move in top_moves:
                                if new_move.move in existing_map:
                                    # Average
                                    old_move = existing_map[new_move.move]
                                    avg_mv = MoveCandidate(
                                        move=new_move.move,
                                        winrate=(old_move.winrate + new_move.winrate) / 2,
                                        score_lead=(old_move.score_lead + new_move.score_lead) / 2,
                                        visits=new_move.visits # Visits are same for the entry, so keep same
                                    )
                                    merged_moves.append(avg_mv)
                                else:
                                    # Keep new unique moves from source? 
                                    # Or strict average means intersection?
                                    # Usually we want union.
                                    merged_moves.append(new_move)
                            
                            # Add back moves from existing that weren't in source
                            source_map_keys = {m.move for m in top_moves}
                            for old_move in existing.top_moves:
                                if old_move.move not in source_map_keys:
                                    merged_moves.append(old_move)
                                    
                            # Update local
                            self.put(
                                board_hash=row['board_hash'],
                                moves_sequence=row['moves_sequence'],
                                board_size=row['board_size'],
                                komi=row['komi'],
                                top_moves=merged_moves,
                                engine_visits=row['engine_visits'],
                                model_name=f"{row['model_name']}+merged"
                            )
                            stats['merged'] += 1
                        else:
                            # Insert new
                            self.put(
                                board_hash=row['board_hash'],
                                moves_sequence=row['moves_sequence'],
                                board_size=row['board_size'],
                                komi=row['komi'],
                                top_moves=top_moves,
                                engine_visits=row['engine_visits'],
                                model_name=row['model_name']
                            )
                            stats['inserted'] += 1
                            
                    except Exception as e:
                        print(f"Error merging row: {e}")
                        stats['errors'] += 1
                        
        except Exception as e:
            print(f"Failed to open source DB: {e}")
            stats['errors'] += 1
            
        return stats

    def __repr__(self) -> str:
        return f"AnalysisCache(db_path={self.db_path}, entries={self.count()})"
