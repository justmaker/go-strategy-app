# Go Strategy Analysis Tool

A Go (Weiqi/Baduk) strategy analysis application powered by KataGo AI. Features a web GUI, REST API, CLI, and automated opening book generation with intelligent caching.

## Features

- **Interactive Web GUI**: Click-to-play interface with real-time AI analysis
- **REST API**: Cross-platform access for mobile/desktop clients (Flutter-ready)
- **KataGo Integration**: World-class AI move suggestions with winrate and score estimates
- **Smart Caching**: SQLite-based cache with D4 symmetry optimization (8x efficiency)
- **Opening Book Generator**: Automated BFS exploration with configurable scheduling
- **Multi-Board Support**: 9x9, 13x13, and 19x19 boards
- **Visual Move Quality**: Color-coded suggestions (Blue=Best, Green=Good, Yellow=OK)

## Requirements

- Python 3.8+
- KataGo binary (CPU or GPU version)
- KataGo neural network model (e.g., `kata1-b18c384nbt-*.bin.gz`)

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/justmaker/go-strategy-app.git
cd go-strategy-app
```

### 2. Set Up Python Environment

```bash
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 3. Set Up KataGo

**Option A: Automatic Setup (Linux/Mac)**
```bash
./setup_katago.sh
```

**Option B: Manual Setup**
1. Download KataGo from [KataGo Releases](https://github.com/lightvector/KataGo/releases)
2. Download a neural network model (b18 recommended for CPU)
3. Place files in the `katago/` directory
4. Update paths in `config.yaml`

### 4. Configure (Optional)

Edit `config.yaml` to customize:
- KataGo paths (auto-detected for Mac/Linux)
- Default visit counts for analysis
- Database location

## Usage

### Web GUI (Streamlit)

```bash
source venv/bin/activate
streamlit run src/gui.py --server.port 8501
```

Access at **http://localhost:8501**

Features:
- Click on board to place stones
- Automatic AI analysis after each move
- Adjustable board size and komi
- View top 3 move candidates with statistics

### REST API (FastAPI)

```bash
source venv/bin/activate
uvicorn src.api:app --host 0.0.0.0 --port 8000
```

Access:
- API: **http://localhost:8000**
- Swagger Docs: **http://localhost:8000/docs**
- OpenAPI Spec: **http://localhost:8000/openapi.json**

Example requests:
```bash
# Health check
curl http://localhost:8000/health

# Analyze a position
curl -X POST http://localhost:8000/analyze \
  -H "Content-Type: application/json" \
  -d '{"board_size": 9, "moves": ["B E5", "W C3"], "komi": 7.5}'

# Query cache only (fast)
curl -X POST http://localhost:8000/query \
  -H "Content-Type: application/json" \
  -d '{"board_size": 9, "moves": ["B E5"]}'
```

### Command Line Interface

```bash
source venv/bin/activate

# Analyze a position
python -m src.cli --size 19 --moves "B Q16" "W D4" "B Q3"

# 9x9 board analysis
python -m src.cli --size 9 --moves "B E5" "W C3"

# Handicap game (4 stones, White to play)
python -m src.cli --size 19 --handicap 4 --moves "W E4"

# Custom komi
python -m src.cli --size 19 --komi 6.5 --moves "B D4"

# Force refresh (bypass cache)
python -m src.cli --size 19 --moves "B Q16" --refresh

# View cache statistics
python -m src.cli --stats
```

### Opening Book Generator

Pre-calculate opening positions for fast cache hits:

```bash
source venv/bin/activate

# Run immediately with default settings (50 visits, depth 10)
python -m src.scripts.build_opening_book

# Custom visits and depth
python -m src.scripts.build_opening_book --visits 100 --depth 8

# Schedule for later (e.g., overnight run at 20:00)
python -m src.scripts.build_opening_book --visits 50 --start-at 20:00

# Start immediately with explicit flag
python -m src.scripts.build_opening_book --visits 50 --start-at now

# Different board size
python -m src.scripts.build_opening_book --board-size 13 --visits 100
```

The generator uses BFS with pruning:
- Explores top 3 moves at each position
- Prunes branches where winrate drops >10% from best move
- Uses symmetry-aware hashing to avoid redundant calculations

### Database Management

```bash
# Export database to SQL (for version control)
python -m src.scripts.export_db

# The seed file at src/assets/seed_data.sql is auto-loaded on first run
```

## Project Structure

```
go-strategy-app/
├── src/
│   ├── api.py              # FastAPI REST API
│   ├── gui.py              # Streamlit web interface
│   ├── cli.py              # Command-line interface
│   ├── analyzer.py         # Main analysis orchestration
│   ├── board.py            # Board state & symmetry transforms
│   ├── cache.py            # SQLite caching layer
│   ├── config.py           # Configuration management
│   ├── database.py         # Database seeding utilities
│   ├── katago_gtp.py       # KataGo GTP communication
│   ├── scripts/
│   │   ├── build_opening_book.py  # Opening book generator
│   │   └── export_db.py           # DB export utility
│   └── assets/
│       └── seed_data.sql   # Initial database seed
├── katago/
│   ├── katago              # KataGo binary (not in git)
│   ├── *.bin.gz            # Neural network model (not in git)
│   └── *.cfg               # KataGo config files
├── data/
│   └── analysis.db         # SQLite cache database
├── config.yaml             # Application configuration
├── requirements.txt        # Python dependencies
└── README.md
```

## Understanding the Analysis

| Metric | Description |
|--------|-------------|
| **Win%** | Probability of winning for the player to move |
| **Score** | Expected point lead (positive = ahead) |
| **Visits** | MCTS simulations for this move (higher = more confident) |

**Move Colors:**
- 🔵 **Blue**: Best move
- 🟢 **Green**: Score loss < 1.0 points
- 🟡 **Yellow**: Score loss < 3.0 points

**Note:** With 7.5 komi, White has compensation for going second. Black's opening moves may show ~48% winrate, which is normal.

## Configuration

`config.yaml` supports multi-platform paths:

```yaml
katago:
  mac:
    katago_path: "katago/katago-mac"
    model_path: "katago/model.bin.gz"
    config_path: "katago/gtp.cfg"
  linux:
    katago_path: "katago/katago"
    model_path: "katago/model.bin.gz"
    config_path: "katago/gtp.cfg"

analysis:
  default_komi: 7.5
  visits_19x19: 150
  visits_small: 500    # For 9x9 and 13x13
  top_moves_count: 3

database:
  path: "data/analysis.db"
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Service health check |
| POST | `/analyze` | Analyze position (may invoke KataGo) |
| POST | `/query` | Cache-only lookup (fast) |
| GET | `/stats` | Cache statistics |

## Development Roadmap

- [x] Phase 1: Core Analysis Engine
  - [x] KataGo GTP integration
  - [x] SQLite caching with symmetry optimization
  - [x] Streamlit GUI
  - [x] Opening book generator
- [x] Phase 2: Cross-Platform API
  - [x] FastAPI REST endpoints
  - [x] Pydantic models (OpenAPI spec)
- [ ] Phase 3: Mobile Client
  - [ ] Flutter app for iOS/Android
  - [ ] Offline-first with local cache sync

## License

MIT License

## Acknowledgments

- [KataGo](https://github.com/lightvector/KataGo) - The incredible Go AI engine
- [Streamlit](https://streamlit.io/) - Rapid web app framework
- [FastAPI](https://fastapi.tiangolo.com/) - Modern Python web framework
