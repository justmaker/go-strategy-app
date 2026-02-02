#!/usr/bin/env python3
"""
Export opening book data from SQLite to JSON format for mobile app bundling.

This script exports the analysis cache to a compressed JSON file that can be
bundled with the Flutter mobile app for offline access.

Usage:
    python -m src.scripts.export_opening_book [options]

Options:
    --output PATH      Output file path (default: mobile/assets/opening_book.json)
    --board-size SIZE  Only export specific board size (9, 13, or 19)
    --min-visits N     Minimum visits to include (default: 50)
    --compress         Compress output with gzip
    --stats            Show statistics only, don't export
"""

import argparse
import gzip
import json
import sqlite3
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

# Add src to path
import os
sys.path.insert(0, os.getcwd())

from src.board import create_board, get_valid_symmetries, transform_gtp_coord, SymmetryTransform
from src.cache import MoveCandidate


def get_db_path() -> Path:
    """Get the database path."""
    return Path(__file__).parent.parent.parent / "data" / "analysis.db"


def export_opening_book(
    db_path: Path,
    output_path: Path,
    board_size: Optional[int] = None,
    min_visits: int = 50,
    compress: bool = False,
) -> Dict[str, Any]:
    """
    Export opening book data to JSON.
    
    Args:
        db_path: Path to SQLite database
        output_path: Output JSON file path
        board_size: Filter by board size (None = all)
        min_visits: Minimum visits threshold
        compress: Whether to gzip the output
        
    Returns:
        Export statistics
    """
    if not db_path.exists():
        raise FileNotFoundError(f"Database not found: {db_path}")
    
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    
    # Build query
    query = """
        SELECT 
            board_hash,
            board_size,
            komi,
            moves_sequence,
            analysis_result,
            engine_visits,
            model_name
        FROM analysis_cache
        WHERE engine_visits >= ?
    """
    params: List[Any] = [min_visits]
    
    if board_size:
        query += " AND board_size = ?"
        params.append(board_size)
    
    query += " ORDER BY board_size, engine_visits DESC"
    
    cursor = conn.execute(query, params)
    
    # Build export data
    entries = []
    stats = {
        'total': 0,
        'by_board_size': {},
        'by_visits': {},
    }
    
    seen_keys: Set[str] = set()
    
    for row in cursor:
        try:
            top_moves_json = json.loads(row['analysis_result'])
            raw_moves = row['moves_sequence'].split(';') if row['moves_sequence'] else []
            board_size = row['board_size']
            komi = row['komi']
            
            # Clean moves: B[Q16] -> B Q16
            cleaned_moves = []
            for m in raw_moves:
                if '[' in m and ']' in m:
                    cleaned_moves.append(m.replace('[', ' ').replace(']', ''))
                else:
                    cleaned_moves.append(m)

            # Create board state to compute symmetries
            board = create_board(size=board_size, moves=cleaned_moves, komi=komi)
            
            # Generate all 8 symmetries
            # Note: We use all 8 regardless of board symmetry for simple app lookup
            all_transforms = [
                SymmetryTransform.IDENTITY,
                SymmetryTransform.ROT_90,
                SymmetryTransform.ROT_180,
                SymmetryTransform.ROT_270,
                SymmetryTransform.MIRROR_X,
                SymmetryTransform.MIRROR_Y,
                SymmetryTransform.MIRROR_DIAG,
                SymmetryTransform.MIRROR_ANTI_DIAG
            ]
            
            for transform in all_transforms:
                # 1. Transform moves sequence
                transformed_moves = []
                for m_str in cleaned_moves:
                    if not m_str: continue
                    parts = m_str.split(' ')
                    if len(parts) == 2:
                        color, coord = parts[0], parts[1]
                        new_coord = transform_gtp_coord(coord, board_size, transform)
                        transformed_moves.append(f"{color} {new_coord}")
                    else:
                        transformed_moves.append(m_str) # e.g. "B PASS"
                
                # 2. Build move key for uniqueness
                move_seq_str = ";".join(transformed_moves).replace(" ", "[")
                # Add brackets for app format compatibility: B E5 -> B[E5]
                # Wait, OpeningBookService._buildMoveKey uses internal format
                # Let's check OpeningBookService.buildMoveKeyFromGtp: 
                # converts ["B E5"] to "B[E5]" via join(';')
                
                app_moves_string = ";".join([m.replace(" ", "[") + "]" if " " in m else m for m in transformed_moves])
                
                unique_key = f"{board_size}:{komi}:{app_moves_string}"
                if unique_key in seen_keys:
                    continue
                seen_keys.add(unique_key)
                
                # 3. Transform top candidates
                transformed_candidates = []
                for move_cand in top_moves_json:
                    m_gtp = move_cand['move']
                    new_gtp = transform_gtp_coord(m_gtp, board_size, transform)
                    
                    transformed_candidates.append({
                        'move': new_gtp,
                        'winrate': move_cand['winrate'],
                        'scoreLead': move_cand['scoreLead'],
                        'visits': move_cand['visits']
                    })
                
                # 4. Generate hash for this variant (optional but good for consistency)
                # For now, we skip hash re-computation as the App uses moves-key primarily.
                # But let's do it if we want the 'h' key to be accurate.
                variant_board = create_board(size=board_size, moves=transformed_moves, komi=komi)
                variant_hash = variant_board.compute_zobrist_hash()

                entry = {
                    'h': variant_hash,
                    's': board_size,
                    'k': komi,
                    'm': app_moves_string,
                    't': transformed_candidates,
                    'v': row['engine_visits'],
                }
                entries.append(entry)
                
            # Update stats (unique canonical positions)
            stats['total'] += 1
            bs = row['board_size']
            stats['by_board_size'][bs] = stats['by_board_size'].get(bs, 0) + 1
            v = row['engine_visits']
            stats['by_visits'][v] = stats['by_visits'].get(v, 0) + 1
            
        except Exception as e:
            print(f"Warning: Failed to process entry: {e}")
            continue
    
    conn.close()
    
    # Build output structure
    output = {
        'version': 1,
        'generated_at': __import__('datetime').datetime.now().isoformat(),
        'stats': {
            'total_entries': stats['total'],
            'by_board_size': stats['by_board_size'],
            'min_visits': min_visits,
        },
        'entries': entries,
    }
    
    # Write output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    if compress:
        output_path = output_path.with_suffix('.json.gz')
        with gzip.open(output_path, 'wt', encoding='utf-8') as f:
            json.dump(output, f, separators=(',', ':'))  # Compact JSON
    else:
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(output, f, separators=(',', ':'))  # Compact JSON
    
    stats['output_path'] = str(output_path)
    stats['output_size'] = output_path.stat().st_size
    
    return stats


def show_stats(db_path: Path) -> None:
    """Show database statistics without exporting."""
    if not db_path.exists():
        print(f"Database not found: {db_path}")
        return
    
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    
    print("\n=== Opening Book Statistics ===\n")
    
    # Total count
    total = conn.execute("SELECT COUNT(*) FROM analysis_cache").fetchone()[0]
    print(f"Total entries: {total}")
    
    # By board size
    print("\nBy board size:")
    cursor = conn.execute("""
        SELECT board_size, COUNT(*) as cnt, 
               MIN(engine_visits) as min_v, MAX(engine_visits) as max_v,
               AVG(engine_visits) as avg_v
        FROM analysis_cache
        GROUP BY board_size
        ORDER BY board_size
    """)
    for row in cursor:
        print(f"  {row['board_size']}x{row['board_size']}: {row['cnt']} entries "
              f"(visits: {row['min_v']}-{row['max_v']}, avg={row['avg_v']:.0f})")
    
    # By visits
    print("\nBy visit count:")
    cursor = conn.execute("""
        SELECT engine_visits, COUNT(*) as cnt
        FROM analysis_cache
        GROUP BY engine_visits
        ORDER BY cnt DESC
        LIMIT 10
    """)
    for row in cursor:
        print(f"  {row['engine_visits']} visits: {row['cnt']} entries")
    
    # File size
    db_size = db_path.stat().st_size / 1024 / 1024
    print(f"\nDatabase size: {db_size:.2f} MB")
    
    conn.close()


def main():
    parser = argparse.ArgumentParser(
        description="Export opening book to JSON for mobile app"
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=Path("mobile/assets/opening_book.json"),
        help="Output file path"
    )
    parser.add_argument(
        "--board-size", "-s",
        type=int,
        choices=[9, 13, 19],
        help="Only export specific board size"
    )
    parser.add_argument(
        "--min-visits", "-v",
        type=int,
        default=50,
        help="Minimum visits to include (default: 50)"
    )
    parser.add_argument(
        "--compress", "-c",
        action="store_true",
        help="Compress output with gzip"
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Show statistics only"
    )
    
    args = parser.parse_args()
    db_path = get_db_path()
    
    if args.stats:
        show_stats(db_path)
        return
    
    print(f"Exporting opening book from {db_path}...")
    print(f"  Board size: {args.board_size or 'all'}")
    print(f"  Min visits: {args.min_visits}")
    print(f"  Compress: {args.compress}")
    
    try:
        stats = export_opening_book(
            db_path=db_path,
            output_path=args.output,
            board_size=args.board_size,
            min_visits=args.min_visits,
            compress=args.compress,
        )
        
        print(f"\nExport complete!")
        print(f"  Total entries: {stats['total']}")
        print(f"  By board size: {stats['by_board_size']}")
        print(f"  Output: {stats['output_path']}")
        print(f"  Size: {stats['output_size'] / 1024:.1f} KB")
        
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
