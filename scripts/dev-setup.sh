#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Setting up Musestruct development environment...${NC}"

# Generate random secrets
generate_secret() {
    openssl rand -hex 32
}

SESSION_SECRET=$(generate_secret)
POSTGRES_PASSWORD="musestruct_$(openssl rand -hex 8)"

# Create .env file in backend directory
ENV_FILE="backend/.env"

if [ -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}⚠️  $ENV_FILE already exists. Backing up to $ENV_FILE.backup${NC}"
    cp "$ENV_FILE" "$ENV_FILE.backup"
fi

echo -e "${BLUE}📝 Creating $ENV_FILE with generated credentials...${NC}"

cat > "$ENV_FILE" << EOF
# Database Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=musestruct
POSTGRES_USER=musestruct
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
DATABASE_URL=postgresql://musestruct:$POSTGRES_PASSWORD@localhost:5432/musestruct

# Server Configuration
SERVER_HOST=127.0.0.1
SERVER_PORT=8080
RUST_LOG=debug

# Authentication
SESSION_SECRET=$SESSION_SECRET

# Streaming Services
QOBUZ_APP_ID=your-qobuz-app-id
QOBUZ_SECRET=your-qobuz-secret
SPOTIFY_CLIENT_ID=your-spotify-client-id
SPOTIFY_CLIENT_SECRET=your-spotify-client-secret

# CORS Configuration
CORS_ORIGIN=http://localhost:3000,http://127.0.0.1:3000
EOF

# Update docker-compose.yml environment variables
echo -e "${BLUE}📝 Creating .env file for Docker Compose...${NC}"

cat > ".env" << EOF
POSTGRES_DB=musestruct
POSTGRES_USER=musestruct
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_PORT=5432
EOF

echo -e "${GREEN}✅ Environment files created successfully!${NC}"
echo -e "${BLUE}📋 Generated credentials:${NC}"
echo -e "  Database: musestruct"
echo -e "  User: musestruct" 
echo -e "  Password: $POSTGRES_PASSWORD"
echo -e "  Session Secret: Generated"
echo
echo -e "${YELLOW}🔐 Remember to:${NC}"
echo -e "  1. Update QOBUZ_APP_ID and QOBUZ_SECRET in backend/.env"
echo -e "  2. Update SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET in backend/.env"
echo -e "  3. Keep your credentials secure"
echo -e "  4. Never commit .env files to version control"
echo
echo -e "${GREEN}🎉 Setup complete! You can now run 'start-backend' to start development.${NC}"
