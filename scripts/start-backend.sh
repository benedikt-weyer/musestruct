#!/usr/bin/env bash

# Start backend development with hot-reload
# This script starts the PostgreSQL database and runs cargo watch for hot-reload development

echo "🚀 Starting backend development environment..."

# Start PostgreSQL database
echo "Starting PostgreSQL database..."
docker-compose up -d postgres

# Wait a moment for database to be ready
sleep 2

# Start cargo watch for hot-reload development
echo "Starting cargo watch for hot-reload development..."
cargo watch -C backend -x run