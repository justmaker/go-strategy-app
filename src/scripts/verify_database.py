#!/usr/bin/env python3
"""
Verify and clean up the analysis database.
Checks for consistency, low visit counts, and provides a summary.
"""

import sys
import os
from pathlib import Path

# Add src to path
sys.path.insert(0, os.getcwd())

from src.cache import AnalysisCache
from src.config import load_config

def main():
    print("=" * 60)
    print("Go Strategy - Database Verification Helper")
    print("=" * 60)
    
    config = load_config()
    cache = AnalysisCache(config)
    stats = cache.get_stats()
    
    print(f"Database Path: {stats['db_path']}")
    print(f"Total Entries: {stats['total_entries']}")
    print(f"File Size:     {stats['db_size_bytes'] / 1024 / 1024:.2f} MB")
    print("-" * 60)
    
    print("Breakdown by Board Size:")
    for size, count in stats['by_board_size'].items():
        print(f"  {size}x{size}: {count} entries")
    
    print("\nVisit Count Distribution (Top 10):")
    # We'll check the most common visit counts
    with cache._get_connection() as conn:
        counts = conn.execute("""
            SELECT engine_visits, COUNT(*) as cnt 
            FROM analysis_cache 
            GROUP BY engine_visits 
            ORDER BY cnt DESC 
            LIMIT 10
        """).fetchall()
        for row in counts:
            print(f"  {row['engine_visits']} visits: {row['cnt']} positions")

    # Check for potential issues
    print("\nHealth Checks:")
    
    # 1. Low visit counts
    threshold = 10
    with cache._get_connection() as conn:
        low_visits = conn.execute(
            "SELECT COUNT(*) FROM analysis_cache WHERE engine_visits < ?", 
            (threshold,)
        ).fetchone()[0]
        
    if low_visits > 0:
        print(f"  [!] Found {low_visits} entries with < {threshold} visits (likely interrupted).")
        print(f"      Recommendation: Run 'DELETE FROM analysis_cache WHERE engine_visits < {threshold}'")
    else:
        print(f"  [OK] No extremely low visit entries found.")

    # 2. Consistent Komi
    with cache._get_connection() as conn:
        komi_counts = conn.execute(
            "SELECT komi, COUNT(*) as cnt FROM analysis_cache GROUP BY komi"
        ).fetchall()
    
    if len(komi_counts) > 1:
        print(f"  [i] Multiple Komi values found in DB:")
        for row in komi_counts:
            print(f"      - Komi {row['komi']}: {row['cnt']} entries")
    else:
        print(f"  [OK] Consistent Komi usage.")

    # 3. Model consistency
    if len(stats['by_model']) > 1:
        print(f"  [i] Multiple KataGo models found in DB:")
        for model, count in stats['by_model'].items():
            print(f"      - {model}: {count} entries")
            
    print("-" * 60)
    print("Verification complete.")

if __name__ == "__main__":
    main()
