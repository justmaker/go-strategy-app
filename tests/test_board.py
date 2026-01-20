"""
Unit tests for board.py module.

Tests:
- BoardState creation and manipulation
- Zobrist hash computation
- Handicap stone placement
- GTP coordinate conversion
"""

import pytest
import sys
from pathlib import Path

# Add src to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.board import (
    BoardState,
    ZobristHasher,
    create_board,
    gtp_to_coords,
    coords_to_gtp,
    get_handicap_positions,
    HANDICAP_19x19,
    HANDICAP_13x13,
    HANDICAP_9x9,
)


class TestCoordinateConversion:
    """Tests for GTP coordinate conversion."""
    
    def test_gtp_to_coords_basic(self):
        """Test basic GTP to coordinate conversion."""
        assert gtp_to_coords("A1", 19) == (0, 0)
        assert gtp_to_coords("T19", 19) == (18, 18)
        assert gtp_to_coords("D4", 19) == (3, 3)
        assert gtp_to_coords("Q16", 19) == (15, 15)
    
    def test_gtp_to_coords_skips_i(self):
        """Test that column I is skipped (Go convention)."""
        # H is index 7, J is index 8 (I is skipped)
        assert gtp_to_coords("H1", 19) == (7, 0)
        assert gtp_to_coords("J1", 19) == (8, 0)
    
    def test_gtp_to_coords_case_insensitive(self):
        """Test case insensitivity."""
        assert gtp_to_coords("d4", 19) == gtp_to_coords("D4", 19)
        assert gtp_to_coords("q16", 19) == gtp_to_coords("Q16", 19)
    
    def test_gtp_to_coords_invalid(self):
        """Test invalid coordinates raise ValueError."""
        with pytest.raises(ValueError):
            gtp_to_coords("", 19)
        with pytest.raises(ValueError):
            gtp_to_coords("A", 19)
        with pytest.raises(ValueError):
            gtp_to_coords("I1", 19)  # I is skipped
        with pytest.raises(ValueError):
            gtp_to_coords("A20", 19)  # Out of bounds
        with pytest.raises(ValueError):
            gtp_to_coords("Z1", 19)  # Invalid column
    
    def test_coords_to_gtp(self):
        """Test coordinate to GTP conversion."""
        assert coords_to_gtp(0, 0) == "A1"
        assert coords_to_gtp(18, 18) == "T19"
        assert coords_to_gtp(3, 3) == "D4"
        assert coords_to_gtp(15, 15) == "Q16"
    
    def test_roundtrip(self):
        """Test roundtrip conversion."""
        for x in range(19):
            for y in range(19):
                gtp = coords_to_gtp(x, y)
                x2, y2 = gtp_to_coords(gtp, 19)
                assert (x, y) == (x2, y2)


class TestHandicapPositions:
    """Tests for handicap stone positions."""
    
    def test_handicap_19x19(self):
        """Test 19x19 handicap positions."""
        assert get_handicap_positions(19, 2) == ["D4", "Q16"]
        assert get_handicap_positions(19, 4) == ["D4", "Q16", "D16", "Q4"]
        assert get_handicap_positions(19, 9) == HANDICAP_19x19[9]
    
    def test_handicap_13x13(self):
        """Test 13x13 handicap positions."""
        assert get_handicap_positions(13, 2) == ["D4", "K10"]
        assert get_handicap_positions(13, 4) == ["D4", "K10", "D10", "K4"]
    
    def test_handicap_9x9(self):
        """Test 9x9 handicap positions."""
        assert get_handicap_positions(9, 2) == ["C3", "G7"]
        assert get_handicap_positions(9, 4) == ["C3", "G7", "C7", "G3"]
    
    def test_handicap_less_than_2(self):
        """Test handicap < 2 returns empty list."""
        assert get_handicap_positions(19, 0) == []
        assert get_handicap_positions(19, 1) == []
    
    def test_invalid_handicap(self):
        """Test invalid handicap raises ValueError."""
        with pytest.raises(ValueError):
            get_handicap_positions(19, 10)
    
    def test_invalid_board_size(self):
        """Test invalid board size raises ValueError."""
        with pytest.raises(ValueError):
            get_handicap_positions(15, 4)


class TestBoardState:
    """Tests for BoardState class."""
    
    def test_creation_default(self):
        """Test default board creation."""
        board = BoardState()
        assert board.size == 19
        assert board.komi == 7.5
        assert board.next_player == 'B'
        assert len(board.stones) == 0
        assert len(board.moves) == 0
    
    def test_creation_with_size(self):
        """Test board creation with different sizes."""
        for size in [9, 13, 19]:
            board = BoardState(size=size)
            assert board.size == size
    
    def test_invalid_size(self):
        """Test invalid board size raises ValueError."""
        with pytest.raises(ValueError):
            BoardState(size=15)
    
    def test_play_move(self):
        """Test playing a move."""
        board = BoardState()
        board.play("B", "Q16")
        
        assert len(board.stones) == 1
        assert (15, 15) in board.stones
        assert board.stones[(15, 15)] == 'B'
        assert board.next_player == 'W'
        assert len(board.moves) == 1
    
    def test_play_multiple_moves(self):
        """Test playing multiple moves."""
        board = BoardState()
        board.play("B", "Q16")
        board.play("W", "D4")
        board.play("B", "Q3")
        
        assert len(board.stones) == 3
        assert board.next_player == 'W'
        assert len(board.moves) == 3
    
    def test_play_occupied_position(self):
        """Test playing on occupied position raises ValueError."""
        board = BoardState()
        board.play("B", "Q16")
        
        with pytest.raises(ValueError):
            board.play("W", "Q16")
    
    def test_play_moves(self):
        """Test play_moves method."""
        board = BoardState()
        board.play_moves(["B Q16", "W D4", "B Q3"])
        
        assert len(board.stones) == 3
        assert len(board.moves) == 3
    
    def test_setup_handicap(self):
        """Test handicap setup."""
        board = BoardState()
        board.setup_handicap(4)
        
        assert len(board.stones) == 4
        assert len(board.handicap_stones) == 4
        assert board.next_player == 'W'  # White plays first after handicap
        
        # Verify handicap positions
        for coord in ["D4", "Q16", "D16", "Q4"]:
            x, y = gtp_to_coords(coord, 19)
            assert board.stones[(x, y)] == 'B'
    
    def test_gtp_setup_commands(self):
        """Test GTP setup commands generation."""
        board = BoardState(size=19, komi=7.5)
        board.play("B", "Q16")
        
        commands = board.get_gtp_setup_commands()
        
        assert "boardsize 19" in commands
        assert "clear_board" in commands
        assert "komi 7.5" in commands
        assert "play B Q16" in commands
    
    def test_moves_sequence_string(self):
        """Test moves sequence string generation."""
        board = BoardState()
        board.play_moves(["B Q16", "W D4"])
        
        seq = board.get_moves_sequence_string()
        assert "B[Q16]" in seq
        assert "W[D4]" in seq
    
    def test_copy(self):
        """Test board copy."""
        board = BoardState()
        board.play("B", "Q16")
        
        copy = board.copy()
        
        assert copy.size == board.size
        assert copy.stones == board.stones
        assert copy.moves == board.moves
        assert copy is not board
        assert copy.stones is not board.stones


class TestZobristHasher:
    """Tests for Zobrist hashing."""
    
    def test_hasher_creation(self):
        """Test hasher creation."""
        hasher = ZobristHasher()
        assert hasher.max_size == 19
    
    def test_hash_empty_board(self):
        """Test hash of empty board."""
        hasher = ZobristHasher()
        
        hash1 = hasher.compute_hash({}, 'B', 7.5)
        hash2 = hasher.compute_hash({}, 'B', 7.5)
        
        assert hash1 == hash2
        assert len(hash1) == 16  # 64-bit hex
    
    def test_hash_different_stones(self):
        """Test different stones produce different hashes."""
        hasher = ZobristHasher()
        
        hash1 = hasher.compute_hash({(0, 0): 'B'}, 'W', 7.5)
        hash2 = hasher.compute_hash({(0, 1): 'B'}, 'W', 7.5)
        
        assert hash1 != hash2
    
    def test_hash_different_colors(self):
        """Test different colors produce different hashes."""
        hasher = ZobristHasher()
        
        hash1 = hasher.compute_hash({(0, 0): 'B'}, 'W', 7.5)
        hash2 = hasher.compute_hash({(0, 0): 'W'}, 'B', 7.5)
        
        assert hash1 != hash2
    
    def test_hash_different_player(self):
        """Test different next player produces different hash."""
        hasher = ZobristHasher()
        
        hash1 = hasher.compute_hash({(0, 0): 'B'}, 'B', 7.5)
        hash2 = hasher.compute_hash({(0, 0): 'B'}, 'W', 7.5)
        
        assert hash1 != hash2
    
    def test_hash_different_komi(self):
        """Test different komi produces different hash."""
        hasher = ZobristHasher()
        
        hash1 = hasher.compute_hash({}, 'B', 7.5)
        hash2 = hasher.compute_hash({}, 'B', 6.5)
        
        assert hash1 != hash2
    
    def test_hash_reproducible(self):
        """Test same seed produces same hashes."""
        hasher1 = ZobristHasher(seed=42)
        hasher2 = ZobristHasher(seed=42)
        
        stones = {(3, 3): 'B', (15, 15): 'W'}
        
        hash1 = hasher1.compute_hash(stones, 'B', 7.5)
        hash2 = hasher2.compute_hash(stones, 'B', 7.5)
        
        assert hash1 == hash2


class TestCreateBoard:
    """Tests for create_board factory function."""
    
    def test_create_basic(self):
        """Test basic board creation."""
        board = create_board(size=19)
        assert board.size == 19
        assert board.komi == 7.5
    
    def test_create_with_handicap(self):
        """Test board creation with handicap."""
        board = create_board(size=19, handicap=4)
        
        assert len(board.stones) == 4
        assert board.next_player == 'W'
        assert board.komi == 0.5  # Default komi for handicap
    
    def test_create_with_moves(self):
        """Test board creation with moves."""
        board = create_board(
            size=19,
            moves=["B Q16", "W D4"]
        )
        
        assert len(board.stones) == 2
        assert len(board.moves) == 2
    
    def test_create_with_handicap_and_moves(self):
        """Test board creation with both handicap and moves."""
        board = create_board(
            size=19,
            handicap=4,
            moves=["W E4", "B R4"]
        )
        
        assert len(board.stones) == 6  # 4 handicap + 2 moves
        assert len(board.moves) == 2
        assert len(board.handicap_stones) == 4


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
