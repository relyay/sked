# Build artifacts go to dist/.

version := `git describe --tags --always --dirty 2>/dev/null || echo dev`
dist := justfile_directory() / "dist"

# List targets.
default:
    @just --list

# Build the server binary: dist/skedd (static, host platform unless GOOS/GOARCH are set).
server:
    cd server && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version={{version}}" -o {{dist}}/skedd ./cmd/skedd
    @echo "→ {{dist}}/skedd ({{version}})"

# Build the iOS app as a release .ipa: dist/Sked.ipa.
ios:
    cd ios && xtool dev build --configuration release --ipa
    cp ios/xtool/Sked.ipa {{dist}}/Sked.ipa
    @echo "→ {{dist}}/Sked.ipa"
