#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURE THESE (can be overridden by env) ===
ASE_DIR="${ASE_DIR:-$HOME/src/aseprite}"
APP_NAME="Aseprite.app"
# In CI use a workspace-local directory to simplify artifact collection
if [ -n "${GITHUB_WORKFLOW:-}" ]; then
  ASE_DIR="${PWD}/aseprite-work"
  echo "CI detected, using ASE_DIR=${ASE_DIR}"
fi
# =======================

CI_MODE=false
[ -n "${GITHUB_WORKFLOW:-}" ] && CI_MODE=true

# Optional ASEPRITE_VERSION override (like linux script)
if [ -n "${ASEPRITE_VERSION:-}" ]; then
  echo "Using ASEPRITE_VERSION from environment: ${ASEPRITE_VERSION}"
fi

echo "=== 1) Install Homebrew packages if missing ==="
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Please install Homebrew first."
  exit 1
fi
brew install cmake ninja

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

echo "=== 3.5) Detect Skia version ==="
if [ -f "aseprite/laf/misc/skia-tag.txt" ]; then
  SKIA_TAG=$(cat aseprite/laf/misc/skia-tag.txt)
  echo "Detected Skia version from skia-tag.txt: ${SKIA_TAG}"
else
  echo "skia-tag.txt not found, detecting from Aseprite version..."
  cd aseprite
  ASEPRITE_VERSION="${ASEPRITE_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")}"
  cd ..
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

if $CI_MODE; then
  echo "=== CI mode: packaging artifact instead of installing to /Applications ==="
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
  mkdir -p github
  mv "${OUTDIR}" github/
  echo "Packaged artifact: github/aseprite-${ASEPRITE_VERSION}"
  # Expose version
  echo "ASEPRITE_VERSION=${ASEPRITE_VERSION}" >> "${GITHUB_OUTPUT:-/dev/null}" || true
  echo "=== CI build complete ==="
  exit 0
fi

echo "=== 7) Copy built app to /Applications ==="
if [ -d "${BIN_DIR}/${APP_NAME}" ]; then
  echo "Copying ${APP_NAME} to /Applications/"
  sudo cp -R "${BIN_DIR}/${APP_NAME}" /Applications/
  echo "Done. You may now run it from /Applications/${APP_NAME}"
else
  echo "Error: built app not found at ${BIN_DIR}/${APP_NAME}"
  exit 1
fi

echo "=== 8) Post-build: bundle icu data (optional) ==="
ICU_DATA="${SKIA_DEST}/third_party/externals/icu/flutter/icudtl.dat"
if [ -f "${ICU_DATA}" ]; then
  echo "Copying icudtl.dat to application resources..."
  sudo cp "${ICU_DATA}" "/Applications/${APP_NAME}/Contents/MacOS/"
fi

echo "=== Build & installation complete ==="
exit 0