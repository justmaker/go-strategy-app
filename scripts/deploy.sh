#!/bin/bash

# Go Strategy App - Production Deployment Script

set -e

# Ensure we are in the project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo "🚀 Go Strategy Analysis Tool - Deployment Script"
echo "==============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi

    print_status "Docker and Docker Compose are available"
}

# Check if KataGo files exist
check_katago() {
    if [ ! -f "katago/katago" ]; then
        print_warning "KataGo binary not found in katago/katago"
        print_warning "You may need to run setup_katago.sh or place the binary manually"
    else
        print_status "KataGo binary found"
    fi

    if ! ls katago/*.bin.gz 1> /dev/null 2>&1; then
        print_warning "KataGo model file not found in katago/"
        print_warning "Please download a KataGo model (recommended: b18)"
    else
        print_status "KataGo model file found"
    fi
}

# Setup data directory
setup_data() {
    mkdir -p data
    print_status "Data directory created"
}

# Build Docker images
build_images() {
    print_status "Building Docker images..."

    # Build API image
    docker build -t go-strategy-api:latest -f docker/api/Dockerfile .

    # Build Web image
    docker build -t go-strategy-web:latest -f docker/web/Dockerfile .

    print_status "Docker images built successfully"
}

# Start services
start_services() {
    print_status "Starting services..."

    docker-compose up -d

    print_status "Services started"
    print_status "Waiting for services to be ready..."

    # Wait for API to be healthy
    max_attempts=30
    attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -f http://localhost:8000/health &> /dev/null; then
            print_status "API is healthy"
            break
        fi

        echo "Waiting for API to be ready... ($attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done

    if [ $attempt -gt $max_attempts ]; then
        print_error "API failed to start within timeout"
        exit 1
    fi
}

# Show status
show_status() {
    echo ""
    echo "📊 Service Status:"
    echo "=================="

    echo "🔗 Web GUI: http://localhost:8501"
    echo "🔗 API: http://localhost:8000"
    echo "🔗 API Docs: http://localhost:8000/docs"

    echo ""
    echo "📋 Docker Services:"
    docker-compose ps

    echo ""
    echo "📝 Useful Commands:"
    echo "=================="
    echo "View logs: docker-compose logs -f"
    echo "Stop services: docker-compose down"
    echo "Restart: docker-compose restart"
    echo "Rebuild: docker-compose up --build -d"
}

# Main deployment function
deploy() {
    print_status "Starting deployment..."

    check_docker
    check_katago
    setup_data
    build_images
    start_services
    show_status

    echo ""
    print_status "🎉 Deployment completed successfully!"
    print_status "Your Go Strategy Analysis Tool is now running!"
}

# Stop services
stop() {
    print_status "Stopping services..."
    docker-compose down
    print_status "Services stopped"
}

# Restart services
restart() {
    print_status "Restarting services..."
    docker-compose restart
    print_status "Services restarted"
}

# Show logs
logs() {
    docker-compose logs -f
}

# Clean up
cleanup() {
    print_status "Cleaning up..."
    docker-compose down -v
    docker system prune -f
    print_status "Cleanup completed"
}

# Main script
case "${1:-deploy}" in
    "deploy")
        deploy
        ;;
    "start")
        start_services
        ;;
    "stop")
        stop
        ;;
    "restart")
        restart
        ;;
    "logs")
        logs
        ;;
    "cleanup")
        cleanup
        ;;
    "status")
        show_status
        ;;
    *)
        echo "Usage: $0 {deploy|start|stop|restart|logs|cleanup|status}"
        echo ""
        echo "Commands:"
        echo "  deploy   - Full deployment (default)"
        echo "  start    - Start services"
        echo "  stop     - Stop services"
        echo "  restart  - Restart services"
        echo "  logs     - Show service logs"
        echo "  cleanup  - Clean up containers and volumes"
        echo "  status   - Show service status"
        exit 1
        ;;
esac