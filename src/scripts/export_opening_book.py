#!/usr/bin/env python3
"""
Export opening book data from SQLite to JSON or SQLite format for mobile app bundling.

This script exports the analysis cache to a compressed JSON file or a SQLite
database that can be bundled with the Flutter mobile app for offline access.

Usage:
    python -m src.scripts.export_opening_book [options]

Options:
    --output PATH      Output file path (default: mobile/assets/opening_book.json)
    --format FORMAT    Output format: json or sqlite (default: json)
    --board-size SIZE  Only export specific board size (9, 13, or 19)
    --min-visits N     Minimum visits to include (default: 50)
    --compress         Compress output with gzip
    --stats            Show statistics only, don't export
"""

import argparse
import datetime
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
    filter_dead_moves: bool = True,
) -> Dict[str, Any]:
    """
    Export opening book data to JSON.

    Args:
        db_path: Path to SQLite database
        output_path: Output JSON file path
        board_size: Filter by board size (None = all)
        min_visits: Minimum visits threshold
        compress: Whether to gzip the output
        filter_dead_moves: Remove top moves that have no follow-up data

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

    # If filter_dead_moves is enabled, first collect all existing sequences
    # INCLUDING all 8 symmetry transforms of each sequence
    existing_sequences: Set[str] = set()
    if filter_dead_moves:
        print("Collecting existing sequences for dead move filtering...")
        print("  (including all symmetry transforms)")
        seq_cursor = conn.execute(
            "SELECT board_size, komi, moves_sequence FROM analysis_cache WHERE engine_visits >= ?",
            [min_visits]
        )

        all_transforms = [
            SymmetryTransform.IDENTITY,
            SymmetryTransform.ROTATE_90,
            SymmetryTransform.ROTATE_180,
            SymmetryTransform.ROTATE_270,
            SymmetryTransform.FLIP_HORIZONTAL,
            SymmetryTransform.FLIP_VERTICAL,
            SymmetryTransform.FLIP_DIAGONAL,
            SymmetryTransform.FLIP_ANTIDIAGONAL
        ]

        for row in seq_cursor:
            bs = row['board_size']
            k = row['komi']
            seq = row['moves_sequence'] or ''

            # Parse moves
            if seq:
                raw_parts = seq.split(';')
                cleaned_moves = []
                for p in raw_parts:
                    if not p:
                        continue
                    if '[' in p and ']' in p:
                        cleaned_moves.append(p.replace('[', ' ').replace(']', ''))
                    else:
                        cleaned_moves.append(p)
            else:
                cleaned_moves = []

            # Generate all 8 symmetry transforms
            for transform in all_transforms:
                try:
                    transformed = []
                    for m in cleaned_moves:
                        parts = m.split(' ')
                        if len(parts) == 2:
                            color, coord = parts[0], parts[1]
                            new_coord = transform_gtp_coord(coord, bs, transform)
                            transformed.append(f"{color}[{new_coord}]")
                        else:
                            transformed.append(m)
                    app_seq = ";".join(transformed)
                    existing_sequences.add(f"{bs}:{k}:{app_seq}")
                except Exception:
                    # Skip invalid sequences (e.g., out of bounds coordinates)
                    pass

        print(f"  Found {len(existing_sequences)} unique sequences (with symmetries)")

    cursor = conn.execute(query, params)

    # Build export data
    entries = []
    stats = {
        'total': 0,
        'by_board_size': {},
        'by_visits': {},
        'filtered_moves': 0,
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
                SymmetryTransform.ROTATE_90,
                SymmetryTransform.ROTATE_180,
                SymmetryTransform.ROTATE_270,
                SymmetryTransform.FLIP_HORIZONTAL,
                SymmetryTransform.FLIP_VERTICAL,
                SymmetryTransform.FLIP_DIAGONAL,
                SymmetryTransform.FLIP_ANTIDIAGONAL
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
                
                # 3. Transform top candidates and optionally filter dead moves
                # Determine next player
                num_black = app_moves_string.count('B[')
                num_white = app_moves_string.count('W[')
                next_player = 'B' if num_black == num_white else 'W'

                transformed_candidates = []
                for move_cand in top_moves_json:
                    m_gtp = move_cand['move']
                    new_gtp = transform_gtp_coord(m_gtp, board_size, transform)

                    # Check if this move has follow-up data
                    if filter_dead_moves and existing_sequences:
                        if app_moves_string:
                            next_seq = f"{app_moves_string};{next_player}[{new_gtp}]"
                        else:
                            next_seq = f"{next_player}[{new_gtp}]"
                        next_key = f"{board_size}:{komi}:{next_seq}"
                        if next_key not in existing_sequences:
                            stats['filtered_moves'] += 1
                            continue  # Skip this move - no follow-up data

                    transformed_candidates.append({
                        'move': new_gtp,
                        'winrate': move_cand['winrate'],
                        'scoreLead': move_cand['score_lead'],
                        'visits': move_cand['visits']
                    })

                # Skip entry if no valid moves remain
                if filter_dead_moves and not transformed_candidates:
                    continue

                # 4. Generate hash for this variant (optional but good for consistency)
                # For now, we skip hash re-computation as the App uses moves-key primarily.
                # But let's do it if we want the 'h' key to be accurate.
                variant_board = create_board(size=board_size, moves=transformed_moves, komi=komi)
                variant_hash = variant_board.compute_hash()

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
        'version': 2,  # Bumped version for filtered moves
        'generated_at': __import__('datetime').datetime.now().isoformat(),
        'stats': {
            'total_entries': stats['total'],
            'by_board_size': stats['by_board_size'],
            'min_visits': min_visits,
            'filtered_dead_moves': stats.get('filtered_moves', 0),
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


def export_opening_book_sqlite(
    db_path: Path,
    output_path: Path,
    board_size: Optional[int] = None,
    min_visits: int = 50,
    filter_dead_moves: bool = True,
) -> Dict[str, Any]:
    """
    Export opening book data to SQLite for mobile app bundling.

    Stores canonical entries only (no symmetry expansion).
    The Dart app handles symmetry at query time.

    Args:
        db_path: Path to source SQLite database
        output_path: Output SQLite file path
        board_size: Filter by board size (None = all)
        min_visits: Minimum visits threshold
        filter_dead_moves: Remove top moves that have no follow-up data

    Returns:
        Export statistics
    """
    if not db_path.exists():
        raise FileNotFoundError(f"Database not found: {db_path}")

    src_conn = sqlite3.connect(str(db_path))
    src_conn.row_factory = sqlite3.Row

    # Remove existing output file
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        output_path.unlink()

    dst_conn = sqlite3.connect(str(output_path))
    dst_conn.execute("PRAGMA journal_mode=OFF")
    dst_conn.execute("PRAGMA synchronous=OFF")
    dst_conn.execute("PRAGMA page_size=4096")

    # Create schema (no indices yet - add after bulk insert for speed)
    dst_conn.execute("""
        CREATE TABLE opening_book (
            id INTEGER PRIMARY KEY,
            board_size INTEGER NOT NULL,
            komi REAL NOT NULL,
            moves_sequence TEXT NOT NULL DEFAULT '',
            top_moves TEXT NOT NULL,
            visits INTEGER NOT NULL
        )
    """)
    dst_conn.execute("""
        CREATE TABLE opening_book_meta (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    """)

    # Build dead-move filter set if needed (canonical sequences only)
    existing_sequences: Set[str] = set()
    if filter_dead_moves:
        print("Collecting existing sequences for dead move filtering...")
        seq_cursor = src_conn.execute(
            "SELECT board_size, komi, moves_sequence FROM analysis_cache WHERE engine_visits >= ?",
            [min_visits]
        )
        for row in seq_cursor:
            bs = row['board_size']
            k = row['komi']
            seq = row['moves_sequence'] or ''
            existing_sequences.add(f"{bs}:{k}:{seq}")
        print(f"  Found {len(existing_sequences)} canonical sequences")

    # Build main query
    query = """
        SELECT
            board_size,
            komi,
            moves_sequence,
            analysis_result,
            engine_visits
        FROM analysis_cache
        WHERE engine_visits >= ?
    """
    params: List[Any] = [min_visits]

    if board_size:
        query += " AND board_size = ?"
        params.append(board_size)

    query += " ORDER BY board_size, engine_visits DESC"

    cursor = src_conn.execute(query, params)

    stats: Dict[str, Any] = {
        'total': 0,
        'by_board_size': {},
        'filtered_moves': 0,
    }

    batch = []
    batch_size = 5000

    for row in cursor:
        try:
            top_moves_json = json.loads(row['analysis_result'])
            bs = row['board_size']
            komi_val = row['komi']
            seq = row['moves_sequence'] or ''
            visits = row['engine_visits']

            # Optionally filter dead moves
            if filter_dead_moves and existing_sequences and top_moves_json:
                # Determine next player from move sequence
                if seq:
                    num_black = seq.count('B[')
                    num_white = seq.count('W[')
                else:
                    num_black = 0
                    num_white = 0
                next_player = 'B' if num_black == num_white else 'W'

                filtered_candidates = []
                for mc in top_moves_json:
                    m_gtp = mc['move']
                    if seq:
                        next_seq = f"{seq};{next_player}[{m_gtp}]"
                    else:
                        next_seq = f"{next_player}[{m_gtp}]"
                    next_key = f"{bs}:{komi_val}:{next_seq}"
                    if next_key in existing_sequences:
                        filtered_candidates.append(mc)
                    else:
                        stats['filtered_moves'] += 1

                if not filtered_candidates:
                    continue
                top_moves_json = filtered_candidates

            # Convert to compact JSON format: {m, w, s, v}
            compact_moves = json.dumps([
                {
                    'm': mc['move'],
                    'w': round(mc['winrate'], 6),
                    's': round(mc['score_lead'], 2),
                    'v': mc['visits'],
                }
                for mc in top_moves_json
            ], separators=(',', ':'))

            batch.append((bs, komi_val, seq, compact_moves, visits))

            if len(batch) >= batch_size:
                dst_conn.executemany(
                    "INSERT INTO opening_book (board_size, komi, moves_sequence, top_moves, visits) VALUES (?, ?, ?, ?, ?)",
                    batch,
                )
                batch.clear()

            stats['total'] += 1
            stats['by_board_size'][bs] = stats['by_board_size'].get(bs, 0) + 1

        except Exception as e:
            print(f"Warning: Failed to process entry: {e}")
            continue

    # Flush remaining batch
    if batch:
        dst_conn.executemany(
            "INSERT INTO opening_book (board_size, komi, moves_sequence, top_moves, visits) VALUES (?, ?, ?, ?, ?)",
            batch,
        )

    # NOTE: Index is NOT created here to reduce bundled file size.
    # The Dart app creates the index on first launch after decompression.
    # This saves ~300MB in the uncompressed DB and ~30MB compressed.

    # Insert metadata
    dst_conn.execute(
        "INSERT INTO opening_book_meta (key, value) VALUES (?, ?)",
        ('version', '1'),
    )
    dst_conn.execute(
        "INSERT INTO opening_book_meta (key, value) VALUES (?, ?)",
        ('generated_at', datetime.datetime.now().isoformat()),
    )
    dst_conn.execute(
        "INSERT INTO opening_book_meta (key, value) VALUES (?, ?)",
        ('total_entries', str(stats['total'])),
    )
    dst_conn.execute(
        "INSERT INTO opening_book_meta (key, value) VALUES (?, ?)",
        ('by_board_size', json.dumps(stats['by_board_size'])),
    )
    dst_conn.execute(
        "INSERT INTO opening_book_meta (key, value) VALUES (?, ?)",
        ('min_visits', str(min_visits)),
    )

    dst_conn.commit()

    # VACUUM to compact
    print("Running VACUUM...")
    dst_conn.execute("VACUUM")
    dst_conn.close()
    src_conn.close()

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
        description="Export opening book for mobile app"
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=None,
        help="Output file path (default depends on format)"
    )
    parser.add_argument(
        "--format", "-f",
        choices=["json", "sqlite"],
        default="json",
        help="Output format: json or sqlite (default: json)"
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
    parser.add_argument(
        "--no-filter-dead-moves",
        action="store_true",
        help="Don't filter out moves that have no follow-up data"
    )

    args = parser.parse_args()
    db_path = get_db_path()

    if args.stats:
        show_stats(db_path)
        return

    # Set default output path based on format
    if args.output is None:
        if args.format == "sqlite":
            args.output = Path("mobile/assets/data/opening_book.db")
        else:
            args.output = Path("mobile/assets/opening_book.json")

    filter_dead = not args.no_filter_dead_moves
    print(f"Exporting opening book from {db_path}...")
    print(f"  Format: {args.format}")
    print(f"  Board size: {args.board_size or 'all'}")
    print(f"  Min visits: {args.min_visits}")
    print(f"  Compress: {args.compress}")
    print(f"  Filter dead moves: {filter_dead}")

    try:
        if args.format == "sqlite":
            stats = export_opening_book_sqlite(
                db_path=db_path,
                output_path=args.output,
                board_size=args.board_size,
                min_visits=args.min_visits,
                filter_dead_moves=filter_dead,
            )
        else:
            stats = export_opening_book(
                db_path=db_path,
                output_path=args.output,
                board_size=args.board_size,
                min_visits=args.min_visits,
                compress=args.compress,
                filter_dead_moves=filter_dead,
            )

        print(f"\nExport complete!")
        print(f"  Total entries: {stats['total']}")
        print(f"  By board size: {stats['by_board_size']}")
        if stats.get('filtered_moves'):
            print(f"  Filtered dead moves: {stats['filtered_moves']}")
        print(f"  Output: {stats['output_path']}")
        print(f"  Size: {stats['output_size'] / 1024 / 1024:.1f} MB")

    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
