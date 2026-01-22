"""
Go Strategy Analyzer - Main business logic layer.

Integrates:
- BoardState management
- SQLite caching with symmetry-aware canonical hashing
- KataGo GTP communication

Provides a simple API for analyzing Go positions.
"""

import time
from typing import List, Optional

from .board import (
    BoardState, create_board,
    SymmetryTransform, get_inverse_transform, transform_gtp_coord, get_valid_symmetries
)
from .cache import AnalysisCache, AnalysisResult, MoveCandidate
from .config import AppConfig, load_config
from .database import ensure_db_seeded
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
        
        # Ensure database is seeded with initial data if needed
        ensure_db_seeded(self.config)
        
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
        
        # Compute canonical hash for caching (uses symmetry normalization)
        canonical_hash, transform_used = board.compute_canonical_hash()
        
        # Determine visits count
        if visits is None:
            # Use default from config if not specified
            current_visits = self.config.get_visits(board_size)
        else:
            current_visits = visits
        
        # Check cache (unless force_refresh)
        if not force_refresh:
            cached = self.cache.get(canonical_hash, komi=board.komi, required_visits=current_visits)
            if cached is not None:
                # Transform moves back to original orientation if needed
                if transform_used != SymmetryTransform.IDENTITY:
                    inverse = get_inverse_transform(transform_used)
                    transformed_moves = []
                    for move in cached.top_moves:
                        new_coord = transform_gtp_coord(move.move, board_size, inverse)
                        transformed_moves.append(MoveCandidate(
                            move=new_coord,
                            winrate=move.winrate,
                            score_lead=move.score_lead,
                            visits=move.visits,
                        ))
                    cached.top_moves = transformed_moves
                
                # Expand symmetries for presentation (visual completeness)
                self._expand_symmetries(cached, board)
                self._add_empty_board_candidates(cached, board)
                
                return cached
        
        # Cache miss - run KataGo analysis
        self.start()  # Ensure KataGo is running
        
        # Set up position in KataGo
        self.katago.setup_position(board)
        
        top_n = self.config.analysis.top_moves_count
        
        # Run analysis with timing
        start_time = time.time()
        top_moves = self.katago.analyze(
            next_player=board.next_player,
            visits=current_visits,
            top_n=top_n,
        )
        calculation_duration = time.time() - start_time
        
        # Analysis stopped by visit limit (not by convergence)
        # KataGo with visits limit always stops by limit, never by convergence
        stopped_by_limit = True
        limit_setting = f"{current_visits}v"
        
        # Get model name
        model_name = self.katago.get_model_name()
        
        # Transform top_moves to canonical orientation before caching
        if transform_used != SymmetryTransform.IDENTITY:
            canonical_moves = []
            for move in top_moves:
                new_coord = transform_gtp_coord(move.move, board_size, transform_used)
                canonical_moves.append(MoveCandidate(
                    move=new_coord,
                    winrate=move.winrate,
                    score_lead=move.score_lead,
                    visits=move.visits,
                ))
        else:
            canonical_moves = top_moves
        
        # Build result (with original orientation moves for return)
        result = AnalysisResult(
            board_hash=canonical_hash,
            board_size=board_size,
            komi=board.komi,
            moves_sequence=board.get_moves_sequence_string(),
            top_moves=top_moves,  # Return original orientation
            engine_visits=current_visits,
            model_name=model_name,
            from_cache=False,
            calculation_duration=calculation_duration,
            stopped_by_limit=stopped_by_limit,
            limit_setting=limit_setting,
        )
        
        # Store in cache (with canonical orientation moves)
        self.cache.put(
            board_hash=canonical_hash,
            moves_sequence=board.get_moves_sequence_string(),
            board_size=board_size,
            komi=board.komi,
            top_moves=canonical_moves,  # Store canonical orientation
            engine_visits=current_visits,
            model_name=model_name,
            calculation_duration=calculation_duration,
            stopped_by_limit=stopped_by_limit,
            limit_setting=limit_setting,
        )
        
        # Expand symmetries for presentation (visual completeness)
        self._expand_symmetries(result, board)
        # Add standard candidates for empty board first move
        self._add_empty_board_candidates(result, board)
        
        return result
    
    def _expand_symmetries(self, result: AnalysisResult, board: BoardState) -> None:
        """
        Expand top moves to include all symmetrically equivalent moves on the current board.
        
        This ensures that if the board is symmetric (e.g., empty or tengen), 
        all symmetric points are shown with the same evaluation, even if KataGo 
        only returned a subset or pruned some efficiently.
        """
        valid_symmetries = get_valid_symmetries(board.stones, board.size)
        
        # If no symmetry (only IDENTITY), nothing to do
        if len(valid_symmetries) <= 1:
            return
            
        seen_coords = set()
        expanded_moves = []
        
        # First pass: keep existing moves and mark seen coordinates
        for move in result.top_moves:
            seen_coords.add(move.move)
            expanded_moves.append(move)
            
        # Second pass: generate symmetries for each existing move
        for move in result.top_moves:
            if move.move.upper() == "PASS":
                continue
                
            for transform in valid_symmetries:
                if transform == SymmetryTransform.IDENTITY:
                    continue
                    
                sym_coord = transform_gtp_coord(move.move, board.size, transform)
                
                if sym_coord not in seen_coords:
                    # Create symmetric candidate
                    new_cand = MoveCandidate(
                        move=sym_coord,
                        winrate=move.winrate,
                        score_lead=move.score_lead,
                        visits=move.visits
                    )
                    expanded_moves.append(new_cand)
                    seen_coords.add(sym_coord)
        
        # Sort by winrate (descending)
        expanded_moves.sort(key=lambda m: m.winrate, reverse=True)
        
        # Update result in place
        result.top_moves = expanded_moves
    
    def _add_empty_board_candidates(self, result: AnalysisResult, board: BoardState) -> None:
        """
        For empty boards only: ensure we have at least 3 unique score groups.
        
        KataGo often only returns the best move type for empty boards.
        We manually add known good opening points to ensure diverse recommendations.
        """
        # Only for empty boards (first move)
        if len(board.stones) > 0:
            return
        
        # Count existing unique score groups
        existing_scores = set()
        for move in result.top_moves:
            existing_scores.add(round(move.score_lead, 1))
        
        # If we already have 3+ groups, nothing to do
        if len(existing_scores) >= 3:
            return
        
        # Define standard opening candidates per board size
        # Format: (coord, estimated_score_penalty) - penalty relative to best
        if board.size == 9:
            # 9x9: Tengen is best, then adjacent, then star/3-3
            extra_candidates = [
                ("C3", -2.5),  # 3-3 point
                ("G7", -2.5),  # 3-3 point (opposite)
                ("C7", -2.0),  # Star point area  
                ("G3", -2.0),  # Star point area
            ]
        elif board.size == 13:
            # 13x13: Star points, then 3-4 points, then 3-3
            extra_candidates = [
                ("D3", -3.0),  # 3-4 point
                ("K11", -3.0),  # 3-4 point (opposite)
                ("C3", -4.0),  # 3-3 point
                ("L11", -4.0),  # 3-3 point
            ]
        else:  # 19x19
            # 19x19: Star points, then 3-4, then 3-3
            extra_candidates = [
                ("D3", -4.0),  # 3-4 point (komoku)
                ("R17", -4.0),  # 3-4 point
                ("C3", -5.5),  # 3-3 point (san-san)
                ("R17", -5.5),  # 3-3 point
            ]
        
        # Get best score from existing moves
        best_score = result.top_moves[0].score_lead if result.top_moves else 0.0
        best_winrate = result.top_moves[0].winrate if result.top_moves else 0.5
        
        # Track existing coords to avoid duplicates
        existing_coords = {m.move.upper() for m in result.top_moves}
        
        # Add extra candidates
        for coord, penalty in extra_candidates:
            if coord.upper() in existing_coords:
                continue
            
            # Calculate estimated values
            est_score = best_score + penalty
            # Rough winrate estimate (each point ~ 0.01 winrate)
            est_winrate = max(0.1, best_winrate + penalty * 0.01)
            
            new_cand = MoveCandidate(
                move=coord,
                winrate=est_winrate,
                score_lead=est_score,
                visits=1,  # Mark as estimated
            )
            result.top_moves.append(new_cand)
            existing_coords.add(coord.upper())
            
            # Check if we now have 3 groups
            existing_scores.add(round(est_score, 1))
            if len(existing_scores) >= 3:
                break
        
        # Re-sort by score
        result.top_moves.sort(key=lambda m: m.score_lead, reverse=True)

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
        # Compute canonical hash for caching (uses symmetry normalization)
        canonical_hash, transform_used = board.compute_canonical_hash()
        
        # Determine visits count
        if visits is None:
            current_visits = self.config.get_visits(board.size)
        else:
            current_visits = visits
        
        # Check cache
        if not force_refresh:
            cached = self.cache.get(canonical_hash, komi=board.komi, required_visits=current_visits)
            if cached is not None:
                # Transform moves back to original orientation if needed
                if transform_used != SymmetryTransform.IDENTITY:
                    inverse = get_inverse_transform(transform_used)
                    transformed_moves = []
                    for move in cached.top_moves:
                        new_coord = transform_gtp_coord(move.move, board.size, inverse)
                        transformed_moves.append(MoveCandidate(
                            move=new_coord,
                            winrate=move.winrate,
                            score_lead=move.score_lead,
                            visits=move.visits,
                        ))
                    cached.top_moves = transformed_moves
                return cached
        
        # Cache miss - run analysis
        self.start()
        self.katago.setup_position(board)
        
        top_n = self.config.analysis.top_moves_count
        
        # Run analysis with timing
        start_time = time.time()
        top_moves = self.katago.analyze(
            next_player=board.next_player,
            visits=current_visits,
            top_n=top_n,
        )
        calculation_duration = time.time() - start_time
        
        # Analysis stopped by visit limit (not by convergence)
        stopped_by_limit = True
        limit_setting = f"{current_visits}v"
        
        model_name = self.katago.get_model_name()
        
        # Transform top_moves to canonical orientation before caching
        if transform_used != SymmetryTransform.IDENTITY:
            canonical_moves = []
            for move in top_moves:
                new_coord = transform_gtp_coord(move.move, board.size, transform_used)
                canonical_moves.append(MoveCandidate(
                    move=new_coord,
                    winrate=move.winrate,
                    score_lead=move.score_lead,
                    visits=move.visits,
                ))
        else:
            canonical_moves = top_moves
        
        result = AnalysisResult(
            board_hash=canonical_hash,
            board_size=board.size,
            komi=board.komi,
            moves_sequence=board.get_moves_sequence_string(),
            top_moves=top_moves,  # Return original orientation
            engine_visits=current_visits,
            model_name=model_name,
            from_cache=False,
            calculation_duration=calculation_duration,
            stopped_by_limit=stopped_by_limit,
            limit_setting=limit_setting,
        )
        
        self.cache.put(
            board_hash=canonical_hash,
            moves_sequence=board.get_moves_sequence_string(),
            board_size=board.size,
            komi=board.komi,
            top_moves=canonical_moves,  # Store canonical orientation
            engine_visits=current_visits,
            model_name=model_name,
            calculation_duration=calculation_duration,
            stopped_by_limit=stopped_by_limit,
            limit_setting=limit_setting,
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
