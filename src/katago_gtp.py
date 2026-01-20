"""
KataGo GTP (Go Text Protocol) communication module.

Provides a persistent subprocess wrapper for KataGo engine:
- Long-running process (starts once, reuses for multiple analyses)
- Thread-safe command execution
- Graceful shutdown with atexit registration
- kata-analyze output parsing
"""

import atexit
import re
import subprocess
import threading
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from .board import BoardState
from .cache import MoveCandidate
from .config import KataGoConfig


# ============================================================================
# Exceptions
# ============================================================================

class KataGoError(Exception):
    """Base exception for KataGo errors."""
    pass


class KataGoStartupError(KataGoError):
    """Raised when KataGo fails to start."""
    pass


class KataGoCommandError(KataGoError):
    """Raised when a GTP command fails."""
    pass


class KataGoProcessError(KataGoError):
    """Raised when the KataGo process dies unexpectedly."""
    pass


# ============================================================================
# KataGo GTP Wrapper
# ============================================================================

class KataGoGTP:
    """
    Persistent KataGo GTP subprocess wrapper.
    
    Features:
    - Lazy initialization (starts on first use)
    - Long-running process (reused for multiple analyses)
    - Thread-safe command execution
    - Automatic cleanup on program exit
    
    Usage:
        katago = KataGoGTP(config)
        katago.start()  # Or let it auto-start on first command
        
        board = BoardState(size=19)
        board.play("B", "Q16")
        
        katago.setup_position(board)
        moves = katago.analyze(next_player="B", visits=150)
        
        katago.shutdown()  # Or let atexit handle it
    
    Context Manager:
        with KataGoGTP(config) as katago:
            moves = katago.analyze(...)
    """
    
    def __init__(self, config: KataGoConfig):
        """
        Initialize the KataGo wrapper.
        
        Args:
            config: KataGo configuration with paths to executable, model, and config
        """
        self.config = config
        self.process: Optional[subprocess.Popen] = None
        self.model_name: str = ""
        self._lock = threading.Lock()
        self._started = False
        self._shutdown_registered = False
    
    def start(self) -> None:
        """
        Start the KataGo subprocess.
        
        This method is idempotent - calling it multiple times has no effect
        if the process is already running.
        
        Raises:
            KataGoStartupError: If KataGo fails to start
        """
        with self._lock:
            if self._started and self.process is not None:
                # Check if process is still alive
                if self.process.poll() is None:
                    return  # Already running
                else:
                    # Process died, need to restart
                    self._started = False
            
            self._do_start()
    
    def _do_start(self) -> None:
        """Internal method to start the process (must hold lock)."""
        # Validate paths
        katago_path = Path(self.config.katago_path)
        model_path = Path(self.config.model_path)
        config_path = Path(self.config.config_path)
        
        # Build command
        cmd = [
            str(katago_path),
            "gtp",
            "-model", str(model_path),
            "-config", str(config_path),
        ]
        
        try:
            self.process = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,  # Ignore stderr to prevent buffer deadlock
                text=True,
                bufsize=1,  # Line buffered
            )
        except FileNotFoundError:
            raise KataGoStartupError(
                f"KataGo executable not found: {self.config.katago_path}"
            )
        except PermissionError:
            raise KataGoStartupError(
                f"Permission denied executing: {self.config.katago_path}"
            )
        except Exception as e:
            raise KataGoStartupError(f"Failed to start KataGo: {e}")
        
        # Register cleanup on exit
        if not self._shutdown_registered:
            atexit.register(self.shutdown)
            self._shutdown_registered = True
        
        self._started = True
        
        # Get model name from KataGo
        try:
            response = self._send_command_internal("name")
            self.model_name = response.strip()
        except Exception:
            # Non-critical, use placeholder
            self.model_name = "unknown"
    
    def _ensure_running(self) -> None:
        """Ensure the process is running, start if needed."""
        if not self._started or self.process is None:
            self.start()
        elif self.process.poll() is not None:
            # Process died, restart
            self._started = False
            self.start()
    
    def _send_command_internal(self, cmd: str) -> str:
        """
        Send a GTP command (internal, assumes lock is held).
        
        Args:
            cmd: GTP command string
            
        Returns:
            Response content (without "= " prefix)
            
        Raises:
            KataGoCommandError: If command fails
            KataGoProcessError: If process is not running
        """
        if self.process is None or self.process.stdin is None or self.process.stdout is None:
            raise KataGoProcessError("KataGo process is not running")
        
        # Send command
        try:
            self.process.stdin.write(cmd + "\n")
            self.process.stdin.flush()
        except BrokenPipeError:
            raise KataGoProcessError("KataGo process died unexpectedly")
        
        # Read response (GTP response ends with double newline)
        response_lines = []
        while True:
            try:
                line = self.process.stdout.readline()
            except Exception as e:
                raise KataGoProcessError(f"Error reading from KataGo: {e}")
            
            if not line:
                # EOF - process died
                raise KataGoProcessError("KataGo process terminated unexpectedly")
            
            line = line.rstrip('\n')
            
            if line == "":
                # Empty line marks end of response
                break
            
            response_lines.append(line)
        
        if not response_lines:
            return ""
        
        response = "\n".join(response_lines)
        
        # Check for error
        if response.startswith("?"):
            error_msg = response[2:] if len(response) > 2 else "Unknown error"
            raise KataGoCommandError(f"GTP command failed: {error_msg}")
        
        # Remove "= " prefix
        if response.startswith("= "):
            return response[2:]
        elif response.startswith("="):
            return response[1:].lstrip()
        
        return response
    
    def send_command(self, cmd: str) -> str:
        """
        Send a GTP command to KataGo.
        
        Thread-safe and auto-starts the process if needed.
        
        Args:
            cmd: GTP command string (e.g., "boardsize 19")
            
        Returns:
            Response content
            
        Raises:
            KataGoCommandError: If command fails
            KataGoProcessError: If process errors occur
        """
        with self._lock:
            self._ensure_running()
            return self._send_command_internal(cmd)
    
    def setup_position(self, board: BoardState) -> None:
        """
        Set up a board position in KataGo.
        
        Sends boardsize, clear_board, komi, and all moves.
        
        Args:
            board: BoardState to set up
        """
        commands = board.get_gtp_setup_commands()
        
        with self._lock:
            self._ensure_running()
            for cmd in commands:
                self._send_command_internal(cmd)
    
    def analyze(self, next_player: str, visits: int, top_n: int = 3) -> List[MoveCandidate]:
        """
        Get top candidate moves using kata-analyze (provides scoreLead).
        
        Args:
            next_player: 'B' or 'W'
            visits: Number of visits for analysis
            top_n: Number of top moves to return
            
        Returns:
            List of MoveCandidate objects
        """
        import time
        import select
        
        with self._lock:
            self._ensure_running()
            
            if self.process is None or self.process.stdin is None or self.process.stdout is None:
                raise KataGoProcessError("KataGo process is not running")
            
            # Use kata-analyze which provides scoreLead
            # Format: kata-analyze <player> interval <centiseconds>
            cmd = f"kata-analyze {next_player} interval 10"  # 10 centiseconds = 100ms interval
            
            # Send command
            try:
                self.process.stdin.write(cmd + "\n")
                self.process.stdin.flush()
            except BrokenPipeError:
                raise KataGoProcessError("KataGo process died unexpectedly")
            
            # Read response lines
            response_lines = []
            start_time = time.time()
            timeout = 10  # seconds
            min_visits_needed = min(visits, 10)  # At least this many visits before returning
            
            while True:
                elapsed = time.time() - start_time
                if elapsed > timeout:
                    break
                
                try:
                    readable, _, _ = select.select([self.process.stdout], [], [], 0.2)
                except:
                    break
                
                if readable:
                    line = self.process.stdout.readline()
                    if line:
                        line = line.rstrip('\n')
                        if line.startswith("info "):
                            response_lines.append(line)
                            # Check if we have enough visits on the best move
                            if len(response_lines) >= 2:
                                match = re.search(r'visits\s+(\d+)', line)
                                if match and int(match.group(1)) >= min_visits_needed:
                                    break
                        elif line.startswith("="):
                            continue
                else:
                    # No data available, check if we have enough results
                    if len(response_lines) >= 2:
                        break
            
            # Send stop command to end analysis
            try:
                self.process.stdin.write("stop\n")
                self.process.stdin.flush()
                # Drain remaining output
                while True:
                    readable, _, _ = select.select([self.process.stdout], [], [], 0.3)
                    if readable:
                        line = self.process.stdout.readline()
                        if not line or line.strip() == "":
                            break
                    else:
                        break
            except:
                pass
            
            # Parse the last line (most up-to-date analysis)
            if response_lines:
                last_line = response_lines[-1]
                candidates = self._parse_kata_analyze_line(last_line, top_n)
                if candidates:
                    return candidates
            
            # Fallback to genmove if kata-analyze failed
            response = self._send_command_internal(f"genmove {next_player}")
            best_move = response.strip().upper()
            self._send_command_internal("undo")
            
            if best_move and best_move != "PASS" and best_move != "RESIGN":
                return [MoveCandidate(
                    move=best_move,
                    winrate=0.5,
                    score_lead=0.0,
                    visits=visits,
                )]
            
            return []
    
    def _parse_kata_analyze_line(self, line: str, top_n: int) -> List[MoveCandidate]:
        """
        Parse kata-analyze output line.
        
        Format: info move Q3 visits 45 winrate 0.523445 scoreLead 0.312 prior 0.0892 order 0 pv Q3 R4 Q5 info move R4 ...
        Note: winrate is a decimal (0.52 = 52%), scoreLead is in points (positive = good for player to move)
        """
        moves = []
        parts = re.split(r'info move\s+', line)
        
        for part in parts[1:]:
            if not part.strip():
                continue
            
            words = part.split()
            if not words:
                continue
            move_name = words[0].upper()
            
            visits_match = re.search(r'visits\s+(\d+)', part)
            winrate_match = re.search(r'winrate\s+([\d.]+)', part)
            score_match = re.search(r'scoreLead\s+(-?[\d.]+)', part)
            
            if visits_match and winrate_match:
                try:
                    move_visits = int(visits_match.group(1))
                    # kata-analyze winrate is already a decimal (0.52 = 52%)
                    winrate = float(winrate_match.group(1))
                    # scoreLead is in points, positive = good for player to move
                    score_lead = float(score_match.group(1)) if score_match else 0.0
                    
                    moves.append(MoveCandidate(
                        move=move_name,
                        visits=move_visits,
                        winrate=winrate,
                        score_lead=score_lead,
                    ))
                except (ValueError, AttributeError):
                    continue
        
        # Sort by visits (descending) to get moves with most analysis
        moves.sort(key=lambda m: m.visits, reverse=True)
        return moves[:top_n]
    
    def _parse_analyze_output(self, output: str, top_n: int) -> List[MoveCandidate]:
        """
        Parse kata-analyze output.
        
        KataGo kata-analyze output format:
        info move Q3 visits 45 winrate 0.523445 scoreLead 0.312 prior 0.0892 order 0 pv Q3 R4 Q5
        info move R4 visits 38 winrate 0.518923 scoreLead 0.287 prior 0.0756 order 1 pv R4 Q3 R6
        
        Args:
            output: Raw output from kata-analyze
            top_n: Number of moves to return
            
        Returns:
            List of MoveCandidate objects sorted by visits
        """
        moves = []
        
        for line in output.strip().split("\n"):
            line = line.strip()
            if not line.startswith("info move"):
                continue
            
            move_data = self._parse_info_line(line)
            if move_data:
                moves.append(move_data)
        
        # Sort by visits (descending) and take top N
        moves.sort(key=lambda m: m.visits, reverse=True)
        return moves[:top_n]
    
    def _parse_info_line(self, line: str) -> Optional[MoveCandidate]:
        """
        Parse a single info line from kata-analyze output.
        
        Args:
            line: Single line starting with "info move"
            
        Returns:
            MoveCandidate if parsing succeeds, None otherwise
        """
        # Use regex to extract key-value pairs
        patterns = {
            'move': r'move\s+(\S+)',
            'visits': r'visits\s+(\d+)',
            'winrate': r'winrate\s+([\d.]+)',
            'scoreLead': r'scoreLead\s+(-?[\d.]+)',
        }
        
        values = {}
        for key, pattern in patterns.items():
            match = re.search(pattern, line)
            if match:
                values[key] = match.group(1)
        
        # Ensure we have all required fields
        if not all(k in values for k in ['move', 'visits', 'winrate', 'scoreLead']):
            return None
        
        try:
            return MoveCandidate(
                move=values['move'],
                visits=int(values['visits']),
                winrate=float(values['winrate']),
                score_lead=float(values['scoreLead']),
            )
        except (ValueError, KeyError):
            return None
    
    def get_model_name(self) -> str:
        """
        Get the name/version of the loaded model.
        
        Returns:
            Model name string
        """
        return self.model_name
    
    def is_running(self) -> bool:
        """Check if the KataGo process is running."""
        return (
            self._started 
            and self.process is not None 
            and self.process.poll() is None
        )
    
    def shutdown(self) -> None:
        """
        Gracefully shutdown the KataGo process.
        
        Sends 'quit' command and waits for process to terminate.
        Safe to call multiple times.
        """
        with self._lock:
            if self.process is None:
                return
            
            try:
                # Send quit command
                if self.process.poll() is None:  # Still running
                    try:
                        if self.process.stdin is not None:
                            self.process.stdin.write("quit\n")
                            self.process.stdin.flush()
                    except (BrokenPipeError, OSError):
                        pass  # Process already dead
                    
                    # Wait for graceful shutdown
                    try:
                        self.process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        # Force kill
                        self.process.kill()
                        self.process.wait(timeout=2)
            except Exception:
                # Last resort
                if self.process.poll() is None:
                    self.process.kill()
            finally:
                self.process = None
                self._started = False
    
    def __enter__(self) -> 'KataGoGTP':
        """Context manager entry."""
        self.start()
        return self
    
    def __exit__(self, *args) -> None:
        """Context manager exit."""
        self.shutdown()
    
    def __del__(self):
        """Destructor - ensure cleanup."""
        try:
            self.shutdown()
        except Exception:
            pass
    
    def __repr__(self) -> str:
        status = "running" if self.is_running() else "stopped"
        return f"KataGoGTP(status={status}, model={self.model_name})"


# ============================================================================
# Singleton Instance (Optional)
# ============================================================================

_global_katago: Optional[KataGoGTP] = None


def get_katago(config: KataGoConfig) -> KataGoGTP:
    """
    Get or create a global KataGo instance.
    
    Useful for CLI applications that want a single shared instance.
    
    Args:
        config: KataGo configuration
        
    Returns:
        KataGoGTP instance
    """
    global _global_katago
    
    if _global_katago is None:
        _global_katago = KataGoGTP(config)
    
    return _global_katago


def shutdown_global_katago() -> None:
    """Shutdown the global KataGo instance if it exists."""
    global _global_katago
    
    if _global_katago is not None:
        _global_katago.shutdown()
        _global_katago = None
