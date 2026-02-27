#!/usr/bin/env python3
"""Split opening_book.db into per-board-size databases and compress them.

Produces:
  mobile/assets/data/opening_book_9x9.db.gz
  mobile/assets/data/opening_book_13x13.db.gz
  mobile/assets/data/opening_book_19x19.db.gz
"""

import gzip
import json
import os
import sqlite3
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, '..', '..'))
SOURCE_DB = os.path.join(PROJECT_ROOT, 'mobile', 'assets', 'data', 'opening_book.db')
OUTPUT_DIR = os.path.join(PROJECT_ROOT, 'mobile', 'assets', 'data')

BOARD_SIZES = [9, 13, 19]


def create_target_db(path: str) -> sqlite3.Connection:
    """Create a new SQLite DB with the opening_book schema."""
    if os.path.exists(path):
        os.remove(path)
    conn = sqlite3.connect(path)
    conn.execute("""
        CREATE TABLE opening_book (
            id INTEGER PRIMARY KEY,
            board_size INTEGER NOT NULL,
            komi REAL NOT NULL,
            moves_sequence TEXT NOT NULL DEFAULT '',
            top_moves TEXT NOT NULL,
            visits INTEGER NOT NULL
        )
    """)
    conn.execute("""
        CREATE TABLE opening_book_meta (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    """)
    return conn


def split_db():
    if not os.path.exists(SOURCE_DB):
        print(f"Error: Source DB not found: {SOURCE_DB}")
        sys.exit(1)

    src = sqlite3.connect(SOURCE_DB)
    src.row_factory = sqlite3.Row

    for board_size in BOARD_SIZES:
        db_name = f'opening_book_{board_size}x{board_size}'
        db_path = os.path.join(OUTPUT_DIR, f'{db_name}.db')
        gz_path = os.path.join(OUTPUT_DIR, f'{db_name}.db.gz')

        print(f"\n=== Splitting board_size={board_size} ===")

        # Count rows
        count = src.execute(
            "SELECT COUNT(*) FROM opening_book WHERE board_size = ?",
            (board_size,)
        ).fetchone()[0]
        print(f"  Rows: {count:,}")

        if count == 0:
            print(f"  Skipping (no data)")
            continue

        # Create target DB and copy data
        target = create_target_db(db_path)

        batch_size = 10000
        offset = 0
        copied = 0

        while True:
            rows = src.execute(
                "SELECT board_size, komi, moves_sequence, top_moves, visits "
                "FROM opening_book WHERE board_size = ? "
                "ORDER BY id LIMIT ? OFFSET ?",
                (board_size, batch_size, offset)
            ).fetchall()

            if not rows:
                break

            target.executemany(
                "INSERT INTO opening_book (board_size, komi, moves_sequence, top_moves, visits) "
                "VALUES (?, ?, ?, ?, ?)",
                [(r['board_size'], r['komi'], r['moves_sequence'], r['top_moves'], r['visits']) for r in rows]
            )
            copied += len(rows)
            offset += batch_size

            if copied % 100000 == 0:
                print(f"  Copied {copied:,} / {count:,}...")

        # Write metadata
        by_board_size = json.dumps({str(board_size): count})
        target.execute(
            "INSERT INTO opening_book_meta (key, value) VALUES (?, ?)",
            ('total_entries', str(count))
        )
        target.execute(
            "INSERT INTO opening_book_meta (key, value) VALUES (?, ?)",
            ('by_board_size', by_board_size)
        )

        target.commit()
        target.close()

        db_size = os.path.getsize(db_path)
        print(f"  DB size: {db_size / 1024 / 1024:.1f} MB")

        # Compress with gzip (streaming)
        print(f"  Compressing to {gz_path}...")
        with open(db_path, 'rb') as f_in:
            with gzip.open(gz_path, 'wb', compresslevel=9) as f_out:
                while True:
                    chunk = f_in.read(64 * 1024)
                    if not chunk:
                        break
                    f_out.write(chunk)

        gz_size = os.path.getsize(gz_path)
        print(f"  Compressed: {gz_size / 1024 / 1024:.1f} MB (ratio: {db_size / gz_size:.1f}x)")

        # Clean up uncompressed DB
        os.remove(db_path)
        print(f"  Removed uncompressed DB")

    src.close()
    print("\n=== Done! ===")

    # Summary
    print("\nGenerated files:")
    for board_size in BOARD_SIZES:
        gz_path = os.path.join(OUTPUT_DIR, f'opening_book_{board_size}x{board_size}.db.gz')
        if os.path.exists(gz_path):
            size = os.path.getsize(gz_path)
            print(f"  {os.path.basename(gz_path)}: {size / 1024 / 1024:.1f} MB")


if __name__ == '__main__':
    split_db()
