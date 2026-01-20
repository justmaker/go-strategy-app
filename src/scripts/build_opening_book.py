#!/usr/bin/env python3
"""
Script to pre-calculate the opening book for a 9x9 Go board up to depth 10.
Uses Breadth-First Search (BFS) with pruning.
"""

import sys
import collections
from typing import List, Tuple, Set
from tqdm import tqdm

# Add src to path if needed (assuming running from project root)
import os
sys.path.append(os.getcwd())

from src.analyzer import GoAnalyzer
from src.board import create_board

def main():
    print("Starting 9x9 Opening Book Generation...")
    
    # Initialize Analyzer
    # GoAnalyzer handles caching automatically.
    # It will use the configuration from config.yaml (default visits, etc.)
    with GoAnalyzer() as analyzer:
        
        # BFS Queue: (list_of_moves_gtp_strings, depth)
        # Start with empty board
        queue = collections.deque()
        queue.append(([], 0))
        
        # Keep track of visited positions to handle transpositions
        visited_hashes: Set[str] = set()
        
        # Progress bar
        # Since we don't know total nodes, we just count up
        pbar = tqdm(desc="Nodes Processed", unit="node")
        
        nodes_count = 0
        
        try:
            while queue:
                moves, depth = queue.popleft()
                
                # Check depth limit
                if depth >= 10:
                    continue
                
                # Create board state to get hash and next player
                # (We do this before analysis to check visited_hashes)
                board = create_board(size=9, moves=moves)
                board_hash = board.compute_hash()
                
                if board_hash in visited_hashes:
                    continue
                visited_hashes.add(board_hash)
                
                # Perform Analysis
                # logic: analyze() checks cache, if miss runs KataGo, then saves to cache.
                try:
                    result = analyzer.analyze(
                        board_size=9,
                        moves=moves,
                        # visits=None takes from config (likely enough for opening book, e.g. 500-1000)
                    )
                except Exception as e:
                    print(f"\nError analyzing position: {e}")
                    continue
                
                nodes_count += 1
                pbar.update(1)
                
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
            print("\nProcess interrupted by user.")
        finally:
            pbar.close()
            print(f"\nCompleted. Processed {nodes_count} unique positions.")
            print(f"Total unique positions in cache: {analyzer.cache.count()}")

if __name__ == "__main__":
    main()
