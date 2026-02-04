#!/usr/bin/env python3
"""
Import KataGo official 9x9 opening book into the analysis cache.

The KataGo book is stored as HTML files with embedded JavaScript data.
This script parses those files and imports them into our SQLite database.

Usage:
    python -m src.scripts.import_katago_book --book-path katago/books/book9x9tt-20241105.tar.gz
"""

import argparse
import json
import os
import re
import sqlite3
import sys
import tarfile
import tempfile
from collections import deque
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from src.board import coords_to_gtp, get_zobrist_hasher, GTP_COLUMNS
from src.cache import MoveCandidate
from src.config import load_config, get_db_path


# ============================================================================
# Data Classes
# ============================================================================

@dataclass
class KataGoPosition:
    """Parsed KataGo book position."""
    board: List[int]  # Flat array, 0=empty, 1=black, 2=white
    next_player: int  # 1=black, 2=white
    moves: List[Dict[str, Any]]  # Move candidates
    links: Dict[int, str]  # Child links {board_idx: path}
    link_syms: Dict[int, int]  # Symmetry for each link
    html_path: str  # Original path for debugging


# ============================================================================
# HTML Parsing
# ============================================================================

def parse_html_file(content: str, html_path: str) -> Optional[KataGoPosition]:
    """
    Parse KataGo HTML book file content.

    The HTML contains JavaScript with:
    - const board = [0,0,0,...];  // 81 values for 9x9
    - const nextPla = 1;  // 1=black, 2=white
    - const moves = [{xy:[[x,y]], wl:0.5, ssM:1.0, v:1000}, ...];
    - const links = {idx: 'path', ...};
    - const linkSyms = {idx: sym, ...};
    """
    try:
        # Extract board array
        board_match = re.search(r'const board = \[([\d,]+)\];', content)
        if not board_match:
            return None
        board = [int(x) for x in board_match.group(1).split(',') if x.strip()]

        # Extract next player
        next_pla_match = re.search(r'const nextPla = (\d+);', content)
        if not next_pla_match:
            return None
        next_player = int(next_pla_match.group(1))

        # Extract moves (complex JSON-like structure)
        moves_match = re.search(r"const moves = (\[.*?\]);", content, re.DOTALL)
        moves = []
        if moves_match:
            # Parse the JavaScript object notation
            moves_str = moves_match.group(1)
            # Convert JS notation to valid JSON
            # Replace single quotes with double quotes, handle unquoted keys
            moves_str = re.sub(r"'", '"', moves_str)
            moves_str = re.sub(r'(\w+):', r'"\1":', moves_str)
            # Handle trailing commas
            moves_str = re.sub(r',\s*]', ']', moves_str)
            moves_str = re.sub(r',\s*}', '}', moves_str)
            try:
                moves = json.loads(moves_str)
            except json.JSONDecodeError:
                # Fallback: extract key values with regex
                moves = parse_moves_fallback(moves_match.group(1))

        # Extract links
        links_match = re.search(r'const links = \{(.*?)\};', content, re.DOTALL)
        links = {}
        if links_match:
            links_str = links_match.group(1)
            # Parse format: 12:'../A3/xxx.html',
            for match in re.finditer(r"(\d+):'([^']+)'", links_str):
                idx = int(match.group(1))
                path = match.group(2)
                links[idx] = path

        # Extract link symmetries
        link_syms_match = re.search(r'const linkSyms = \{(.*?)\};', content, re.DOTALL)
        link_syms = {}
        if link_syms_match:
            syms_str = link_syms_match.group(1)
            for match in re.finditer(r'(\d+):(\d+)', syms_str):
                idx = int(match.group(1))
                sym = int(match.group(2))
                link_syms[idx] = sym

        return KataGoPosition(
            board=board,
            next_player=next_player,
            moves=moves,
            links=links,
            link_syms=link_syms,
            html_path=html_path
        )

    except Exception as e:
        print(f"Error parsing {html_path}: {e}")
        return None


def parse_moves_fallback(moves_str: str) -> List[Dict[str, Any]]:
    """Fallback parser for moves array when JSON parsing fails."""
    moves = []
    # Match each move object
    for match in re.finditer(r"\{([^}]+)\}", moves_str):
        move_content = match.group(1)
        move = {}

        # Extract xy coordinates
        xy_match = re.search(r"'xy':\[\[([^\]]+)\]", move_content)
        if xy_match:
            coords = []
            for coord_match in re.finditer(r'\[(\d+),(\d+)\]', xy_match.group(0)):
                coords.append([int(coord_match.group(1)), int(coord_match.group(2))])
            move['xy'] = coords

        # Check for 'pass' or 'other' move
        if "'move':'pass'" in move_content or '"move":"pass"' in move_content:
            move['move'] = 'pass'
        elif "'move':'other'" in move_content or '"move":"other"' in move_content:
            move['move'] = 'other'

        # Extract numeric values
        for key in ['wl', 'ssM', 'v', 'p', 'av', 'wlRad', 'sRad']:
            pattern = rf"'{key}':([0-9.e+-]+)|" + rf'"{key}":([0-9.e+-]+)'
            value_match = re.search(pattern, move_content)
            if value_match:
                val_str = value_match.group(1) or value_match.group(2)
                try:
                    move[key] = float(val_str)
                except ValueError:
                    pass

        if move:
            moves.append(move)

    return moves


# ============================================================================
# Coordinate Conversion
# ============================================================================

def katago_xy_to_gtp(x: int, y: int, board_size: int = 9) -> str:
    """
    Convert KataGo 0-indexed coordinates to GTP format.

    KataGo uses (x, y) where:
    - x is column (0 = left)
    - y is row (0 = bottom in their visualization)

    GTP uses columns A-J (skip I) and rows 1-9.
    """
    # For 9x9: A-J columns (skip I), so use first 9 letters of GTP_COLUMNS
    col = GTP_COLUMNS[x]
    row = y + 1
    return f"{col}{row}"


def board_array_to_stones(board: List[int], board_size: int = 9) -> Dict[Tuple[int, int], str]:
    """
    Convert KataGo flat board array to stones dictionary.

    board[y * board_size + x] where:
    - 0 = empty
    - 1 = black
    - 2 = white
    """
    stones = {}
    for idx, val in enumerate(board):
        if val != 0:
            x = idx % board_size
            y = idx // board_size
            color = 'B' if val == 1 else 'W'
            stones[(x, y)] = color
    return stones


# ============================================================================
# Database Operations
# ============================================================================

def clear_9x9_entries(db_path: str) -> int:
    """Delete all existing 9x9 entries from the database."""
    conn = sqlite3.connect(db_path)
    cursor = conn.execute("DELETE FROM analysis_cache WHERE board_size = 9")
    deleted = cursor.rowcount
    conn.commit()
    conn.close()
    return deleted


def insert_position(
    conn: sqlite3.Connection,
    board_hash: str,
    moves_sequence: str,
    board_size: int,
    komi: float,
    top_moves: List[MoveCandidate],
    engine_visits: int,
    model_name: str = "KataGo-Book"
) -> bool:
    """Insert a position into the database."""
    result_json = json.dumps([m.to_dict() for m in top_moves])

    try:
        conn.execute("""
            INSERT OR REPLACE INTO analysis_cache
            (board_hash, moves_sequence, board_size, komi,
             analysis_result, engine_visits, model_name, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            board_hash,
            moves_sequence,
            board_size,
            komi,
            result_json,
            engine_visits,
            model_name,
            datetime.now().isoformat()
        ))
        return True
    except sqlite3.Error as e:
        print(f"Database error: {e}")
        return False


# ============================================================================
# Main Import Logic
# ============================================================================

def build_moves_sequence(move_history: List[Tuple[str, str]]) -> str:
    """
    Build moves sequence string from history.

    Format: "B[E5];W[C3];B[G7]"
    """
    if not move_history:
        return ""

    parts = []
    for color, coord in move_history:
        parts.append(f"{color}[{coord}]")
    return ";".join(parts)


def import_katago_book(
    book_path: str,
    db_path: str,
    board_size: int = 9,
    komi: float = 7.5,
    max_depth: int = 50,
    min_visits: int = 1000,
    clear_existing: bool = True,
    dry_run: bool = False
) -> Dict[str, int]:
    """
    Import KataGo opening book into the database.

    Uses BFS traversal starting from root position.

    Args:
        book_path: Path to the tar.gz book file
        db_path: Path to the SQLite database
        board_size: Board size (should be 9 for this book)
        komi: Komi value (7.5 for Tromp-Taylor rules)
        max_depth: Maximum depth to import
        min_visits: Minimum visits threshold for a position
        clear_existing: Whether to clear existing 9x9 entries
        dry_run: If True, don't actually write to database

    Returns:
        Stats dictionary with import results
    """
    stats = {
        'positions_parsed': 0,
        'positions_imported': 0,
        'positions_skipped_visits': 0,
        'positions_skipped_error': 0,
        'max_depth_reached': 0,
    }

    hasher = get_zobrist_hasher()

    # Clear existing entries
    if clear_existing and not dry_run:
        deleted = clear_9x9_entries(db_path)
        print(f"Cleared {deleted} existing 9x9 entries")

    # Open database connection
    conn = None
    if not dry_run:
        conn = sqlite3.connect(db_path)
        conn.execute("PRAGMA journal_mode=WAL")

    # Extract and process tar file
    with tempfile.TemporaryDirectory() as tmpdir:
        print(f"Extracting {book_path} to {tmpdir}...")
        with tarfile.open(book_path, 'r:gz') as tar:
            tar.extractall(tmpdir)

        html_dir = Path(tmpdir) / "html"
        root_path = html_dir / "root" / "root.html"

        if not root_path.exists():
            print(f"Error: Root file not found at {root_path}")
            return stats

        # BFS traversal
        # Queue items: (html_path, move_history, depth)
        queue = deque([(str(root_path), [], 0)])
        visited_paths = set()
        visited_hashes = set()

        batch_count = 0
        batch_size = 1000

        while queue:
            html_path, move_history, depth = queue.popleft()

            if html_path in visited_paths:
                continue
            visited_paths.add(html_path)

            if depth > max_depth:
                stats['max_depth_reached'] += 1
                continue

            # Read and parse the HTML file
            try:
                with open(html_path, 'r', encoding='utf-8') as f:
                    content = f.read()
            except FileNotFoundError:
                stats['positions_skipped_error'] += 1
                continue

            position = parse_html_file(content, html_path)
            if position is None:
                stats['positions_skipped_error'] += 1
                continue

            stats['positions_parsed'] += 1

            # Convert board to stones dict
            stones = board_array_to_stones(position.board, board_size)
            next_player = 'B' if position.next_player == 1 else 'W'

            # Compute Zobrist hash
            board_hash, _ = hasher.compute_canonical_hash(
                stones, next_player, komi, board_size
            )

            # Skip if already processed (from different path)
            if board_hash in visited_hashes:
                continue
            visited_hashes.add(board_hash)

            # Extract top moves
            top_moves = []
            total_visits = 0

            for move_data in position.moves:
                # Skip 'other' and 'pass' special moves
                if move_data.get('move') in ('other', 'pass'):
                    continue

                xy_coords = move_data.get('xy', [])
                if not xy_coords:
                    continue

                # Use first coordinate (others are symmetric equivalents)
                x, y = xy_coords[0]
                gtp_coord = katago_xy_to_gtp(x, y, board_size)

                winrate = move_data.get('wl', 0.5)
                score_lead = move_data.get('ssM', 0.0)
                visits = int(move_data.get('v', 0))

                # KataGo wl is from current player's perspective
                # Our winrate is always from black's perspective
                if next_player == 'W':
                    winrate = 1.0 - winrate
                    score_lead = -score_lead

                top_moves.append(MoveCandidate(
                    move=gtp_coord,
                    winrate=winrate,
                    score_lead=score_lead,
                    visits=visits
                ))

                total_visits += visits

            # Skip positions with too few visits
            if total_visits < min_visits:
                stats['positions_skipped_visits'] += 1
            else:
                # Build moves sequence
                moves_sequence = build_moves_sequence(move_history)

                # Insert into database
                if not dry_run and conn:
                    success = insert_position(
                        conn,
                        board_hash,
                        moves_sequence,
                        board_size,
                        komi,
                        top_moves,
                        total_visits,
                        "KataGo-Book-9x9"
                    )
                    if success:
                        stats['positions_imported'] += 1
                        batch_count += 1

                        if batch_count >= batch_size:
                            conn.commit()
                            batch_count = 0
                            print(f"  Imported {stats['positions_imported']} positions...")
                else:
                    stats['positions_imported'] += 1

            # Add children to queue
            html_parent = Path(html_path).parent
            for board_idx, rel_path in position.links.items():
                # Calculate the move that leads to this child
                x = board_idx % board_size
                y = board_idx // board_size
                gtp_coord = katago_xy_to_gtp(x, y, board_size)

                child_history = move_history + [(next_player, gtp_coord)]

                # Resolve relative path
                child_path = str((html_parent / rel_path).resolve())

                if child_path not in visited_paths:
                    queue.append((child_path, child_history, depth + 1))

            # Progress update
            if stats['positions_parsed'] % 10000 == 0:
                print(f"Parsed {stats['positions_parsed']} positions, "
                      f"imported {stats['positions_imported']}, "
                      f"queue size: {len(queue)}")

    # Final commit
    if conn:
        conn.commit()
        conn.close()

    return stats


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Import KataGo official opening book into analysis cache"
    )
    parser.add_argument(
        "--book-path",
        default="katago/books/book9x9tt-20241105.tar.gz",
        help="Path to the KataGo book tar.gz file"
    )
    parser.add_argument(
        "--board-size",
        type=int,
        default=9,
        help="Board size (default: 9)"
    )
    parser.add_argument(
        "--komi",
        type=float,
        default=7.5,
        help="Komi value (default: 7.5 for Tromp-Taylor)"
    )
    parser.add_argument(
        "--max-depth",
        type=int,
        default=50,
        help="Maximum depth to import (default: 50)"
    )
    parser.add_argument(
        "--min-visits",
        type=int,
        default=10000,
        help="Minimum total visits for a position (default: 10000)"
    )
    parser.add_argument(
        "--no-clear",
        action="store_true",
        help="Don't clear existing 9x9 entries before import"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse files but don't write to database"
    )
    parser.add_argument(
        "--db-path",
        help="Path to database (default: from config)"
    )

    args = parser.parse_args()

    # Get database path
    if args.db_path:
        db_path = args.db_path
    else:
        config = load_config()
        db_path = str(get_db_path(config))

    print(f"KataGo Book Importer")
    print(f"=" * 50)
    print(f"Book path: {args.book_path}")
    print(f"Database:  {db_path}")
    print(f"Board size: {args.board_size}")
    print(f"Komi: {args.komi}")
    print(f"Max depth: {args.max_depth}")
    print(f"Min visits: {args.min_visits}")
    print(f"Clear existing: {not args.no_clear}")
    print(f"Dry run: {args.dry_run}")
    print(f"=" * 50)

    if not Path(args.book_path).exists():
        print(f"Error: Book file not found: {args.book_path}")
        sys.exit(1)

    stats = import_katago_book(
        book_path=args.book_path,
        db_path=db_path,
        board_size=args.board_size,
        komi=args.komi,
        max_depth=args.max_depth,
        min_visits=args.min_visits,
        clear_existing=not args.no_clear,
        dry_run=args.dry_run
    )

    print(f"\n{'=' * 50}")
    print(f"Import Complete!")
    print(f"=" * 50)
    print(f"Positions parsed:        {stats['positions_parsed']:,}")
    print(f"Positions imported:      {stats['positions_imported']:,}")
    print(f"Skipped (low visits):    {stats['positions_skipped_visits']:,}")
    print(f"Skipped (parse error):   {stats['positions_skipped_error']:,}")
    print(f"Max depth cutoffs:       {stats['max_depth_reached']:,}")


if __name__ == "__main__":
    main()
