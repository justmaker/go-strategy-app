#!/usr/bin/env python3
"""
Fill depth gaps in the opening book by directly analyzing child positions
of existing entries, without BFS traversal from root.

This is much faster than build_opening_book_parallel.py for filling gaps
because it skips the expensive BFS traversal of all existing data.

Usage:
    python -m src.scripts.fill_depth_gaps --board-size 13 --parent-depth 12 --branching 3
"""

import argparse
import collections
import json
import logging
import sqlite3
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

import os
sys.path.insert(0, os.getcwd())

from src.board import create_board
from src.cache import AnalysisCache, MoveCandidate
from src.config import load_config
from src.scripts.build_opening_book_parallel import KataGoAnalysisEngine, parse_response

# Setup logging
log_dir = Path("logs")
log_dir.mkdir(exist_ok=True)
log_file = log_dir / f"fill_depth_gaps_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)


def get_db_path() -> Path:
    return Path(__file__).parent.parent.parent / "data" / "analysis.db"


def find_missing_children(
    db_path: Path,
    board_size: int,
    parent_depth: int,
    branching: int,
    wr_threshold: float = 0.10,
) -> List[Tuple[List[str], str]]:
    """
    Find child positions at parent_depth+1 that are missing from the cache.

    Returns list of (moves_list, moves_sequence_str) for missing positions.
    """
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row

    # Get all positions at parent_depth
    query = """
        SELECT moves_sequence, analysis_result, engine_visits
        FROM analysis_cache
        WHERE board_size = ? AND engine_visits >= 250
    """
    cursor = conn.execute(query, (board_size,))

    # Filter by depth in Python (since depth is derived from moves_sequence)
    parent_positions = []
    for row in cursor:
        seq = row['moves_sequence'] or ''
        depth = seq.count(';') + 1 if seq else 0
        if depth == parent_depth:
            parent_positions.append(row)

    logger.info(f"Found {len(parent_positions)} positions at depth {parent_depth}")

    # Build set of existing child hashes for fast lookup
    logger.info("Building existing hash set...")
    all_hashes: Set[str] = set()
    cursor2 = conn.execute(
        "SELECT board_hash FROM analysis_cache WHERE board_size = ?",
        (board_size,)
    )
    for row in cursor2:
        all_hashes.add(row['board_hash'])
    logger.info(f"Existing hashes: {len(all_hashes)}")

    conn.close()

    # Find missing children
    missing = []
    checked = 0
    skipped_existing = 0
    skipped_error = 0

    for parent in parent_positions:
        seq = parent['moves_sequence'] or ''
        try:
            top_moves = json.loads(parent['analysis_result'])
        except json.JSONDecodeError:
            continue

        # Parse parent moves
        if seq:
            raw_parts = seq.split(';')
            parent_moves = []
            for p in raw_parts:
                if not p:
                    continue
                if '[' in p and ']' in p:
                    parent_moves.append(p.replace('[', ' ').replace(']', ''))
                else:
                    parent_moves.append(p)
        else:
            parent_moves = []

        # Determine next player
        num_b = seq.count('B[')
        num_w = seq.count('W[')
        next_player = 'B' if num_b == num_w else 'W'

        # Get best winrate for threshold
        best_wr = top_moves[0]['winrate'] if top_moves else 0.5

        selected = 0
        for mc in top_moves[:20]:
            if mc['winrate'] < (best_wr - wr_threshold):
                break
            if mc['move'].upper() == 'PASS':
                continue

            new_move = f"{next_player} {mc['move']}"
            child_moves = parent_moves + [new_move]

            try:
                child_board = create_board(size=board_size, moves=child_moves)
                child_hash, _ = child_board.compute_canonical_hash()
                checked += 1

                if child_hash in all_hashes:
                    skipped_existing += 1
                    selected += 1
                    if selected >= branching:
                        break
                    continue

                missing.append((child_moves, child_hash))
                all_hashes.add(child_hash)  # Avoid duplicates
                selected += 1
                if selected >= branching:
                    break
            except Exception:
                skipped_error += 1
                continue

    logger.info(f"Checked: {checked}, Existing: {skipped_existing}, "
                f"Missing: {len(missing)}, Errors: {skipped_error}")
    return missing


def analyze_positions(
    missing: List[Tuple[List[str], str]],
    board_size: int,
    visits: int,
    batch_size: int,
    config_path: str,
    model_path: str,
    katago_path: str,
) -> Tuple[int, int]:
    """Analyze missing positions with KataGo. Returns (success, errors)."""
    config = load_config()
    cache = AnalysisCache(config=config)

    engine = KataGoAnalysisEngine(
        config_path=config_path,
        model_path=model_path,
        katago_path=katago_path,
    )
    engine.start()

    pending: Dict[str, Tuple[List[str], str]] = {}
    queue = collections.deque(missing)
    query_counter = 0
    success = 0
    errors = 0
    start_time = time.time()

    try:
        while queue or pending:
            # Fill batch
            while len(pending) < batch_size and queue:
                moves, child_hash = queue.popleft()
                query_id = f"q{query_counter}"
                query_counter += 1
                pending[query_id] = (moves, child_hash)
                engine.send_query(query_id, board_size, moves, visits)

            # Process responses
            if pending:
                response = engine.get_response(timeout=5.0)
                if response:
                    if "error" in response:
                        logger.error(f"KataGo error: {response.get('error')}")
                        qid = response.get("id", "")
                        if qid in pending:
                            del pending[qid]
                            errors += 1
                        continue

                    query_id, candidates, ownership = parse_response(response)

                    if query_id not in pending:
                        continue

                    moves, child_hash = pending.pop(query_id)
                    success += 1

                    if candidates:
                        moves_str = ";".join(
                            f"{m.split()[0]}[{m.split()[1]}]" for m in moves
                        ) if moves else ""
                        total_visits = sum(c.visits for c in candidates)

                        cache.put(
                            board_hash=child_hash,
                            moves_sequence=moves_str,
                            board_size=board_size,
                            komi=7.5,
                            top_moves=candidates[:20],
                            engine_visits=total_visits,
                            model_name="kata1-b18c384nbt",
                            ownership=ownership,
                        )

                    if success % 100 == 0:
                        elapsed = time.time() - start_time
                        rate = success / elapsed if elapsed > 0 else 0
                        remaining = len(queue) + len(pending)
                        eta_s = remaining / rate if rate > 0 else 0
                        eta_h = eta_s / 3600
                        logger.info(
                            f"Analyzed: {success}/{len(missing)} | "
                            f"Remaining: {remaining} | "
                            f"Rate: {rate:.1f}/s | "
                            f"ETA: {eta_h:.1f}h"
                        )

    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    finally:
        engine.shutdown()

    elapsed = time.time() - start_time
    logger.info("=" * 60)
    logger.info(f"Analyzed: {success} | Errors: {errors} | Time: {elapsed/60:.1f} min")
    logger.info("=" * 60)

    return success, errors


def main():
    parser = argparse.ArgumentParser(description="Fill depth gaps in opening book")
    parser.add_argument('--board-size', type=int, default=13, choices=[9, 13, 19])
    parser.add_argument('--parent-depth', type=int, required=True,
                        help='Depth of parent positions (will generate children at parent-depth+1)')
    parser.add_argument('--branching', type=int, default=3,
                        help='Max children per parent to generate (default: 3)')
    parser.add_argument('--visits', type=int, default=500)
    parser.add_argument('--batch-size', type=int, default=64)
    parser.add_argument('--wr-threshold', type=float, default=0.10,
                        help='Winrate threshold below best move (default: 0.10)')
    parser.add_argument('--katago-path', type=str, default=None)
    parser.add_argument('--model-path', type=str, default=None)
    parser.add_argument('--config-path', type=str, default=None)

    args = parser.parse_args()
    db_path = get_db_path()
    config = load_config()

    logger.info("=" * 60)
    logger.info("Fill Depth Gaps")
    logger.info("=" * 60)
    logger.info(f"Board size:    {args.board_size}x{args.board_size}")
    logger.info(f"Parent depth:  {args.parent_depth}")
    logger.info(f"Child depth:   {args.parent_depth + 1}")
    logger.info(f"Branching:     {args.branching}")
    logger.info(f"Visits:        {args.visits}")
    logger.info(f"WR threshold:  {args.wr_threshold}")
    logger.info("=" * 60)

    # Step 1: Find missing children
    logger.info("Step 1: Finding missing child positions...")
    missing = find_missing_children(
        db_path=db_path,
        board_size=args.board_size,
        parent_depth=args.parent_depth,
        branching=args.branching,
        wr_threshold=args.wr_threshold,
    )

    if not missing:
        logger.info("No missing children found! All gaps are filled.")
        return

    logger.info(f"Found {len(missing)} missing positions to analyze")

    # Step 2: Analyze with KataGo
    logger.info("Step 2: Analyzing missing positions with KataGo...")
    config_path = args.config_path or "katago/analysis_gpu.cfg"
    model_path = args.model_path or config.katago.model_path
    katago_path = args.katago_path or config.katago.katago_path

    success, errors = analyze_positions(
        missing=missing,
        board_size=args.board_size,
        visits=args.visits,
        batch_size=args.batch_size,
        config_path=config_path,
        model_path=model_path,
        katago_path=katago_path,
    )

    logger.info(f"Done! Analyzed {success} positions, {errors} errors")


if __name__ == "__main__":
    main()
