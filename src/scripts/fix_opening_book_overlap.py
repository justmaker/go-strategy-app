#!/usr/bin/env python3
"""Fix opening book DB: remove top_moves that overlap with already-occupied positions."""

import sqlite3
import json
import os
import gzip
import shutil


def fix_db(db_path: str):
    """Remove overlapping top_moves from a single DB file."""
    db = sqlite3.connect(db_path)

    cursor = db.execute('SELECT rowid, moves_sequence, top_moves FROM opening_book')
    rows = list(cursor)

    fixed_count = 0

    for rowid, seq, top_moves_json in rows:
        if not seq:
            continue

        top_moves = json.loads(top_moves_json)

        # Parse occupied positions from sequence
        occupied = set()
        for part in seq.split(';'):
            if '[' in part and ']' in part:
                coord = part.split('[')[1].rstrip(']')
                occupied.add(coord.upper())

        # Remove overlapping top_moves
        cleaned = [m for m in top_moves if m['m'].upper() not in occupied]

        if len(cleaned) < len(top_moves):
            fixed_count += 1
            new_json = json.dumps(cleaned, separators=(',', ':'))
            db.execute('UPDATE opening_book SET top_moves = ? WHERE rowid = ?',
                       (new_json, rowid))

    db.commit()
    db.close()

    print(f"  Fixed {fixed_count} entries (removed overlapping moves)")


def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    for board_size in [13, 19]:
        gz_path = os.path.join(base_dir, f'mobile/assets/data/opening_book_{board_size}x{board_size}.db.gz')
        db_path = f'/tmp/opening_book_{board_size}x{board_size}_fix.db'

        print(f"\n=== Fixing {board_size}x{board_size} ===")

        # Decompress from original
        with gzip.open(gz_path, 'rb') as f_in:
            with open(db_path, 'wb') as f_out:
                shutil.copyfileobj(f_in, f_out)

        fix_db(db_path)

        # Recompress
        with open(db_path, 'rb') as f_in:
            with gzip.open(gz_path, 'wb', compresslevel=9) as f_out:
                shutil.copyfileobj(f_in, f_out)

        new_size = os.path.getsize(gz_path)
        print(f"  Output: {gz_path} ({new_size / 1024:.1f} KB)")


if __name__ == '__main__':
    main()
