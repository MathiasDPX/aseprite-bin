#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Aseprite.app"
ASE_DIR="${PWD}/aseprite-work"
REPO_ROOT="${PWD}"
# =======================

# Optional ASEPRITE_VERSION override
if [ -n "${ASEPRITE_VERSION:-}" ]; then
  echo "Using ASEPRITE_VERSION from environment: ${ASEPRITE_VERSION}"
fi

echo "=== 1) Install Homebrew packages if missing ==="
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Please install Homebrew first."
  exit 1
fi

if brew list --versions cmake >/dev/null 2>&1; then
  echo "cmake is already installed and up-to-date."
else
  brew install cmake
fi

if brew list --versions ninja >/dev/null 2>&1; then
  echo "ninja is already installed and up-to-date."
else
  brew install ninja
fi

if brew list --versions jpeg-turbo >/dev/null 2>&1; then
  echo "jpeg-turbo is already installed and up-to-date."
else
  brew install jpeg-turbo
fi

echo "=== 2) Create directory structure ==="
mkdir -p "${ASE_DIR}"
cd "${ASE_DIR}"

echo "=== 3) Clone Aseprite repository ==="
if [ ! -d aseprite ]; then
  git clone --recursive https://github.com/aseprite/aseprite.git
else
  echo "Repository already exists; pulling updates"
  cd aseprite
  git pull
  git submodule update --init --recursive
  cd ..
fi

echo "=== 3.4) Determine Aseprite version tag ==="
if [ -z "${ASEPRITE_VERSION:-}" ]; then
  echo "Detecting latest tag from local aseprite repository..."
  git -C aseprite fetch --tags --quiet || true
  ASEPRITE_VERSION=$(git -C aseprite tag --sort=creatordate | tail -n1 || echo "unknown")
fi
echo "Building aseprite ${ASEPRITE_VERSION}"

echo "=== 3.5) Detect Skia version ==="
if [ -f "aseprite/laf/misc/skia-tag.txt" ]; then
  SKIA_TAG=$(cat aseprite/laf/misc/skia-tag.txt)
  echo "Detected Skia version from skia-tag.txt: ${SKIA_TAG}"
else
  echo "skia-tag.txt not found, detecting from Aseprite version..."
  if [[ "${ASEPRITE_VERSION}" == *beta* ]]; then
    SKIA_TAG="m124-08a5439a6b"
  else
    SKIA_TAG="m102-861e4743af"
  fi
  echo "Using Skia version: ${SKIA_TAG} (based on Aseprite version: ${ASEPRITE_VERSION})"
fi

echo "=== 4) Download & extract Skia for both architectures ==="
SKIA_ARM64_URL="https://github.com/aseprite/skia/releases/download/${SKIA_TAG}/Skia-macOS-Release-arm64.zip"
SKIA_X64_URL="https://github.com/aseprite/skia/releases/download/${SKIA_TAG}/Skia-macOS-Release-x64.zip"

SKIA_ARM64_DEST="${ASE_DIR}/skia-${SKIA_TAG}-arm64"
SKIA_X64_DEST="${ASE_DIR}/skia-${SKIA_TAG}-x64"
SKIA_UNIVERSAL_DEST="${ASE_DIR}/skia-${SKIA_TAG}-universal"

# Download arm64
if [ ! -d "${SKIA_ARM64_DEST}" ]; then
  echo "Downloading Skia arm64..."
  curl -L -o skia-${SKIA_TAG}-arm64.zip "${SKIA_ARM64_URL}"
  unzip skia-${SKIA_TAG}-arm64.zip -d "${SKIA_ARM64_DEST}"
  rm skia-${SKIA_TAG}-arm64.zip
else
  echo "Skia arm64 directory exists: ${SKIA_ARM64_DEST}"
fi

# Download x64
if [ ! -d "${SKIA_X64_DEST}" ]; then
  echo "Downloading Skia x64..."
  curl -L -o skia-${SKIA_TAG}-x64.zip "${SKIA_X64_URL}"
  unzip skia-${SKIA_TAG}-x64.zip -d "${SKIA_X64_DEST}"
  rm skia-${SKIA_TAG}-x64.zip
else
  echo "Skia x64 directory exists: ${SKIA_X64_DEST}"
fi

echo "=== 4.5) Create universal Skia library ==="
if [ ! -d "${SKIA_UNIVERSAL_DEST}" ]; then
  echo "Creating universal Skia library..."
  mkdir -p "${SKIA_UNIVERSAL_DEST}/out/Release-universal"
  
  # Copy headers and other files from arm64 (they should be identical)
  rsync -a --exclude='out' "${SKIA_ARM64_DEST}/" "${SKIA_UNIVERSAL_DEST}/"
  
  # Create universal libskia.a using lipo
  lipo -create \
    "${SKIA_ARM64_DEST}/out/Release-arm64/libskia.a" \
    "${SKIA_X64_DEST}/out/Release-x64/libskia.a" \
    -output "${SKIA_UNIVERSAL_DEST}/out/Release-universal/libskia.a"

  # Also try to create universal libskshaper.a and libskunicode.a (if present)
  for libname in libskshaper.a libskunicode.a; do
    ARM_LIB="${SKIA_ARM64_DEST}/out/Release-arm64/${libname}"
    X64_LIB="${SKIA_X64_DEST}/out/Release-x64/${libname}"
    OUT_LIB="${SKIA_UNIVERSAL_DEST}/out/Release-universal/${libname}"
    if [ -f "${ARM_LIB}" ] && [ -f "${X64_LIB}" ]; then
      echo "Creating universal ${libname}..."
      lipo -create "${ARM_LIB}" "${X64_LIB}" -output "${OUT_LIB}"
    else
      echo "Warning: ${libname} not found for both archs; will fall back to libskia.a at link time if needed."
    fi
  done

  echo "Universal Skia libraries created in ${SKIA_UNIVERSAL_DEST}/out/Release-universal"
else
  echo "Universal Skia directory exists: ${SKIA_UNIVERSAL_DEST}"
fi

echo "=== 5) Configure CMake build ==="
cd "${ASE_DIR}/aseprite"
BUILD_DIR="build"
rm -rf "${BUILD_DIR}"
mkdir "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Resolve SDK path dynamically; allow override via OSX_SDK_PATH
OSX_SDK_PATH="${OSX_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"

# Resolve Skia libraries (fallback to libskia.a if shaper/unicode are not present)
SKIA_LIB_UNI="${SKIA_UNIVERSAL_DEST}/out/Release-universal/libskia.a"
SKSHAPER_LIB_UNI="${SKIA_UNIVERSAL_DEST}/out/Release-universal/libskshaper.a"
SKUNICODE_LIB_UNI="${SKIA_UNIVERSAL_DEST}/out/Release-universal/libskunicode.a"

if [ ! -f "${SKSHAPER_LIB_UNI}" ]; then
  SKSHAPER_LIB_UNI="${SKIA_LIB_UNI}"
fi
if [ ! -f "${SKUNICODE_LIB_UNI}" ]; then
  SKUNICODE_LIB_UNI="${SKIA_LIB_UNI}"
fi

cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DCMAKE_OSX_SYSROOT="${OSX_SDK_PATH}" \
  -DLAF_BACKEND=skia \
  -DSKIA_DIR="${SKIA_UNIVERSAL_DEST}" \
  -DSKIA_LIBRARY_DIR="${SKIA_UNIVERSAL_DEST}/out/Release-universal" \
  -DSKIA_LIBRARY="${SKIA_LIB_UNI}" \
  -DSKSHAPER_LIBRARY="${SKSHAPER_LIB_UNI}" \
  -DSKUNICODE_LIBRARY="${SKUNICODE_LIB_UNI}" \
  -DLIBJPEG_TURBO_INCLUDE_DIR="$(brew --prefix jpeg-turbo)/include" \
  -DLIBJPEG_TURBO_LIBRARY="$(brew --prefix jpeg-turbo)/lib/libjpeg.a" \
  -DPNG_ARM_NEON=off \
  -G Ninja \
  ..

echo "=== 6) Build Aseprite ==="
ninja aseprite

BIN_DIR="${ASE_DIR}/aseprite/${BUILD_DIR}/bin"

echo "=== 6.5) Verify universal binary ==="
if [ -f "${BIN_DIR}/${APP_NAME}/Contents/MacOS/aseprite" ]; then
  echo "Architectures in built binary:"
  lipo -info "${BIN_DIR}/${APP_NAME}/Contents/MacOS/aseprite"
fi

echo "=== Packaging artifact ==="
OUTDIR="${ASE_DIR}/aseprite-${ASEPRITE_VERSION}"
rm -rf "${OUTDIR}"
mkdir -p "${OUTDIR}"
if [ -d "${BIN_DIR}/${APP_NAME}" ]; then
  cp -R "${BIN_DIR}/${APP_NAME}" "${OUTDIR}/"
else
  echo "Error: built app not found for packaging"
  exit 1
fi
cp -R "${ASE_DIR}/aseprite/docs" "${OUTDIR}/docs" 2>/dev/null || true
# Minimal portable marker
echo "# Portable marker" > "${OUTDIR}/aseprite.ini"
# ICU data (optional) - use from universal skia
ICU_DATA="${SKIA_UNIVERSAL_DEST}/third_party/externals/icu/flutter/icudtl.dat"
if [ -f "${ICU_DATA}" ]; then
  cp "${ICU_DATA}" "${OUTDIR}/"
fi

mkdir -p "${REPO_ROOT}/github"
mv "${OUTDIR}" "${REPO_ROOT}/github/"
echo "Packaged artifact: ${REPO_ROOT}/github/aseprite-${ASEPRITE_VERSION}"
# Expose version
echo "ASEPRITE_VERSION=${ASEPRITE_VERSION}" >> "${GITHUB_OUTPUT:-/dev/null}" || true
echo "=== Build complete ==="
exit 0