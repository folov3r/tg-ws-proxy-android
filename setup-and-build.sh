#!/usr/bin/env bash
# ============================================================================
#  TG WS Proxy Android — пересборка APK "одной командой" (Linux / WSL2)
#
#  Что делает скрипт:
#   1. Скачивает JDK 21 (Amazon Corretto) в ~/.local/opt/jdk21
#   2. Скачивает Gradle 9.6.0 в ~/.local/opt/gradle-9.6.0
#   3. Скачивает Android command-line tools в ~/android-sdk
#   4. Доставляет platform-tools, platform android-35, build-tools 36.0.0
#   5. Генерирует ключ подписи release.keystore (если его ещё нет)
#   6. Собирает universal release APK и кладёт его в dist/
#
#  Root/sudo НЕ нужен: всё ставится в домашний каталог.
#  Первый запуск: ~15-40 минут (качается ~700 МБ). Повторный: 1-5 минут.
#
#  Запуск:  bash setup-and-build.sh
# ============================================================================
set -euo pipefail

JDK_DIR="$HOME/.local/opt/jdk21"
GRADLE_VER="9.6.0"
GRADLE_DIR="$HOME/.local/opt/gradle-$GRADLE_VER"
SDK_DIR="$HOME/android-sdk"
CMDLINE_ZIP_URL="https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip"
CORRETTO_URL="https://corretto.aws/downloads/latest/amazon-corretto-21-x64-linux-jdk.tar.gz"
GRADLE_URL="https://services.gradle.org/distributions/gradle-$GRADLE_VER-bin.zip"

cd "$(dirname "$0")"
PROJECT_DIR="$(pwd)"
DL_DIR="$HOME/.cache/tgwsproxy-build"
mkdir -p "$DL_DIR" "$HOME/.local/opt"

say() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mОШИБКА: %s\033[0m\n' "$*" >&2; exit 1; }

for cmd in curl tar unzip; do
    command -v "$cmd" >/dev/null 2>&1 || fail "не найдена команда '$cmd'. Установи её: sudo apt install $cmd (Debian/Ubuntu) или sudo pacman -S $cmd (Arch)."
done

# ---------------------------------------------------------------------------
# 1. JDK 21
# ---------------------------------------------------------------------------
if [ -x "$JDK_DIR/bin/java" ]; then
    say "JDK уже установлен: $JDK_DIR"
else
    say "Скачиваю JDK 21 (Amazon Corretto, ~200 МБ)..."
    curl -fL --retry 5 --retry-all-errors -o "$DL_DIR/jdk21.tar.gz" "$CORRETTO_URL"
    tar -xzf "$DL_DIR/jdk21.tar.gz" -C "$HOME/.local/opt"
    JDK_REAL="$(find "$HOME/.local/opt" -maxdepth 1 -type d -name 'amazon-corretto-21*' | head -1)"
    [ -n "$JDK_REAL" ] || fail "не удалось распаковать JDK"
    ln -sfn "$JDK_REAL" "$JDK_DIR"
fi
export JAVA_HOME="$JDK_DIR"
export PATH="$JAVA_HOME/bin:$PATH"
"$JAVA_HOME/bin/java" -version >/dev/null 2>&1 || fail "JDK не запускается"

# ---------------------------------------------------------------------------
# 2. Gradle
# ---------------------------------------------------------------------------
if [ -x "$GRADLE_DIR/bin/gradle" ]; then
    say "Gradle уже установлен: $GRADLE_DIR"
else
    say "Скачиваю Gradle $GRADLE_VER (~135 МБ)..."
    curl -fL --retry 5 --retry-all-errors -o "$DL_DIR/gradle.zip" "$GRADLE_URL"
    unzip -q -o "$DL_DIR/gradle.zip" -d "$HOME/.local/opt"
fi

# ---------------------------------------------------------------------------
# 3. Android SDK
# ---------------------------------------------------------------------------
export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"
SDKMANAGER="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
if [ -x "$SDKMANAGER" ]; then
    say "Android command-line tools уже установлены"
else
    say "Скачиваю Android command-line tools (~158 МБ)..."
    curl -fL --retry 5 --retry-all-errors -o "$DL_DIR/cmdline-tools.zip" "$CMDLINE_ZIP_URL"
    mkdir -p "$SDK_DIR/cmdline-tools"
    unzip -q -o "$DL_DIR/cmdline-tools.zip" -d "$SDK_DIR/cmdline-tools"
    rm -rf "$SDK_DIR/cmdline-tools/latest"
    mv "$SDK_DIR/cmdline-tools/cmdline-tools" "$SDK_DIR/cmdline-tools/latest"
    SDKMANAGER="$SDK_DIR/cmdline-tools/latest/bin/sdkmanager"
fi

say "Ставлю компоненты Android SDK: platform-tools, android-35, build-tools 36.0.0..."
yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true
set +o pipefail
yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" \
    "platform-tools" "platforms;android-35" "build-tools;36.0.0" >"$DL_DIR/sdkmanager.log" 2>&1
SDKMANAGER_RC="${PIPESTATUS[1]}"
set -o pipefail
if [ "$SDKMANAGER_RC" -ne 0 ] && ! grep -q "100% Computing updates" "$DL_DIR/sdkmanager.log"; then
    tail -30 "$DL_DIR/sdkmanager.log" || true
    fail "sdkmanager не смог установить компоненты Android SDK (код $SDKMANAGER_RC)"
fi
tail -2 "$DL_DIR/sdkmanager.log" || true

# ---------------------------------------------------------------------------
# 4. Ключ подписи + local.properties
# ---------------------------------------------------------------------------
if [ ! -f release.keystore ]; then
    say "Генерирую ключ подписи release.keystore (один раз, храни его!)..."
    PASS="$(head -c 256 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 24)"
    "$JAVA_HOME/bin/keytool" -genkeypair -keystore release.keystore -alias tgwsproxy \
        -keyalg RSA -keysize 4096 -validity 10000 \
        -storepass "$PASS" -keypass "$PASS" \
        -dname "CN=TG WS Proxy Local Build, O=Local, C=RU" >/dev/null 2>&1
    {
        echo "KEYSTORE_FILE=../release.keystore"
        echo "KEYSTORE_PASSWORD=$PASS"
        echo "KEY_ALIAS=tgwsproxy"
        echo "KEY_PASSWORD=$PASS"
    } > .keystore.properties
    chmod 600 .keystore.properties
else
    say "Ключ подписи уже есть: release.keystore"
    # Если файла с паролями нет, но пароли уже прописаны в local.properties — переносим их.
    if [ ! -f .keystore.properties ] && grep -q '^KEYSTORE_PASSWORD=' local.properties 2>/dev/null; then
        grep -E '^(KEYSTORE_FILE|KEYSTORE_PASSWORD|KEY_ALIAS|KEY_PASSWORD)=' local.properties > .keystore.properties
        chmod 600 .keystore.properties
    fi
fi

if [ ! -f .keystore.properties ]; then
    say "ВНИМАНИЕ: release.keystore есть, но пароль от него неизвестен."
    say "Release-APK будет подписан debug-ключом. Чтобы подписывать своим ключом,"
    say "восстанови .keystore.properties (пароль) или удали release.keystore и запусти скрипт снова."
fi

{
    echo "sdk.dir=$ANDROID_HOME"
    [ -f .keystore.properties ] && cat .keystore.properties
} > local.properties

# ---------------------------------------------------------------------------
# 5. Сборка
# ---------------------------------------------------------------------------
say "Собираю universal release APK (первый раз Gradle докачает зависимости)..."
"$GRADLE_DIR/bin/gradle" --console=plain assembleUniversalRelease

VERSION_NAME="$(grep -oP 'versionName\s*=\s*"\K[^"]+' app/build.gradle.kts | head -1)"
VERSION_NAME="${VERSION_NAME:-dev}"
OUT="$(find app/build/outputs/apk/universal/release -name '*.apk' | head -1)"
[ -n "$OUT" ] || fail "APK не найден — смотри лог сборки выше"

mkdir -p "$PROJECT_DIR/dist"
DEST="$PROJECT_DIR/dist/tgwsproxy-${VERSION_NAME}-universal-release.apk"
cp "$OUT" "$DEST"

say "ГОТОВО!"
echo "APK: $DEST"
echo "Размер: $(du -h "$DEST" | cut -f1)"
echo "SHA-256: $(sha256sum "$DEST" | cut -d' ' -f1)"
echo
echo "Установка на телефон: перекинь APK на устройство и открой его,"
echo "или по USB с включённой отладкой:"
echo "  $ANDROID_HOME/platform-tools/adb install -r \"$DEST\""
echo
echo "ВАЖНО: ключ release.keystore и .keystore.properties — это подпись приложения."
echo "Сделай их бэкап. Без них новые сборки не установятся поверх старых."
