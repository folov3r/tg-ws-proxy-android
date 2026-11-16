#!/usr/bin/env bash
# Local Linux build helper for amurcanov/tg-ws-proxy-android.
# Toolchain installed without root:
#   JDK 21  -> ~/.local/opt/jdk21
#   Gradle  -> ~/.local/opt/gradle-9.6.0
#   Android SDK -> ~/android-sdk (platform-android-35, build-tools 35/36)
set -euo pipefail
cd "$(dirname "$0")"

export JAVA_HOME="${JAVA_HOME:-$HOME/.local/opt/jdk21}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
GRADLE="${GRADLE:-$HOME/.local/opt/gradle-9.6.0/bin/gradle}"

task="${1:-assembleUniversalRelease}"
exec "$GRADLE" --console=plain "$task"
