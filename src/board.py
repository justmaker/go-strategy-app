"""
Board state management for Go Strategy Analysis Tool.

Provides:
- BoardState: Manages board position, moves, and handicap stones
- Zobrist Hash: Unique hash for board positions (for caching)
- Standard handicap stone placements for 9x9, 13x13, 19x19
"""

import random
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set, Tuple

# Seed for reproducible Zobrist hash values
ZOBRIST_SEED = 42

# GTP column letters (I is skipped in Go)
GTP_COLUMNS = "ABCDEFGHJKLMNOPQRST"


# ============================================================================
# Standard Handicap Positions
# ============================================================================

# 19x19 standard handicap positions (star points)
HANDICAP_19x19 = {
    2: ["D4", "Q16"],
    3: ["D4", "Q16", "D16"],
    4: ["D4", "Q16", "D16", "Q4"],
    5: ["D4", "Q16", "D16", "Q4", "K10"],
    6: ["D4", "Q16", "D16", "Q4", "D10", "Q10"],
    7: ["D4", "Q16", "D16", "Q4", "D10", "Q10", "K10"],
    8: ["D4", "Q16", "D16", "Q4", "D10", "Q10", "K4", "K16"],
    9: ["D4", "Q16", "D16", "Q4", "D10", "Q10", "K4", "K16", "K10"],
}

# 13x13 standard handicap positions
HANDICAP_13x13 = {
    2: ["D4", "K10"],
    3: ["D4", "K10", "D10"],
    4: ["D4", "K10", "D10", "K4"],
    5: ["D4", "K10", "D10", "K4", "G7"],
    6: ["D4", "K10", "D10", "K4", "D7", "K7"],
    7: ["D4", "K10", "D10", "K4", "D7", "K7", "G7"],
    8: ["D4", "K10", "D10", "K4", "D7", "K7", "G4", "G10"],
    9: ["D4", "K10", "D10", "K4", "D7", "K7", "G4", "G10", "G7"],
}

# 9x9 standard handicap positions
HANDICAP_9x9 = {
    2: ["C3", "G7"],
    3: ["C3", "G7", "C7"],
    4: ["C3", "G7", "C7", "G3"],
    5: ["C3", "G7", "C7", "G3", "E5"],
    6: ["C3", "G7", "C7", "G3", "C5", "G5"],
    7: ["C3", "G7", "C7", "G3", "C5", "G5", "E5"],
    8: ["C3", "G7", "C7", "G3", "C5", "G5", "E3", "E7"],
    9: ["C3", "G7", "C7", "G3", "C5", "G5", "E3", "E7", "E5"],
}


def get_handicap_positions(board_size: int, handicap: int) -> List[str]:
    """
    Get standard handicap stone positions for a given board size.
    
    Args:
        board_size: Size of the board (9, 13, or 19)
        handicap: Number of handicap stones (2-9)
        
    Returns:
        List of GTP coordinates for handicap stones (e.g., ["D4", "Q16"])
        
    Raises:
        ValueError: If board_size or handicap is invalid
    """
    if handicap < 2:
        return []
    
    if handicap > 9:
        raise ValueError(f"Handicap must be 2-9, got {handicap}")
    
    if board_size == 19:
        positions = HANDICAP_19x19.get(handicap)
    elif board_size == 13:
        positions = HANDICAP_13x13.get(handicap)
    elif board_size == 9:
        positions = HANDICAP_9x9.get(handicap)
    else:
        raise ValueError(f"Board size must be 9, 13, or 19, got {board_size}")
    
    if positions is None:
        raise ValueError(f"Invalid handicap {handicap} for board size {board_size}")
    
    return positions


# ============================================================================
# Coordinate Conversion
# ============================================================================

def gtp_to_coords(gtp_coord: str, board_size: int = 19) -> Tuple[int, int]:
    """
    Convert GTP coordinate (e.g., "Q16") to (x, y) tuple.
    
    In GTP:
    - Columns are A-T (I is skipped), left to right
    - Rows are 1-19, bottom to top
    
    We use:
    - x: 0 to board_size-1, left to right
    - y: 0 to board_size-1, bottom to top
    
    Args:
        gtp_coord: GTP coordinate string (e.g., "Q16", "D4")
        board_size: Size of the board
        
    Returns:
        (x, y) tuple
        
    Raises:
        ValueError: If coordinate is invalid
    """
    if not gtp_coord or len(gtp_coord) < 2:
        raise ValueError(f"Invalid GTP coordinate: {gtp_coord}")
    
    col = gtp_coord[0].upper()
    try:
        row = int(gtp_coord[1:])
    except ValueError:
        raise ValueError(f"Invalid GTP coordinate: {gtp_coord}")
    
    if col not in GTP_COLUMNS:
        raise ValueError(f"Invalid column letter: {col}")
    
    x = GTP_COLUMNS.index(col)
    y = row - 1  # Convert 1-based to 0-based
    
    if not (0 <= x < board_size and 0 <= y < board_size):
        raise ValueError(f"Coordinate {gtp_coord} out of bounds for {board_size}x{board_size}")
    
    return (x, y)


def coords_to_gtp(x: int, y: int) -> str:
    """
    Convert (x, y) coordinates to GTP string.
    
    Args:
        x: Column index (0-based)
        y: Row index (0-based)
        
    Returns:
        GTP coordinate string (e.g., "Q16")
    """
    col = GTP_COLUMNS[x]
    row = y + 1
    return f"{col}{row}"


# ============================================================================
# Zobrist Hashing
# ============================================================================

class ZobristHasher:
    """
    Zobrist hashing for Go board positions.
    
    Uses XOR-based hashing for efficient incremental updates.
    The hash includes:
    - Stone positions (Black and White)
    - Next player to move
    - Komi (quantized)
    """
    
    def __init__(self, max_board_size: int = 19, seed: int = ZOBRIST_SEED):
        """
        Initialize Zobrist hash tables.
        
        Args:
            max_board_size: Maximum board size to support
            seed: Random seed for reproducible hash values
        """
        self.max_size = max_board_size
        self.rng = random.Random(seed)
        
        # Hash tables: [color][x][y] -> 64-bit hash value
        # color: 0 = Black, 1 = White
        self.stone_hash: List[List[List[int]]] = [
            [[self._random_hash() for _ in range(max_board_size)]
             for _ in range(max_board_size)]
            for _ in range(2)
        ]
        
        # Hash for next player (XOR if White to play)
        self.player_hash = self._random_hash()
        
        # Hash for different komi values (quantized to 0.5)
        # Range: -100 to +100 in 0.5 increments
        self.komi_hash: Dict[float, int] = {}
        for i in range(-200, 201):
            komi = i * 0.5
            self.komi_hash[komi] = self._random_hash()
    
    def _random_hash(self) -> int:
        """Generate a random 64-bit hash value."""
        return self.rng.getrandbits(64)
    
    def _quantize_komi(self, komi: float) -> float:
        """Quantize komi to nearest 0.5."""
        return round(komi * 2) / 2
    
    def compute_hash(
        self,
        stones: Dict[Tuple[int, int], str],
        next_player: str,
        komi: float
    ) -> str:
        """
        Compute Zobrist hash for a board position.
        
        Args:
            stones: Dictionary of {(x, y): color} where color is 'B' or 'W'
            next_player: 'B' or 'W'
            komi: Komi value
            
        Returns:
            Hex string representation of the hash
        """
        h = 0
        
        # XOR in all stones
        for (x, y), color in stones.items():
            color_idx = 0 if color == 'B' else 1
            h ^= self.stone_hash[color_idx][x][y]
        
        # XOR in player to move (if White)
        if next_player == 'W':
            h ^= self.player_hash
        
        # XOR in komi
        q_komi = self._quantize_komi(komi)
        if q_komi in self.komi_hash:
            h ^= self.komi_hash[q_komi]
        
        return format(h, '016x')


# Global Zobrist hasher instance
_zobrist_hasher: Optional[ZobristHasher] = None


def get_zobrist_hasher() -> ZobristHasher:
    """Get or create the global Zobrist hasher."""
    global _zobrist_hasher
    if _zobrist_hasher is None:
        _zobrist_hasher = ZobristHasher()
    return _zobrist_hasher


# ============================================================================
# Board State
# ============================================================================

@dataclass
class BoardState:
    """
    Represents the state of a Go board.
    
    Attributes:
        size: Board size (9, 13, or 19)
        stones: Dictionary of placed stones {(x, y): 'B' or 'W'}
        moves: List of moves in order [(color, coord), ...]
        handicap_stones: List of handicap stone coordinates
        komi: Komi value
        next_player: Next player to move ('B' or 'W')
    """
    size: int = 19
    stones: Dict[Tuple[int, int], str] = field(default_factory=dict)
    moves: List[Tuple[str, str]] = field(default_factory=list)
    handicap_stones: List[str] = field(default_factory=list)
    komi: float = 7.5
    next_player: str = 'B'
    
    def __post_init__(self):
        """Validate board state after initialization."""
        if self.size not in (9, 13, 19):
            raise ValueError(f"Board size must be 9, 13, or 19, got {self.size}")
    
    def setup_handicap(self, handicap: int) -> None:
        """
        Place standard handicap stones on the board.
        
        Args:
            handicap: Number of handicap stones (2-9)
        """
        if handicap < 2:
            return
        
        positions = get_handicap_positions(self.size, handicap)
        self.handicap_stones = positions.copy()
        
        for coord in positions:
            x, y = gtp_to_coords(coord, self.size)
            self.stones[(x, y)] = 'B'
        
        # After handicap, White plays first
        self.next_player = 'W'
    
    def play(self, color: str, coord: str) -> None:
        """
        Play a move on the board.
        
        Args:
            color: 'B' or 'W'
            coord: GTP coordinate (e.g., "Q16")
            
        Raises:
            ValueError: If move is invalid
        """
        color = color.upper()
        if color not in ('B', 'W'):
            raise ValueError(f"Color must be 'B' or 'W', got {color}")
        
        x, y = gtp_to_coords(coord, self.size)
        
        if (x, y) in self.stones:
            raise ValueError(f"Position {coord} is already occupied")
        
        self.stones[(x, y)] = color
        self.moves.append((color, coord))
        
        # Update next player
        self.next_player = 'W' if color == 'B' else 'B'
    
    def play_moves(self, moves: List[str]) -> None:
        """
        Play a sequence of moves.
        
        Args:
            moves: List of moves in GTP format, e.g., ["B Q16", "W D4", "B Q3"]
        """
        for move in moves:
            parts = move.strip().split()
            if len(parts) != 2:
                raise ValueError(f"Invalid move format: {move}. Expected 'COLOR COORD'")
            color, coord = parts
            self.play(color, coord)
    
    def compute_hash(self) -> str:
        """
        Compute Zobrist hash for the current board state.
        
        Returns:
            Hex string hash of the position
        """
        hasher = get_zobrist_hasher()
        return hasher.compute_hash(self.stones, self.next_player, self.komi)
    
    def get_gtp_setup_commands(self) -> List[str]:
        """
        Generate GTP commands to set up this board position.
        
        Returns:
            List of GTP commands
        """
        commands = [
            f"boardsize {self.size}",
            "clear_board",
            f"komi {self.komi}",
        ]
        
        # Add handicap stones
        for coord in self.handicap_stones:
            commands.append(f"play B {coord}")
        
        # Add moves
        for color, coord in self.moves:
            commands.append(f"play {color} {coord}")
        
        return commands
    
    def get_moves_sequence_string(self) -> str:
        """
        Get a string representation of the move sequence.
        
        Returns:
            String like "B[Q16];W[D4];B[Q3]" or empty string if no moves
        """
        parts = []
        
        # Include handicap stones
        for coord in self.handicap_stones:
            parts.append(f"B[{coord}]")
        
        # Include moves
        for color, coord in self.moves:
            parts.append(f"{color}[{coord}]")
        
        return ";".join(parts)
    
    def copy(self) -> 'BoardState':
        """Create a deep copy of this board state."""
        return BoardState(
            size=self.size,
            stones=self.stones.copy(),
            moves=self.moves.copy(),
            handicap_stones=self.handicap_stones.copy(),
            komi=self.komi,
            next_player=self.next_player,
        )
    
    def __repr__(self) -> str:
        return (
            f"BoardState(size={self.size}, "
            f"stones={len(self.stones)}, "
            f"moves={len(self.moves)}, "
            f"handicap={len(self.handicap_stones)}, "
            f"komi={self.komi}, "
            f"next={self.next_player})"
        )


def create_board(
    size: int = 19,
    handicap: int = 0,
    komi: Optional[float] = None,
    moves: Optional[List[str]] = None
) -> BoardState:
    """
    Factory function to create a BoardState with optional setup.
    
    Args:
        size: Board size (9, 13, or 19)
        handicap: Number of handicap stones (0-9)
        komi: Komi value (default: 7.5, or 0.5 for handicap games)
        moves: List of moves in GTP format, e.g., ["B Q16", "W D4"]
        
    Returns:
        Configured BoardState instance
    """
    # Default komi based on handicap
    if komi is None:
        komi = 0.5 if handicap >= 2 else 7.5
    
    board = BoardState(size=size, komi=komi)
    
    if handicap >= 2:
        board.setup_handicap(handicap)
    
    if moves:
        board.play_moves(moves)
    
    return board
