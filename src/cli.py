"""
Command-line interface for Go Strategy Analysis Tool.

Usage:
    # Basic analysis
    python -m src.cli --size 19 --moves "B Q16" "W D4" "B Q3"
    
    # With handicap
    python -m src.cli --size 19 --handicap 4 --moves "W E4"
    
    # Custom komi
    python -m src.cli --size 19 --komi 6.5 --moves "B D4"
    
    # Cache stats
    python -m src.cli --stats
    
    # Clear cache
    python -m src.cli --clear-cache
"""

import argparse
import sys
from typing import List, Optional

from .analyzer import GoAnalyzer, format_result
from .config import load_config


def parse_args(args: Optional[List[str]] = None) -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        prog="go-strategy",
        description="Go/Weiqi Strategy Analysis Tool using KataGo",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Analyze opening position
  %(prog)s --size 19 --moves "B Q16" "W D4" "B Q3"
  
  # Handicap game (4 stones)
  %(prog)s --size 19 --handicap 4 --moves "W E4" "B R4"
  
  # 9x9 board
  %(prog)s --size 9 --moves "B E5" "W C3"
  
  # Custom komi
  %(prog)s --size 19 --komi 6.5 --moves "B D4"
  
  # Force re-analysis (ignore cache)
  %(prog)s --size 19 --moves "B Q16" --refresh
  
  # Show cache statistics
  %(prog)s --stats
  
  # Clear cache
  %(prog)s --clear-cache
        """
    )
    
    # Analysis parameters
    parser.add_argument(
        "--size", "-s",
        type=int,
        choices=[9, 13, 19],
        default=19,
        help="Board size (default: 19)"
    )
    
    parser.add_argument(
        "--moves", "-m",
        nargs="+",
        help='Moves in GTP format, e.g., "B Q16" "W D4"'
    )
    
    parser.add_argument(
        "--handicap", "-H",
        type=int,
        default=0,
        choices=range(0, 10),
        metavar="N",
        help="Number of handicap stones (0-9, default: 0)"
    )
    
    parser.add_argument(
        "--komi", "-k",
        type=float,
        default=None,
        help="Komi value (default: 7.5, or 0.5 for handicap games)"
    )
    
    parser.add_argument(
        "--config", "-c",
        type=str,
        default=None,
        help="Path to config.yaml file"
    )
    
    parser.add_argument(
        "--refresh", "-r",
        action="store_true",
        help="Force re-analysis, ignore cache"
    )
    
    # Utility commands
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Show cache statistics"
    )
    
    parser.add_argument(
        "--clear-cache",
        action="store_true",
        help="Clear all cached analyses"
    )
    
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output result as JSON"
    )
    
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Verbose output"
    )
    
    return parser.parse_args(args)


def show_stats(analyzer: GoAnalyzer) -> None:
    """Display cache statistics."""
    stats = analyzer.get_cache_stats()
    
    print("=" * 50)
    print("Cache Statistics")
    print("=" * 50)
    print(f"Total entries: {stats['total_entries']}")
    print(f"Database path: {stats['db_path']}")
    print(f"Database size: {stats['db_size_bytes'] / 1024:.1f} KB")
    
    if stats['by_board_size']:
        print("\nBy board size:")
        for size, count in sorted(stats['by_board_size'].items()):
            print(f"  {size}x{size}: {count}")
    
    if stats['by_model']:
        print("\nBy model:")
        for model, count in stats['by_model'].items():
            print(f"  {model}: {count}")
    
    print("=" * 50)


def clear_cache(analyzer: GoAnalyzer) -> None:
    """Clear the analysis cache."""
    count = analyzer.get_cache_stats()['total_entries']
    
    if count == 0:
        print("Cache is already empty.")
        return
    
    # Confirm
    response = input(f"Clear {count} cached entries? [y/N]: ")
    if response.lower() != 'y':
        print("Cancelled.")
        return
    
    deleted = analyzer.clear_cache()
    print(f"Deleted {deleted} entries.")


def run_analysis(
    analyzer: GoAnalyzer,
    args: argparse.Namespace,
) -> int:
    """Run analysis and display results."""
    moves = args.moves or []
    
    if args.verbose:
        print(f"Board size: {args.size}x{args.size}")
        print(f"Handicap: {args.handicap}")
        print(f"Komi: {args.komi or 'default'}")
        print(f"Moves: {moves}")
        print(f"Force refresh: {args.refresh}")
        print()
    
    try:
        result = analyzer.analyze(
            board_size=args.size,
            moves=moves,
            handicap=args.handicap,
            komi=args.komi,
            force_refresh=args.refresh,
        )
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Analysis failed: {e}", file=sys.stderr)
        return 1
    
    # Output
    if args.json:
        import json
        print(json.dumps(result.to_dict(), indent=2))
    else:
        print(format_result(result))
    
    return 0


def main(args: Optional[List[str]] = None) -> int:
    """Main entry point."""
    parsed = parse_args(args)
    
    # Load config
    try:
        config = load_config(parsed.config)
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        print("Please create a config.yaml file or specify --config path.", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Config error: {e}", file=sys.stderr)
        return 1
    
    # Handle utility commands (don't need KataGo)
    if parsed.stats or parsed.clear_cache:
        analyzer = GoAnalyzer(config=config)
        
        if parsed.stats:
            show_stats(analyzer)
        
        if parsed.clear_cache:
            clear_cache(analyzer)
        
        return 0
    
    # Require moves for analysis
    if not parsed.moves and parsed.handicap == 0:
        print("Error: Please provide --moves or --handicap for analysis.", file=sys.stderr)
        print("Use --help for usage information.", file=sys.stderr)
        return 1
    
    # Run analysis with context manager (ensures cleanup)
    try:
        with GoAnalyzer(config=config) as analyzer:
            return run_analysis(analyzer, parsed)
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
