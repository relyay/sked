# Build artifacts go to dist/. The server is built and run by compose:
#   podman compose up -d

dist := justfile_directory() / "dist"
android_home := env("ANDROID_HOME", env("HOME") / "Android/Sdk")

# List targets.
default:
    @just --list

# Build the iOS app as a release .ipa: dist/Sked.ipa.
ios:
    cd ios && xtool dev build --configuration release --ipa
    cp ios/xtool/Sked.ipa {{dist}}/Sked.ipa
    @echo "→ {{dist}}/Sked.ipa"

# Build the Android app as a release .apk: dist/Sked.apk (signed with the debug key).
android:
    cd android && ANDROID_HOME={{android_home}} ./gradlew --no-daemon -q :app:testDebugUnitTest :app:assembleRelease
    cp android/app/build/outputs/apk/release/app-release.apk {{dist}}/Sked.apk
    @echo "→ {{dist}}/Sked.apk"
