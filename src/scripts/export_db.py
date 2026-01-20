
import sys
import sqlite3
import shutil
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from src.config import load_config, get_db_path

def export_db():
    print("Exporting database to SQL seed file...")
    
    # Load config to find DB
    try:
        config = load_config()
        db_path = get_db_path(config)
    except Exception as e:
        print(f"Error loading config: {e}")
        return
        
    if not db_path.exists():
        print(f"Database not found at {db_path}. Nothing to export.")
        return

    # Define output path
    assets_dir = project_root / "src" / "assets"
    assets_dir.mkdir(parents=True, exist_ok=True)
    seed_file = assets_dir / "seed_data.sql"
    
    print(f"Source DB: {db_path}")
    print(f"Target SQL: {seed_file}")

    try:
        # Connect to DB
        conn = sqlite3.connect(db_path)
        
        # Open output file
        with open(seed_file, 'w', encoding='utf-8') as f:
            # Iterate through lines and write to file
            for line in conn.iterdump():
                f.write('%s\n' % line)
                
        print("Export successful!")
        
        # Verify size
        size = seed_file.stat().st_size
        print(f"Seed file size: {size / 1024:.2f} KB")
        
    except sqlite3.Error as e:
        print(f"SQLite error: {e}")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        if 'conn' in locals():
            conn.close()

if __name__ == "__main__":
    export_db()
