"""
Streamlit Web GUI for Go Strategy Analysis Tool.

Features:
- Click on board to place stones
- Coordinate labels (A-T, 1-19)
- KataGo analysis with visual suggestions

Run with:
    cd /home/rexhsu/go-strategy-app
    source venv/bin/activate
    streamlit run src/gui.py --server.address 0.0.0.0 --server.port 8501
"""

import streamlit as st
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image
import io
from typing import List, Tuple, Optional
import sys
from pathlib import Path

from streamlit_image_coordinates import streamlit_image_coordinates

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.analyzer import GoAnalyzer
from src.cache import MoveCandidate


# ============================================================================
# Constants for Board Drawing
# ============================================================================

# Board image dimensions
BOARD_PADDING = 40  # Padding for coordinate labels
CELL_SIZE = 30      # Pixels per cell
STONE_RADIUS = 13   # Stone radius in pixels


def get_board_image_size(board_size: int) -> int:
    """Calculate total image size including padding."""
    return BOARD_PADDING * 2 + CELL_SIZE * (board_size - 1)


def pixel_to_board_coords(x: int, y: int, board_size: int) -> Tuple[int, int]:
    """
    Convert pixel coordinates to board coordinates.
    Returns (col, row) or (-1, -1) if outside board.
    """
    img_size = get_board_image_size(board_size)
    board_area = CELL_SIZE * (board_size - 1)
    
    # Calculate relative position within board area
    board_x = x - BOARD_PADDING
    board_y = y - BOARD_PADDING
    
    # Convert to grid coordinates with rounding
    col = round(board_x / CELL_SIZE)
    row = round(board_y / CELL_SIZE)
    
    # Check bounds
    if 0 <= col < board_size and 0 <= row < board_size:
        return (col, row)
    return (-1, -1)


def board_to_pixel_coords(col: int, row: int) -> Tuple[int, int]:
    """Convert board coordinates to pixel coordinates."""
    x = BOARD_PADDING + col * CELL_SIZE
    y = BOARD_PADDING + row * CELL_SIZE
    return (x, y)


# ============================================================================
# Coordinate Conversion (GTP format)
# ============================================================================

def gtp_to_coords(gtp_move: str, board_size: int) -> Tuple[int, int]:
    """
    Convert GTP coordinate (e.g., 'Q16') to (col, row) indices.
    GTP: A-T (skip I), 1-19 from bottom-left
    Returns: (col, row) where (0,0) is top-left in display
    """
    if not gtp_move or gtp_move.upper() == "PASS":
        return (-1, -1)
    
    col_letter = gtp_move[0].upper()
    row_num = int(gtp_move[1:])
    
    # A=0, B=1, ..., H=7, J=8 (skip I)
    if col_letter >= 'J':
        col = ord(col_letter) - ord('A') - 1
    else:
        col = ord(col_letter) - ord('A')
    
    # GTP row 1 = bottom, we want row 0 = top
    row = board_size - row_num
    
    return (col, row)


def coords_to_gtp(col: int, row: int, board_size: int) -> str:
    """Convert (col, row) to GTP coordinate."""
    # Skip 'I'
    if col >= 8:
        letter = chr(ord('A') + col + 1)
    else:
        letter = chr(ord('A') + col)
    
    number = board_size - row
    return f"{letter}{number}"


def col_to_letter(col: int) -> str:
    """Convert column index to letter (skip I)."""
    if col >= 8:
        return chr(ord('A') + col + 1)
    return chr(ord('A') + col)


# ============================================================================
# Star Points
# ============================================================================

def get_star_points(board_size: int) -> List[Tuple[int, int]]:
    """Get star point coordinates for a given board size."""
    if board_size == 9:
        return [(2, 2), (6, 2), (4, 4), (2, 6), (6, 6)]
    elif board_size == 13:
        return [(3, 3), (9, 3), (6, 6), (3, 9), (9, 9)]
    elif board_size == 19:
        return [
            (3, 3), (9, 3), (15, 3),
            (3, 9), (9, 9), (15, 9),
            (3, 15), (9, 15), (15, 15)
        ]
    return []


# ============================================================================
# Board Drawing with PIL (for clickable image)
# ============================================================================

def draw_board_pil(
    board_size: int,
    stones: List[Tuple[str, int, int]],  # List of (color, col, row)
    suggested_moves: Optional[List[MoveCandidate]] = None,
    last_move: Optional[Tuple[int, int]] = None,
) -> Image.Image:
    """
    Draw a Go board as PIL Image for click interaction.
    """
    from PIL import ImageDraw, ImageFont
    
    img_size = get_board_image_size(board_size)
    
    # Create image with board color
    board_color = (222, 184, 135)  # Burlywood RGB
    img = Image.new('RGB', (img_size, img_size), board_color)
    draw = ImageDraw.Draw(img)
    
    # Try to load a font, fallback to default
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 12)
        small_font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 10)
    except:
        font = ImageFont.load_default()
        small_font = font
    
    # Draw grid lines
    for i in range(board_size):
        x = BOARD_PADDING + i * CELL_SIZE
        y = BOARD_PADDING + i * CELL_SIZE
        
        # Vertical lines
        draw.line([(x, BOARD_PADDING), (x, BOARD_PADDING + (board_size - 1) * CELL_SIZE)], 
                  fill='black', width=1)
        # Horizontal lines
        draw.line([(BOARD_PADDING, y), (BOARD_PADDING + (board_size - 1) * CELL_SIZE, y)], 
                  fill='black', width=1)
    
    # Draw coordinate labels
    for i in range(board_size):
        letter = col_to_letter(i)
        row_num = str(board_size - i)
        
        x = BOARD_PADDING + i * CELL_SIZE
        y = BOARD_PADDING + i * CELL_SIZE
        
        # Top labels (letters)
        draw.text((x - 4, 5), letter, fill='black', font=font)
        # Bottom labels (letters)
        draw.text((x - 4, img_size - 20), letter, fill='black', font=font)
        # Left labels (numbers)
        draw.text((5, y - 6), row_num, fill='black', font=font)
        # Right labels (numbers)
        draw.text((img_size - 25, y - 6), row_num, fill='black', font=font)
    
    # Draw star points
    star_points = get_star_points(board_size)
    for col, row in star_points:
        px, py = board_to_pixel_coords(col, row)
        r = 3
        draw.ellipse([px - r, py - r, px + r, py + r], fill='black')
    
    # Draw stones
    occupied = set()
    for color, col, row in stones:
        px, py = board_to_pixel_coords(col, row)
        occupied.add((col, row))
        
        stone_color = 'black' if color == 'B' else 'white'
        outline_color = 'black'
        
        r = STONE_RADIUS
        draw.ellipse([px - r, py - r, px + r, py + r], 
                     fill=stone_color, outline=outline_color, width=2)
        
        # Mark last move with a small circle
        if last_move and (col, row) == last_move:
            marker_color = 'white' if color == 'B' else 'black'
            mr = 4
            draw.ellipse([px - mr, py - mr, px + mr, py + mr], 
                         outline=marker_color, width=2)
    
    # Draw suggested moves with info labels directly on the point
    if suggested_moves:
        # Blue (best), Green (2nd), Yellow (3rd)
        colors = [(100, 150, 255), (100, 220, 100), (255, 220, 80)]
        
        # Load fonts for info text
        try:
            info_font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 10)
        except:
            info_font = small_font
        
        for i, move in enumerate(suggested_moves[:3]):
            if move.move.upper() == "PASS":
                continue
            col, row = gtp_to_coords(move.move, board_size)
            if col < 0 or (col, row) in occupied:
                continue
            
            px, py = board_to_pixel_coords(col, row)
            r = STONE_RADIUS + 2  # Slightly larger circle to fit text
            
            # Draw colored circle (larger to fit text)
            draw.ellipse([px - r, py - r, px + r, py + r], 
                         fill=colors[i], outline='black', width=1)
            
            # Format winrate and score
            winrate_pct = move.winrate * 100
            score_sign = "+" if move.score_lead >= 0 else ""
            
            winrate_text = f"{winrate_pct:.1f}"
            score_text = f"{score_sign}{move.score_lead:.1f}"
            
            # Draw winrate on top, score on bottom (centered on the point)
            draw.text((px, py - 5), winrate_text, fill='black', font=info_font, anchor='mm')
            draw.text((px, py + 6), score_text, fill='black', font=info_font, anchor='mm')
    
    return img


# ============================================================================
# Session State Management
# ============================================================================

def init_session_state():
    """Initialize session state variables."""
    if 'moves' not in st.session_state:
        st.session_state.moves = []
    if 'board_size' not in st.session_state:
        st.session_state.board_size = 9
    if 'komi' not in st.session_state:
        st.session_state.komi = 7.5
    if 'handicap' not in st.session_state:
        st.session_state.handicap = 0
    if 'analysis_result' not in st.session_state:
        st.session_state.analysis_result = None
    if 'analyzer' not in st.session_state:
        st.session_state.analyzer = None
    if 'last_click' not in st.session_state:
        st.session_state.last_click = None


def get_stones_from_moves(moves: List[str], board_size: int) -> List[Tuple[str, int, int]]:
    """Parse moves list and return stone positions."""
    stones = []
    for move_str in moves:
        parts = move_str.strip().split()
        if len(parts) != 2:
            continue
        color = parts[0].upper()
        coord = parts[1].upper()
        
        if coord == "PASS":
            continue
        
        col, row = gtp_to_coords(coord, board_size)
        if col >= 0 and row >= 0:
            stones.append((color, col, row))
    
    return stones


def get_occupied_positions(stones: List[Tuple[str, int, int]]) -> set:
    """Get set of occupied positions."""
    return {(col, row) for _, col, row in stones}


def get_next_player(moves: List[str], handicap: int) -> str:
    """Determine whose turn it is."""
    if handicap > 0 and len(moves) == 0:
        return 'W'
    
    black_moves = sum(1 for m in moves if m.startswith('B'))
    white_moves = sum(1 for m in moves if m.startswith('W'))
    
    if handicap > 0:
        if black_moves + handicap <= white_moves:
            return 'B'
        return 'W'
    else:
        if black_moves <= white_moves:
            return 'B'
        return 'W'


# ============================================================================
# Main App
# ============================================================================

def main():
    st.set_page_config(
        page_title="Go Strategy Analyzer",
        page_icon="",
        layout="wide",
    )
    
    init_session_state()
    
    # Title
    st.title("Go Strategy Analyzer")
    st.markdown("*Powered by KataGo - Click on the board to place stones*")
    
    # Sidebar
    with st.sidebar:
        st.header("Settings")
        
        # Board size
        new_board_size = st.selectbox(
            "Board Size",
            options=[9, 13, 19],
            index=[9, 13, 19].index(st.session_state.board_size),
        )
        if new_board_size != st.session_state.board_size:
            st.session_state.board_size = new_board_size
            st.session_state.moves = []
            st.session_state.analysis_result = None
            st.rerun()
        
        # Komi
        st.session_state.komi = st.number_input(
            "Komi",
            min_value=0.0,
            max_value=20.0,
            value=st.session_state.komi,
            step=0.5,
        )
        
        # Handicap
        new_handicap = st.selectbox(
            "Handicap",
            options=list(range(10)),
            index=st.session_state.handicap,
        )
        if new_handicap != st.session_state.handicap:
            st.session_state.handicap = new_handicap
            st.session_state.moves = []
            st.session_state.analysis_result = None
            st.rerun()
        
        st.markdown("---")
        
        # Control buttons
        col1, col2 = st.columns(2)
        with col1:
            if st.button("Clear", type="secondary", use_container_width=True):
                st.session_state.moves = []
                # Auto-analyze empty board
                try:
                    if st.session_state.analyzer is None:
                        st.session_state.analyzer = GoAnalyzer(
                            config_path=str(PROJECT_ROOT / "config.yaml")
                        )
                    result = st.session_state.analyzer.analyze(
                        board_size=st.session_state.board_size,
                        moves=None,
                        handicap=st.session_state.handicap,
                        komi=st.session_state.komi,
                    )
                    st.session_state.analysis_result = result
                except:
                    st.session_state.analysis_result = None
                st.rerun()
        
        with col2:
            if st.button("Undo", type="secondary", use_container_width=True):
                if st.session_state.moves:
                    st.session_state.moves.pop()
                    # Auto-analyze after undo
                    try:
                        if st.session_state.analyzer is None:
                            st.session_state.analyzer = GoAnalyzer(
                                config_path=str(PROJECT_ROOT / "config.yaml")
                            )
                        result = st.session_state.analyzer.analyze(
                            board_size=st.session_state.board_size,
                            moves=st.session_state.moves if st.session_state.moves else None,
                            handicap=st.session_state.handicap,
                            komi=st.session_state.komi,
                        )
                        st.session_state.analysis_result = result
                    except:
                        st.session_state.analysis_result = None
                    st.rerun()
        
        # Pass button
        if st.button("Pass", type="secondary", use_container_width=True):
            next_player = get_next_player(st.session_state.moves, st.session_state.handicap)
            st.session_state.moves.append(f"{next_player} PASS")
            st.session_state.analysis_result = None
            st.rerun()
        
        st.markdown("---")
        
        # Analysis button
        if st.button("Ask KataGo", type="primary", use_container_width=True):
            with st.spinner("Analyzing..."):
                try:
                    if st.session_state.analyzer is None:
                        st.session_state.analyzer = GoAnalyzer(
                            config_path=str(PROJECT_ROOT / "config.yaml")
                        )
                    
                    result = st.session_state.analyzer.analyze(
                        board_size=st.session_state.board_size,
                        moves=st.session_state.moves if st.session_state.moves else None,
                        handicap=st.session_state.handicap,
                        komi=st.session_state.komi,
                    )
                    st.session_state.analysis_result = result
                    st.rerun()
                    
                except Exception as e:
                    st.error(f"Analysis failed: {e}")
        
        st.markdown("---")
        st.header("Cache Stats")
        
        try:
            if st.session_state.analyzer is None:
                st.session_state.analyzer = GoAnalyzer(
                    config_path=str(PROJECT_ROOT / "config.yaml")
                )
            stats = st.session_state.analyzer.get_cache_stats()
            st.write(f"Cached: {stats.get('total_entries', 0)}")
        except Exception as e:
            st.warning(f"Cache unavailable")
    
    # Main content area
    col_board, col_info = st.columns([2, 1])
    
    with col_board:
        # Get current state
        stones = get_stones_from_moves(st.session_state.moves, st.session_state.board_size)
        occupied = get_occupied_positions(stones)
        
        # Get last move
        last_move = None
        if st.session_state.moves:
            last = st.session_state.moves[-1].split()
            if len(last) == 2 and last[1].upper() != "PASS":
                last_move = gtp_to_coords(last[1], st.session_state.board_size)
        
        # Get suggested moves
        suggested = None
        if st.session_state.analysis_result:
            suggested = st.session_state.analysis_result.top_moves
        
        # Draw board as PIL image
        board_img = draw_board_pil(
            board_size=st.session_state.board_size,
            stones=stones,
            suggested_moves=suggested,
            last_move=last_move,
        )
        
        # Display clickable image
        coords = streamlit_image_coordinates(
            board_img,
            key=f"board_{len(st.session_state.moves)}_{st.session_state.analysis_result is not None}",
        )
        
        # Handle click
        if coords is not None:
            click_x = coords["x"]
            click_y = coords["y"]
            
            col, row = pixel_to_board_coords(click_x, click_y, st.session_state.board_size)
            
            if col >= 0 and row >= 0 and (col, row) not in occupied:
                # Valid click on empty intersection
                next_player = get_next_player(st.session_state.moves, st.session_state.handicap)
                gtp_coord = coords_to_gtp(col, row, st.session_state.board_size)
                
                st.session_state.moves.append(f"{next_player} {gtp_coord}")
                
                # Auto-analyze after each move
                try:
                    if st.session_state.analyzer is None:
                        st.session_state.analyzer = GoAnalyzer(
                            config_path=str(PROJECT_ROOT / "config.yaml")
                        )
                    
                    result = st.session_state.analyzer.analyze(
                        board_size=st.session_state.board_size,
                        moves=st.session_state.moves,
                        handicap=st.session_state.handicap,
                        komi=st.session_state.komi,
                    )
                    st.session_state.analysis_result = result
                except Exception as e:
                    st.session_state.analysis_result = None
                
                st.rerun()
    
    with col_info:
        # Current turn
        next_player = get_next_player(st.session_state.moves, st.session_state.handicap)
        player_name = "Black" if next_player == 'B' else "White"
        player_symbol = "" if next_player == 'B' else ""
        
        st.markdown(f"### Next: {player_symbol} {player_name}")
        
        st.markdown("---")
        
        # Analysis results
        st.markdown("### Analysis")
        
        if st.session_state.analysis_result:
            result = st.session_state.analysis_result
            
            source = "Cache" if result.from_cache else "KataGo"
            st.success(f"Source: {source}")
            
            st.caption("Win% = player's chance after move | Score = point lead")
            st.markdown("**Top Moves:**")
            
            labels = ['A', 'B', 'C', 'D', 'E']
            for i, move in enumerate(result.top_moves[:5]):
                winrate_pct = move.winrate * 100
                score_sign = "+" if move.score_lead >= 0 else ""
                
                st.markdown(
                    f"**{labels[i]}. {move.move}** - "
                    f"Win: {winrate_pct:.1f}% | "
                    f"Score: {score_sign}{move.score_lead:.1f}"
                )
        else:
            st.info("Click 'Ask KataGo' to analyze")
        
        st.markdown("---")
        
        # Move history
        st.markdown("### Move History")
        
        if st.session_state.moves:
            # Show moves in a compact format
            move_count = len(st.session_state.moves)
            st.write(f"Total: {move_count} moves")
            
            # Show last 10 moves
            recent = st.session_state.moves[-10:]
            for i, m in enumerate(recent):
                move_num = move_count - len(recent) + i + 1
                st.text(f"{move_num}. {m}")
        else:
            st.text("(No moves yet)")
        
        st.markdown("---")
        
        # Game info
        st.markdown("### Game Info")
        st.write(f"Board: {st.session_state.board_size}x{st.session_state.board_size}")
        st.write(f"Komi: {st.session_state.komi}")
        st.write(f"Handicap: {st.session_state.handicap}")


if __name__ == "__main__":
    main()
