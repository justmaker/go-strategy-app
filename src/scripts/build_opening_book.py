
import sys
from collections import deque
from pathlib import Path
from tqdm import tqdm

# Add project root to path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from src.analyzer import GoAnalyzer
from src.config import load_config

def build_opening_book():
    """
    Generate an opening book for 9x9 Go.
    
    Configuration:
    - Board Size: 9x9
    - Depth: 10 plies
    - Branching: Top 3 moves
    - Pruning: Drop > 10% winrate
    """
    print("=" * 50)
    print("Starting 9x9 Opening Book Generator")
    print("=" * 50)
    
    # internal constants
    BOARD_SIZE = 9
    MAX_DEPTH = 10
    TOP_N = 3
    PRUNE_THRESHOLD = 0.10  # 10% winrate drop
    
    # Load config and initialize analyzer
    try:
        config = load_config()
        analyzer = GoAnalyzer(config=config)
        analyzer.start()
    except Exception as e:
        print(f"Error initializing: {e}")
        return

    # Queue for BFS: (moves_list, depth)
    # moves_list example: ["B C5", "W G5"]
    queue = deque([([], 0)])
    
    # Track items to avoid cycles and transpositions
    processed_hashes = set()
    
    print(f"Settings: Size={BOARD_SIZE}, Depth={MAX_DEPTH}, Branching={TOP_N}")
    print("Press Ctrl+C to stop early (results are saved to DB automatically).")
    
    pbar = tqdm(desc="Positions Analyzed", unit="pos")
    
    try:
        while queue:
            current_moves, depth = queue.popleft()
            
            # Analyze position
            # This automatically caches the result in SQLite
            result = analyzer.analyze(
                board_size=BOARD_SIZE,
                moves=current_moves,
                komi=7.5, # Standard komi
                force_refresh=False
            )
            
            # Check for transpositions
            if result.board_hash in processed_hashes:
                # We've already expanded this position from a different (likely shorter) path
                continue
            
            processed_hashes.add(result.board_hash)
            pbar.update(1)
            
            # Stop expansion if we reached max depth
            if depth >= MAX_DEPTH:
                continue
                
            # No moves available (game over or error)
            if not result.top_moves:
                continue
            
            # Determine best winrate for pruning
            best_winrate = result.top_moves[0].winrate
            
            # Determine next player color
            # If empty, B. If last was B, W. If last was W, B.
            next_player = "B"
            if current_moves:
                last_color = current_moves[-1].split()[0]
                next_player = "W" if last_color == "B" else "B"
            
            # Branching logic
            candidates_count = 0
            for move in result.top_moves[:TOP_N]:
                if move.move.upper() == "PASS" or move.move.upper() == "RESIGN":
                    continue
                
                # Pruning: Skip if winrate drops too much
                # Note: Winrate is always from perspective of player-to-move in our abstraction
                if (best_winrate - move.winrate) > PRUNE_THRESHOLD:
                    continue
                
                # Create new move sequence
                new_move_str = f"{next_player} {move.move}"
                new_sequence = current_moves + [new_move_str]
                
                # Add to queue
                queue.append((new_sequence, depth + 1))
                candidates_count += 1
            
            # Update status
            pbar.set_postfix({"Depth": depth, "Q": len(queue)})
            
    except KeyboardInterrupt:
        print("\n\nStopping generator...")
    except Exception as e:
        print(f"\n\nError: {e}")
    finally:
        analyzer.shutdown()
        pbar.close()
        print("\nGenerator finished.")
        print(f"Total unique positions processed: {len(processed_hashes)}")
        print("Results saved to database.")

if __name__ == "__main__":
    build_opening_book()
