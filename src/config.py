"""
Configuration management for Go Strategy Analysis Tool.

Loads configuration from config.yaml and provides typed access.
Supports both Mac (Darwin) and Linux platforms with automatic detection.
"""

import os
import platform
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import yaml


def get_platform() -> str:
    """
    Detect the current operating system.
    
    Returns:
        'mac' for macOS/Darwin, 'linux' for Linux
    """
    system = platform.system().lower()
    if system == 'darwin':
        return 'mac'
    elif system == 'linux':
        return 'linux'
    else:
        # Default to linux for other Unix-like systems
        return 'linux'


@dataclass
class KataGoConfig:
    """KataGo engine configuration."""
    katago_path: str
    model_path: str
    config_path: str


@dataclass
class AnalysisConfig:
    """Analysis parameters configuration."""
    default_komi: float = 7.5
    visits_19x19: int = 150
    visits_small: int = 500
    top_moves_count: int = 10


@dataclass
class DatabaseConfig:
    """Database configuration."""
    path: str = "data/analysis.db"


@dataclass
class AppConfig:
    """Main application configuration."""
    katago: KataGoConfig
    analysis: AnalysisConfig = field(default_factory=AnalysisConfig)
    database: DatabaseConfig = field(default_factory=DatabaseConfig)
    
    def get_visits(self, board_size: int) -> int:
        """
        Get the appropriate number of visits based on board size.
        
        Args:
            board_size: Size of the board (9, 13, or 19)
            
        Returns:
            Number of visits for analysis
        """
        if board_size == 19:
            return self.analysis.visits_19x19
        else:
            return self.analysis.visits_small


def load_config(config_path: Optional[str] = None) -> AppConfig:
    """
    Load configuration from YAML file.
    
    Args:
        config_path: Path to config.yaml. If None, searches in:
                     1. Current directory
                     2. Project root (relative to this file)
    
    Returns:
        AppConfig instance
        
    Raises:
        FileNotFoundError: If config file not found
        ValueError: If config file is invalid
    """
    if config_path is None:
        # Search for config.yaml
        search_paths = [
            Path.cwd() / "config.yaml",
            Path(__file__).parent.parent / "config.yaml",
        ]
        
        for path in search_paths:
            if path.exists():
                config_path = str(path)
                break
        else:
            raise FileNotFoundError(
                f"config.yaml not found. Searched in: {[str(p) for p in search_paths]}"
            )
    
    with open(config_path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)
    
    if not data:
        raise ValueError(f"Config file is empty: {config_path}")
    
    # Parse KataGo config (required)
    katago_data = data.get("katago", {})
    if not katago_data:
        raise ValueError("Missing 'katago' section in config")
    
    # Detect platform and get platform-specific config
    current_platform = get_platform()
    project_root = Path(__file__).parent.parent
    
    # Check for multi-platform config (has 'mac' or 'linux' subsections)
    if 'mac' in katago_data or 'linux' in katago_data:
        platform_data = katago_data.get(current_platform, {})
        if not platform_data:
            raise ValueError(f"No config found for platform '{current_platform}'")
        
        katago_path = platform_data.get("katago_path", "")
        model_path = platform_data.get("model_path", "")
        cfg_path = platform_data.get("config_path", "")
    else:
        # Legacy single-platform config (backward compatibility)
        katago_path = katago_data.get("katago_path", "")
        model_path = katago_data.get("model_path", "")
        cfg_path = katago_data.get("config_path", "")
    
    # Resolve relative paths to absolute paths
    def resolve_path(p: str) -> str:
        if not p:
            return p
        path = Path(p)
        if not path.is_absolute():
            path = project_root / path
        return str(path.resolve())
    
    katago_config = KataGoConfig(
        katago_path=resolve_path(katago_path),
        model_path=resolve_path(model_path),
        config_path=resolve_path(cfg_path),
    )
    
    # Parse analysis config (optional, has defaults)
    analysis_data = data.get("analysis", {})
    analysis_config = AnalysisConfig(
        default_komi=analysis_data.get("default_komi", 7.5),
        visits_19x19=analysis_data.get("visits_19x19", 150),
        visits_small=analysis_data.get("visits_small", 500),
        top_moves_count=analysis_data.get("top_moves_count", 3),
    )
    
    # Parse database config (optional, has defaults)
    db_data = data.get("database", {})
    db_config = DatabaseConfig(
        path=db_data.get("path", "data/analysis.db"),
    )
    
    return AppConfig(
        katago=katago_config,
        analysis=analysis_config,
        database=db_config,
    )


def get_project_root() -> Path:
    """Get the project root directory."""
    return Path(__file__).parent.parent


def get_db_path(config: AppConfig) -> Path:
    """
    Get the absolute path to the database file.
    
    Args:
        config: Application configuration
        
    Returns:
        Absolute path to database file
    """
    db_path = Path(config.database.path)
    if not db_path.is_absolute():
        db_path = get_project_root() / db_path
    return db_path
