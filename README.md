# Go Strategy Analysis Tool

A web-based Go (Weiqi/Baduk) strategy analyzer powered by KataGo.

## Features

- **Interactive Board**: Click to place stones on 9x9, 13x13, or 19x19 boards
- **KataGo Analysis**: Get AI-powered move suggestions with winrate and score estimates
- **Visual Suggestions**: Top 3 moves displayed directly on the board
  - Blue = Best move
  - Green = 2nd best
  - Yellow = 3rd best
- **Auto-Analysis**: Automatically analyzes after each move
- **SQLite Caching**: Caches analysis results for instant replay

## Requirements

- Python 3.8+
- KataGo (CPU or GPU version)
- KataGo neural network model

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
pip install streamlit matplotlib pyyaml streamlit-image-coordinates pillow
```

3. Download KataGo:
   - Get KataGo from https://github.com/lightvector/KataGo/releases
   - Download a neural network model from https://katagotraining.org/
   - Place in `katago/` directory

4. Configure `config.yaml`:
```yaml
katago:
  katago_path: "/path/to/katago"
  model_path: "/path/to/model.bin.gz"
  config_path: "/path/to/config.cfg"
```

## Usage

```bash
source venv/bin/activate
streamlit run src/gui.py --server.address 0.0.0.0 --server.port 8501
```

Access the web interface at http://localhost:8501

## Project Structure

```
go-strategy-app/
├── src/
│   ├── gui.py           # Streamlit web interface
│   ├── analyzer.py      # GoAnalyzer orchestration
│   ├── katago_gtp.py    # KataGo GTP communication
│   ├── board.py         # Board state management
│   ├── cache.py         # SQLite caching
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
