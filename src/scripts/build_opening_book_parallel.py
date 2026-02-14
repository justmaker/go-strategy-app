#!/usr/bin/env python3
"""
Parallel opening book generation using KataGo Analysis Engine.

Uses KataGo's JSON-based analysis engine for high-throughput GPU utilization.
Sends multiple positions in parallel for batch processing.

Usage:
    python -m src.scripts.build_opening_book_parallel --board-size 19 --depth 12 --visits 500
"""

import argparse
import collections
import json
import logging
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path
from queue import Queue, Empty
from typing import Dict, List, Optional, Set, Tuple

import os
sys.path.insert(0, os.getcwd())

from src.board import create_board
from src.cache import AnalysisCache, MoveCandidate
from src.config import load_config

# Setup logging
log_dir = Path("logs")
log_dir.mkdir(exist_ok=True)
log_file = log_dir / f"opening_book_parallel_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)


class KataGoAnalysisEngine:
    """KataGo Analysis Engine wrapper for parallel batch processing."""

    def __init__(self, config_path: str, model_path: str, katago_path: str):
        self.config_path = config_path
        self.model_path = model_path
        self.katago_path = katago_path
        self.process: Optional[subprocess.Popen] = None
        self.response_queue: Queue = Queue()
        self.pending_queries: Dict[str, dict] = {}
        self._lock = threading.Lock()
        self._reader_thread: Optional[threading.Thread] = None
        self._running = False

    def start(self):
        """Start the KataGo analysis engine."""
        cmd = [
            self.katago_path,
            "analysis",
            "-config", self.config_path,
            "-model", self.model_path,
        ]

        logger.info(f"Starting KataGo analysis engine: {' '.join(cmd)}")

        self.process = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1
        )

        self._running = True

        # Start reader thread
        self._reader_thread = threading.Thread(target=self._read_responses, daemon=True)
        self._reader_thread.start()

        # Wait for engine to initialize
        time.sleep(2)
        logger.info("KataGo analysis engine started")

    def _read_responses(self):
        """Background thread to read responses from KataGo."""
        while self._running and self.process:
            try:
                line = self.process.stdout.readline()
                if not line:
                    break
                line = line.strip()
                if line:
                    try:
                        response = json.loads(line)
                        self.response_queue.put(response)
                    except json.JSONDecodeError:
                        logger.warning(f"Invalid JSON response: {line[:100]}")
            except Exception as e:
                if self._running:
                    logger.error(f"Error reading response: {e}")
                break

    def send_query(self, query_id: str, board_size: int, moves: List[str],
                   max_visits: int, komi: float = 7.5) -> None:
        """Send an analysis query to KataGo."""
        # Convert moves to KataGo format
        katago_moves = []
        for move in moves:
            parts = move.split()
            if len(parts) == 2:
                player = parts[0].upper()
                coord = parts[1].upper()
                katago_moves.append([player, coord])

        query = {
            "id": query_id,
            "rules": "chinese",
            "komi": komi,
            "boardXSize": board_size,
            "boardYSize": board_size,
            "moves": katago_moves,
            "maxVisits": max_visits,
            "includeOwnership": True,
            "includePolicy": False,
        }

        query_str = json.dumps(query)

        with self._lock:
            self.pending_queries[query_id] = query
            self.process.stdin.write(query_str + "\n")
            self.process.stdin.flush()

    def get_response(self, timeout: float = 60.0) -> Optional[dict]:
        """Get a response from KataGo."""
        try:
            return self.response_queue.get(timeout=timeout)
        except Empty:
            return None

    def shutdown(self):
        """Shutdown the KataGo engine."""
        self._running = False
        if self.process:
            try:
                # Send termination
                self.process.stdin.write('{"id":"shutdown","action":"terminate"}\n')
                self.process.stdin.flush()
                self.process.wait(timeout=5)
            except:
                self.process.kill()
            self.process = None


def parse_response(response: dict) -> Tuple[str, List[MoveCandidate], Optional[List[float]]]:
    """Parse KataGo analysis response into move candidates."""
    query_id = response.get("id", "")
    move_infos = response.get("moveInfos", [])
    ownership = response.get("ownership")

    candidates = []
    for info in move_infos:
        move = info.get("move", "").upper()
        if move == "PASS":
            continue
        visits = info.get("visits", 0)
        winrate = info.get("winrate", 0.5)
        score_lead = info.get("scoreLead", 0.0)

        candidates.append(MoveCandidate(
            move=move,
            visits=visits,
            winrate=winrate,
            score_lead=score_lead
        ))

    # Sort by visits
    candidates.sort(key=lambda m: m.visits, reverse=True)

    return query_id, candidates[:10], ownership


def main():
    parser = argparse.ArgumentParser(description="Parallel opening book generation")
    parser.add_argument('--board-size', type=int, default=19, choices=[9, 13, 19])
    parser.add_argument('--depth', type=int, default=12)
    parser.add_argument('--visits', type=int, default=500)
    parser.add_argument('--batch-size', type=int, default=32,
                        help='Number of positions to analyze in parallel')
    args = parser.parse_args()

    logger.info("=" * 60)
    logger.info(f"{args.board_size}x{args.board_size} Parallel Opening Book Generation")
    logger.info("=" * 60)
    logger.info(f"Board size:  {args.board_size}x{args.board_size}")
    logger.info(f"Max depth:   {args.depth}")
    logger.info(f"Visits:      {args.visits}")
    logger.info(f"Batch size:  {args.batch_size}")
    logger.info("=" * 60)

    # Load config
    config = load_config()

    # Initialize cache
    cache = AnalysisCache(config=config)

    # Initialize KataGo analysis engine
    engine = KataGoAnalysisEngine(
        config_path="katago/analysis_gpu.cfg",
        model_path=config.katago.model_path,
        katago_path=config.katago.katago_path
    )
    engine.start()

    # BFS Queue
    queue = collections.deque()
    queue.append(([], 0))  # (moves, depth)

    visited_hashes: Set[str] = set()

    # Stats
    total_processed = 0
    cache_hits = 0
    cache_misses = 0
    start_time = time.time()

    # Pending batch
    pending_batch: Dict[str, Tuple[List[str], int]] = {}  # query_id -> (moves, depth)
    query_counter = 0

    try:
        logger.info(f"Starting main loop. Queue: {len(queue)}, Batch: {len(pending_batch)}")
        while queue or pending_batch:
            # Fill batch from queue
            while len(pending_batch) < args.batch_size and queue:
                moves, depth = queue.popleft()
                logger.debug(f"Processing depth={depth}, moves={len(moves)}")

                if depth >= args.depth:
                    logger.debug(f"Skipping - depth {depth} >= {args.depth}")
                    continue

                # Create board and get canonical hash
                board = create_board(size=args.board_size, moves=moves)
                canonical_hash, _ = board.compute_canonical_hash()

                if canonical_hash in visited_hashes:
                    continue
                visited_hashes.add(canonical_hash)

                # Check cache
                cached = cache.get(
                    board_hash=canonical_hash,
                    komi=7.5,
                    required_visits=None  # Get highest visits
                )

                if cached:
                    cache_hits += 1
                    total_processed += 1
                    logger.info(f"Cache HIT: depth={depth}, moves={len(moves)}, top_moves={len(cached.top_moves)}")

                    # Add children to queue
                    result = cached
                    next_player = board.next_player
                    best_winrate = result.top_moves[0].winrate if result.top_moves else 0.5

                    selected = 0
                    seen_child_hashes = set()
                    for move_cand in result.top_moves[:20]:
                        if move_cand.winrate < (best_winrate - 0.10):
                            break
                        if move_cand.move.upper() == 'PASS':
                            continue

                        new_move = f"{next_player} {move_cand.move}"
                        new_moves = list(moves) + [new_move]

                        try:
                            child_board = create_board(size=args.board_size, moves=new_moves)
                            child_hash, _ = child_board.compute_canonical_hash()

                            if child_hash in visited_hashes or child_hash in seen_child_hashes:
                                continue
                            seen_child_hashes.add(child_hash)

                            queue.append((new_moves, depth + 1))
                            selected += 1
                            logger.debug(f"Added child: {move_cand.move} at depth {depth+1}")
                            if selected >= 3:
                                break
                        except Exception as e:
                            logger.warning(f"Error creating child board: {e}")
                            continue
                    logger.info(f"Added {selected} children to queue. Queue size: {len(queue)}")
                else:
                    # Send to KataGo
                    query_id = f"q{query_counter}"
                    query_counter += 1
                    pending_batch[query_id] = (moves, depth)
                    engine.send_query(query_id, args.board_size, moves, args.visits)

            # Process responses
            if pending_batch:
                response = engine.get_response(timeout=1.0)
                if response:
                    if "error" in response:
                        logger.error(f"KataGo error: {response.get('error')}")
                        query_id = response.get("id", "")
                        if query_id in pending_batch:
                            del pending_batch[query_id]
                        continue

                    query_id, candidates, ownership = parse_response(response)

                    if query_id not in pending_batch:
                        continue

                    moves, depth = pending_batch.pop(query_id)
                    cache_misses += 1
                    total_processed += 1

                    # Create board for this position
                    board = create_board(size=args.board_size, moves=moves)
                    canonical_hash, _ = board.compute_canonical_hash()
                    next_player = board.next_player

                    # Store in cache
                    if candidates:
                        moves_str = ";".join(moves) if moves else ""
                        total_visits = sum(c.visits for c in candidates)

                        cache.put(
                            board_hash=canonical_hash,
                            moves_sequence=moves_str,
                            board_size=args.board_size,
                            komi=7.5,
                            top_moves=candidates[:10],
                            engine_visits=total_visits,
                            model_name="kata1-b18c384nbt",
                            ownership=ownership
                        )

                        # Add children to queue
                        best_winrate = candidates[0].winrate if candidates else 0.5
                        selected = 0
                        seen_child_hashes = set()

                        for move_cand in candidates[:20]:
                            if move_cand.winrate < (best_winrate - 0.10):
                                break
                            if move_cand.move.upper() == 'PASS':
                                continue

                            new_move = f"{next_player} {move_cand.move}"
                            new_moves = list(moves) + [new_move]

                            try:
                                child_board = create_board(size=args.board_size, moves=new_moves)
                                child_hash, _ = child_board.compute_canonical_hash()

                                if child_hash in visited_hashes or child_hash in seen_child_hashes:
                                    continue
                                seen_child_hashes.add(child_hash)

                                queue.append((new_moves, depth + 1))
                                selected += 1
                                if selected >= 3:
                                    break
                            except:
                                continue

                    # Progress update
                    if total_processed % 100 == 0:
                        elapsed = time.time() - start_time
                        rate = total_processed / elapsed if elapsed > 0 else 0
                        logger.info(
                            f"Processed: {total_processed} | "
                            f"Queue: {len(queue)} | "
                            f"Pending: {len(pending_batch)} | "
                            f"Hits: {cache_hits} | "
                            f"Misses: {cache_misses} | "
                            f"Rate: {rate:.1f}/s"
                        )

    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    finally:
        engine.shutdown()

        elapsed = time.time() - start_time
        logger.info("=" * 60)
        logger.info("Summary")
        logger.info("=" * 60)
        logger.info(f"Total processed:  {total_processed}")
        logger.info(f"Cache hits:       {cache_hits}")
        logger.info(f"Cache misses:     {cache_misses}")
        logger.info(f"Elapsed time:     {elapsed/60:.1f} minutes")
        logger.info(f"Rate:             {total_processed/elapsed:.1f} positions/sec")
        logger.info("=" * 60)


if __name__ == "__main__":
    main()
