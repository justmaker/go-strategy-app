# Handover Instructions: Go Strategy App

## Current State
- **Task**: We are pre-calculating the 9x9 opening book.
- **Progress**: The script `src/scripts/build_opening_book.py` has been created and verified on Mac.
- **Dependencies**: `tqdm` and `pyyaml` are required and listed in `requirements.txt`.

## Getting Started on Linux (OpenCode)

1. **Environment Setup**
   ```bash
   # Ensure you are in the project root
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

2. **KataGo Setup**
   - **Important**: Your local Mac build of KataGo (if copied over) will likely **NOT** work on Linux.
   - Run the setup script to fetch the Linux binary and model:
     ```bash
     chmod +x setup_katago.sh
     ./setup_katago.sh
     ```
   - This will populate the `katago/` directory with the Linux binary and the neural net model.
   - **Verification**: The `config.yaml` is already pre-configured for Linux to look in `katago/katago`.

3. **Running the Opening Book Generator**
   ```bash
   python3 src/scripts/build_opening_book.py
   ```
   - This script automatically uses the SQLite cache.
   - If you stop it (Ctrl+C), you can resume later; existing entries in the database won't be re-analyzed.

4. **Database**
   - The data is stored in `data/analysis.db`.
   - To export the finished book as seed data (e.g., for commiting to git):
     ```bash
     python3 src/scripts/export_db.py
     ```

## Next Steps
- Run the generation script until depth 10 is satisfactorily covered.
- Verify the generated database by running the GUI (`streamlit run src/gui.py`) and exploring the opening moves.
