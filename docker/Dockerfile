FROM julia:1.11

WORKDIR /app

# Install system dependencies required for ADRIA
# - git: for Pkg.add(url=...)
# - xorg/libx11/libgl1: often needed for Makie (even headless CairoMakie sometimes checks for libs)
# - ca-certificates: for secure S3/HTTP operations
RUN apt-get update && apt-get install -y \
    git \
    curl \
    ca-certificates \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Try to coerce Julia to build across multiple targets (Optimization)
ENV JULIA_CPU_TARGET=x86_64;haswell;skylake;skylake-avx512;tigerlake

# Copy project files
COPY ./src /app/src
COPY ./Manifest.toml /app/Manifest.toml
COPY ./Project.toml /app/Project.toml

# Instantiate environment and precompile
# We strictly use the requested module name: CoralbloxCf
RUN julia -t auto --project=. \
    -e "using Pkg; Pkg.instantiate(); using CoralbloxCf; Pkg.precompile();"

# Setup Entrypoint
COPY ./docker/docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Runtime Environment Variables (Defaults)
# DATA_PACKAGE_PATH: Where the input data (Moore/GBR folders) are mounted
# ADRIA_OUTPUT_DIR: Scratch space for intermediate processing
ENV DATA_PACKAGE_PATH="/data/inputs"
ENV ADRIA_OUTPUT_DIR="/tmp/adria_scratch"

# Entrypoint
# Validates mounts and hands off to Julia
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh", "julia", "--project=.", "-t", "auto", "-e"]

# Default Command
# Executes the run() function exported by your wrapper module
CMD ["using CoralbloxCf; CoralbloxCf.run()"]
