# Use the official Rust image as the base image
FROM rust:1.90-trixie AS builder

# Set the working directory inside the container
WORKDIR /app

# Copy the Cargo.toml and Cargo.lock files
COPY Cargo.toml Cargo.lock ./

# Create dummy source files to build dependencies
RUN mkdir -p src/bin && \
    echo "fn main() {}" > src/main.rs && \
    echo "// dummy lib" > src/lib.rs && \
    echo "fn main() {}" > src/bin/migrate.rs

# Build dependencies (this will be cached if Cargo.toml doesn't change)
RUN cargo build --release && rm -rf src

# Copy the source code
COPY src ./src
COPY migrations ./migrations

# Build the application
RUN cargo build --release

# Use a smaller base image for the runtime
FROM debian:trixie-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
RUN useradd -m -u 1001 appuser

# Set the working directory
WORKDIR /app

# Copy the binary from the builder stage
COPY --from=builder /app/target/release/musestruct_backend /app/musestruct_backend
COPY --from=builder /app/target/release/migrate /app/migrate

# Create directories for cache and music
RUN mkdir -p /app/cache /app/own_music && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose the port the app runs on
EXPOSE 8080

# Set environment variables
ENV RUST_LOG=info
ENV DATABASE_URL=postgresql://musestruct:musestruct123@postgres:5432/musestruct

# Run the application
CMD ["./musestruct_backend"]
