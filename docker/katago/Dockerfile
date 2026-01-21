FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy KataGo setup script
COPY setup_katago.sh .
RUN chmod +x setup_katago.sh

# Create katago directory
RUN mkdir -p katago

# Note: KataGo binary and model files should be mounted as volumes
# The setup script can be run manually if needed

CMD ["/bin/bash"]