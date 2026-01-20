"""
Unit tests for cache.py module.

Tests:
- AnalysisCache CRUD operations
- MoveCandidate and AnalysisResult data classes
- Cache statistics
"""

import json
import os
import tempfile
import pytest
import sys
from pathlib import Path

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.cache import (
    AnalysisCache,
    AnalysisResult,
    MoveCandidate,
)


@pytest.fixture
def temp_db():
    """Create a temporary database file."""
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    yield path
    # Cleanup
    if os.path.exists(path):
        os.unlink(path)


@pytest.fixture
def cache(temp_db):
    """Create a cache instance with temporary database."""
    return AnalysisCache(db_path=temp_db)


@pytest.fixture
def sample_moves():
    """Sample move candidates."""
    return [
        MoveCandidate(move="Q3", winrate=0.523, score_lead=0.31, visits=45),
        MoveCandidate(move="R4", winrate=0.518, score_lead=0.28, visits=38),
        MoveCandidate(move="C16", winrate=0.515, score_lead=0.24, visits=32),
    ]


class TestMoveCandidate:
    """Tests for MoveCandidate data class."""
    
    def test_creation(self):
        """Test basic creation."""
        move = MoveCandidate(
            move="Q16",
            winrate=0.523,
            score_lead=0.31,
            visits=100
        )
        
        assert move.move == "Q16"
        assert move.winrate == 0.523
        assert move.score_lead == 0.31
        assert move.visits == 100
    
    def test_to_dict(self):
        """Test serialization to dict."""
        move = MoveCandidate(
            move="Q16",
            winrate=0.523,
            score_lead=0.31,
            visits=100
        )
        
        d = move.to_dict()
        
        assert d['move'] == "Q16"
        assert d['winrate'] == 0.523
        assert d['score_lead'] == 0.31
        assert d['visits'] == 100
    
    def test_from_dict(self):
        """Test deserialization from dict."""
        d = {
            'move': 'Q16',
            'winrate': 0.523,
            'score_lead': 0.31,
            'visits': 100
        }
        
        move = MoveCandidate.from_dict(d)
        
        assert move.move == "Q16"
        assert move.winrate == 0.523
    
    def test_roundtrip(self):
        """Test serialization roundtrip."""
        original = MoveCandidate(
            move="Q16",
            winrate=0.523,
            score_lead=0.31,
            visits=100
        )
        
        restored = MoveCandidate.from_dict(original.to_dict())
        
        assert restored.move == original.move
        assert restored.winrate == original.winrate
        assert restored.score_lead == original.score_lead
        assert restored.visits == original.visits


class TestAnalysisResult:
    """Tests for AnalysisResult data class."""
    
    def test_creation(self, sample_moves):
        """Test basic creation."""
        result = AnalysisResult(
            board_hash="abc123",
            board_size=19,
            komi=7.5,
            moves_sequence="B[Q16];W[D4]",
            top_moves=sample_moves,
            engine_visits=150,
            model_name="kata1-b10",
        )
        
        assert result.board_hash == "abc123"
        assert result.board_size == 19
        assert len(result.top_moves) == 3
        assert result.from_cache is False
    
    def test_to_dict(self, sample_moves):
        """Test serialization to dict."""
        result = AnalysisResult(
            board_hash="abc123",
            board_size=19,
            komi=7.5,
            moves_sequence="B[Q16]",
            top_moves=sample_moves,
            engine_visits=150,
            model_name="kata1-b10",
        )
        
        d = result.to_dict()
        
        assert d['board_hash'] == "abc123"
        assert d['board_size'] == 19
        assert len(d['top_moves']) == 3
        assert d['top_moves'][0]['move'] == "Q3"
    
    def test_from_dict(self, sample_moves):
        """Test deserialization from dict."""
        d = {
            'board_hash': 'abc123',
            'board_size': 19,
            'komi': 7.5,
            'moves_sequence': 'B[Q16]',
            'top_moves': [m.to_dict() for m in sample_moves],
            'engine_visits': 150,
            'model_name': 'kata1-b10',
            'from_cache': True,
        }
        
        result = AnalysisResult.from_dict(d)
        
        assert result.board_hash == "abc123"
        assert len(result.top_moves) == 3
        assert result.top_moves[0].move == "Q3"


class TestAnalysisCache:
    """Tests for AnalysisCache class."""
    
    def test_creation(self, cache):
        """Test cache creation."""
        assert cache.count() == 0
    
    def test_put_and_get(self, cache, sample_moves):
        """Test storing and retrieving."""
        cache.put(
            board_hash="hash123",
            moves_sequence="B[Q16]",
            board_size=19,
            komi=7.5,
            top_moves=sample_moves,
            engine_visits=150,
            model_name="kata1-b10",
        )
        
        result = cache.get("hash123", komi=7.5)
        
        assert result is not None
        assert result.board_hash == "hash123"
        assert result.board_size == 19
        assert result.komi == 7.5
        assert len(result.top_moves) == 3
        assert result.from_cache is True
        assert result.engine_visits == 150
        assert result.model_name == "kata1-b10"
    
    def test_get_missing(self, cache):
        """Test getting non-existent entry."""
        result = cache.get("nonexistent", komi=7.5)
        assert result is None
    
    def test_count(self, cache, sample_moves):
        """Test count method."""
        assert cache.count() == 0
        
        cache.put(
            board_hash="hash1",
            moves_sequence="",
            board_size=19,
            komi=7.5,
            top_moves=sample_moves,
            engine_visits=150,
            model_name="test",
        )
        assert cache.count() == 1
        
        cache.put(
            board_hash="hash2",
            moves_sequence="",
            board_size=19,
            komi=7.5,
            top_moves=sample_moves,
            engine_visits=150,
            model_name="test",
        )
        assert cache.count() == 2
    
    def test_delete(self, cache, sample_moves):
        """Test delete method."""
        cache.put(
            board_hash="hash123",
            moves_sequence="",
            board_size=19,
            komi=7.5,
            top_moves=sample_moves,
            engine_visits=150,
            model_name="test",
        )
        
        assert cache.count() == 1
        
        result = cache.delete("hash123")
        assert result is True
        assert cache.count() == 0
        
        # Delete non-existent
        result = cache.delete("hash123")
        assert result is False
    
    def test_clear(self, cache, sample_moves):
        """Test clear method."""
        # Add multiple entries
        for i in range(5):
            cache.put(
                board_hash=f"hash{i}",
                moves_sequence="",
                board_size=19,
                komi=7.5,
                top_moves=sample_moves,
                engine_visits=150,
                model_name="test",
            )
        
        assert cache.count() == 5
        
        deleted = cache.clear()
        
        assert deleted == 5
        assert cache.count() == 0
    
    def test_replace_existing(self, cache, sample_moves):
        """Test replacing existing entry behavior with multi-visit support."""
        # 1. Insert first entry with 100 visits
        cache.put(
            board_hash="hash123",
            moves_sequence="old",
            board_size=19,
            komi=7.5,
            top_moves=sample_moves,
            engine_visits=100,
            model_name="old-model",
        )
    
        # 2. Insert SAME hash but DIFFERENT visits (200)
        # Should create a NEW entry (total 2)
        new_moves = [MoveCandidate(move="E5", winrate=0.6, score_lead=1.0, visits=200)]
        cache.put(
            board_hash="hash123",
            moves_sequence="new",
            board_size=19,
            komi=7.5,
            top_moves=new_moves,
            engine_visits=200,
            model_name="new-model",
        )
        
        # Expect 2 distinct entries now
        assert cache.count() == 2
        
        # Verify checking for specific visits gets the right one
        res_100 = cache.get("hash123", komi=7.5, required_visits=100)
        assert res_100.engine_visits == 100
        assert res_100.model_name == "old-model"
        
        res_200 = cache.get("hash123", komi=7.5, required_visits=200)
        assert res_200.engine_visits == 200
        assert res_200.model_name == "new-model"
        
        # 3. Insert SAME hash AND SAME visits (200)
        # Should REPLACE the existing 200-visit entry (total still 2)
        newer_moves = [MoveCandidate(move="F5", winrate=0.7, score_lead=2.0, visits=200)]
        cache.put(
            board_hash="hash123",
            moves_sequence="newest",
            board_size=19,
            komi=7.5,
            top_moves=newer_moves,
            engine_visits=200,
            model_name="newest-model",
        )

        assert cache.count() == 2
        res_updated = cache.get("hash123", komi=7.5, required_visits=200)
        assert res_updated.model_name == "newest-model"
    
    def test_stats(self, cache, sample_moves):
        """Test get_stats method."""
        # Add entries with different board sizes
        for size in [9, 9, 13, 19, 19, 19]:
            cache.put(
                board_hash=f"hash_{size}_{cache.count()}",
                moves_sequence="",
                board_size=size,
                komi=7.5,
                top_moves=sample_moves,
                engine_visits=150,
                model_name="test-model",
            )
        
        stats = cache.get_stats()
        
        assert stats['total_entries'] == 6
        assert stats['by_board_size'][9] == 2
        assert stats['by_board_size'][13] == 1
        assert stats['by_board_size'][19] == 3
        assert stats['by_model']['test-model'] == 6
        assert stats['db_size_bytes'] > 0
    
    def test_multiple_models(self, cache, sample_moves):
        """Test tracking multiple models."""
        models = ["kata1-b10", "kata1-b15", "kata1-b18"]
        
        for i, model in enumerate(models):
            cache.put(
                board_hash=f"hash_{i}",
                moves_sequence="",
                board_size=19,
                komi=7.5,
                top_moves=sample_moves,
                engine_visits=150,
                model_name=model,
            )
        
        stats = cache.get_stats()
        
        for model in models:
            assert stats['by_model'][model] == 1


class TestCachePersistence:
    """Tests for cache persistence across instances."""
    
    def test_persistence(self, temp_db, sample_moves):
        """Test data persists across cache instances."""
        # Create cache and add data
        cache1 = AnalysisCache(db_path=temp_db)
        cache1.put(
            board_hash="persistent_hash",
            moves_sequence="B[Q16]",
            board_size=19,
            komi=7.5,
            top_moves=sample_moves,
            engine_visits=150,
            model_name="test",
        )
        
        # Create new instance
        cache2 = AnalysisCache(db_path=temp_db)
        
        result = cache2.get("persistent_hash", komi=7.5)
        
        assert result.board_hash == "persistent_hash"
        assert len(result.top_moves) == 3


class TestCacheStats:
    """Tests for cache statistics aggregation."""
    
    def test_visit_counts(self, cache, sample_moves):
        """Test get_visit_counts aggregation."""
        # Add entries with different visit counts for Board Size 19
        visits_data = [100, 100, 200, 500, 500, 500]
        for i, v in enumerate(visits_data):
            cache.put(
                board_hash=f"hash_19_{i}",
                moves_sequence="",
                board_size=19,
                komi=7.5,
                top_moves=sample_moves,
                engine_visits=v,
                model_name="test",
            )
            
        # Add entries for Board Size 9 (should be ignored)
        cache.put(
            board_hash="hash_9_1",
            moves_sequence="",
            board_size=9,
            komi=7.5,
            top_moves=sample_moves,
            engine_visits=100,
            model_name="test",
        )
        
        counts = cache.get_visit_counts(19, komi=7.5)
        
        # Verify counts for size 19
        assert len(counts) == 3
        assert counts[100] == 2
        assert counts[200] == 1
        assert counts[500] == 3
        
        # Verify size 9
        counts_9 = cache.get_visit_counts(9, komi=7.5)
        assert counts_9[100] == 1


class TestCacheMerge:
    """Tests for database merging functionality."""
    
    def test_merge_db(self, cache, sample_moves, temp_db):
        """Test merging another database into the main cache."""
        import sqlite3
        
        # 1. Create a "source" database with some data
        # We need a separate file for the source DB
        fd, source_path = tempfile.mkstemp(suffix=".db")
        os.close(fd)
        
        try:
            source_cache = AnalysisCache(db_path=source_path)
            
            # Entry A: Unique to Source (New Hash)
            source_cache.put(
                board_hash="hash_source_only",
                moves_sequence="B[Q16]",
                board_size=19,
                komi=7.5,
                top_moves=sample_moves,
                engine_visits=100,
                model_name="source_model"
            )
            
            # Entry B: Conflict (Same Hash, Same Visits) -> Should Merge
            # Modify sample moves slightly for source
            source_moves_b = [
                MoveCandidate(move="Q3", winrate=0.60, score_lead=1.0, visits=45), # Higher than sample (0.523)
                MoveCandidate(move="K10", winrate=0.40, score_lead=-0.5, visits=10) # New move
            ]
            source_cache.put(
                board_hash="hash_conflict",
                moves_sequence="",
                board_size=19,
                komi=7.5,
                top_moves=source_moves_b,
                engine_visits=100,
                model_name="source_model"
            )
            
            # 2. Setup Local Cache
            # Entry B: Local version
            cache.put(
                board_hash="hash_conflict",
                moves_sequence="",
                board_size=19,
                komi=7.5,
                top_moves=sample_moves, # Has Q3 (0.523), R4, C16
                engine_visits=100,
                model_name="local_model"
            )
            
            # 3. Perform Merge
            stats = cache.merge_database(source_path)
            
            assert stats['inserted'] == 1
            assert stats['merged'] == 1
            assert stats['errors'] == 0
            
            # 4. Verify Results
            
            # Check Inserted (hash_source_only)
            res_new = cache.get("hash_source_only", komi=7.5)
            assert res_new is not None
            assert res_new.model_name == "source_model"
            
            # Check Merged (hash_conflict)
            res_merged = cache.get("hash_conflict", komi=7.5)
            assert res_merged is not None
            assert "merged" in res_merged.model_name
            
            # Verify Averaging Logic for "Q3"
            # Local: 0.523, Source: 0.60 -> Avg: 0.5615
            q3_move = next(m for m in res_merged.top_moves if m.move == "Q3")
            assert 0.56 < q3_move.winrate < 0.562
            
            # Verify Union Logic (R4 from Local, K10 from Source should both exist)
            all_moves = {m.move for m in res_merged.top_moves}
            assert "Q3" in all_moves
            assert "R4" in all_moves # From Local
            assert "K10" in all_moves # From Source
            
        finally:
            if os.path.exists(source_path):
                os.unlink(source_path)

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
