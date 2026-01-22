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
from src.sgf_handler import parse_sgf, create_sgf


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
    stones: List[Tuple[str, int, int, int]],  # List of (color, col, row, move_number) - move_number is 0 for handicap stones
    suggested_moves: Optional[List[MoveCandidate]] = None,
    last_move: Optional[Tuple[int, int]] = None,
    show_move_numbers: bool = True,
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
        move_font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 11)
    except:
        try:
            # Mac fallback
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 12)
            small_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 10)
            move_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 11)
        except:
            font = ImageFont.load_default()
            small_font = font
            move_font = font
    
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
    for stone_data in stones:
        color, col, row = stone_data[0], stone_data[1], stone_data[2]
        move_number = stone_data[3] if len(stone_data) > 3 else 0
        
        px, py = board_to_pixel_coords(col, row)
        occupied.add((col, row))
        
        stone_color = 'black' if color == 'B' else 'white'
        outline_color = 'black'
        
        r = STONE_RADIUS
        draw.ellipse([px - r, py - r, px + r, py + r], 
                     fill=stone_color, outline=outline_color, width=2)
        
        # Draw move number on stone
        if show_move_numbers and move_number > 0:
            text_color = 'white' if color == 'B' else 'black'
            num_text = str(move_number)
            # Center the text on stone
            draw.text((px, py), num_text, fill=text_color, font=move_font, anchor='mm')
        elif last_move and (col, row) == last_move and not show_move_numbers:
            # Mark last move with a small circle only when move numbers are off
            marker_color = 'white' if color == 'B' else 'black'
            mr = 4
            draw.ellipse([px - mr, py - mr, px + mr, py + mr], 
                         outline=marker_color, width=2)
    
    # Draw suggested moves with score loss coloring
    if suggested_moves and len(suggested_moves) > 0:
        # Determine best score (from top move)
        best_score = suggested_moves[0].score_lead
        
        # Load fonts for info text
        try:
            info_font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 10)
        except:
            info_font = small_font
        
        # Draw top moves (up to 5, though usually we only show top few on board to avoid clutter)
        # User requested coloring based on loss. 
        # heavily restrict on-board visualization to top 3 or those with low loss to avoid clutter?
        # The prompt implies we should show the candidates "based on Score Loss". 
        # Let's show top 5 but filter by loss? Or just top 5.
        
        for i, move in enumerate(suggested_moves[:5]):
            if move.move.upper() == "PASS":
                continue
            col, row = gtp_to_coords(move.move, board_size)
            if col < 0 or (col, row) in occupied:
                continue
            
            # Calculate score loss
            loss = best_score - move.score_lead
            
            # Determine color based on Score Loss AND Winrate Loss
            # Blue: Best Move (Loss ~ 0 AND Winrate ~ Best) - handles symmetric moves correctly
            # Green: Loss < 1.0 (or negative loss but not best winrate)
            # Yellow: Loss < 3.0
            
            best_winrate = suggested_moves[0].winrate
            winrate_loss = best_winrate - move.winrate
            
            # Strict criteria for Blue: Must be best score AND best winrate (within margin)
            if loss <= 0.05 and winrate_loss <= 0.005:
                fill_color = (100, 150, 255) # Blue
            elif loss < 1.0:
                fill_color = (100, 220, 100) # Green
            elif loss < 3.0:
                fill_color = (255, 220, 80)  # Yellow
            else:
                continue # Don't draw moves with high loss on the board to keep it clean
            
            px, py = board_to_pixel_coords(col, row)
            r = STONE_RADIUS + 2
            
            # Draw colored circle
            draw.ellipse([px - r, py - r, px + r, py + r], 
                         fill=fill_color, outline='black', width=1)
            
            # Format winrate and score
            winrate_pct = move.winrate * 100
            score_sign = "+" if move.score_lead >= 0 else ""
            
            winrate_text = f"{winrate_pct:.1f}"
            score_text = f"{score_sign}{move.score_lead:.1f}"
            
            # Draw text
            draw.text((px, py - 6), winrate_text, fill='black', font=info_font, anchor='mm')
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
    if 'analyzer' not in st.session_state:
        st.session_state.analyzer = None
        
    # Initialize analyzer if needed (needed for checking opening book)
    try:
        if st.session_state.analyzer is None:
            st.session_state.analyzer = GoAnalyzer(
                config_path=str(PROJECT_ROOT / "config.yaml")
            )
    except Exception:
        pass

    if 'visits' not in st.session_state:
        # Check if opening book exists for current settings
        book_visits = 0
        if st.session_state.analyzer:
            book_visits = st.session_state.analyzer.cache.get_opening_book_visits(
                board_size=st.session_state.get('board_size', 9),
                komi=st.session_state.get('komi', 7.5),
                handicap=st.session_state.get('handicap', 0)
            )
            
        if book_visits > 0:
            st.session_state.visits = book_visits
        else:
            st.session_state.visits = 50
    if 'analysis_result' not in st.session_state:
        # Auto-analyze on initial load to show Black's first move suggestions
        st.session_state.analysis_result = None
        try:
            # Re-ensure analyzer is ready
            if st.session_state.analyzer is None:
                st.session_state.analyzer = GoAnalyzer(
                    config_path=str(PROJECT_ROOT / "config.yaml")
                )
            
            result = st.session_state.analyzer.analyze(
                board_size=st.session_state.get('board_size', 9),
                moves=None,
                handicap=st.session_state.get('handicap', 0),
                komi=st.session_state.get('komi', 7.5),
                visits=st.session_state.get('visits', 300),
            )
            st.session_state.analysis_result = result
        except Exception:
            pass  # Silently fail if KataGo not available
    if 'last_click' not in st.session_state:
        st.session_state.last_click = None
    if 'show_move_numbers' not in st.session_state:
        st.session_state.show_move_numbers = True  # Default ON like Sabaki



def get_stones_from_moves(moves: List[str], board_size: int) -> List[Tuple[str, int, int, int]]:
    """Parse moves list and return stone positions with move numbers.
    
    Returns:
        List of (color, col, row, move_number) tuples.
        move_number starts from 1 for the first move.
    """
    stones = []
    move_number = 0
    for move_str in moves:
        parts = move_str.strip().split()
        if len(parts) != 2:
            continue
        color = parts[0].upper()
        coord = parts[1].upper()
        move_number += 1
        
        if coord == "PASS":
            continue
        
        col, row = gtp_to_coords(coord, board_size)
        if col >= 0 and row >= 0:
            stones.append((color, col, row, move_number))
    
    return stones


def get_occupied_positions(stones: List[Tuple[str, int, int, int]]) -> set:
    """Get set of occupied positions."""
    return {(stone[1], stone[2]) for stone in stones}


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
    
    # Custom CSS to override default red slider color
    st.markdown("""
        <style>
        /* Slider track and thumb */
        .stSlider [data-baseweb="slider"] {
            color: #333333;
        }
        .stSlider [data-testid="stTickBar"] {
            color: #333333;
        }
        /* Slider value text */
        .stSlider [data-testid="stThumbValue"] {
            color: #333333 !important;
        }
        /* Select slider text */
        div[data-baseweb="select"] {
            color: #333333;
        }
        </style>
    """, unsafe_allow_html=True)
    
    init_session_state()
    
    # Title
    st.title("Go Strategy Analyzer")
    st.markdown("*Powered by KataGo - Click on the board to place stones*")
    
    # Sidebar
    with st.sidebar:
        st.header("Settings")
        
        # Board size - Three buttons
        st.write("**Board Size**")
        size_col1, size_col2, size_col3 = st.columns(3)
        
        def switch_board_size(new_size: int):
            """Helper to switch board size and trigger analysis."""
            if new_size != st.session_state.board_size:
                st.session_state.board_size = new_size
                st.session_state.moves = []
                st.session_state.analysis_result = None
                
                # Update default visits based on board size
                if st.session_state.analyzer:
                    book_visits = st.session_state.analyzer.cache.get_opening_book_visits(
                        board_size=new_size,
                        komi=st.session_state.get('komi', 7.5),
                        handicap=st.session_state.get('handicap', 0)
                    )
                    if book_visits > 0:
                        st.session_state.visits = book_visits
                
                # Auto-analyze empty board to show first move suggestions
                try:
                    if st.session_state.analyzer is None:
                        st.session_state.analyzer = GoAnalyzer(
                            config_path=str(PROJECT_ROOT / "config.yaml")
                        )
                    
                    current_visits = st.session_state.get('visits', 50)
                    
                    result = st.session_state.analyzer.analyze(
                        board_size=new_size,
                        moves=None,
                        handicap=st.session_state.get('handicap', 0),
                        komi=st.session_state.get('komi', 7.5),
                        visits=current_visits,
                    )
                    st.session_state.analysis_result = result
                except Exception as e:
                    st.session_state.analysis_result = None
                
                st.rerun()
        
        with size_col1:
            if st.button("9x9", use_container_width=True, 
                        type="primary" if st.session_state.board_size == 9 else "secondary"):
                switch_board_size(9)
        with size_col2:
            if st.button("13x13", use_container_width=True,
                        type="primary" if st.session_state.board_size == 13 else "secondary"):
                switch_board_size(13)
        with size_col3:
            if st.button("19x19", use_container_width=True,
                        type="primary" if st.session_state.board_size == 19 else "secondary"):
                switch_board_size(19)
        
        # Komi
        st.session_state.komi = st.number_input(
            "Komi",
            min_value=0.0,
            max_value=20.0,
            value=st.session_state.komi,
            step=0.5,
            format="%.1f",
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
        
        st.markdown("---")
        
        # Control buttons (Clear, Undo, Pass)
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
                        visits=st.session_state.visits,
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
                            visits=st.session_state.visits,
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
        
        # ================================================================
        # SGF Import/Export
        # ================================================================
        st.subheader("📁 SGF Import/Export")
        
        # SGF Upload
        uploaded_file = st.file_uploader(
            "Load SGF",
            type=["sgf"],
            help="Upload an SGF file to load the game",
            key="sgf_uploader"
        )
        
        if uploaded_file is not None:
            try:
                # Read and parse the SGF
                sgf_content = uploaded_file.read().decode("utf-8", errors="replace")
                game_data = parse_sgf(sgf_content)
                
                # Update session state with loaded game
                loaded_size = game_data["board_size"]
                if loaded_size in [9, 13, 19]:
                    st.session_state.board_size = loaded_size
                else:
                    st.warning(f"Board size {loaded_size} not supported. Using 19x19.")
                    st.session_state.board_size = 19
                
                st.session_state.komi = game_data["komi"]
                st.session_state.handicap = game_data["handicap"]
                st.session_state.moves = game_data["moves"]
                
                # Handle handicap stones (add as initial moves)
                if game_data["handicap_stones"]:
                    # Handicap stones are added as Black moves at the beginning
                    handicap_moves = [f"B {coord}" for coord in game_data["handicap_stones"]]
                    st.session_state.moves = handicap_moves + st.session_state.moves
                
                # Show metadata
                meta = game_data.get("metadata", {})
                if meta:
                    info_parts = []
                    if "black_player" in meta:
                        info_parts.append(f"Black: {meta['black_player']}")
                    if "white_player" in meta:
                        info_parts.append(f"White: {meta['white_player']}")
                    if "result" in meta:
                        info_parts.append(f"Result: {meta['result']}")
                    if info_parts:
                        st.info(" | ".join(info_parts))
                
                st.success(f"Loaded {len(game_data['moves'])} moves from SGF!")
                
                # Auto-analyze the loaded position
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
                        visits=st.session_state.visits,
                    )
                    st.session_state.analysis_result = result
                except Exception as e:
                    st.session_state.analysis_result = None
                
                st.rerun()
                
            except Exception as e:
                st.error(f"Failed to load SGF: {e}")
        
        # SGF Download
        if st.session_state.moves:
            sgf_content = create_sgf(
                board_size=st.session_state.board_size,
                moves=st.session_state.moves,
                komi=st.session_state.komi,
                handicap=st.session_state.handicap,
                game_name="Go Strategy App Analysis",
            )
            
            st.download_button(
                label="💾 Download SGF",
                data=sgf_content,
                file_name="game.sgf",
                mime="application/x-go-sgf",
                use_container_width=True,
                help="Download current game as SGF file"
            )
        else:
            st.caption("No moves to export yet.")
        
        st.markdown("---")
        
        # Show Move Numbers toggle
        st.session_state.show_move_numbers = st.checkbox(
            "Show Move Numbers",
            value=st.session_state.show_move_numbers,
            help="Display move numbers (1, 2, 3...) on stones like Sabaki"
        )
        
        # Visits Control
        # Define discrete visit levels (non-linear for better UX)
        all_visit_levels = [10, 50, 100, 200, 300, 500, 1000, 2000, 5000]
        
        # Check if we have an opening book for this configuration
        has_book = False
        # Check if we have an opening book for this configuration
        book_visits = 0
        if st.session_state.analyzer:
            book_visits = st.session_state.analyzer.cache.get_opening_book_visits(
                board_size=st.session_state.board_size,
                komi=st.session_state.komi,
                handicap=st.session_state.handicap,
            )

        # If opening book exists, enforce minimum visits to ensure quality
        has_book = book_visits > 0
        if has_book:
            min_visits = book_visits
            visit_levels = [v for v in all_visit_levels if v >= min_visits]
        else:
            visit_levels = all_visit_levels
        
        # Ensure current visits is valid
        current_visits = st.session_state.visits
        if current_visits not in visit_levels:
            # Snap to nearest valid value (at least the minimum)
            if visit_levels:
                current_visits = min(visit_levels, key=lambda x: abs(x - current_visits))
                if current_visits < visit_levels[0]:
                    current_visits = visit_levels[0]
            else:
                current_visits = 50 # Fallback
            st.session_state.visits = current_visits
            
        st.session_state.visits = st.select_slider(
            "Analysis Strength (Visits)",
            options=visit_levels,
            value=current_visits,
            help=f"{min_visits}+=Opening Book" if has_book else "10=Debug, 50=Fast, 500+=Strong"
        )
        
        # Show cached data availability
        if st.session_state.analyzer:
            visit_stats = st.session_state.analyzer.get_visit_stats(
                st.session_state.board_size,
                st.session_state.komi
            )
            if visit_stats:
                st.caption("Cached Data Availability:")
                
                # Check if current selection has data
                curr_count = visit_stats.get(st.session_state.visits, 0)
                st.write(f"Current ({st.session_state.visits}): **{curr_count}** entries")
                
                with st.expander("See all cached depths"):
                    # Sort by visit count
                    sorted_stats = sorted(visit_stats.items())
                    # Use radio button for direct selection
                    options = [f"{v} visits: {c} entries" for v, c in sorted_stats]
                    visit_values = [v for v, c in sorted_stats]
                    
                    # Find current index
                    current_idx = 0
                    if st.session_state.visits in visit_values:
                        current_idx = visit_values.index(st.session_state.visits)
                    
                    selected = st.radio(
                        "Select visit depth:",
                        options=options,
                        index=current_idx,
                        label_visibility="collapsed"
                    )
                    
                    # Get selected visit value
                    selected_idx = options.index(selected)
                    selected_visits = visit_values[selected_idx]
                    
                    if selected_visits != st.session_state.visits:
                        st.session_state.visits = selected_visits
                        st.session_state.analysis_result = None
                        st.rerun()

        # Re-analyze if visits changed (handled by rerun/select_slider interactivity)
        if st.session_state.analysis_result and st.session_state.analysis_result.engine_visits != st.session_state.visits:
            st.session_state.analysis_result = None
            st.rerun()
        
        if st.session_state.analyzer:
             with st.expander("Data Management"):
                st.caption("Manage cached analysis data.")
                
                # 1. Download Current DB
                from src.config import get_db_path
                from datetime import datetime
                db_path = get_db_path(st.session_state.analyzer.config)
                if db_path.exists():
                     with open(db_path, "rb") as f:
                        # Generate descriptive filename
                        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                        board_size = st.session_state.board_size
                        komi = st.session_state.komi
                        handicap = st.session_state.handicap
                        visits = st.session_state.visits
                        filename = f"go_analysis_{board_size}x{board_size}_k{komi}_h{handicap}_v{visits}_{timestamp}.db"
                        
                        st.download_button(
                            label="Download Database",
                            data=f,
                            file_name=filename,
                            mime="application/x-sqlite3"
                        )
                
                # 2. Upload and Merge
                uploaded_file = st.file_uploader("Merge Database", type=["db", "sqlite", "sql"])
                if uploaded_file is not None:
                     if st.button("Merge Uploaded Data"):
                        with st.spinner("Merging data..."):
                            import tempfile
                            import os
                            
                            # Save uploaded file to temp
                            with tempfile.NamedTemporaryFile(delete=False, suffix=".db") as tmp_file:
                                tmp_file.write(uploaded_file.getvalue())
                                tmp_path = tmp_file.name
                            
                            try:
                                # Perform merge
                                stats = st.session_state.analyzer.cache.merge_database(tmp_path)
                                st.success(f"Merge Complete! Inserted: {stats['inserted']}, Merged: {stats['merged']}, Errors: {stats['errors']}")
                                # Refresh stats display
                                st.rerun()
                            except Exception as e:
                                st.error(f"Merge failed: {e}")
                            finally:
                                # Cleanup
                                if os.path.exists(tmp_path):
                                    os.unlink(tmp_path)
        
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
            show_move_numbers=st.session_state.show_move_numbers,
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
                        visits=st.session_state.visits,
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
            
            best_score = result.top_moves[0].score_lead if result.top_moves else 0
            
            for i, move in enumerate(result.top_moves[:10]): # Show more moves in list
                winrate_pct = move.winrate * 100
                score_sign = "+" if move.score_lead >= 0 else ""
                loss = best_score - move.score_lead
                
                # Determine color indicator based on loss
                best_winrate = result.top_moves[0].winrate
                winrate_loss = best_winrate - move.winrate
                
                if loss <= 0.05 and winrate_loss <= 0.005:
                    indicator = "🔵" # Blue for Best (and equivalents)
                    color_style = "color: #4da6ff; font-weight: bold;"
                elif loss < 1.0:
                    indicator = "🟢" # Green
                    color_style = "color: #4dce4d;"
                elif loss < 3.0:
                    indicator = "🟡" # Yellow
                    color_style = "color: #e6e600;"
                else:
                    indicator = "⚪"
                    color_style = "color: #cccccc;"
                
                # Format with custom styling
                st.markdown(
                    f"<span style='{color_style}'>{indicator} **{i+1}. {move.move}**</span> "
                    f"| Win: `{winrate_pct:5.1f}%` "
                    f"| Score: `{score_sign}{move.score_lead:.1f}` "
                    f"| Loss: `{loss:.1f}`",
                    unsafe_allow_html=True
                )
        else:
            st.info("Place a stone to see analysis")
        
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
