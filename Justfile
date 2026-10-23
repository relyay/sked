# Build artifacts go to dist/.

version := `git describe --tags --always --dirty 2>/dev/null || echo dev`
dist := justfile_directory() / "dist"

# List targets.
default:
    @just --list

# Build the server binary: dist/vksitd (static, linux/amd64 unless GOOS/GOARCH are set).
server:
    cd server && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version={{version}}" -o {{dist}}/vksitd ./cmd/vksitd
    @echo "→ {{dist}}/vksitd ({{version}})"

# Build the iOS app as a release .ipa: dist/VKSIT.ipa.
ios:
    cd ios && xtool dev build --configuration release --ipa
    cp ios/xtool/VKSIT.ipa {{dist}}/VKSIT.ipa
    @echo "→ {{dist}}/VKSIT.ipa"
