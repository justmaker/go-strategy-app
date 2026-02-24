import unittest
from unittest.mock import MagicMock, patch
import tempfile
import shutil
import os
import sys
from pathlib import Path
import pytest

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.analyzer import GoAnalyzer, CacheMissError
from src.board import BoardState, create_board
from src.cache import AnalysisResult, MoveCandidate
from src.config import AppConfig, KataGoConfig, DatabaseConfig

class TestAnalyzerEmptyBoard(unittest.TestCase):
    def setUp(self):
        # Create a temp directory for the database
        self.test_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.test_dir, "test.db")

        # Mock config
        self.config = AppConfig(
            katago=KataGoConfig(katago_path="dummy", model_path="dummy", config_path="dummy"),
            database=DatabaseConfig(path=self.db_path)
        )

        # Patch ensure_db_seeded to avoid side effects
        patcher = patch('src.analyzer.ensure_db_seeded')
        self.mock_ensure_seeded = patcher.start()
        self.addCleanup(patcher.stop)

        # Initialize analyzer in cache_only mode
        self.analyzer = GoAnalyzer(config=self.config, cache_only=True)

    def tearDown(self):
        shutil.rmtree(self.test_dir)

    def test_add_candidates_empty_9x9(self):
        """Test adding candidates for empty 9x9 board."""
        board = BoardState(size=9)

        # Initial candidates (just Tengen)
        initial_moves = [
            MoveCandidate(move="E5", winrate=0.47, score_lead=0.0, visits=100)
        ]

        result = AnalysisResult(
            board_hash="hash",
            board_size=9,
            komi=7.5,
            moves_sequence="",
            top_moves=initial_moves,
            engine_visits=100,
            model_name="test_model"
        )

        self.analyzer._add_empty_board_candidates(result, board)

        # Expect E5, C3, C7
        # C3: score penalty -1.0, winrate drop 0.02 -> score -1.0, wr 0.45
        # C7: score penalty -4.0, winrate drop 0.07 -> score -4.0, wr 0.40

        self.assertEqual(len(result.top_moves), 3)
        moves = {m.move: m for m in result.top_moves}

        self.assertIn("E5", moves)
        self.assertIn("C3", moves)
        self.assertIn("C7", moves)

        self.assertAlmostEqual(moves["C3"].score_lead, -1.0)
        self.assertAlmostEqual(moves["C3"].winrate, 0.45)

        self.assertAlmostEqual(moves["C7"].score_lead, -4.0)
        self.assertAlmostEqual(moves["C7"].winrate, 0.40)

    def test_add_candidates_empty_13x13(self):
        """Test adding candidates for empty 13x13 board."""
        board = BoardState(size=13)

        # Initial candidates (just Star point)
        initial_moves = [
            MoveCandidate(move="D4", winrate=0.47, score_lead=0.0, visits=100)
        ]

        result = AnalysisResult(
            board_hash="hash",
            board_size=13,
            komi=7.5,
            moves_sequence="",
            top_moves=initial_moves,
            engine_visits=100,
            model_name="test_model"
        )

        self.analyzer._add_empty_board_candidates(result, board)

        # Expect D4, D3, C3
        # D3: score penalty -1.5, winrate drop 0.02
        # C3: score penalty -5.0, winrate drop 0.07

        self.assertEqual(len(result.top_moves), 3)
        moves = {m.move: m for m in result.top_moves}

        self.assertIn("D4", moves)
        self.assertIn("D3", moves)
        self.assertIn("C3", moves)

        self.assertAlmostEqual(moves["D3"].score_lead, -1.5)
        self.assertAlmostEqual(moves["C3"].score_lead, -5.0)

    def test_add_candidates_empty_19x19(self):
        """Test adding candidates for empty 19x19 board."""
        board = BoardState(size=19)

        # Initial candidates (just Star point)
        initial_moves = [
            MoveCandidate(move="D4", winrate=0.47, score_lead=0.0, visits=100)
        ]

        result = AnalysisResult(
            board_hash="hash",
            board_size=19,
            komi=7.5,
            moves_sequence="",
            top_moves=initial_moves,
            engine_visits=100,
            model_name="test_model"
        )

        self.analyzer._add_empty_board_candidates(result, board)

        # Expect D4, D3, C3
        # D3: score penalty -2.0, winrate drop 0.02
        # C3: score penalty -6.0, winrate drop 0.07

        self.assertEqual(len(result.top_moves), 3)
        moves = {m.move: m for m in result.top_moves}

        self.assertIn("D4", moves)
        self.assertIn("D3", moves)
        self.assertIn("C3", moves)

        self.assertAlmostEqual(moves["D3"].score_lead, -2.0)
        self.assertAlmostEqual(moves["C3"].score_lead, -6.0)

    def test_non_empty_board(self):
        """Test that nothing is added if board is not empty."""
        board = BoardState(size=19)
        board.play("B", "Q16")

        initial_moves = [
            MoveCandidate(move="D4", winrate=0.47, score_lead=0.0, visits=100)
        ]

        result = AnalysisResult(
            board_hash="hash",
            board_size=19,
            komi=7.5,
            moves_sequence="B[Q16]",
            top_moves=list(initial_moves), # copy
            engine_visits=100,
            model_name="test_model"
        )

        self.analyzer._add_empty_board_candidates(result, board)

        self.assertEqual(len(result.top_moves), 1)
        self.assertEqual(result.top_moves[0].move, "D4")

    def test_already_diverse(self):
        """Test that nothing is added if existing candidates are diverse enough."""
        board = BoardState(size=19)

        # 3 moves with different scores
        initial_moves = [
            MoveCandidate(move="D4", winrate=0.47, score_lead=0.0, visits=100),
            MoveCandidate(move="D3", winrate=0.45, score_lead=-2.0, visits=50),
            MoveCandidate(move="C3", winrate=0.40, score_lead=-6.0, visits=20),
        ]

        result = AnalysisResult(
            board_hash="hash",
            board_size=19,
            komi=7.5,
            moves_sequence="",
            top_moves=list(initial_moves),
            engine_visits=100,
            model_name="test_model"
        )

        self.analyzer._add_empty_board_candidates(result, board)

        self.assertEqual(len(result.top_moves), 3)

    def test_partial_existing(self):
        """Test adding missing candidates when some already exist."""
        board = BoardState(size=19)

        # D4 and D3 exist, but C3 is missing.
        # Note: scores must be distinct enough to count as groups.
        initial_moves = [
            MoveCandidate(move="D4", winrate=0.47, score_lead=0.0, visits=100),
            MoveCandidate(move="D3", winrate=0.45, score_lead=-2.0, visits=50),
        ]

        result = AnalysisResult(
            board_hash="hash",
            board_size=19,
            komi=7.5,
            moves_sequence="",
            top_moves=list(initial_moves),
            engine_visits=100,
            model_name="test_model"
        )

        self.analyzer._add_empty_board_candidates(result, board)

        self.assertEqual(len(result.top_moves), 3)
        moves = {m.move: m for m in result.top_moves}

        self.assertIn("D4", moves)
        self.assertIn("D3", moves)
        self.assertIn("C3", moves)

        # Verify D3 wasn't overwritten (visits should be 50)
        self.assertEqual(moves["D3"].visits, 50)

        # Verify C3 is the added one (visits=1)
        self.assertEqual(moves["C3"].visits, 1)

    def test_duplicate_check_by_coord(self):
        """Test that duplicate coordinates are avoided even if scores differ."""
        board = BoardState(size=19)

        # D4 exists. D3 exists but with different score than expected?
        # The logic checks: if coord.upper() in existing_coords: continue

        initial_moves = [
            MoveCandidate(move="D4", winrate=0.47, score_lead=0.0, visits=100),
            MoveCandidate(move="D3", winrate=0.45, score_lead=-1.0, visits=50), # Score -1.0, expected -2.0
        ]

        result = AnalysisResult(
            board_hash="hash",
            board_size=19,
            komi=7.5,
            moves_sequence="",
            top_moves=list(initial_moves),
            engine_visits=100,
            model_name="test_model"
        )

        self.analyzer._add_empty_board_candidates(result, board)

        # Should add C3, but NOT D3 again
        moves = {m.move: m for m in result.top_moves}

        self.assertIn("D3", moves)
        # Count occurrences of D3
        d3_count = sum(1 for m in result.top_moves if m.move == "D3")
        self.assertEqual(d3_count, 1)
        self.assertEqual(moves["D3"].score_lead, -1.0) # The existing one kept

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

if __name__ == "__main__":
    unittest.main()
