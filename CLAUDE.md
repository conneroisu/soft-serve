# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Soft Serve is a self-hostable Git server for the command line, developed by Charm. It provides:
- SSH-accessible TUI for browsing repositories
- Support for cloning repos over SSH, HTTP, and Git protocol
- Git LFS support with both HTTP and SSH backends
- User management and access control
- Webhook support for repository events
- Repository management via SSH commands

## Common Commands

### Development
```bash
# Install dependencies
go mod download
go mod tidy

# Build the server
go build ./cmd/soft

# Run the server (requires git to be installed)
go run ./cmd/soft serve

# Browse local repositories
go run ./cmd/soft browse
```

### Testing
```bash
# Run all tests
go test ./...

# Run tests with verbose output
go test -v ./...

# Run tests with Postgres backend
SOFT_SERVE_DB_DRIVER=postgres \
SOFT_SERVE_DB_DATA_SOURCE="postgres://postgres:postgres@localhost/postgres?sslmode=disable" \
go test ./...

# Run a specific test package
go test ./pkg/backend/...
go test ./pkg/ssh/...

# Run integration tests (uses testscript framework)
go test ./testscript/...
```

### Linting
```bash
# Requires golangci-lint installed
golangci-lint run

# The project uses multiple linters configured in .golangci.yml
```

### Release
```bash
# Build release binaries with GoReleaser
goreleaser build --snapshot --clean
```

## Architecture

### Core Components

1. **Command Layer (`cmd/soft/`)**
   - `serve/` - Main server implementation handling SSH, HTTP, and Git protocols
   - `admin/` - Administrative commands for server management
   - `browse/` - TUI browser for exploring repositories
   - `hook/` - Git hooks management

2. **Package Layer (`pkg/`)**
   - `access/` - Access control and authorization logic
   - `backend/` - Core backend services for repos, users, and auth
   - `config/` - Configuration management with YAML and env var support
   - `db/` - Database abstraction layer supporting SQLite and PostgreSQL
   - `git/` - Git operations, including LFS support
   - `ssh/` - SSH server implementation with command handling
   - `ui/` - Terminal UI components using Bubble Tea
   - `web/` - HTTP server for Git operations
   - `webhook/` - Webhook delivery system

3. **Server Protocols**
   - SSH server (default port 23231) - Git operations and TUI access
   - HTTP server (default port 23232) - Git HTTP protocol and LFS
   - Git daemon (default port 9418) - Git protocol support
   - Stats server (default port 23233) - Metrics endpoint

### Key Design Patterns

- **Context-based Configuration**: Config is passed through context for clean dependency injection
- **Interface-driven Backend**: Backend operations use interfaces for testability
- **Database Migrations**: Automatic schema migrations for both SQLite and PostgreSQL
- **SSH Command Router**: Maps SSH commands to handlers for Git and admin operations
- **Middleware Architecture**: HTTP and SSH servers use middleware for auth, logging, etc.

### Authentication & Authorization

- **SSH Authentication**: Public key authentication for users
- **HTTP Authentication**: Token-based auth using access tokens
- **Access Levels**: no-access, read-only, read-write, admin-access
- **Repository Collaborators**: Fine-grained access control per repository

### Testing Strategy

- **Unit Tests**: Standard Go testing for individual packages
- **Integration Tests**: `testscript` framework for end-to-end testing
- **Database Tests**: Support for both SQLite and PostgreSQL testing
- **Mock Interfaces**: Backend interfaces allow for easy mocking

## Development Notes

### Environment Variables
All configuration can be overridden with `SOFT_SERVE_` prefixed environment variables:
- `SOFT_SERVE_DATA_PATH` - Data directory location
- `SOFT_SERVE_SSH_LISTEN_ADDR` - SSH server address
- `SOFT_SERVE_HTTP_LISTEN_ADDR` - HTTP server address
- `SOFT_SERVE_DB_DRIVER` - Database driver (sqlite/postgres)
- `SOFT_SERVE_DB_DATA_SOURCE` - Database connection string
- `SOFT_SERVE_INITIAL_ADMIN_KEYS` - SSH keys for initial admin user

### First-time Setup
```bash
# Run with initial admin key
SOFT_SERVE_INITIAL_ADMIN_KEYS="$(cat ~/.ssh/id_ed25519.pub)" go run ./cmd/soft serve
```

### Database Considerations
- Default uses SQLite with foreign keys enabled
- PostgreSQL requires creating the database first: `CREATE DATABASE soft_serve`
- Migrations run automatically on startup

### Git Hooks
- Server-side hooks supported: pre-receive, update, post-update, post-receive
- Global hooks in `<data_path>/hooks/`
- Per-repository hooks in `<repo_path>/hooks/`

### SSH Server Details
- Uses Wish (Charm's SSH middleware framework)
- Commands routed through SSH command parser
- Git operations use git-upload-pack/git-receive-pack
- Admin commands require authentication and appropriate access level