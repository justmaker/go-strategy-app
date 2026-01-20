g# Go Strategy Analysis Tool

A web-based Go (Weiqi/Baduk) strategy analyzer powered by KataGo.

## Features

- **Interactive Board**: Click to place stones on 9x9, 13x13, or 19x19 boards
- **KataGo Analysis**: Get AI-powered move suggestions with winrate and score estimates
- **Visual Suggestions**: Candidates colored by quality (Score Loss):
  - 🔵 **Blue**: Best Move
  - 🟢 **Green**: Loss < 1.0 points
  - 🟡 **Yellow**: Loss < 3.0 points
- **Opening Book**: Pre-calculate standard openings (especially 9x9) with pruning logic
- **Database Tools**: Auto-seeding DB and Git-friendly export tools

## Requirements

- Python 3.8+
- KataGo (CPU or GPU version)
- KataGo neural network model
- Dependencies: `streamlit`, `matplotlib`, `pyyaml`, `streamlit-image-coordinates`, `pillow`, `tqdm`

## Installation

1. Clone the repository:
```bash
git clone https://github.com/justmaker/go-strategy-app.git
cd go-strategy-app
```

2. Create virtual environment:
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
# Or manually: pip install streamlit matplotlib pyyaml streamlit-image-coordinates pillow tqdm
```

3. Download KataGo:
   - Run the setup script (Linux/Mac) to download KataGo + Model automatically:
     ```bash
     ./setup_katago.sh
     ```
   - OR manually place them in the `katago/` directory.

4. Configure `config.yaml` (already set up by default script).

## Usage

### Web Interface
```bash
source venv/bin/activate
streamlit run src/gui.py
```
Access at http://localhost:8501

### Opening Book Generator
Run this to pre-calculate the 9x9 opening book (Top 3 moves, 10 ply depth):
```bash
python3 src/scripts/build_opening_book.py
```

### Database Management
Export your current DB to a seed file (for committing to Git):
```bash
python3 src/scripts/export_db.py
```

## Project Structure

```
go-strategy-app/
├── src/
│   ├── gui.py           # Streamlit web interface
│   ├── analyzer.py      # GoAnalyzer orchestration
│   ├── scripts/         # Helper scripts
│   │   ├── build_opening_book.py  # 9x9 opening book generator
│   │   └── export_db.py           # DB to SQL dump utility
│   ├── assets/          
│   │   └── seed_data.sql # Initial database seed
│   ├── katago_gtp.py    # KataGo GTP communication
│   ├── board.py         # Board state management
│   ├── cache.py         # SQLite caching (w/ auto-seeding)
│   └── config.py        # Configuration loading
├── katago/
│   ├── katago           # KataGo binary (not in git)
│   ├── *.bin.gz         # Neural network (not in git)
│   └── *.cfg            # Config files
├── config.yaml          # Main configuration
└── README.md
```

## Understanding the Analysis

- **Win%**: The current player's probability of winning after making this move
- **Score**: Expected point lead (positive = good for current player)

Note: With 7.5 komi, White starts with an advantage, so Black's opening moves may show lower winrates.

## License

MIT License
