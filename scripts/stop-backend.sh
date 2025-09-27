#!/usr/bin/env bash

# Stop backend development environment
# This script stops cargo watch, cargo run processes, and the PostgreSQL database

echo "🛑 Stopping backend development environment..."

# Kill cargo watch and cargo run processes
echo "Stopping cargo processes..."
pkill -f 'cargo watch' && pkill -f 'cargo run'

# Stop and remove database container
echo "Stopping database..."
docker-compose down

echo "Backend and database stopped"
