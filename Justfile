# Build artifacts go to dist/. The server is built and run by compose:
#   podman compose up -d

dist := justfile_directory() / "dist"

# List targets.
default:
    @just --list

# Build the iOS app as a release .ipa: dist/Sked.ipa.
ios:
    cd ios && xtool dev build --configuration release --ipa
    cp ios/xtool/Sked.ipa {{dist}}/Sked.ipa
    @echo "→ {{dist}}/Sked.ipa"
