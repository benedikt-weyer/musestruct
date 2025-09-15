# Musestruct 🎵

A cross-platform music library management application that helps you structure and organize your music collection. Stream from various services like Qobuz in hi-fi quality, manage local files, and create playlists - all in one beautiful interface.

## ✨ Features

### MVP Features (Current)
- **User Authentication**: Secure registration and login with session-based auth
- **Multiple Streaming Services**: Search and discover music from Qobuz and Spotify
- **Hi-Fi Streaming**: Stream music in lossless and hi-res quality (Qobuz)
- **Music Previews**: 30-second track previews (Spotify)
- **Service Selection**: Easy switching between streaming platforms
- **Cross-Platform**: Native apps for Android, iOS, Windows, macOS, and Linux
- **Modern UI**: Beautiful, responsive Material Design interface

### Planned Features
- **Local Music**: Import and manage your local music files
- **Additional Streaming Services**: Connect Tidal, Apple Music, YouTube Music, and more
- **Smart Playlists**: AI-powered playlist generation and recommendations
- **Music Organization**: Advanced tagging, metadata editing, and library organization
- **Sync Across Devices**: Keep your library synchronized across all devices
- **Social Features**: Share playlists and discover music from friends

## 🏗️ Architecture

### Backend (Rust)
- **Framework**: Axum web framework with Tokio async runtime
- **Database**: PostgreSQL with SeaORM for type-safe database operations
- **Authentication**: Session-based auth with Argon2 password hashing
- **API**: RESTful API with JSON responses
- **Streaming**: Interface-based design for multiple streaming service integrations

### Frontend (Flutter)
- **Framework**: Flutter for native cross-platform development
- **State Management**: Provider pattern for reactive state management
- **Audio**: just_audio for high-quality audio playback
- **HTTP**: Native HTTP client for API communication
- **Security**: flutter_secure_storage for secure token storage

### Infrastructure
- **Containerization**: Docker Compose for development and deployment
- **Development**: Nix flakes for reproducible development environment
- **Database**: PostgreSQL with automatic migrations

## 🚀 Quick Start

### Prerequisites
- [Nix](https://nixos.org/download.html) with flakes enabled
- Docker (for database)
- Qobuz account (for music streaming)

### Development Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd musestruct
   ```

2. **Enter development environment**
   ```bash
   nix develop
   ```

3. **Set up environment**
   ```bash
   ./dev-setup.sh
   ```
   This will generate database credentials and create the necessary `.env` files.

4. **Configure Streaming Services (Optional)**
   Edit `backend/.env` and add your streaming service credentials:
   ```bash
   # Qobuz (for hi-fi streaming)
   QOBUZ_APP_ID=your-qobuz-app-id
   QOBUZ_SECRET=your-qobuz-secret
   
   # Spotify (for music discovery)
   SPOTIFY_CLIENT_ID=your-spotify-client-id
   SPOTIFY_CLIENT_SECRET=your-spotify-client-secret
   ```

5. **Start the backend**
   ```bash
   start-backend
   ```
   This will start PostgreSQL and the Rust backend server.

6. **Start the Flutter app** (in a new terminal)
   ```bash
   flutter run
   ```

### Available Commands

- `start-backend` - Start PostgreSQL database and Rust backend with hot reload
- `stop-backend` - Stop both the backend server and database
- `flutter run` - Start the Flutter app
- `flutter build` - Build the app for production

## 📁 Project Structure

```
musestruct/
├── backend/                 # Rust backend
│   ├── src/
│   │   ├── models/         # Database models
│   │   ├── handlers/       # API route handlers
│   │   ├── services/       # Business logic services
│   │   └── main.rs         # Application entry point
│   ├── migrations/         # Database migrations
│   └── Cargo.toml         # Rust dependencies
├── lib/                    # Flutter frontend
│   ├── models/            # Data models
│   ├── services/          # API and audio services
│   ├── providers/         # State management
│   ├── screens/           # UI screens
│   ├── widgets/           # Reusable UI components
│   └── main.dart          # App entry point
├── docker-compose.yml     # PostgreSQL container
├── dev-setup.sh          # Development setup script
├── flake.nix             # Nix development environment
└── README.md             # This file
```

## 🔧 API Endpoints

### Authentication
- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - User login
- `POST /api/auth/logout` - User logout
- `GET /api/auth/me` - Get current user info

### Music Streaming
- `GET /api/streaming/search` - Search for music across services
- `GET /api/streaming/stream-url` - Get stream URL for a track
- `GET /api/streaming/services` - Get available streaming services
- `POST /api/streaming/connect/qobuz` - Connect Qobuz account
- `POST /api/streaming/connect/spotify` - Connect Spotify account

### Playlists (Coming Soon)
- `GET /api/playlists` - Get user playlists
- `POST /api/playlists` - Create new playlist
- `GET /api/playlists/:id` - Get playlist details

## 🎵 Streaming Services

### Qobuz Integration
Musestruct integrates with Qobuz to provide:
- **Hi-Res Audio**: Up to 24-bit/192kHz lossless streaming
- **Extensive Catalog**: Millions of tracks across all genres
- **High-Quality Metadata**: Rich album information and artwork
- **Full Track Streaming**: Complete songs for premium users

### Spotify Integration
Musestruct integrates with Spotify to provide:
- **Extensive Catalog**: Millions of tracks and comprehensive metadata
- **Music Discovery**: Leverage Spotify's powerful search algorithms
- **Track Previews**: 30-second high-quality previews via Web API
- **No Premium Required**: Works with free Spotify accounts

### Setup Instructions
To use streaming service integrations:

**Qobuz:**
1. Sign up for a Qobuz account
2. Obtain API credentials from Qobuz Developer Portal
3. Add credentials to your environment configuration

**Spotify:**
1. Create a Spotify Developer account
2. Create an application to get Client ID and Secret
3. Add credentials to your environment configuration

### Adding New Services
The streaming interface is designed to be extensible. To add a new service:

1. Implement the `StreamingService` trait
2. Add service-specific authentication
3. Register the service in the application
4. Update the frontend to support the new service

## 🛠️ Development

### Backend Development
```bash
# Start development server with hot reload
start-backend

# Run tests
cd backend && cargo test

# Check code
cd backend && cargo clippy

# Format code
cd backend && cargo fmt
```

### Frontend Development
```bash
# Start development with hot reload
flutter run

# Run tests
flutter test

# Build for production
flutter build <platform>

# Generate code (for JSON serialization)
flutter packages pub run build_runner build
```

### Database Management

Musestruct uses SeaORM migrations for database schema management.

```bash
# Migrations run automatically when starting the backend
start-backend

# Manual migration commands
cd backend

# Run all pending migrations
cargo run --bin migrate -- up

# Check migration status
cargo run --bin migrate -- status

# Rollback last migration
cargo run --bin migrate -- down

# Create a new migration
cargo run --bin migrate -- generate MIGRATION_NAME

# Reset database (warning: destroys all data)
docker-compose down -v
start-backend
```

### Database Access
```bash
# Connect to database directly
docker-compose exec postgres psql -U musestruct -d musestruct

# View migration history
docker-compose exec postgres psql -U musestruct -d musestruct -c "SELECT * FROM seaql_migrations;"
```

## 🚢 Deployment

### Backend Deployment
1. Build the Rust application:
   ```bash
   cd backend && cargo build --release
   ```

2. Set up PostgreSQL database
3. Configure environment variables
4. Run migrations and start the server

### Frontend Deployment
```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release

# Desktop
flutter build windows --release
flutter build macos --release
flutter build linux --release

# Web
flutter build web --release
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style
- **Rust**: Follow standard Rust conventions with `cargo fmt` and `cargo clippy`
- **Dart/Flutter**: Follow Dart style guide with `flutter format`
- **Commits**: Use conventional commit messages

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Axum](https://github.com/tokio-rs/axum) - Modern Rust web framework
- [SeaORM](https://github.com/SeaQL/sea-orm) - Async ORM for Rust
- [Flutter](https://flutter.dev) - Cross-platform UI framework
- [just_audio](https://pub.dev/packages/just_audio) - Flutter audio player
- [Qobuz](https://www.qobuz.com) - Hi-fi music streaming service

## 🐛 Known Issues

- Qobuz authentication requires valid API credentials
- Some streaming features require premium subscriptions
- Local file support is planned for future releases

## 📞 Support

If you encounter any issues or have questions:
1. Check the [Issues](https://github.com/your-repo/musestruct/issues) page
2. Create a new issue with detailed information
3. Join our community discussions

---

**Musestruct** - Structure your music, elevate your experience. 🎵