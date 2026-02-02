import argparse
import json
import subprocess
import sys
import time
import random
import os
import signal

def run_game(katago_path, config_path, model_path, board_size, visits, output_dir):
    # Construct the command to run KataGo analysis engine
    cmd = [
        katago_path,
        "analysis",
        "-config", config_path,
        "-model", model_path,
        "-quit-without-input" # Ensure it exits if pipe closes
    ]

    print(f"Starting KataGo: {' '.join(cmd)}")
    process = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, # Merge stderr into stdout to capture errors
        encoding='utf-8',
        bufsize=1 # Line buffered
    )

    moves = []
    komi = 7.5 if board_size == 19 else 6.5 # Standard komi
    
    # Simple SGF header
    sgf_content = f"(;GM[1]FF[4]SZ[{board_size}]KM[{komi}]PB[KataGo]PW[KataGo]RE[?]"

    color = "B"
    game_over = False
    
    # We will play up to board_size^2 * 1.5 moves to prevent infinite loops, or until 2 passes
    max_moves = int(board_size * board_size * 2) 
    pass_count = 0

    while not game_over and len(moves) < max_moves:
        # Construct query
        query = {
            "id": str(len(moves)),
            "moves": moves,
            "rules": "chinese",
            "komi": komi,
            "boardXSize": board_size,
            "boardYSize": board_size,
            "maxVisits": visits,
            "includePolicy": False
        }
        
        process.stdin.write(json.dumps(query) + "\n")
        process.stdin.flush()

        while True:
            response_line = process.stdout.readline()
            if not response_line:
                break
            
            response_line = response_line.strip()
            if not response_line:
                continue

            # Check if it's a JSON response (starts with {)
            if response_line.startswith('{'):
                try:
                    response = json.loads(response_line)
                    break # Found the response!
                except json.JSONDecodeError:
                    print(f"KataGo Output (Invalid JSON): {response_line}")
            else:
                 # Log other output (init info, tuning, etc)
                 print(f"KataGo Log: {response_line}")

        if not response_line:
            print("KataGo process ended unexpectedly.")
            break
        if "error" in response:
            print(f"KataGo Error: {response['error']}")
            break

        move_infos = response["moveInfos"]
        if not move_infos:
            print("No moves returned")
            break

        # Filter top 3 moves
        # Sort by order (usually visits/score) provided by KataGo
        # KataGo generally sorts moveInfos by order unless specified otherwise
        # Better to sort explicitely by visits desc
        move_infos.sort(key=lambda x: x["visits"], reverse=True)
        
        top_n = min(len(move_infos), 3)
        top_moves = move_infos[:top_n]
        
        # Select one weighted by visits? The user said "all moves are within top 3".
        # Let's just pick randomly among the top 3 to ensure diversity, or weighted.
        # Let's do weighted random choice based on visits
        total_visits = sum(m["visits"] for m in top_moves)
        if total_visits > 0:
            pick_val = random.uniform(0, total_visits)
            current_sum = 0
            selected_move_info = top_moves[0]
            for m in top_moves:
                current_sum += m["visits"]
                if pick_val <= current_sum:
                    selected_move_info = m
                    break
        else:
             selected_move_info = top_moves[0]
        
        move = selected_move_info["move"]
        print(f"Move {len(moves)+1}: {color} {move} (Top {top_n} choices used)")

        moves.append([color, move])
        
        # SGF formatting
        sgf_move_str = ""
        if move == "pass":
            pass_count += 1
            sgf_move_str = ""
        else:
            pass_count = 0
            # Convert coordinate (e.g. Q16) to SGF (pd)
            # This is a bit complex without a library, but minimal implementation:
            # KataGo coords: A1 is bottom-left? No, usually standard GTP (A is left, 1 is bottom)
            # But KataGo JSON analysis uses human readable coords like "Q4"
            # SGF uses aa (top-left) to ss (bottom-right) usually.
            # Let's just store the GTP coordinate in a comment for now to be safe,
            # or use a simple converter.
            # For simplicity in this script, we'll just save the raw move sequence in the file name or a minimal log.
            # Implementing robust GTP->SGF conversion from scratch is error prone.
            pass

        if pass_count >= 2:
            game_over = True

        color = "W" if color == "B" else "B"

    process.terminate()
    
    # Save results
    timestamp = int(time.time())
    filename = f"{output_dir}/game_{board_size}x{board_size}_{timestamp}.json"
    print(f"Saving game record to {filename}")
    with open(filename, 'w') as f:
        json.dump({"board_size": board_size, "moves": moves}, f, indent=2)

def main():
    parser = argparse.ArgumentParser(description="Run constrained self-play")
    parser.add_argument("--katago", required=True, help="Path to KataGo executable")
    parser.add_argument("--config", required=True, help="Path to analysis config")
    parser.add_argument("--model", required=True, help="Path to model file")
    parser.add_argument("--output", default="./games", help="Output directory")
    args = parser.parse_args()

    os.makedirs(args.output, exist_ok=True)

    # 9x9, 13x13, 19x19
    for size in [9, 13, 19]:
        print(f"--- Starting {size}x{size} game ---")
        run_game(args.katago, args.config, args.model, size, 100, args.output)

if __name__ == "__main__":
    main()
