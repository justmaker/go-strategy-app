"""
FastAPI REST API for Go Strategy Analysis Tool.

Exposes the analysis engine via HTTP endpoints for cross-platform clients.

Usage:
    # Start the server
    uvicorn src.api:app --host 0.0.0.0 --port 8000 --reload
    
    # Or run directly
    python -m src.api
"""

from contextlib import asynccontextmanager
from enum import Enum
from typing import List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from .analyzer import GoAnalyzer
from .board import create_board
from .cache import AnalysisCache
from .config import load_config


# ============================================================================
# Pydantic Models (OpenAPI Schema)
# ============================================================================

class BoardSize(int, Enum):
    """Supported board sizes."""
    SMALL = 9
    MEDIUM = 13
    LARGE = 19


class MoveCandidateResponse(BaseModel):
    """A candidate move with analysis statistics."""
    move: str = Field(..., description="GTP coordinate (e.g., 'Q16', 'D4')")
    winrate: float = Field(..., ge=0, le=1, description="Win rate as decimal (0.0-1.0)")
    score_lead: float = Field(..., description="Score lead (positive = ahead)")
    visits: int = Field(..., ge=0, description="Number of MCTS visits for this move")
    
    class Config:
        json_schema_extra = {
            "example": {
                "move": "Q16",
                "winrate": 0.523,
                "score_lead": 0.8,
                "visits": 150
            }
        }


class AnalysisResponse(BaseModel):
    """Complete analysis result for a board position."""
    board_hash: str = Field(..., description="Zobrist hash of the position")
    board_size: int = Field(..., description="Board size (9, 13, or 19)")
    komi: float = Field(..., description="Komi value")
    moves_sequence: str = Field(..., description="Move sequence string (e.g., 'B[Q16];W[D4]')")
    top_moves: List[MoveCandidateResponse] = Field(..., description="Top candidate moves")
    engine_visits: int = Field(..., description="Total visits used for analysis")
    model_name: str = Field(..., description="KataGo model name")
    from_cache: bool = Field(..., description="Whether result was from cache")
    timestamp: Optional[str] = Field(None, description="Analysis timestamp (ISO format)")
    
    class Config:
        json_schema_extra = {
            "example": {
                "board_hash": "a1b2c3d4e5f6g7h8",
                "board_size": 19,
                "komi": 7.5,
                "moves_sequence": "B[Q16];W[D4]",
                "top_moves": [
                    {"move": "Q3", "winrate": 0.52, "score_lead": 0.5, "visits": 50},
                    {"move": "R14", "winrate": 0.51, "score_lead": 0.3, "visits": 45},
                ],
                "engine_visits": 150,
                "model_name": "kata1-b18c384",
                "from_cache": False,
                "timestamp": "2024-01-21T20:00:00"
            }
        }


class AnalyzeRequest(BaseModel):
    """Request body for /analyze endpoint."""
    board_size: int = Field(default=19, ge=9, le=19, description="Board size (9, 13, or 19)")
    moves: List[str] = Field(default=[], description="List of moves in GTP format (e.g., ['B Q16', 'W D4'])")
    handicap: int = Field(default=0, ge=0, le=9, description="Number of handicap stones (0-9)")
    komi: Optional[float] = Field(default=None, description="Komi value (default: 7.5, or 0.5 for handicap)")
    visits: Optional[int] = Field(default=None, ge=1, description="Override default visit count")
    force_refresh: bool = Field(default=False, description="Bypass cache and force new analysis")
    
    class Config:
        json_schema_extra = {
            "example": {
                "board_size": 19,
                "moves": ["B Q16", "W D4", "B Q3"],
                "handicap": 0,
                "komi": 7.5,
                "visits": 150,
                "force_refresh": False
            }
        }


class QueryRequest(BaseModel):
    """Request body for /query endpoint (cache lookup only)."""
    board_size: int = Field(default=19, ge=9, le=19, description="Board size (9, 13, or 19)")
    moves: List[str] = Field(default=[], description="List of moves in GTP format")
    handicap: int = Field(default=0, ge=0, le=9, description="Number of handicap stones")
    komi: Optional[float] = Field(default=None, description="Komi value")
    
    class Config:
        json_schema_extra = {
            "example": {
                "board_size": 9,
                "moves": ["B E5"],
                "handicap": 0,
                "komi": 7.5
            }
        }


class QueryResponse(BaseModel):
    """Response for /query endpoint."""
    found: bool = Field(..., description="Whether position was found in cache")
    result: Optional[AnalysisResponse] = Field(None, description="Analysis result if found")
    
    class Config:
        json_schema_extra = {
            "example": {
                "found": True,
                "result": {
                    "board_hash": "a1b2c3d4",
                    "board_size": 9,
                    "komi": 7.5,
                    "moves_sequence": "B[E5]",
                    "top_moves": [{"move": "C3", "winrate": 0.48, "score_lead": -0.2, "visits": 100}],
                    "engine_visits": 500,
                    "model_name": "kata1-b18c384",
                    "from_cache": True,
                    "timestamp": "2024-01-21T19:00:00"
                }
            }
        }


class HealthResponse(BaseModel):
    """Health check response."""
    status: str = Field(..., description="Service status")
    cache_entries: int = Field(..., description="Number of cached positions")
    katago_running: bool = Field(..., description="Whether KataGo engine is running")


class ErrorResponse(BaseModel):
    """Error response."""
    detail: str = Field(..., description="Error message")


# ============================================================================
# Application State
# ============================================================================

class AppState:
    """Application state container."""
    analyzer: Optional[GoAnalyzer] = None
    config = None


state = AppState()


# ============================================================================
# Lifespan Management
# ============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifecycle (startup/shutdown)."""
    # Startup
    print("Starting Go Strategy API...")
    state.config = load_config()
    state.analyzer = GoAnalyzer(config=state.config)
    state.analyzer.start()
    print(f"KataGo started. Cache has {state.analyzer.cache.count()} entries.")
    
    yield
    
    # Shutdown
    print("Shutting down Go Strategy API...")
    if state.analyzer:
        state.analyzer.shutdown()
    print("Shutdown complete.")


# ============================================================================
# FastAPI Application
# ============================================================================

app = FastAPI(
    title="Go Strategy Analysis API",
    description="""
REST API for Go (Weiqi/Baduk) position analysis powered by KataGo.

## Features
- Analyze board positions with AI recommendations
- Cache-backed for fast repeated queries
- Symmetry-aware canonical hashing (8x cache efficiency)
- Support for 9x9, 13x13, and 19x19 boards

## Usage
1. Use `/analyze` to get AI move recommendations (may invoke KataGo)
2. Use `/query` to check cache only (fast, no KataGo)
3. Use `/health` to check service status
    """,
    version="1.0.0",
    lifespan=lifespan,
    responses={
        500: {"model": ErrorResponse, "description": "Internal server error"},
    },
)

# CORS middleware for cross-origin requests (Flutter web, etc.)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================================
# Endpoints
# ============================================================================

@app.get(
    "/health",
    response_model=HealthResponse,
    tags=["System"],
    summary="Health check",
    description="Check if the API service is running and get basic status.",
)
async def health_check():
    """Return service health status."""
    return HealthResponse(
        status="ok",
        cache_entries=state.analyzer.cache.count() if state.analyzer else 0,
        katago_running=state.analyzer.is_running() if state.analyzer else False,
    )


@app.post(
    "/analyze",
    response_model=AnalysisResponse,
    tags=["Analysis"],
    summary="Analyze a board position",
    description="""
Analyze a Go board position and return top candidate moves.

This endpoint will:
1. Check cache for existing analysis
2. If not found (or force_refresh=True), run KataGo analysis
3. Cache and return the result

**Note:** If KataGo analysis is needed, this may take several seconds.
    """,
    responses={
        400: {"model": ErrorResponse, "description": "Invalid request parameters"},
    },
)
async def analyze_position(request: AnalyzeRequest):
    """Analyze a board position."""
    if not state.analyzer:
        raise HTTPException(status_code=500, detail="Analyzer not initialized")
    
    # Validate board size
    if request.board_size not in (9, 13, 19):
        raise HTTPException(status_code=400, detail="Board size must be 9, 13, or 19")
    
    try:
        result = state.analyzer.analyze(
            board_size=request.board_size,
            moves=request.moves if request.moves else None,
            handicap=request.handicap,
            komi=request.komi,
            visits=request.visits,
            force_refresh=request.force_refresh,
        )
        
        return AnalysisResponse(
            board_hash=result.board_hash,
            board_size=result.board_size,
            komi=result.komi,
            moves_sequence=result.moves_sequence,
            top_moves=[
                MoveCandidateResponse(
                    move=m.move,
                    winrate=m.winrate,
                    score_lead=m.score_lead,
                    visits=m.visits,
                )
                for m in result.top_moves
            ],
            engine_visits=result.engine_visits,
            model_name=result.model_name,
            from_cache=result.from_cache,
            timestamp=result.timestamp,
        )
        
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Analysis failed: {str(e)}")


@app.post(
    "/query",
    response_model=QueryResponse,
    tags=["Analysis"],
    summary="Query cache for a position",
    description="""
Check if a board position exists in the cache.

This is a fast lookup that does NOT invoke KataGo.
Use this when you only want cached results.
    """,
)
async def query_cache(request: QueryRequest):
    """Query cache for a position without running analysis."""
    if not state.analyzer:
        raise HTTPException(status_code=500, detail="Analyzer not initialized")
    
    try:
        # Build board state to get canonical hash
        komi = request.komi
        if komi is None:
            komi = 0.5 if request.handicap >= 2 else 7.5
            
        board = create_board(
            size=request.board_size,
            handicap=request.handicap,
            komi=komi,
            moves=request.moves if request.moves else None,
        )
        
        # Get canonical hash for symmetry-aware lookup
        canonical_hash, transform_used = board.compute_canonical_hash()
        
        # Query cache
        cached = state.analyzer.cache.get(
            canonical_hash,
            komi=board.komi,
            required_visits=None,  # Get highest visits available
        )
        
        if cached is None:
            return QueryResponse(found=False, result=None)
        
        # Transform moves back if needed
        from .board import SymmetryTransform, get_inverse_transform, transform_gtp_coord
        
        top_moves = cached.top_moves
        if transform_used != SymmetryTransform.IDENTITY:
            inverse = get_inverse_transform(transform_used)
            top_moves = []
            for m in cached.top_moves:
                new_coord = transform_gtp_coord(m.move, request.board_size, inverse)
                top_moves.append(MoveCandidateResponse(
                    move=new_coord,
                    winrate=m.winrate,
                    score_lead=m.score_lead,
                    visits=m.visits,
                ))
        else:
            top_moves = [
                MoveCandidateResponse(
                    move=m.move,
                    winrate=m.winrate,
                    score_lead=m.score_lead,
                    visits=m.visits,
                )
                for m in cached.top_moves
            ]
        
        return QueryResponse(
            found=True,
            result=AnalysisResponse(
                board_hash=cached.board_hash,
                board_size=cached.board_size,
                komi=cached.komi,
                moves_sequence=cached.moves_sequence,
                top_moves=top_moves,
                engine_visits=cached.engine_visits,
                model_name=cached.model_name,
                from_cache=True,
                timestamp=cached.timestamp,
            ),
        )
        
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Query failed: {str(e)}")


@app.get(
    "/stats",
    tags=["System"],
    summary="Get cache statistics",
    description="Get detailed statistics about the analysis cache.",
)
async def get_stats():
    """Return cache statistics."""
    if not state.analyzer:
        raise HTTPException(status_code=500, detail="Analyzer not initialized")
    
    return state.analyzer.get_cache_stats()


# ============================================================================
# Main Entry Point
# ============================================================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "src.api:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
    )
