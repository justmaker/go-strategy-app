import sys
from pathlib import Path
PROJECT_ROOT = Path(__file__).parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.analyzer import GoAnalyzer

def test():
    print("Initializing GoAnalyzer...")
    analyzer = GoAnalyzer(config_path="config.yaml")
    print("Analyzer ready. Analyzing 9x9 empty board...")
    # This should be a cache hit, but let's see.
    result = analyzer.analyze(board_size=9, moves=None, visits=500)
    print(f"Analysis complete! Source: {'Cache' if result.from_cache else 'Engine'}")
    print(f"Top move: {result.top_moves[0].move if result.top_moves else 'None'}")
    analyzer.shutdown()

if __name__ == "__main__":
    test()
