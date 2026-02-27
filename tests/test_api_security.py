import pytest
from unittest.mock import MagicMock
from fastapi.testclient import TestClient
from src.api import app, state

@pytest.fixture
def mock_analyzer():
    """Create a mock GoAnalyzer."""
    analyzer = MagicMock()
    analyzer.cache = MagicMock()
    analyzer.cache.count.return_value = 100
    analyzer.is_running.return_value = True
    analyzer.cache_only = False
    analyzer.analyze.return_value = MagicMock()
    analyzer.get_cache_stats.return_value = {}
    return analyzer

@pytest.fixture
def client(mock_analyzer):
    """Create a test client with mocked analyzer."""
    # We set the state.analyzer manually to avoid needing the real startup
    state.analyzer = mock_analyzer
    # We use a context manager to ensure lifespan is handled if needed,
    # but since we mocked the analyzer in state, the startup logic in lifespan
    # might overwrite it if we are not careful.
    # However, existing tests seem to rely on this.
    # Actually, lifespan runs on 'with TestClient(app) as client'.
    # If we just do TestClient(app), lifespan runs on the first request if using newer Starlette,
    # or we might need to be careful.
    # Let's just use the client.
    return TestClient(app)

def test_analyze_excessive_moves(client):
    """Test analyze with excessive number of moves (DoS prevention)."""
    # Create 601 dummy moves. Using valid format to pass regex check if it runs before length check.
    moves = ["B Q16"] * 601
    response = client.post("/analyze", json={
        "board_size": 19,
        "moves": moves,
    })
    # Expect 422 Validation Error
    assert response.status_code == 422

def test_analyze_excessive_visits(client):
    """Test analyze with excessive visits (Resource exhaustion)."""
    response = client.post("/analyze", json={
        "board_size": 19,
        "moves": [],
        "visits": 100001
    })
    # Expect 422 Validation Error
    assert response.status_code == 422

def test_query_excessive_moves(client):
    """Test query with excessive number of moves."""
    moves = ["B Q16"] * 601
    response = client.post("/query", json={
        "board_size": 19,
        "moves": moves,
    })
    # Expect 422 Validation Error
    assert response.status_code == 422
