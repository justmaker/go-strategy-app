"""
Database utilities for Go Strategy Analysis Tool.

Provides database seeding and initialization functions.
"""

import sqlite3
from pathlib import Path
from typing import Optional

from .config import AppConfig, load_config, get_db_path


def ensure_db_seeded(config: Optional[AppConfig] = None) -> bool:
    """
    Ensure the database exists and is seeded with initial data if needed.
    
    This function checks if the SQLite database file exists. If it doesn't,
    it looks for seed_data.sql and imports it to bootstrap the database
    with pre-calculated analysis results.
    
    Args:
        config: Application configuration. If None, loads from config.yaml.
        
    Returns:
        True if database was seeded, False if it already existed.
    """
    if config is None:
        config = load_config()
    
    db_path = get_db_path(config)
    seed_path = Path(__file__).parent / "assets" / "seed_data.sql"
    
    # Check if database already exists and has data
    if db_path.exists() and db_path.stat().st_size > 0:
        # Database exists, no seeding needed
        return False
    
    # Database doesn't exist or is empty - check for seed file
    if not seed_path.exists():
        print(f"No seed file found at {seed_path}")
        return False
    
    # Ensure parent directory exists
    db_path.parent.mkdir(parents=True, exist_ok=True)
    
    print(f"Seeding database from {seed_path}...")
    
    try:
        # Read seed SQL
        with open(seed_path, 'r', encoding='utf-8') as f:
            seed_sql = f.read()
        
        # Connect and execute seed script
        conn = sqlite3.connect(str(db_path))
        try:
            conn.executescript(seed_sql)
            conn.commit()
            
            # Count entries
            cursor = conn.execute("SELECT COUNT(*) FROM analysis_cache")
            count = cursor.fetchone()[0]
            
            print(f"Database seeded from SQL. ({count} entries)")
            return True
            
        finally:
            conn.close()
            
    except Exception as e:
        print(f"Failed to seed database: {e}")
        return False


def get_db_stats(config: Optional[AppConfig] = None) -> dict:
    """
    Get basic statistics about the database.
    
    Args:
        config: Application configuration. If None, loads from config.yaml.
        
    Returns:
        Dictionary with database statistics.
    """
    if config is None:
        config = load_config()
    
    db_path = get_db_path(config)
    
    if not db_path.exists():
        return {
            'exists': False,
            'path': str(db_path),
            'size_bytes': 0,
            'entry_count': 0,
        }
    
    conn = sqlite3.connect(str(db_path))
    try:
        cursor = conn.execute("SELECT COUNT(*) FROM analysis_cache")
        count = cursor.fetchone()[0]
    except sqlite3.OperationalError:
        count = 0
    finally:
        conn.close()
    
    return {
        'exists': True,
        'path': str(db_path),
        'size_bytes': db_path.stat().st_size,
        'entry_count': count,
    }
