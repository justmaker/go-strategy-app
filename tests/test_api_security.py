"""
Security tests for the FastAPI REST API.

Tests:
- Input validation for unbounded parameters (AnalyzeRequest, QueryRequest)
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import MagicMock

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from fastapi.testclient import TestClient
from src.api import app, state


# --- Constants ---

MAX_MOVES = 600
MAX_VISITS = 100000


# --- Fixtures ---

@pytest.fixture
def mock_analyzer():
    """Create a mock GoAnalyzer."""
    analyzer = MagicMock()
    analyzer.cache = MagicMock()
    analyzer.cache.count.return_value = 100
    analyzer.is_running.return_value = True
    analyzer.cache_only = False
    analyzer.analyze.return_value = MagicMock()  # Mock analysis result
    return analyzer


@pytest.fixture
def client(mock_analyzer):
    """Create a test client with mocked analyzer."""
    # We need to make sure state.analyzer is set to our mock.
    # Note: TestClient(app) might trigger lifespan which overwrites state.analyzer.
    # However, for these tests, we primarily care about Pydantic validation which happens BEFORE
    # the endpoint logic (and thus before state.analyzer is used).
    state.analyzer = mock_analyzer
    return TestClient(app, raise_server_exceptions=False)


# --- Security Tests ---

class TestAnalyzeSecurity:
    """Security tests for POST /analyze."""

    def test_analyze_excessive_moves(self, client):
        """Test analyze with moves list exceeding limit returns 422."""
        moves = ["B Q16"] * (MAX_MOVES + 1)
        response = client.post("/analyze", json={
            "board_size": 19,
            "moves": moves,
        })
        assert response.status_code == 422
        # Ensure the error is about the length
        assert "List should have at most" in str(response.json()) or "length" in str(response.json())

    def test_analyze_excessive_visits(self, client):
        """Test analyze with visits exceeding limit returns 422."""
        response = client.post("/analyze", json={
            "board_size": 19,
            "moves": ["B Q16"],
            "visits": MAX_VISITS + 1,
        })
        assert response.status_code == 422
        # Ensure the error is about the value
        assert "Input should be less than or equal to" in str(response.json()) or "le" in str(response.json())

    def test_analyze_valid_limits(self, client):
        """Test analyze with valid limits passes validation."""
        # This test ensures we didn't break valid requests
        response = client.post("/analyze", json={
            "board_size": 19,
            "moves": ["B Q16"] * MAX_MOVES,
            "visits": MAX_VISITS,
        })
        # Validation should pass (so not 422).
        # Application might return 400 due to invalid game logic (same move twice)
        # or 500 if the mock isn't working as expected, but as long as it's not 422,
        # the Pydantic validation allowed the input.
        assert response.status_code != 422


class TestQuerySecurity:
    """Security tests for POST /query."""

    def test_query_excessive_moves(self, client):
        """Test query with moves list exceeding limit returns 422."""
        moves = ["B Q16"] * (MAX_MOVES + 1)
        response = client.post("/query", json={
            "board_size": 19,
            "moves": moves,
        })
        assert response.status_code == 422
