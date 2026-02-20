# MAKE_RUSTDESK.md - Guia Completa de Compilacion

## Tabla de Contenidos

- [Requisitos Generales](#requisitos-generales)
- [Feature Flags de Cargo](#feature-flags-de-cargo)
- [1. Version CLI (sin UI)](#1-version-cli-sin-ui)
- [2. Version Flutter Desktop](#2-version-flutter-desktop)
  - [Windows](#windows-flutter)
  - [Linux](#linux-flutter)
  - [macOS](#macos-flutter)
- [3. Version Flutter Mobile](#3-version-flutter-mobile)
  - [Android](#android)
  - [iOS](#ios)
- [4. Version Sciter Legacy (Deprecada)](#4-version-sciter-legacy-deprecada)
- [5. Docker Build (Linux)](#5-docker-build-linux)
- [6. Paquetes Linux](#6-paquetes-linux)
- [7. CI/CD (GitHub Actions)](#7-cicd-github-actions)
- [Resumen de Entregables](#resumen-de-entregables)

---

## Requisitos Generales

### Todas las plataformas

| Herramienta       | Version Minima | Notas                          |
|-------------------|----------------|--------------------------------|
| Rust              | 1.75           | 1.81+ para macOS Apple Silicon |
| Python            | 3.x            | Para `build.py`                |
| Git               | cualquiera     | Con soporte de submodulos      |
| CMake             | 3.29.7+        |                                |
| vcpkg             | commit `120dea`| Ver seccion vcpkg              |

### vcpkg (obligatorio)

```bash
git clone https://github.com/microsoft/vcpkg
cd vcpkg
# Windows
.\bootstrap-vcpkg.bat
# Linux/macOS
./bootstrap-vcpkg.sh

# Instalar dependencias
vcpkg install libvpx libyuv opus aom
```

Configurar variable de entorno:

```bash
# Linux/macOS
export VCPKG_ROOT=/ruta/a/vcpkg

# Windows PowerShell
$env:VCPKG_ROOT="C:\ruta\a\vcpkg"

# Windows CMD
set VCPKG_ROOT=C:\ruta\a\vcpkg
```

---

## Feature Flags de Cargo

Definidos en `Cargo.toml`:

| Feature                  | Descripcion                                      | Plataforma      |
|--------------------------|--------------------------------------------------|-----------------|
| `cli`                    | Compilacion CLI sin interfaz grafica              | Todas           |
| `flutter`                | UI moderna con Flutter                            | Todas           |
| `inline`                 | UI legacy con Sciter                              | Desktop         |
| `hwcodec`                | Codecs de video por hardware (H264/H265)          | Desktop         |
| `vram`                   | Optimizacion de memoria GPU                       | Windows         |
| `mediacodec`             | Android MediaCodec                                | Android         |
| `unix-file-copy-paste`   | Copiar/pegar archivos via X11                     | Linux           |
| `screencapturekit`       | Captura nativa de pantalla                        | macOS           |
| `use_dasp`               | Resampling de audio (default)                     | Todas           |
| `plugin_framework`       | Soporte de plugins                                | Todas           |

**Default:** `use_dasp`

---

## 1. Version CLI (sin UI)

Compila RustDesk como herramienta de linea de comandos, sin interfaz grafica. Soporta port-forward y conexion por CLI.

### Compilar

```bash
cargo build --features cli --release
```

### Entregable

| Plataforma | Ruta                              |
|------------|-----------------------------------|
| Windows    | `target\release\rustdesk.exe`     |
| Linux      | `target/release/rustdesk`         |
| macOS      | `target/release/rustdesk`         |

### Uso

```bash
# Port forward: remote-id:local-port:remote-port[:remote-host]
rustdesk --port-forward 123456789:15985:5985:10.0.0.12

# Port forward con key
rustdesk --port-forward 123456789:15985:5985:10.0.0.12 --key MI_KEY

# Conectar (test)
rustdesk --connect REMOTE_ID --key MI_KEY

# Iniciar servidor
rustdesk --server
```

### Parametros CLI

| Flag               | Formato                                              |
|--------------------|------------------------------------------------------|
| `--port-forward`   | `remote-id:local-port:remote-port[:remote-host]`     |
| `--connect`        | `REMOTE_ID`                                          |
| `--key`            | `KEY`                                                |
| `--server`         | (sin valor)                                          |

---

## 2. Version Flutter Desktop

### Requisitos adicionales

- Flutter SDK 3.24.5
- LLVM 15.0.6 (Windows)

### Windows (Flutter)

#### Requisitos Windows

- Visual Studio 2022 con MSVC toolchain
- vcpkg con triplet `x64-windows-static`
- Flutter SDK
- LLVM 15.0.6

#### Compilar paso a paso

```powershell
# 1. Compilar Virtual Display DLL (opcional)
cd libs\virtual_display\dylib
cargo build --release
cd ..\..\..

# 2. Compilar libreria Rust
cargo build --features flutter --lib --release
# Con hardware codec:
cargo build --features flutter,hwcodec --lib --release
# Con VRAM:
cargo build --features flutter,vram --lib --release

# 3. Compilar Flutter
cd flutter
flutter build windows --release
cd ..
```

#### Compilar con build.py

```powershell
python3 build.py --flutter
python3 build.py --flutter --release
python3 build.py --flutter --hwcodec
python3 build.py --flutter --vram
```

#### Entregables Windows

| Tipo                | Ruta                                                         |
|---------------------|--------------------------------------------------------------|
| App sin empaquetar  | `flutter\build\windows\x64\runner\Release\`                  |
| Instalador portable | `rustdesk-<version>-install.exe` (raiz del proyecto)         |
| Virtual Display DLL | `target\release\dylib_virtual_display.dll`                   |

#### Crear instalador portable (opcional)

```powershell
cd libs\portable
pip3 install -r requirements.txt
python3 generate.py -f ..\..\flutter\build\windows\x64\runner\Release -o . -e ..\..\flutter\build\windows\x64\runner\Release\rustdesk.exe
```

### Linux (Flutter)

#### Requisitos Linux (Debian/Ubuntu)

```bash
sudo apt install -y g++ gcc git curl nasm yasm libgtk-3-dev clang \
  libxcb-randr0-dev libxdo-dev libxfixes-dev libxcb-shape0-dev \
  libxcb-xfixes0-dev libasound2-dev libpam0g-dev libpulse-dev \
  cmake make libssl-dev libgstreamer1.0-dev \
  libgstreamer-plugins-base1.0-dev ninja-build
```

#### Compilar

```bash
# 1. Compilar libreria
cargo build --features flutter,hwcodec --lib --release

# 2. Fix FFI binding (si es necesario)
sed -i "s/ffi.NativeFunction<ffi.Bool Function(DartPort/ffi.NativeFunction<ffi.Uint8 Function(DartPort/g" \
  flutter/lib/generated_bridge.dart

# 3. Compilar Flutter
cd flutter
flutter build linux --release
```

#### Con build.py

```bash
python3 build.py --flutter
python3 build.py --flutter --hwcodec
python3 build.py --flutter --unix-file-copy-paste
```

#### Entregables Linux

| Tipo     | Ruta                                                  |
|----------|-------------------------------------------------------|
| Bundle   | `flutter/build/linux/x64/release/bundle/`             |
| DEB      | `rustdesk-<version>.deb` (ver seccion Paquetes Linux) |

### macOS (Flutter)

#### Requisitos macOS

- Xcode 13+
- Deployment target: macOS 10.14+
- Certificados de firma (para distribucion)

#### Compilar

```bash
# 1. Compilar libreria
MACOSX_DEPLOYMENT_TARGET=10.14 cargo build --features flutter,hwcodec --lib --release

# 2. Copiar dylib
cp target/release/liblibrustdesk.dylib target/release/librustdesk.dylib

# 3. Compilar Flutter
cd flutter
flutter build macos --release

# 4. Copiar servicio
cp -rf ../target/release/service ./build/macos/Build/Products/Release/RustDesk.app/Contents/MacOS/
```

#### Con build.py

```bash
python3 build.py --flutter
python3 build.py --flutter --screencapturekit
```

#### Entregables macOS

| Tipo     | Ruta                                                          |
|----------|---------------------------------------------------------------|
| App      | `flutter/build/macos/Build/Products/Release/RustDesk.app`     |
| DMG      | `rustdesk-<version>.dmg` (tras empaquetar)                    |

---

## 3. Version Flutter Mobile

### Android

#### Requisitos

- Android SDK
- Android NDK r27c
- Flutter SDK 3.24.5
- Java JDK 11+
- cargo-ndk (`cargo install cargo-ndk`)

#### Compilar dependencias nativas

```bash
# Para cada arquitectura:
bash flutter/build_android_deps.sh arm64-v8a
bash flutter/build_android_deps.sh armeabi-v7a
bash flutter/build_android_deps.sh x86_64
```

#### Arquitecturas soportadas

| ABI            | Rust Target                   | vcpkg Triplet      |
|----------------|-------------------------------|---------------------|
| `arm64-v8a`    | `aarch64-linux-android`       | `arm64-android`     |
| `armeabi-v7a`  | `armv7a-linux-androideabi`    | `arm-neon-android`  |
| `x86_64`       | `x86_64-linux-android`        | `x64-android`       |
| `x86`          | `i686-linux-android`          | `x86-android`       |

#### Compilar libreria

```bash
cargo ndk --platform 21 --target aarch64-linux-android --bindgen \
  build --release --features flutter,hwcodec
```

#### Compilar APK

```bash
cd flutter

# APK unico
flutter build apk --release --target-platform android-arm64,android-arm

# APKs separados por arquitectura
flutter build apk --split-per-abi --release --target-platform android-arm64,android-arm

# App Bundle (Google Play)
flutter build appbundle --release --target-platform android-arm64,android-arm
```

#### Scripts de build

```bash
# Build general
bash flutter/build_android.sh

# Build F-Droid
bash flutter/build_fdroid.sh
```

#### Entregables Android

| Tipo         | Ruta                                                    |
|--------------|---------------------------------------------------------|
| APK          | `flutter/build/app/outputs/apk/release/`                |
| APK por ABI  | `flutter/build/app/outputs/apk/release/app-*-release.apk` |
| App Bundle   | `flutter/build/app/outputs/bundle/release/app-release.aab` |

### iOS

#### Requisitos

- Xcode 13+
- iOS deployment target: 12.0+
- Apple Developer account

#### Compilar

```bash
# 1. Compilar libreria
cargo build --features flutter,hwcodec --release --target aarch64-apple-ios --lib

# 2. Compilar IPA
cd flutter
flutter build ipa --release --no-codesign

# Con ofuscacion
flutter build ipa --release --obfuscate --split-debug-info=./split-debug-info
```

#### Script de build

```bash
bash flutter/build_ios.sh
```

#### Entregables iOS

| Tipo | Ruta                                |
|------|-------------------------------------|
| IPA  | `flutter/build/ios/ipa/RustDesk.ipa` |

---

## 4. Version Sciter Legacy (Deprecada)

> **Nota:** La UI Sciter esta deprecada. Usar Flutter en su lugar.

### Requisitos

- Descargar libreria Sciter segun plataforma:
  - Windows: `sciter.dll`
  - Linux: `libsciter-gtk.so`
  - macOS: `libsciter.dylib`
- Colocar en `target/release/` o `target/debug/`

### Compilar

```bash
# Debug
cargo run

# Release
cargo build --release --features inline
```

### Entregables

| Plataforma | Ruta                          |
|------------|-------------------------------|
| Windows    | `target\release\rustdesk.exe` |
| Linux      | `target/release/rustdesk`     |
| macOS      | `target/release/rustdesk`     |

---

## 5. Docker Build (Linux)

El `Dockerfile` en la raiz del proyecto crea una imagen con todas las dependencias para compilar RustDesk **para Linux**.

### Construir imagen

```bash
docker build -t rustdesk-builder .
```

### Compilar dentro del contenedor

```bash
# Version CLI
docker run --rm -v "$PWD:/home/user/rustdesk" rustdesk-builder --features cli --release

# Version Sciter (legacy)
docker run --rm -v "$PWD:/home/user/rustdesk" rustdesk-builder --release

# Con hardware codec
docker run --rm -v "$PWD:/home/user/rustdesk" rustdesk-builder --features hwcodec --release

# Version Flutter
docker run --rm -v "$PWD:/home/user/rustdesk" rustdesk-builder --features flutter --lib --release
```

### Con cache de cargo (recomendado)

```bash
docker run --rm \
  -v "$PWD:/home/user/rustdesk" \
  -v rustdesk-git-cache:/home/user/.cargo/git \
  -v rustdesk-registry-cache:/home/user/.cargo/registry \
  rustdesk-builder --features cli --release
```

### Entregables (dentro del volumen montado)

| Tipo        | Ruta                          |
|-------------|-------------------------------|
| Binario CLI | `target/release/rustdesk`     |
| Libreria    | `target/release/librustdesk.so` |

> **Importante:** Docker genera binarios **Linux (ELF)**, no ejecutables Windows (.exe).

---

## 6. Paquetes Linux

### Debian/Ubuntu (.deb)

```bash
python3 build.py --flutter
# o manualmente:
cd flutter
mkdir -p tmpdeb/usr/bin tmpdeb/usr/share/rustdesk tmpdeb/etc/rustdesk tmpdeb/etc/pam.d
cp -r build/linux/x64/release/bundle/* tmpdeb/usr/share/rustdesk/
dpkg-deb -b tmpdeb rustdesk-<version>.deb
```

**Control file:** `res/DEBIAN/control`

**Dependencias runtime:**
```
libgtk-3-0, libxcb-randr0, libxdo3, libxfixes3, libxcb-shape0,
libxcb-xfixes0, libasound2, libsystemd0, curl, libva2, libva-drm2,
libva-x11-2, libgstreamer-plugins-base1.0-0, libpam0g, gstreamer1.0-pipewire
```

### Fedora/CentOS (.rpm)

```bash
sed -i "s/Version:    .*/Version:    $(grep '^version' Cargo.toml | head -1 | cut -d'"' -f2)/g" res/rpm-flutter.spec
HBB=$(pwd) rpmbuild -ba res/rpm-flutter.spec
```

**Spec files:**
- `res/rpm.spec` (Sciter)
- `res/rpm-flutter.spec` (Flutter)

**Entregable:** `~/rpmbuild/RPMS/x86_64/rustdesk-<version>-0.x86_64.rpm`

### openSUSE (.rpm)

```bash
sed -i "s/Version:    .*/Version:    <version>/g" res/rpm-suse.spec
HBB=$(pwd) rpmbuild -ba res/rpm-suse.spec
```

**Entregable:** `~/rpmbuild/RPMS/x86_64/rustdesk-<version>-suse.rpm`

### Arch/Manjaro (.pkg.tar.zst)

```bash
sed -i "s/pkgver=.*/pkgver=<version>/g" res/PKGBUILD
HBB=$(pwd) FLUTTER=1 makepkg -f
```

**Entregable:** `rustdesk-<version>-manjaro-arch.pkg.tar.zst`

### AppImage

Requiere el `.deb` ya construido y `appimage-builder`.

**Config:** `appimage/AppImageBuilder-x86_64.yml`

**Entregable:** `RustDesk-<version>.AppImage`

---

## 7. CI/CD (GitHub Actions)

Los workflows se encuentran en `.github/workflows/`:

| Workflow              | Archivo                | Proposito                           |
|-----------------------|------------------------|-------------------------------------|
| Flutter Build         | `flutter-build.yml`    | Build multiplataforma completo      |
| CI                    | `ci.yml`               | Validacion en push/PR               |
| Bridge                | `bridge.yml`           | Generar FFI bindings de Flutter     |

### Versiones usadas en CI

| Herramienta | Version      |
|-------------|--------------|
| Flutter     | 3.24.5       |
| Rust        | 1.75         |
| Rust (macOS)| 1.81         |
| NDK         | r27c         |
| cargo-ndk   | 3.1.2        |
| LLVM        | 15.0.6       |

---

## Resumen de Entregables

| Plataforma / Modo         | Comando Principal                                          | Entregable                                                     |
|---------------------------|------------------------------------------------------------|----------------------------------------------------------------|
| **CLI (Windows)**         | `cargo build --features cli --release`                     | `target\release\rustdesk.exe`                                  |
| **CLI (Linux)**           | `cargo build --features cli --release`                     | `target/release/rustdesk`                                      |
| **CLI (Docker/Linux)**    | `docker run ... rustdesk-builder --features cli --release` | `target/release/rustdesk`                                      |
| **Flutter Windows**       | `python3 build.py --flutter`                               | `flutter\build\windows\x64\runner\Release\`                    |
| **Flutter Linux**         | `python3 build.py --flutter`                               | `flutter/build/linux/x64/release/bundle/`                      |
| **Flutter macOS**         | `python3 build.py --flutter`                               | `flutter/build/macos/Build/Products/Release/RustDesk.app`      |
| **Android APK**           | `flutter build apk --release`                              | `flutter/build/app/outputs/apk/release/`                       |
| **Android Bundle**        | `flutter build appbundle --release`                        | `flutter/build/app/outputs/bundle/release/app-release.aab`     |
| **iOS IPA**               | `flutter build ipa --release`                              | `flutter/build/ios/ipa/RustDesk.ipa`                           |
| **Sciter Legacy**         | `cargo build --release --features inline`                  | `target/release/rustdesk(.exe)`                                |
| **DEB**                   | `python3 build.py --flutter` (en Debian/Ubuntu)            | `rustdesk-<version>.deb`                                       |
| **RPM (Fedora)**          | `rpmbuild -ba res/rpm-flutter.spec`                        | `~/rpmbuild/RPMS/x86_64/rustdesk-<version>.rpm`               |
| **Arch pkg**              | `makepkg -f`                                               | `rustdesk-<version>-manjaro-arch.pkg.tar.zst`                  |
| **AppImage**              | `appimage-builder`                                         | `RustDesk-<version>.AppImage`                                  |
| **Windows Portable**      | `python3 libs/portable/generate.py ...`                    | `rustdesk-<version>-install.exe`                               |
