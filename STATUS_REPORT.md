# Project Status Report

**Date:** 2026-01-23
**Status:** 🟢 Stable / Active Development

## Recent Achievements
- **UI/UX Overhaul**:
    - Fixed sidebar overlap issues with custom CSS layout.
    - Reordered sidebar information hierarchy (Next -> History -> Analysis).
    - Fixed visual glitches with stone coordinates and move history mismatch.
- **Core Logic Fixes**:
    - Unified coordinate systems between GUI and Core Logic (GTP standard `row 1 = bottom`).
    - Fixed `coords_to_gtp` calculation error causing click displacements.
    - Implemented correct color-coding logic for suggested moves based on winrate drop.
- **Data Engineering**:
    - Created automation script `run_data_generation.sh` for multi-size board data generation.
    - Generated preliminary 9x9 opening book (~5500 nodes) cached in SQLite.
    - Verified cache integration in GUI (sub-second response for cached openings).
- **Session Management**:
    - Refactored session handling to be ephemeral (browser-session based) rather than disk-persistent, improving UX for reset scenarios.

## Current System State
- **Web GUI**: Fully functional, responsive, and aesthetically improved.
- **Analysis Engine**: Using KataGo (CPU) with caching layer active.
- **Data**: `data/analysis.db` contains ~5.5k records for 9x9.

## Pending Tasks
- [ ] **Data Generation**: Complete 13x13 (300 visits) and 19x19 (100 visits) runs (Recommended on GPU).
- [ ] **API Verification**: Ensure REST API coordinates align with the recent GUI coordinate fixes.
- [ ] **Mobile Integration**: Verify Flutter app works with the latest backend changes.

## Known Issues
- CPU-based generation is slow for deep searches (Depth > 8).
- Sidebar padding is hardcoded (`10rem`), might need adjustment on ultra-wide or very narrow displays.
