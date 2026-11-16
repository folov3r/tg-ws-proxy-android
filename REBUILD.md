# Пересборка APK — инструкция «для неайтишников»

Этот репозиторий — пересборка [amurcanov/tg-ws-proxy-android](https://github.com/amurcanov/tg-ws-proxy-android)
(который, в свою очередь, форк [Flowseal/tg-ws-proxy](https://github.com/Flowseal/tg-ws-proxy)).

**Зачем:** готовый APK из релизов оригинального форка у меня не заработал — приложение
не запускалось / прокси не поднимался. Сборка **из этих же исходников** на чистой
машине работает: приложение стартует, локальный MTProto-прокси слушает
`127.0.0.1:1443`, Telegram подключается через него.

---

## Вариант 1. Одна команда (Linux или WSL2 на Windows)

Нужно: Linux x86_64 (Arch/Debian/Ubuntu — любая), ~4 ГБ свободного места, интернет.
**Root/sudo не нужен** — всё ставится в домашний каталог.

```bash
git clone https://github.com/folov3r/tg-ws-proxy-android.git
cd tg-ws-proxy-android
bash setup-and-build.sh
```

Скрипт сам:

1. скачает JDK 21 (Amazon Corretto) в `~/.local/opt/jdk21`;
2. скачает Gradle 9.6.0 в `~/.local/opt/gradle-9.6.0`;
3. скачает Android command-line tools в `~/android-sdk` и доставит
   `platform-tools`, `platforms;android-35`, `build-tools;36.0.0`;
4. сгенерирует ключ подписи `release.keystore` (если его ещё нет);
5. соберёт APK и положит его в `dist/`.

Первый запуск: примерно 15–40 минут (скачивается ~700 МБ).
Повторный запуск: 1–5 минут.

В конце скрипт печатает путь к APK, размер и SHA-256. Установка:

```bash
# по USB (в телефоне включить «Отладка по USB»)
~/android-sdk/platform-tools/adb install -r dist/tgwsproxy-*-universal-release.apk

# или просто перекинуть APK на телефон и открыть его
```

### Windows без WSL

Рекомендую всё же **WSL2** (Ubuntu из Microsoft Store) — там работает команда выше.
Нативно под Windows проще поставить Android Studio и открыть папку проекта, но это
несколько гигабайт и много кликов. Скрипт рассчитан на Linux/WSL.

---

## Вариант 2. Вручную, если хочется контролировать каждый шаг

```bash
# 1. JDK 21
mkdir -p ~/.local/opt && cd ~/.local/opt
curl -fL -o jdk.tar.gz https://corretto.aws/downloads/latest/amazon-corretto-21-x64-linux-jdk.tar.gz
tar -xzf jdk.tar.gz && ln -sfn amazon-corretto-21* jdk21

# 2. Gradle 9.6.0
curl -fL -o /tmp/gradle.zip https://services.gradle.org/distributions/gradle-9.6.0-bin.zip
unzip -q /tmp/gradle.zip -d ~/.local/opt

# 3. Android SDK (без root)
mkdir -p ~/android-sdk/cmdline-tools
curl -fL -o /tmp/cmdline-tools.zip \
  https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip
unzip -q /tmp/cmdline-tools.zip -d ~/android-sdk/cmdline-tools
mv ~/android-sdk/cmdline-tools/cmdline-tools ~/android-sdk/cmdline-tools/latest

export JAVA_HOME=~/.local/opt/jdk21
export ANDROID_HOME=~/android-sdk
export PATH="$JAVA_HOME/bin:$PATH"
yes | ~/android-sdk/cmdline-tools/latest/bin/sdkmanager --licenses
~/android-sdk/cmdline-tools/latest/bin/sdkmanager \
  "platform-tools" "platforms;android-35" "build-tools;36.0.0"

# 4. Сборка
cd tg-ws-proxy-android
echo "sdk.dir=$HOME/android-sdk" > local.properties

# ключ подписи (один раз; пароль придумай сам и сохрани!)
$JAVA_HOME/bin/keytool -genkeypair -keystore release.keystore -alias tgwsproxy \
  -keyalg RSA -keysize 4096 -validity 10000 -storepass ПАРОЛЬ -keypass ПАРОЛЬ \
  -dname "CN=TG WS Proxy Local Build, O=Local, C=RU"

cat >> local.properties <<EOF
KEYSTORE_FILE=../release.keystore
KEYSTORE_PASSWORD=ПАРОЛЬ
KEY_ALIAS=tgwsproxy
KEY_PASSWORD=ПАРОЛЬ
EOF

~/.local/opt/gradle-9.6.0/bin/gradle --console=plain assembleUniversalRelease
```

APK появится в `app/build/outputs/apk/universal/release/app-universal-release.apk`.

Для отладочной сборки без своего ключа:

```bash
~/.local/opt/gradle-9.6.0/bin/gradle --console=plain assembleUniversalDebug
```

---

## Что именно было сделано при пересборке

| Шаг | Детали |
|---|---|
| Источник | `git clone https://github.com/amurcanov/tg-ws-proxy-android` (коммит `540e588`) |
| Код приложения | **Не изменялся** — ни Kotlin, ни Rust, ни манифест, ни `build.gradle.kts` |
| JDK | Amazon Corretto 21.0.13 (Linux x64), установлен в домашний каталог |
| Gradle | 9.6.0 (ровно та версия, что в `gradle/wrapper/gradle-wrapper.properties`) |
| Android SDK | `platforms;android-35`, `build-tools;36.0.0`, `platform-tools` |
| NDK / Rust | **Не понадобились**: готовые `libtgwsproxy.so` для `arm64-v8a` и `armeabi-v7a` уже лежат в `app/src/main/jniLibs/` |
| Команда сборки | `gradle assembleUniversalRelease` (R8 + shrinkResources) |
| Подпись | свой ключ RSA 4096, схемы v1+v2+v3, срок 10000 дней |
| Итог | `tgwsproxy-1.2.3-universal-release.apk`, ~4.8 МБ, minSdk 21, targetSdk 35 |

Добавленные файлы (код приложения не затронут):

- `setup-and-build.sh` — установка тулчейна и сборка одной командой;
- `build.sh` — короткий хелпер для уже установленного тулчейна;
- `REBUILD.md` — эта инструкция;
- блок про пересборку в `README.md`.

---

## Подпись, обновления и типичные проблемы

### «Приложение не установлено» / конфликт подписи

APK подписан **другим ключом**, чем официальный. Android не даёт обновить приложение
с другой подписью. Решение: удалить старую версию и установить новую. Настройки и
логи при этом пропадут.

Если собрал сам через `setup-and-build.sh` — ключ создан в `release.keystore`,
пароль в `.keystore.properties`. **Сделай бэкап этих двух файлов**: без них
следующие сборки не установятся поверх текущих.

### Play Защита ругается «небезопасное приложение»

Это проверка репутации для всего, что установлено не из Play Маркета, а не проблема
подписи. Любой самоподписанный APK вызывает такое предупреждение. Нажми
«Подробнее → Всё равно установить» либо отключи проверку в Play Маркете
(профиль → Play Защита → шестерёнка → выключить «Проверять приложения»).

### Приложение предлагает обновление с GitHub

Внутри есть автопроверка релизов upstream. Она может предложить скачать официальный
APK, но установка не пройдёт из-за другой подписи. Можно выключить проверку
обновлений в настройках приложения.

### Скачивание падает с ошибкой TLS/таймаутом

Сеть до `services.gradle.org` и `dl.google.com` бывает нестабильной. Просто запусти
`bash setup-and-build.sh` ещё раз — уже скачанное не качается заново. При желании
можно скачать архивы вручную (ссылки в скрипте) и положить в `~/.cache/tgwsproxy-build`.

### Как проверить, что APK действительно мой

```bash
~/android-sdk/build-tools/36.0.0/apksigner verify --print-certs \
  dist/tgwsproxy-1.2.3-universal-release.apk
```

Сертификат: `CN=TG WS Proxy Local Build, O=Local, C=RU`.

---

## Лицензия

Проект распространяется под **GPLv3** (оригинальный `tg-ws-proxy` от Flowseal — MIT).
Исходники открыты, изменения приветствуются. При распространении своей сборки
соблюдай условия GPLv3 и сохраняй `LICENSE`/`NOTICE`.
