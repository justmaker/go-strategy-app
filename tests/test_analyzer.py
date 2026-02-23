
import pytest
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.analyzer import GoAnalyzer, CacheMissError

class TestGoAnalyzerValidation:
    @pytest.fixture
    def analyzer(self):
        """Create a GoAnalyzer in cache-only mode to avoid starting KataGo."""
        with patch("src.analyzer.ensure_db_seeded"):
            with patch("src.analyzer.load_config"):
                with patch("src.analyzer.AnalysisCache") as mock_cache_cls:
                    mock_cache = MagicMock()
                    mock_cache_cls.return_value = mock_cache
                    # Setup cache to return None (miss) by default
                    mock_cache.get.return_value = None

                    analyzer = GoAnalyzer(cache_only=True)
                    return analyzer

    def test_analyze_invalid_board_size(self, analyzer):
        """Test that analyze raises ValueError for invalid board size."""
        with pytest.raises(ValueError, match="Board size must be 9, 13, or 19, got 10"):
            analyzer.analyze(board_size=10)

        with pytest.raises(ValueError, match="Board size must be 9, 13, or 19, got 8"):
            analyzer.analyze(board_size=8)

        with pytest.raises(ValueError, match="Board size must be 9, 13, or 19, got 20"):
            analyzer.analyze(board_size=20)

    def test_analyze_invalid_handicap_negative(self, analyzer):
        """Test that analyze raises ValueError for negative handicap."""
        with pytest.raises(ValueError, match="Handicap must be 0-9, got -1"):
            analyzer.analyze(board_size=19, handicap=-1)

    def test_analyze_invalid_handicap_too_large(self, analyzer):
        """Test that analyze raises ValueError for handicap > 9."""
        with pytest.raises(ValueError, match="Handicap must be 0-9, got 10"):
            analyzer.analyze(board_size=19, handicap=10)

    def test_analyze_valid_inputs(self, analyzer):
        """Test that analyze works with valid inputs (raising CacheMissError means validation passed)."""
        # We expect CacheMissError because we mocked cache.get to return None
        # and we are in cache_only=True mode.
        with pytest.raises(CacheMissError):
            analyzer.analyze(board_size=19, handicap=0)

        with pytest.raises(CacheMissError):
            analyzer.analyze(board_size=13, handicap=9)

        with pytest.raises(CacheMissError):
            analyzer.analyze(board_size=9, handicap=2)
