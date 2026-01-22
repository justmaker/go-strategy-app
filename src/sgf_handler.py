"""
SGF (Smart Game Format) handler for Go Strategy App.

Provides import/export functionality for SGF files using sgfmill library.
"""

from datetime import date
from typing import List, Tuple, Optional, Dict, Any
from sgfmill import sgf


def parse_sgf(sgf_content: str) -> Dict[str, Any]:
    """
    Parse an SGF string and extract game information.
    
    Args:
        sgf_content: Raw SGF file content as string
        
    Returns:
        Dictionary containing:
        - board_size: int (9, 13, or 19)
        - komi: float
        - handicap: int
        - handicap_stones: List of GTP coordinates for handicap stones
        - moves: List of move strings in format "B D4" or "W Q16"
        - metadata: Dict with player names, date, result, etc.
    """
    game = sgf.Sgf_game.from_string(sgf_content)
    root = game.get_root()
    
    # Extract basic properties
    board_size = game.get_size()
    
    # Komi (default to 7.5 if not specified)
    try:
        komi = root.get("KM")
        if komi is None:
            komi = 7.5
    except KeyError:
        komi = 7.5
    
    # Handicap
    try:
        handicap = root.get("HA")
        if handicap is None:
            handicap = 0
    except KeyError:
        handicap = 0
    
    # Handicap stones (AB = Add Black stones at start)
    handicap_stones = []
    try:
        ab_stones = root.get("AB")
        if ab_stones:
            for point in ab_stones:
                if point is not None:
                    gtp_coord = _sgf_point_to_gtp(point, board_size)
                    if gtp_coord:
                        handicap_stones.append(gtp_coord)
    except KeyError:
        pass
    
    # Extract metadata
    metadata = {}
    for prop, key in [("PB", "black_player"), ("PW", "white_player"),
                      ("DT", "date"), ("RE", "result"), 
                      ("EV", "event"), ("GN", "game_name")]:
        try:
            value = root.get(prop)
            if value:
                metadata[key] = value
        except KeyError:
            pass
    
    # Extract moves from main line
    moves = []
    for node in game.get_main_sequence():
        # Skip root node (it has setup, not moves)
        if node is root:
            continue
            
        # Check for B (Black move) or W (White move)
        for color_code, color_letter in [("B", "B"), ("W", "W")]:
            try:
                point = node.get(color_code)
                if point is None:
                    # Pass move
                    moves.append(f"{color_letter} PASS")
                else:
                    gtp_coord = _sgf_point_to_gtp(point, board_size)
                    if gtp_coord:
                        moves.append(f"{color_letter} {gtp_coord}")
            except KeyError:
                pass
    
    return {
        "board_size": board_size,
        "komi": float(komi),
        "handicap": handicap,
        "handicap_stones": handicap_stones,
        "moves": moves,
        "metadata": metadata,
    }


def create_sgf(
    board_size: int,
    moves: List[str],
    komi: float = 7.5,
    handicap: int = 0,
    handicap_stones: Optional[List[str]] = None,
    black_player: str = "Black",
    white_player: str = "White",
    game_name: str = "Go Strategy App Game",
) -> str:
    """
    Create an SGF string from game data.
    
    Args:
        board_size: Board size (9, 13, or 19)
        moves: List of moves in GTP format ("B D4", "W Q16", etc.)
        komi: Komi value
        handicap: Number of handicap stones
        handicap_stones: List of GTP coordinates for handicap stones
        black_player: Black player name
        white_player: White player name
        game_name: Name of the game
        
    Returns:
        SGF formatted string
    """
    game = sgf.Sgf_game(size=board_size)
    root = game.get_root()
    
    # Set properties
    root.set("KM", komi)
    root.set("PB", black_player)
    root.set("PW", white_player)
    root.set("DT", date.today().isoformat())
    root.set("GN", game_name)
    root.set("AP", ("GoStrategyApp", "1.0"))
    
    if handicap > 0:
        root.set("HA", handicap)
    
    # Add handicap stones
    if handicap_stones:
        ab_points = []
        for coord in handicap_stones:
            point = _gtp_to_sgf_point(coord, board_size)
            if point:
                ab_points.append(point)
        if ab_points:
            root.set("AB", ab_points)
    
    # Add moves
    current_node = root
    for move_str in moves:
        parts = move_str.strip().split()
        if len(parts) != 2:
            continue
            
        color = parts[0].upper()
        coord = parts[1].upper()
        
        if color not in ("B", "W"):
            continue
        
        # Create new node
        new_node = current_node.new_child()
        
        if coord == "PASS":
            new_node.set(color, None)
        else:
            point = _gtp_to_sgf_point(coord, board_size)
            if point:
                new_node.set(color, point)
        
        current_node = new_node
    
    return game.serialise().decode("utf-8")


def _sgf_point_to_gtp(point: Tuple[int, int], board_size: int) -> Optional[str]:
    """
    Convert sgfmill point (row, col) to GTP coordinate (e.g., "D4").
    
    sgfmill uses (row, col) where row 0 is the top and col 0 is the left.
    GTP uses column letters (A-T, skipping I) and row numbers (1 = bottom).
    """
    if point is None:
        return None
    
    row, col = point
    
    # Validate
    if not (0 <= row < board_size and 0 <= col < board_size):
        return None
    
    # Column: 0 -> 'A', 1 -> 'B', ... but skip 'I'
    col_letters = "ABCDEFGHJKLMNOPQRST"  # No 'I'
    if col >= len(col_letters):
        return None
    col_letter = col_letters[col]
    
    # Row: sgfmill row 0 = top = GTP row (board_size)
    # sgfmill row (board_size-1) = bottom = GTP row 1
    gtp_row = board_size - row
    
    return f"{col_letter}{gtp_row}"


def _gtp_to_sgf_point(gtp_coord: str, board_size: int) -> Optional[Tuple[int, int]]:
    """
    Convert GTP coordinate (e.g., "D4") to sgfmill point (row, col).
    """
    if not gtp_coord or gtp_coord.upper() == "PASS":
        return None
    
    gtp_coord = gtp_coord.upper()
    
    # Parse column letter
    col_letters = "ABCDEFGHJKLMNOPQRST"  # No 'I'
    col_letter = gtp_coord[0]
    
    if col_letter not in col_letters:
        return None
    
    col = col_letters.index(col_letter)
    
    # Parse row number
    try:
        gtp_row = int(gtp_coord[1:])
    except ValueError:
        return None
    
    # Validate row
    if not (1 <= gtp_row <= board_size):
        return None
    
    # Convert to sgfmill row
    row = board_size - gtp_row
    
    return (row, col)


def load_sgf_file(file_path: str) -> Dict[str, Any]:
    """
    Load and parse an SGF file from disk.
    
    Args:
        file_path: Path to the SGF file
        
    Returns:
        Parsed game data (same as parse_sgf)
    """
    with open(file_path, "rb") as f:
        content = f.read().decode("utf-8", errors="replace")
    return parse_sgf(content)


def save_sgf_file(file_path: str, sgf_content: str) -> None:
    """
    Save an SGF string to a file.
    
    Args:
        file_path: Path to save the file
        sgf_content: SGF formatted string
    """
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(sgf_content)
