"""
Go Strategy Analysis Tool - Python Backend

A local Go/Weiqi opening strategy analysis tool using KataGo engine.
"""

__version__ = "0.1.0"

from .analyzer import GoAnalyzer, CacheMissError, quick_analyze, format_result
from .cache import AnalysisCache, AnalysisResult, MoveCandidate
from .board import BoardState, create_board

__all__ = [
    "GoAnalyzer",
    "CacheMissError",
    "quick_analyze",
    "format_result",
    "AnalysisCache",
    "AnalysisResult",
    "MoveCandidate",
    "BoardState",
    "create_board",
]
