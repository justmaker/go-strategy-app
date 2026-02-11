"""
Unit tests for the FastAPI REST API.

Tests:
- Health check endpoint
- Analyze endpoint with valid/invalid requests
- Query endpoint with valid/invalid requests
- Stats endpoint
- Error response handling
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from fastapi.testclient import TestClient

from src.cache import AnalysisResult, MoveCandidate


# --- Fixtures ---


@pytest.fixture
def sample_analysis_result():
    """Create a sample AnalysisResult for mocking."""
    return AnalysisResult(
        board_hash="abc123def456",
        board_size=19,
        komi=7.5,
        moves_sequence="B[Q16];W[D4]",
        top_moves=[
            MoveCandidate(move="Q3", winrate=0.523, score_lead=0.31, visits=45),
            MoveCandidate(move="R4", winrate=0.518, score_lead=0.28, visits=38),
        ],
        engine_visits=150,
        model_name="kata1-b18c384",
        from_cache=False,
        timestamp="2024-01-01T00:00:00",
    )


@pytest.fixture
def mock_analyzer(sample_analysis_result):
    """Create a mock GoAnalyzer."""
    analyzer = MagicMock()
    analyzer.cache = MagicMock()
    analyzer.cache.count.return_value = 100
    analyzer.is_running.return_value = True
    analyzer.cache_only = False
    analyzer.analyze.return_value = sample_analysis_result
    analyzer.get_cache_stats.return_value = {
        "total_entries": 100,
        "by_board_size": {9: 20, 13: 30, 19: 50},
        "by_model": {"kata1-b18c384": 100},
        "db_size_bytes": 1024000,
        "db_path": "data/analysis.db",
    }
    return analyzer


@pytest.fixture
def client(mock_analyzer):
    """Create a test client with mocked analyzer (bypass lifespan)."""
    from src.api import app, state

    state.analyzer = mock_analyzer
    return TestClient(app, raise_server_exceptions=False)


# --- Health Endpoint ---


class TestHealthEndpoint:
    """Tests for GET /health."""

    def test_health_returns_ok(self, client):
        """Test health check returns status ok."""
        response = client.get("/health")
        assert response.status_code == 200

        data = response.json()
        assert data["status"] == "ok"
        assert data["cache_entries"] == 100
        assert data["katago_running"] is True
        assert data["cache_only_mode"] is False

    def test_health_cache_only_mode(self, client, mock_analyzer):
        """Test health check in cache-only mode."""
        mock_analyzer.is_running.return_value = False
        mock_analyzer.cache_only = True

        response = client.get("/health")
        data = response.json()

        assert data["katago_running"] is False
        assert data["cache_only_mode"] is True


# --- Analyze Endpoint ---


class TestAnalyzeEndpoint:
    """Tests for POST /analyze."""

    def test_analyze_valid_request(self, client):
        """Test analyze with valid request."""
        response = client.post("/analyze", json={
            "board_size": 19,
            "moves": ["B Q16", "W D4"],
            "komi": 7.5,
        })
        assert response.status_code == 200

        data = response.json()
        assert data["board_hash"] == "abc123def456"
        assert data["board_size"] == 19
        assert data["komi"] == 7.5
        assert len(data["top_moves"]) == 2
        assert data["top_moves"][0]["move"] == "Q3"

    def test_analyze_empty_board(self, client):
        """Test analyze with empty board (no moves)."""
        response = client.post("/analyze", json={
            "board_size": 19,
        })
        assert response.status_code == 200

    def test_analyze_9x9(self, client):
        """Test analyze with 9x9 board."""
        response = client.post("/analyze", json={
            "board_size": 9,
            "moves": ["B E5"],
            "komi": 6.5,
        })
        assert response.status_code == 200

    def test_analyze_invalid_board_size(self, client):
        """Test analyze with invalid board size returns 422 (Literal validation)."""
        response = client.post("/analyze", json={
            "board_size": 15,
            "moves": [],
        })
        assert response.status_code == 422

    def test_analyze_invalid_move_format(self, client):
        """Test analyze with invalid move format returns 422 (field_validator)."""
        response = client.post("/analyze", json={
            "board_size": 19,
            "moves": ["INVALID"],
        })
        assert response.status_code == 422
        assert "Invalid move format" in response.json()["detail"][0]["msg"]

    def test_analyze_value_error_from_engine(self, client, mock_analyzer):
        """Test analyze returns 400 on ValueError from analyzer engine."""
        mock_analyzer.analyze.side_effect = ValueError("Bad position state")

        response = client.post("/analyze", json={
            "board_size": 19,
            "moves": ["B Q16"],
        })
        assert response.status_code == 400
        assert "Bad position state" in response.json()["detail"]

    def test_analyze_cache_miss_error(self, client, mock_analyzer):
        """Test analyze returns 404 on CacheMissError (cache-only mode)."""
        from src.analyzer import CacheMissError

        mock_analyzer.analyze.side_effect = CacheMissError("Not in cache")

        response = client.post("/analyze", json={
            "board_size": 19,
            "moves": ["B Q16"],
        })
        assert response.status_code == 404
        assert "cache" in response.json()["detail"].lower()

    def test_analyze_internal_error(self, client, mock_analyzer):
        """Test analyze returns 500 on unexpected error."""
        mock_analyzer.analyze.side_effect = RuntimeError("Engine crashed")

        response = client.post("/analyze", json={
            "board_size": 19,
            "moves": ["B Q16"],
        })
        assert response.status_code == 500
        assert "Analysis failed" in response.json()["detail"]

    def test_analyze_with_handicap(self, client):
        """Test analyze with handicap stones."""
        response = client.post("/analyze", json={
            "board_size": 19,
            "handicap": 4,
            "moves": ["W E4"],
        })
        assert response.status_code == 200

    def test_analyze_with_force_refresh(self, client, mock_analyzer):
        """Test analyze passes force_refresh to analyzer."""
        response = client.post("/analyze", json={
            "board_size": 19,
            "moves": [],
            "force_refresh": True,
        })
        assert response.status_code == 200
        # Verify force_refresh was passed
        mock_analyzer.analyze.assert_called_once()
        call_kwargs = mock_analyzer.analyze.call_args
        assert call_kwargs.kwargs.get("force_refresh") is True


# --- Query Endpoint ---


class TestQueryEndpoint:
    """Tests for POST /query."""

    def test_query_cache_miss(self, client, mock_analyzer):
        """Test query returns found=False when not in cache."""
        mock_analyzer.cache.get.return_value = None

        response = client.post("/query", json={
            "board_size": 19,
            "moves": ["B Q16"],
            "komi": 7.5,
        })
        assert response.status_code == 200

        data = response.json()
        assert data["found"] is False
        assert data["result"] is None

    def test_query_cache_hit(self, client, mock_analyzer, sample_analysis_result):
        """Test query returns found=True with cached result."""
        mock_analyzer.cache.get.return_value = sample_analysis_result

        response = client.post("/query", json={
            "board_size": 19,
            "moves": ["B Q16", "W D4"],
            "komi": 7.5,
        })
        assert response.status_code == 200

        data = response.json()
        assert data["found"] is True
        assert data["result"] is not None
        assert data["result"]["from_cache"] is True

    def test_query_invalid_request(self, client, mock_analyzer):
        """Test query returns 400 on ValueError."""
        mock_analyzer.cache.get.side_effect = ValueError("Bad input")

        # The ValueError comes from board creation, we need to patch create_board
        with patch("src.api.create_board", side_effect=ValueError("Invalid board size")):
            response = client.post("/query", json={
                "board_size": 19,
                "moves": [],
            })
            assert response.status_code == 400


# --- Stats Endpoint ---


class TestStatsEndpoint:
    """Tests for GET /stats."""

    def test_stats_returns_data(self, client):
        """Test stats returns cache statistics."""
        response = client.get("/stats")
        assert response.status_code == 200

        data = response.json()
        assert data["total_entries"] == 100
        assert data["by_board_size"]["9"] == 20
        assert data["by_board_size"]["19"] == 50


# --- Pydantic Validation ---


class TestPydanticValidation:
    """Tests for request/response model validation."""

    def test_analyze_request_defaults(self, client):
        """Test AnalyzeRequest uses correct defaults."""
        response = client.post("/analyze", json={})
        assert response.status_code == 200

    def test_analyze_request_board_size_range(self, client):
        """Test board_size must be between 9 and 19."""
        response = client.post("/analyze", json={"board_size": 3})
        assert response.status_code == 422  # Pydantic validation error

        response = client.post("/analyze", json={"board_size": 25})
        assert response.status_code == 422

    def test_analyze_request_negative_handicap(self, client):
        """Test handicap cannot be negative."""
        response = client.post("/analyze", json={"handicap": -1})
        assert response.status_code == 422

    def test_analyze_request_handicap_too_large(self, client):
        """Test handicap cannot exceed 9."""
        response = client.post("/analyze", json={"handicap": 10})
        assert response.status_code == 422


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
