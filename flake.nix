{
  description = "A tasty, self-hostable Git server for the command line";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = { self, nixpkgs, flake-utils, treefmt-nix }:
    let
      version = "0.8.3"; # Update this to match the actual version
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in
    flake-utils.lib.eachSystem supportedSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Helper function to create rooted commands
        rooted = text:
          builtins.concatStringsSep "\n" [
            ''
              if [ -z "$SOFT_SERVE_ROOT" ]; then
                SOFT_SERVE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              fi
            ''
            text
          ];

        # Script definitions for development commands
        scripts = {
          # Editor commands
          dx = {
            text = rooted ''$EDITOR "$SOFT_SERVE_ROOT"/flake.nix'';
            description = "Edit flake.nix";
          };
          gx = {
            text = rooted ''$EDITOR "$SOFT_SERVE_ROOT"/go.mod'';
            description = "Edit go.mod";
          };

          # Build and run commands
          build = {
            text = rooted ''
              cd "$SOFT_SERVE_ROOT"
              go build -ldflags "-X main.Version=dev -X main.CommitSHA=$(git rev-parse HEAD) -X main.CommitDate=$(date -u +%Y-%m-%dT%H:%M:%SZ)" ./cmd/soft
            '';
            description = "Build soft serve binary";
            runtimeInputs = with pkgs; [ go git ];
          };

          run = {
            text = rooted ''
              cd "$SOFT_SERVE_ROOT"
              go run ./cmd/soft serve
            '';
            description = "Run soft serve server";
            runtimeInputs = with pkgs; [ go git ];
          };

          run-dev = {
            text = rooted ''
              cd "$SOFT_SERVE_ROOT"
              export SOFT_SERVE_DATA_PATH="$SOFT_SERVE_ROOT/.soft-serve"
              ADMIN_KEYS="$(cat ~/.ssh/id_*.pub 2>/dev/null | head -1)"
              export SOFT_SERVE_INITIAL_ADMIN_KEYS="$ADMIN_KEYS"
              go run ./cmd/soft serve
            '';
            description = "Run soft serve in development mode with local data";
            runtimeInputs = with pkgs; [ go git ];
          };

          # Testing commands
          test = {
            text = rooted ''
              cd "$SOFT_SERVE_ROOT"
              go test -v ./...
            '';
            description = "Run all tests";
            runtimeInputs = with pkgs; [ go git ];
          };

          test-integration = {
            text = rooted ''
              cd "$SOFT_SERVE_ROOT"
              go test -v ./testscript/...
            '';
            description = "Run integration tests";
            runtimeInputs = with pkgs; [ go git ];
          };

          test-postgres = {
            text = rooted ''
              cd "$SOFT_SERVE_ROOT"
              export SOFT_SERVE_DB_DRIVER=postgres
              export SOFT_SERVE_DB_DATA_SOURCE="postgres://postgres:postgres@localhost/postgres?sslmode=disable"
              go test -v ./...
            '';
            description = "Run tests with PostgreSQL backend";
            runtimeInputs = with pkgs; [ go git postgresql ];
          };

          # Linting and formatting
          lint = {
            text = rooted ''
              cd "$SOFT_SERVE_ROOT"
              golangci-lint run
            '';
            description = "Run golangci-lint";
            runtimeInputs = with pkgs; [ golangci-lint ];
          };

          fmt = {
            text = rooted ''
              cd "$SOFT_SERVE_ROOT"
              go fmt ./...
              nix fmt
            '';
            description = "Format Go and Nix code";
            runtimeInputs = with pkgs; [ go nixpkgs-fmt ];
          };

          # Utility commands
          clean = {
            text = rooted ''
              cd "$SOFT_SERVE_ROOT"
              rm -rf .soft-serve
              git clean -fdx
            '';
            description = "Clean project and development data";
          };

          update-deps = {
            text = rooted ''
              cd "$SOFT_SERVE_ROOT"
              go mod tidy
              go mod download
            '';
            description = "Update Go dependencies";
            runtimeInputs = with pkgs; [ go git ];
          };

          # Docker commands
          docker-build = {
            text = rooted ''
              cd "$SOFT_SERVE_ROOT"
              docker build -t soft-serve:dev .
            '';
            description = "Build Docker image";
            runtimeInputs = with pkgs; [ docker ];
          };

          docker-run = {
            text = rooted ''
              docker run -it --rm \
                -p 23231:23231 \
                -p 23232:23232 \
                -p 23233:23233 \
                -p 9418:9418 \
                -v "$HOME/.ssh/id_ed25519.pub:/root/.ssh/authorized_keys.d/admin" \
                soft-serve:dev
            '';
            description = "Run Docker container";
            runtimeInputs = with pkgs; [ docker ];
          };

          # Release commands
          release-snapshot = {
            text = rooted ''
              cd "$SOFT_SERVE_ROOT"
              goreleaser build --snapshot --clean
            '';
            description = "Build release snapshot with GoReleaser";
            runtimeInputs = with pkgs; [ goreleaser go git ];
          };
        };

        # Convert scripts to packages
        scriptPackages = pkgs.lib.mapAttrs
          (name: script:
            pkgs.writeShellApplication {
              inherit name;
              inherit (script) text;
              runtimeInputs = script.runtimeInputs or [];
              runtimeEnv = script.env or {};
            }
          )
          scripts;
      in
      {
        packages = {
          default = self.packages.${system}.soft-serve;

          soft-serve = pkgs.buildGoModule rec {
            pname = "soft-serve";
            inherit version;

            src = self;

            vendorHash = "sha256-G/W1nA59vNtKR74iieOhfW1onTaNbYS8hAQI86j4dlU=";

            # Disable CGO as per the project's build requirements
            env.CGO_ENABLED = 0;

            ldflags = [
              "-s"
              "-w"
              "-X main.Version=v${version}"
              "-X main.CommitSHA=${if (self ? rev) then self.rev else "dev"}"
              "-X main.CommitDate=${if (self ? lastModifiedDate) then self.lastModifiedDate else "unknown"}"
            ];

            # The main package is in cmd/soft
            subPackages = [ "cmd/soft" ];

            # Runtime dependencies
            buildInputs = [ pkgs.git ];

            # Rename the binary from 'soft' to 'soft-serve' for clarity
            postInstall = ''
              mv $out/bin/soft $out/bin/soft-serve

              # Generate completions
              mkdir -p $out/share/bash-completion/completions
              mkdir -p $out/share/zsh/site-functions
              mkdir -p $out/share/fish/vendor_completions.d

              $out/bin/soft-serve completion bash > $out/share/bash-completion/completions/soft-serve
              $out/bin/soft-serve completion zsh > $out/share/zsh/site-functions/_soft-serve
              $out/bin/soft-serve completion fish > $out/share/fish/vendor_completions.d/soft-serve.fish

              # Generate man page
              mkdir -p $out/share/man/man1
              $out/bin/soft-serve man > $out/share/man/man1/soft-serve.1
            '';

            meta = with pkgs.lib; {
              description = "A tasty, self-hostable Git server for the command line";
              homepage = "https://github.com/charmbracelet/soft-serve";
              license = licenses.mit;
              maintainers = with maintainers; [ ];
              mainProgram = "soft-serve";
            };
          };
        } // pkgs.lib.genAttrs (builtins.attrNames scripts) (
          name: scriptPackages.${name}
        );

        devShells = {
          default = pkgs.mkShell {
            shellHook = ''
              echo "Welcome to Soft Serve development environment!"
              echo ""
              echo "Available commands:"
              ${pkgs.lib.concatStringsSep "\n" (
                pkgs.lib.mapAttrsToList (name: script:
                  ''echo "  ${name} - ${script.description}"''
                ) scripts
              )}
              echo ""
              echo "Quick start:"
              echo "  run-dev    - Start a development server"
              echo "  test       - Run all tests"
              echo "  lint       - Run linters"
              echo ""

              # Set up development environment
              export SOFT_SERVE_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
            '';

            buildInputs = with pkgs; [
              # Go development
              go_1_24
              gopls
              gotools
              go-tools
              golangci-lint
              goreleaser
              delve
              go-mockery
              gomodifytags
              gotests
              iferr
              impl
              reftools
              gogetdoc
              gofumpt
              golines

              # Database tools
              postgresql
              sqlite
              sqlc

              # Git and VCS
              git
              gh
              git-lfs

              # Development utilities
              gnumake
              jq
              yq
              curl
              wget
              httpie

              # Container tools
              docker
              docker-compose

              # Text processing
              ripgrep
              fd
              bat
              eza

              # Nix tools
              nixpkgs-fmt
              nil
              statix
              deadnix
              nix-tree

              # SSH tools for testing
              openssh
            ] ++ builtins.attrValues scriptPackages;
          };

          # Minimal shell for CI/CD
          ci = pkgs.mkShell {
            buildInputs = with pkgs; [
              go_1_23
              git
              golangci-lint
              postgresql
            ];
          };
        };

        # Formatter configuration using treefmt
        formatter = let
          treefmtModule = {
            projectRootFile = "flake.nix";
            programs = {
              # Nix formatting
              nixpkgs-fmt.enable = true;

              # Go formatting
              gofmt.enable = true;
              gofumpt.enable = true;
              golines.enable = true;

              # General formatting
              prettier = {
                enable = true;
                includes = [ "*.md" "*.yml" "*.yaml" "*.json" ];
              };
            };

            settings.formatter = {
              # Configure golines
              golines = {
                options = [ "-m" "120" "--base-formatter" "gofumpt" ];
              };
            };
          };
        in
          treefmt-nix.lib.mkWrapper pkgs treefmtModule;
      }) // {
        nixosModules.default = { config, lib, pkgs, ... }:
          with lib;
          let
            cfg = config.services.soft-serve;
            settingsFormat = pkgs.formats.yaml { };
            configFile = settingsFormat.generate "config.yaml" cfg.settings;
          in
          {
            options.services.soft-serve = {
              enable = mkEnableOption "Soft Serve Git server";

              package = mkOption {
                type = types.package;
                default = self.packages.${pkgs.system}.soft-serve;
                defaultText = literalExpression "pkgs.soft-serve";
                description = "The Soft Serve package to use";
              };

              dataDir = mkOption {
                type = types.path;
                default = "/var/lib/soft-serve";
                description = "Directory to store Soft Serve data (repositories, database, etc.)";
              };

              user = mkOption {
                type = types.str;
                default = "soft-serve";
                description = "User account under which Soft Serve runs";
              };

              group = mkOption {
                type = types.str;
                default = "soft-serve";
                description = "Group under which Soft Serve runs";
              };

              settings = mkOption {
                type = types.submodule {
                  freeformType = settingsFormat.type;
                  options = {
                    name = mkOption {
                      type = types.str;
                      default = "Soft Serve";
                      description = "The name of the server";
                    };

                    log = {
                      format = mkOption {
                        type = types.enum [ "json" "logfmt" "text" ];
                        default = "text";
                        description = "The log format to use";
                      };
                    };

                    ssh = {
                      listen_addr = mkOption {
                        type = types.str;
                        default = ":23231";
                        description = "The address on which the SSH server will listen";
                      };

                      public_url = mkOption {
                        type = types.str;
                        default = "ssh://localhost:23231";
                        description = "The public URL of the SSH server";
                      };
                    };

                    http = {
                      listen_addr = mkOption {
                        type = types.str;
                        default = ":23232";
                        description = "The address on which the HTTP server will listen";
                      };

                      public_url = mkOption {
                        type = types.str;
                        default = "http://localhost:23232";
                        description = "The public URL of the HTTP server";
                      };
                    };

                    git = {
                      listen_addr = mkOption {
                        type = types.str;
                        default = ":9418";
                        description = "The address on which the Git daemon will listen";
                      };
                    };

                    stats = {
                      listen_addr = mkOption {
                        type = types.str;
                        default = ":23233";
                        description = "The address on which the stats server will listen";
                      };
                    };

                    db = {
                      driver = mkOption {
                        type = types.enum [ "sqlite" "postgres" ];
                        default = "sqlite";
                        description = "The database driver to use";
                      };

                      data_source = mkOption {
                        type = types.str;
                        default = "";
                        description = "The database connection string. If empty, uses default for the driver";
                      };
                    };
                  };
                };
                default = { };
                description = ''
                  Configuration for Soft Serve. See the example config.yaml for all available options.
                '';
              };

              initialAdminKeys = mkOption {
                type = types.listOf types.str;
                default = [ ];
                example = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..." ];
                description = ''
                  SSH public keys for the initial admin user.
                  These keys will have full admin access to the server.
                '';
              };
            };

            config = mkIf cfg.enable {
              systemd.services.soft-serve = {
                description = "Soft Serve Git Server";
                after = [ "network.target" ];
                wantedBy = [ "multi-user.target" ];

                environment = {
                  SOFT_SERVE_DATA_PATH = cfg.dataDir;
                  SOFT_SERVE_INITIAL_ADMIN_KEYS = concatStringsSep "\n" cfg.initialAdminKeys;
                };

                serviceConfig = {
                  Type = "simple";
                  User = cfg.user;
                  Group = cfg.group;
                  ExecStart = "${cfg.package}/bin/soft-serve serve --config ${configFile}";
                  Restart = "always";
                  RestartSec = "10s";

                  # Security hardening
                  NoNewPrivileges = true;
                  PrivateTmp = true;
                  ProtectSystem = "strict";
                  ProtectHome = true;
                  ReadWritePaths = [ cfg.dataDir ];

                  # Allow binding to privileged ports if needed
                  AmbientCapabilities = mkIf (
                    (hasPrefix ":1-" cfg.settings.ssh.listen_addr) ||
                    (hasPrefix ":1-" cfg.settings.http.listen_addr) ||
                    (hasPrefix ":1-" cfg.settings.git.listen_addr)
                  ) [ "CAP_NET_BIND_SERVICE" ];
                };

                preStart = ''
                  # Ensure data directory exists with correct permissions
                  mkdir -p ${cfg.dataDir}
                  chmod 750 ${cfg.dataDir}
                '';
              };

              users.users = mkIf (cfg.user == "soft-serve") {
                soft-serve = {
                  isSystemUser = true;
                  group = cfg.group;
                  home = cfg.dataDir;
                  description = "Soft Serve Git server user";
                };
              };

              users.groups = mkIf (cfg.group == "soft-serve") {
                soft-serve = { };
              };
            };
          };
      };
}
