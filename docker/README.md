# Go Strategy Analysis Tool - Production Deployment

## Prerequisites
- Docker and Docker Compose
- KataGo binary and model files

## Quick Start

1. **Clone and setup**:
   ```bash
   git clone https://github.com/justmaker/go-strategy-app.git
   cd go-strategy-app
   ```

2. **Configure KataGo**:
   ```bash
   # Place KataGo files in katago/ directory:
   # - katago (binary)
   # - kata1-b18c384nbt-*.bin.gz (model)
   # - gtp.cfg (config)
   ```

3. **Start services**:
   ```bash
   docker-compose up -d
   ```

4. **Access applications**:
   - **Web GUI**: http://localhost:8501
   - **API**: http://localhost:8000
   - **API Docs**: http://localhost:8000/docs

## Services

### Backend API (FastAPI)
- Port: 8000
- Health check: http://localhost:8000/health
- Analysis: POST http://localhost:8000/analyze
- Query cache: POST http://localhost:8000/query

### Web GUI (Streamlit)
- Port: 8501
- Interactive Go board with AI analysis

### Database
- SQLite file: `data/analysis.db`
- Persistent volume: `./data`

## Configuration

### Environment Variables
- `KATAGO_MODEL`: Path to KataGo model (default: katago/model.bin.gz)
- `KATAGO_CONFIG`: Path to KataGo config (default: katago/gtp.cfg)
- `KATAGO_BINARY`: Path to KataGo binary (default: katago/katago)

### Volume Mounts
- `./data`: SQLite database
- `./katago`: KataGo files
- `./config.yaml`: Application config

## Development

### Local Development
```bash
# Backend only
docker-compose up api

# Web GUI only
docker-compose up web

# All services
docker-compose up
```

### Building Custom Images
```bash
# Build API image
docker build -t go-strategy-api ./docker/api

# Build Web image
docker build -t go-strategy-web ./docker/web
```

## Production Deployment

### Using Docker Compose
```yaml
version: '3.8'
services:
  api:
    image: ghcr.io/justmaker/go-strategy-app/api:latest
    ports:
      - "8000:8000"
    volumes:
      - ./data:/app/data
      - ./katago:/app/katago
    environment:
      - KATAGO_MODEL=katago/model.bin.gz
    restart: unless-stopped

  web:
    image: ghcr.io/justmaker/go-strategy-app/web:latest
    ports:
      - "8501:8501"
    depends_on:
      - api
    restart: unless-stopped
```

### Using Kubernetes
See `k8s/` directory for Kubernetes manifests.

## Monitoring

### Health Checks
- API: GET /health
- Web: Service responds on port 8501

### Logs
```bash
# View API logs
docker-compose logs api

# View Web logs
docker-compose logs web

# Follow all logs
docker-compose logs -f
```

## Backup

### Database Backup
```bash
# Stop services
docker-compose down

# Backup database
cp data/analysis.db data/analysis.db.backup

# Restart services
docker-compose up -d
```

## Troubleshooting

### Common Issues

1. **KataGo not found**:
   - Ensure KataGo binary is in `katago/katago`
   - Check file permissions: `chmod +x katago/katago`

2. **Model file not found**:
   - Place model file in `katago/` directory
   - Update `config.yaml` if using custom path

3. **Port conflicts**:
   - Change ports in `docker-compose.yml`
   - Ensure ports 8000 and 8501 are available

4. **Database issues**:
   - Check `./data` directory permissions
   - Ensure SQLite file is writable

### Performance Tuning

- **Analysis visits**: Adjust in `config.yaml`
- **Cache size**: Monitor disk usage in `./data`
- **Memory**: Increase Docker memory limits if needed