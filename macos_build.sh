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

SKIA_URL="https://github.com/aseprite/skia/releases/download/${SKIA_TAG}/Skia-macOS-Release-arm64.zip"

echo "=== 4) Download & extract Skia ==="
SKIA_DEST="${ASE_DIR}/skia-${SKIA_TAG}"
if [ ! -d "${SKIA_DEST}" ]; then
  curl -L -o skia-${SKIA_TAG}.zip "${SKIA_URL}"
  unzip skia-${SKIA_TAG}.zip -d "${SKIA_DEST}"
else
  echo "Skia directory exists: ${SKIA_DEST}"
fi

echo "=== 5) Configure CMake build ==="
cd "${ASE_DIR}/aseprite"
BUILD_DIR="build"
rm -rf "${BUILD_DIR}"
mkdir "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
  -DCMAKE_OSX_SYSROOT="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" \
  -DLAF_BACKEND=skia \
  -DSKIA_DIR="${SKIA_DEST}" \
  -DSKIA_LIBRARY_DIR="${SKIA_DEST}/out/Release-arm64" \
  -DSKIA_LIBRARY="${SKIA_DEST}/out/Release-arm64/libskia.a" \
  -G Ninja \
  ..

echo "=== 6) Build Aseprite ==="
ninja aseprite

BIN_DIR="${ASE_DIR}/aseprite/${BUILD_DIR}/bin"

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
# ICU data (optional)
ICU_DATA="${SKIA_DEST}/third_party/externals/icu/flutter/icudtl.dat"
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