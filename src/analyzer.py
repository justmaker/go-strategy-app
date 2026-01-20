"""
Go Strategy Analyzer - Main business logic layer.

Integrates:
- BoardState management
- SQLite caching
- KataGo GTP communication

Provides a simple API for analyzing Go positions.
"""

from typing import List, Optional

from .board import BoardState, create_board
from .cache import AnalysisCache, AnalysisResult, MoveCandidate
from .config import AppConfig, load_config
from .katago_gtp import KataGoGTP


class GoAnalyzer:
    """
    Main analyzer class that integrates all components.
    
    Flow:
    1. Receive analysis request (board size, moves, handicap, komi)
    2. Build BoardState and compute Zobrist hash
    3. Check cache for existing analysis
       - Hit: Return cached result immediately
       - Miss: Run KataGo analysis, cache result, return
    
    Usage:
        # Using context manager (recommended)
        with GoAnalyzer() as analyzer:
            result = analyzer.analyze(
                board_size=19,
                moves=["B Q16", "W D4", "B Q3"],
            )
            for move in result.top_moves:
                print(f"{move.move}: {move.winrate:.1%}")
        
        # Manual lifecycle management
        analyzer = GoAnalyzer()
        analyzer.start()
        result = analyzer.analyze(...)
        analyzer.shutdown()
    """
    
    def __init__(self, config_path: Optional[str] = None, config: Optional[AppConfig] = None):
        """
        Initialize the analyzer.
        
        Args:
            config_path: Path to config.yaml file
            config: Pre-loaded AppConfig (overrides config_path)
        """
        if config is not None:
            self.config = config
        else:
            self.config = load_config(config_path)
        
        self.cache = AnalysisCache(config=self.config)
        self.katago = KataGoGTP(self.config.katago)
        self._started = False
    
    def start(self) -> None:
        """
        Start the analyzer (initializes KataGo).
        
        This is called automatically on first analysis if not called explicitly.
        """
        if not self._started:
            self.katago.start()
            self._started = True
    
    def shutdown(self) -> None:
        """
        Shutdown the analyzer (closes KataGo process).
        
        Safe to call multiple times.
        """
        if self._started:
            self.katago.shutdown()
            self._started = False
    
    def analyze(
        self,
        board_size: int = 19,
        moves: Optional[List[str]] = None,
        handicap: int = 0,
        komi: Optional[float] = None,
        visits: Optional[int] = None,
        force_refresh: bool = False,
    ) -> AnalysisResult:
        """
        Analyze a board position and return top candidate moves.
        
        Args:
            board_size: Size of the board (9, 13, or 19)
            moves: List of moves in GTP format, e.g., ["B Q16", "W D4"]
            handicap: Number of handicap stones (0-9)
            komi: Komi value (default: 7.5, or 0.5 for handicap games)
            visits: Specific visit count (overrides config defaults)
            force_refresh: If True, ignore cache and always run KataGo
            
        Returns:
            AnalysisResult with top candidate moves
        """
        # Validate parameters
        if board_size not in (9, 13, 19):
            raise ValueError(f"Board size must be 9, 13, or 19, got {board_size}")
        
        if handicap < 0 or handicap > 9:
            raise ValueError(f"Handicap must be 0-9, got {handicap}")
        
        # Create board state
        board = create_board(
            size=board_size,
            handicap=handicap,
            komi=komi,
            moves=moves,
        )
        
        # Compute hash for caching
        board_hash = board.compute_hash()
        
        # Determine visits count
        if visits is None:
            # Use default from config if not specified
            current_visits = self.config.get_visits(board_size)
        else:
            current_visits = visits
        
        # Check cache (unless force_refresh)
        if not force_refresh:
            cached = self.cache.get(board_hash, komi=board.komi, required_visits=current_visits)
            if cached is not None:
                return cached
        
        # Cache miss - run KataGo analysis
        self.start()  # Ensure KataGo is running
        
        # Set up position in KataGo
        self.katago.setup_position(board)
        
        top_n = self.config.analysis.top_moves_count
        
        # Run analysis
        top_moves = self.katago.analyze(
            next_player=board.next_player,
            visits=current_visits,
            top_n=top_n,
        )
        
        # Get model name
        model_name = self.katago.get_model_name()
        
        # Build result
        result = AnalysisResult(
            board_hash=board_hash,
            board_size=board_size,
            komi=board.komi,
            moves_sequence=board.get_moves_sequence_string(),
            top_moves=top_moves,
            engine_visits=current_visits,
            model_name=model_name,
            from_cache=False,
        )
        
        # Store in cache
        self.cache.put(
            board_hash=board_hash,
            moves_sequence=board.get_moves_sequence_string(),
            board_size=board_size,
            komi=board.komi,
            top_moves=top_moves,
            engine_visits=current_visits,
            model_name=model_name,
        )
        
        return result
    
    def analyze_board(self, board: BoardState, visits: Optional[int] = None, force_refresh: bool = False) -> AnalysisResult:
        """
        Analyze an existing BoardState object.
        
        Args:
            board: BoardState to analyze
            visits: Specific visit count
            force_refresh: If True, ignore cache
            
        Returns:
            AnalysisResult with top candidate moves
        """
        board_hash = board.compute_hash()
        
        # Determine visits count
        if visits is None:
            current_visits = self.config.get_visits(board.size)
        else:
            current_visits = visits
        
        # Check cache
        if not force_refresh:
            cached = self.cache.get(board_hash, komi=board.komi, required_visits=current_visits)
            if cached is not None:
                return cached
        
        # Cache miss - run analysis
        self.start()
        self.katago.setup_position(board)
        
        top_n = self.config.analysis.top_moves_count
        
        top_moves = self.katago.analyze(
            next_player=board.next_player,
            visits=current_visits,
            top_n=top_n,
        )
        
        model_name = self.katago.get_model_name()
        
        result = AnalysisResult(
            board_hash=board_hash,
            board_size=board.size,
            komi=board.komi,
            moves_sequence=board.get_moves_sequence_string(),
            top_moves=top_moves,
            engine_visits=current_visits,
            model_name=model_name,
            from_cache=False,
        )
        
        self.cache.put(
            board_hash=board_hash,
            moves_sequence=board.get_moves_sequence_string(),
            board_size=board.size,
            komi=board.komi,
            top_moves=top_moves,
            engine_visits=current_visits,
            model_name=model_name,
        )
        
        return result
    
    def get_cache_stats(self) -> dict:
        """Get statistics about the analysis cache."""
        return self.cache.get_stats()
    
    def get_visit_stats(self, board_size: int, komi: float) -> dict:
        """Get visit count distribution for a board size."""
        return self.cache.get_visit_counts(board_size, komi)
    
    def clear_cache(self) -> int:
        """
        Clear all cached analyses.
        
        Returns:
            Number of entries deleted
        """
        return self.cache.clear()
    
    def is_running(self) -> bool:
        """Check if KataGo is running."""
        return self._started and self.katago.is_running()
    
    def __enter__(self) -> 'GoAnalyzer':
        """Context manager entry - starts KataGo."""
        self.start()
        return self
    
    def __exit__(self, *args) -> None:
        """Context manager exit - shuts down KataGo."""
        self.shutdown()
    
    def __repr__(self) -> str:
        status = "running" if self.is_running() else "stopped"
        cache_count = self.cache.count()
        return f"GoAnalyzer(status={status}, cached={cache_count})"


# ============================================================================
# Convenience Functions
# ============================================================================

def quick_analyze(
    board_size: int = 19,
    moves: Optional[List[str]] = None,
    handicap: int = 0,
    komi: Optional[float] = None,
    config_path: Optional[str] = None,
) -> AnalysisResult:
    """
    Quick analysis function for one-off use.
    
    Creates an analyzer, runs analysis, and cleans up.
    For repeated analyses, use GoAnalyzer directly.
    
    Args:
        board_size: Board size (9, 13, or 19)
        moves: List of moves in GTP format
        handicap: Number of handicap stones (0-9)
        komi: Komi value
        config_path: Path to config.yaml
        
    Returns:
        AnalysisResult
    """
    with GoAnalyzer(config_path=config_path) as analyzer:
        return analyzer.analyze(
            board_size=board_size,
            moves=moves,
            handicap=handicap,
            komi=komi,
        )


def format_result(result: AnalysisResult) -> str:
    """
    Format an AnalysisResult as a human-readable string.
    
    Args:
        result: Analysis result to format
        
    Returns:
        Formatted string
    """
    lines = [
        "=" * 50,
        "Go Strategy Analysis",
        "=" * 50,
        f"Board: {result.board_size}x{result.board_size} | Komi: {result.komi}",
        f"Hash: {result.board_hash[:16]}...",
        "",
        f"Top {len(result.top_moves)} Candidates:",
    ]
    
    for i, move in enumerate(result.top_moves, 1):
        winrate_pct = move.winrate * 100
        sign = "+" if move.score_lead >= 0 else ""
        lines.append(
            f"  {i}. {move.move:4s} | "
            f"WinRate: {winrate_pct:5.1f}% | "
            f"ScoreLead: {sign}{move.score_lead:.1f} | "
            f"Visits: {move.visits}"
        )
    
    lines.extend([
        "",
        f"Engine: {result.model_name} | Visits: {result.engine_visits}",
        f"Source: {'Cache' if result.from_cache else 'KataGo (new)'}",
        "=" * 50,
    ])
    
    return "\n".join(lines)
