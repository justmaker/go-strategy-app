"""
Unit tests for katago_gtp.py module.
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import MagicMock

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.katago_gtp import KataGoGTP, KataGoConfig
from src.cache import MoveCandidate

class TestKataGoParsing:
    """Tests for KataGo output parsing."""

    def setup_method(self):
        """Setup mock KataGoGTP instance."""
        config = MagicMock(spec=KataGoConfig)
        # We don't need real paths since we won't start the process
        config.katago_path = "katago"
        config.model_path = "model.bin"
        config.config_path = "config.cfg"
        self.katago = KataGoGTP(config)

    def test_parse_kata_analyze_basic(self):
        """Test parsing a standard kata-analyze output line."""
        line = (
            "info move Q3 visits 45 winrate 0.523445 scoreLead 0.312 prior 0.0892 order 0 pv Q3 R4 Q5 "
            "info move R4 visits 38 winrate 0.518923 scoreLead 0.287 prior 0.0756 order 1 pv R4 Q3 R6"
        )

        candidates = self.katago._parse_kata_analyze_line(line, top_n=3)

        assert len(candidates) == 2

        # Check first move
        c1 = candidates[0]
        assert c1.move == "Q3"
        assert c1.visits == 45
        assert c1.winrate == 0.523445
        assert c1.score_lead == 0.312

        # Check second move
        c2 = candidates[1]
        assert c2.move == "R4"
        assert c2.visits == 38
        assert c2.winrate == 0.518923
        assert c2.score_lead == 0.287

    def test_parse_kata_analyze_top_n(self):
        """Test that top_n limits the results."""
        line = (
            "info move A1 visits 100 winrate 0.5 scoreLead 0.5 "
            "info move A2 visits 90 winrate 0.5 scoreLead 0.5 "
            "info move A3 visits 80 winrate 0.5 scoreLead 0.5"
        )

        candidates = self.katago._parse_kata_analyze_line(line, top_n=2)
        assert len(candidates) == 2
        assert candidates[0].move == "A1"
        assert candidates[1].move == "A2"

    def test_parse_kata_analyze_sorting(self):
        """Test that results are sorted by visits descending."""
        # Note: Input order is deliberately mixed up
        line = (
            "info move A2 visits 10 winrate 0.5 scoreLead 0.5 "
            "info move A1 visits 100 winrate 0.6 scoreLead 1.0"
        )

        candidates = self.katago._parse_kata_analyze_line(line, top_n=2)
        assert len(candidates) == 2
        assert candidates[0].move == "A1"
        assert candidates[0].visits == 100
        assert candidates[1].move == "A2"
        assert candidates[1].visits == 10

    def test_parse_kata_analyze_empty(self):
        """Test parsing an empty or irrelevant line."""
        assert self.katago._parse_kata_analyze_line("", top_n=5) == []
        assert self.katago._parse_kata_analyze_line("some random output", top_n=5) == []

    def test_parse_kata_analyze_missing_score(self):
        """Test parsing when scoreLead is missing (should default to 0.0)."""
        line = "info move Q3 visits 45 winrate 0.523445 prior 0.0892 order 0 pv Q3"

        candidates = self.katago._parse_kata_analyze_line(line, top_n=1)
        assert len(candidates) == 1
        assert candidates[0].score_lead == 0.0

    def test_parse_kata_analyze_malformed(self):
        """Test parsing lines with malformed numbers."""
        line = (
            "info move Q3 visits not_a_number winrate 0.5 scoreLead 0.5 "
            "info move R4 visits 50 winrate not_a_number scoreLead 0.5 "
            "info move D4 visits 100 winrate 0.6 scoreLead 1.0"
        )

        candidates = self.katago._parse_kata_analyze_line(line, top_n=3)
        # Should skip malformed entries and parse the valid one
        assert len(candidates) == 1
        assert candidates[0].move == "D4"

    def test_parse_kata_analyze_negative_values(self):
        """Test parsing negative scoreLead."""
        line = "info move Q3 visits 45 winrate 0.4 scoreLead -1.5"

        candidates = self.katago._parse_kata_analyze_line(line, top_n=1)
        assert len(candidates) == 1
        assert candidates[0].score_lead == -1.5

    def test_parse_kata_analyze_pass(self):
        """Test parsing 'PASS' move."""
        line = "info move PASS visits 100 winrate 0.1 scoreLead -5.0"

        candidates = self.katago._parse_kata_analyze_line(line, top_n=1)
        assert len(candidates) == 1
        assert candidates[0].move == "PASS"

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
