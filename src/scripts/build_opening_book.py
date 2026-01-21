#!/usr/bin/env python3
"""
Script to pre-calculate the opening book for a 9x9 Go board up to depth 10.
Uses Breadth-First Search (BFS) with pruning.

Usage:
    python -m src.scripts.build_opening_book --visits 50 --start-at 20:00
"""

import argparse
import collections
import sys
import time
from datetime import datetime, timedelta
from typing import Set

from tqdm import tqdm

# Add src to path if needed (assuming running from project root)
import os
sys.path.insert(0, os.getcwd())

from src.analyzer import GoAnalyzer
from src.board import create_board


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Generate 9x9 Go opening book up to depth 10.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Run immediately with 50 visits per position
    python -m src.scripts.build_opening_book --visits 50
    
    # Schedule to start at 20:00 tonight (or tomorrow if past 20:00)
    python -m src.scripts.build_opening_book --visits 100 --start-at 20:00
    
    # Run with default visits (50)
    python -m src.scripts.build_opening_book
        """
    )
    
    parser.add_argument(
        '--visits',
        type=int,
        default=50,
        help='Number of KataGo visits per position (default: 50)'
    )
    
    parser.add_argument(
        '--start-at',
        type=str,
        default=None,
        metavar='HH:MM',
        help='Wait until specified time to start (format: HH:MM, e.g., 20:00). Use "now" to start immediately.'
    )
    
    parser.add_argument(
        '--depth',
        type=int,
        default=10,
        help='Maximum depth of opening book (default: 10)'
    )
    
    parser.add_argument(
        '--board-size',
        type=int,
        default=9,
        choices=[9, 13, 19],
        help='Board size (default: 9)'
    )
    
    return parser.parse_args()


def wait_until(target_time_str: str) -> None:
    """
    Wait until the specified time.
    
    If the time is in the past today, waits until that time tomorrow.
    
    Args:
        target_time_str: Time in HH:MM format (e.g., "20:00")
    """
    try:
        target_hour, target_minute = map(int, target_time_str.split(':'))
    except ValueError:
        print(f"Invalid time format: {target_time_str}. Expected HH:MM (e.g., 20:00)")
        sys.exit(1)
    
    now = datetime.now()
    target = now.replace(hour=target_hour, minute=target_minute, second=0, microsecond=0)
    
    # If target time is in the past today, schedule for tomorrow
    if target <= now:
        target += timedelta(days=1)
    
    wait_seconds = (target - now).total_seconds()
    wait_hours = wait_seconds / 3600
    
    print(f"Current time: {now.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Target time:  {target.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Waiting {wait_hours:.1f} hours until {target_time_str} to start analysis...")
    print("(Press Ctrl+C to cancel)")
    print()
    
    # Show countdown every minute for the first 5 minutes, then every 10 minutes
    start_wait = time.time()
    while True:
        remaining = (target - datetime.now()).total_seconds()
        if remaining <= 0:
            break
        
        hours_left = remaining / 3600
        if hours_left > 1:
            print(f"  {hours_left:.1f} hours remaining...", end='\r')
            time.sleep(60)  # Check every minute
        else:
            mins_left = remaining / 60
            print(f"  {mins_left:.0f} minutes remaining...", end='\r')
            time.sleep(30)  # Check every 30 seconds in final hour
    
    print("\nStarting analysis!")


def main():
    args = parse_args()
    
    print("=" * 60)
    print("9x9 Opening Book Generation")
    print("=" * 60)
    print(f"Board size:  {args.board_size}x{args.board_size}")
    print(f"Max depth:   {args.depth}")
    print(f"Visits:      {args.visits}")
    print(f"Start time:  {args.start_at or 'Immediately'}")
    print("=" * 60)
    print()
    
    # Wait if --start-at is specified (unless "now")
    if args.start_at and args.start_at.lower() != "now":
        wait_until(args.start_at)
    
    print("Starting opening book generation...")
    print()
    
    # Initialize Analyzer
    with GoAnalyzer() as analyzer:
        
        # BFS Queue: (list_of_moves_gtp_strings, depth)
        # Start with empty board
        queue = collections.deque()
        queue.append(([], 0))
        
        # Keep track of visited positions to handle transpositions
        visited_hashes: Set[str] = set()
        
        # Progress tracking
        pbar = tqdm(desc="Nodes Processed", unit="node")
        
        nodes_count = 0
        cache_hits = 0
        cache_misses = 0
        
        try:
            while queue:
                moves, depth = queue.popleft()
                
                # Check depth limit
                if depth >= args.depth:
                    continue
                
                # Create board state to get hash and next player
                board = create_board(size=args.board_size, moves=moves)
                
                # Use canonical hash for symmetry-aware deduplication
                canonical_hash, _ = board.compute_canonical_hash()
                
                if canonical_hash in visited_hashes:
                    continue
                visited_hashes.add(canonical_hash)
                
                # Perform Analysis with specified visits
                try:
                    result = analyzer.analyze(
                        board_size=args.board_size,
                        moves=moves,
                        visits=args.visits,
                    )
                    
                    if result.from_cache:
                        cache_hits += 1
                    else:
                        cache_misses += 1
                        
                except Exception as e:
                    print(f"\nError analyzing position: {e}")
                    continue
                
                nodes_count += 1
                pbar.update(1)
                pbar.set_postfix({
                    'depth': depth,
                    'queue': len(queue),
                    'hits': cache_hits,
                    'misses': cache_misses
                })
                
                # Branching Logic
                candidate_moves = result.top_moves
                if not candidate_moves:
                    continue
                
                # 1. Pick Top 3 moves
                top_3 = candidate_moves[:3]
                
                # 2. Pruning: Only follow if winrate is within 10% of best move
                best_winrate = top_3[0].winrate
                
                next_player = board.next_player
                
                for move_cand in top_3:
                    # Check winrate threshold (winrate is 0.0-1.0)
                    if move_cand.winrate < (best_winrate - 0.10):
                        continue
                        
                    # Construct new path
                    new_move_str = f"{next_player} {move_cand.move}"
                    new_moves_list = list(moves)
                    new_moves_list.append(new_move_str)
                    
                    queue.append((new_moves_list, depth + 1))
                    
        except KeyboardInterrupt:
            print("\n\nProcess interrupted by user.")
        finally:
            pbar.close()
            
            print()
            print("=" * 60)
            print("Summary")
            print("=" * 60)
            print(f"Unique positions processed: {nodes_count}")
            print(f"Cache hits:                 {cache_hits}")
            print(f"Cache misses (new):         {cache_misses}")
            print(f"Total cache entries:        {analyzer.cache.count()}")
            print("=" * 60)
            
            # Record completion in metadata if not interrupted (checking queue empty is a proxy for completion)
            if 'queue' in locals() and not queue and nodes_count > 0:
                print("Recording completion in metadata...")
                try:
                    query = """
                        INSERT INTO opening_book_meta 
                        (board_size, komi, handicap, visits, depth, notes) 
                        VALUES (?, ?, ?, ?, ?, ?)
                    """
                    with analyzer.cache._get_connection() as conn:
                        conn.execute(query, (
                            args.board_size, 
                            7.5, # Default komi in analyzer
                            0,   # Default handicap
                            args.visits,
                            args.depth,
                            f"Generated by script, {nodes_count} nodes"
                        ))
                    print("Successfully recorded opening book completion.")
                except Exception as e:
                    print(f"Failed to record metadata: {e}")



if __name__ == "__main__":
    main()
