"""
Unit tests for katago_gtp.py module.
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import MagicMock

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.katago_gtp import KataGoGTP
from src.config import KataGoConfig
from src.cache import MoveCandidate


class TestParseKataAnalyzeLine:
    """Tests for _parse_kata_analyze_line method."""

    @pytest.fixture
    def katago(self):
        """Create a KataGoGTP instance with dummy config."""
        config = KataGoConfig(
            katago_path="/tmp/katago",
            model_path="/tmp/model.bin.gz",
            config_path="/tmp/config.cfg"
        )
        # We don't need to start the process for testing parsing
        return KataGoGTP(config)

    def test_parse_happy_path(self, katago):
        """Test parsing a standard valid output line."""
        line = (
            "info move Q3 visits 45 winrate 0.523445 scoreLead 0.312 prior 0.0892 order 0 pv Q3 R4 Q5 "
            "info move R4 visits 38 winrate 0.518923 scoreLead 0.287 prior 0.0756 order 1 pv R4 Q3 R6"
        )
        moves = katago._parse_kata_analyze_line(line, top_n=3)

        assert len(moves) == 2

        # Check first move (sorted by visits desc)
        m1 = moves[0]
        assert m1.move == "Q3"
        assert m1.visits == 45
        assert m1.winrate == 0.523445
        assert m1.score_lead == 0.312

        # Check second move
        m2 = moves[1]
        assert m2.move == "R4"
        assert m2.visits == 38
        assert m2.winrate == 0.518923
        assert m2.score_lead == 0.287

    def test_parse_malformed_numbers(self, katago):
        """Test parsing with non-numeric values where numbers are expected."""
        # First move has invalid winrate, second has invalid visits
        line = (
            "info move Q3 visits 45 winrate GARBAGE scoreLead 0.312 "
            "info move R4 visits NANA winrate 0.518923 scoreLead 0.287 "
            "info move D4 visits 10 winrate 0.4 scoreLead 0.1"
        )
        moves = katago._parse_kata_analyze_line(line, top_n=3)

        # Should only parse the valid move (D4)
        assert len(moves) == 1
        assert moves[0].move == "D4"
        assert moves[0].visits == 10

    def test_parse_missing_fields(self, katago):
        """Test parsing lines with missing required fields."""
        # Missing winrate
        line1 = "info move Q3 visits 45 scoreLead 0.312"
        moves1 = katago._parse_kata_analyze_line(line1, top_n=3)
        assert len(moves1) == 0

        # Missing visits
        line2 = "info move Q3 winrate 0.523 scoreLead 0.312"
        moves2 = katago._parse_kata_analyze_line(line2, top_n=3)
        assert len(moves2) == 0

    def test_parse_optional_score_lead(self, katago):
        """Test that scoreLead is optional (should default to 0.0)."""
        line = "info move Q3 visits 45 winrate 0.523445"
        moves = katago._parse_kata_analyze_line(line, top_n=3)

        assert len(moves) == 1
        assert moves[0].move == "Q3"
        assert moves[0].visits == 45
        assert moves[0].winrate == 0.523445
        assert moves[0].score_lead == 0.0

    def test_parse_empty_and_garbage(self, katago):
        """Test parsing empty or garbage strings."""
        assert katago._parse_kata_analyze_line("", top_n=3) == []
        assert katago._parse_kata_analyze_line("   ", top_n=3) == []
        assert katago._parse_kata_analyze_line("random garbage string", top_n=3) == []
        assert katago._parse_kata_analyze_line("info move", top_n=3) == []  # missing everything else

    def test_parse_sort_order(self, katago):
        """Test that moves are sorted by visits descending."""
        # Input order: 10 visits, 50 visits, 30 visits
        line = (
            "info move A1 visits 10 winrate 0.4 scoreLead 0.1 "
            "info move B2 visits 50 winrate 0.6 scoreLead 0.5 "
            "info move C3 visits 30 winrate 0.5 scoreLead 0.3"
        )
        moves = katago._parse_kata_analyze_line(line, top_n=3)

        assert len(moves) == 3
        assert moves[0].move == "B2"
        assert moves[0].visits == 50
        assert moves[1].move == "C3"
        assert moves[1].visits == 30
        assert moves[2].move == "A1"
        assert moves[2].visits == 10

    def test_parse_top_n(self, katago):
        """Test that only top N moves are returned."""
        line = (
            "info move A1 visits 10 winrate 0.4 scoreLead 0.1 "
            "info move B2 visits 50 winrate 0.6 scoreLead 0.5 "
            "info move C3 visits 30 winrate 0.5 scoreLead 0.3"
        )
        moves = katago._parse_kata_analyze_line(line, top_n=2)

        assert len(moves) == 2
        assert moves[0].move == "B2"
        assert moves[1].move == "C3"

    def test_parse_edge_case_values(self, katago):
        """Test edge case values like 0 or negative numbers."""
        line = (
            "info move Q3 visits 0 winrate 0.0 scoreLead -10.5 "
            "info move R4 visits 100 winrate 1.0 scoreLead 15.0"
        )
        moves = katago._parse_kata_analyze_line(line, top_n=3)

        assert len(moves) == 2
        # R4 should be first because more visits
        assert moves[0].move == "R4"
        assert moves[0].visits == 100
        assert moves[0].winrate == 1.0
        assert moves[0].score_lead == 15.0

        assert moves[1].move == "Q3"
        assert moves[1].visits == 0
        assert moves[1].winrate == 0.0
        assert moves[1].score_lead == -10.5

    def test_parse_partial_failure(self, katago):
        """Test line with mixed valid and invalid moves."""
        line = (
            "info move A1 visits 10 winrate 0.4 scoreLead 0.1 "
            "info move B2 visits INVALID winrate 0.6 scoreLead 0.5 "
            "info move C3 visits 30 winrate 0.5 scoreLead 0.3"
        )
        moves = katago._parse_kata_analyze_line(line, top_n=3)

        assert len(moves) == 2
        assert moves[0].move == "C3"  # 30 visits
        assert moves[1].move == "A1"  # 10 visits

    def test_parse_scientific_notation(self, katago):
        """Test parsing scientific notation if KataGo ever outputs it."""
        # Python float() handles scientific notation (e.g., 1e-5)
        line = "info move Q3 visits 100 winrate 1.5e-2 scoreLead -1.2e1"
        moves = katago._parse_kata_analyze_line(line, top_n=1)

        assert len(moves) == 1
        assert moves[0].winrate == 0.015
        assert moves[0].score_lead == -12.0


