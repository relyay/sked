# Build artifacts go to dist/.

version := `git describe --tags --always --dirty 2>/dev/null || echo dev`
dist := justfile_directory() / "dist"
# podman if installed, otherwise docker; override with ENGINE=docker.
engine := env("ENGINE", `command -v podman >/dev/null 2>&1 && echo podman || echo docker`)

# List targets.
default:
    @just --list

# Build the server container image used by compose.yaml (localhost/sked-server:latest).
server:
    {{engine}} build --build-arg VERSION={{version}} -t localhost/sked-server:latest -t localhost/sked-server:{{version}} server
    @echo "→ localhost/sked-server:latest ({{version}}); start with: {{engine}} compose up -d"

# Build the server binary without containers: dist/skedd (host platform unless GOOS/GOARCH are set).
server-bin:
    cd server && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version={{version}}" -o {{dist}}/skedd ./cmd/skedd
    @echo "→ {{dist}}/skedd ({{version}})"

# Build the iOS app as a release .ipa: dist/Sked.ipa.
ios:
    cd ios && xtool dev build --configuration release --ipa
    cp ios/xtool/Sked.ipa {{dist}}/Sked.ipa
    @echo "→ {{dist}}/Sked.ipa"
