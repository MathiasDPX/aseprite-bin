#!/bin/bash

# Fail on errors
set -e

# Accept ASEPRITE_VERSION from env; if empty, detect latest release tag via GitHub API
if [ -z "${ASEPRITE_VERSION:-}" ]; then
  echo "Detecting latest Aseprite release tag from GitHub..."
  ASEPRITE_VERSION=$(curl -s https://api.github.com/repos/aseprite/aseprite/releases/latest \
    | grep -Po '"tag_name":\s*"\K[^"]+' || true)
  if [ -z "$ASEPRITE_VERSION" ]; then
    echo "Warning: could not detect latest release, falling back to v1.3.15.2"
    ASEPRITE_VERSION="v1.3.15.2"
  fi
else
  echo "Using ASEPRITE_VERSION from environment: $ASEPRITE_VERSION"
fi

# Working in current repo workspace
WORKDIR="${PWD}"
echo "Workspace: ${WORKDIR}"

# Clone or update aseprite
if [ ! -d "${WORKDIR}/aseprite" ]; then
  echo "Cloning Aseprite ${ASEPRITE_VERSION}"
  git clone --recursive https://github.com/aseprite/aseprite.git "${WORKDIR}/aseprite"
else
  echo "Updating local aseprite"
  cd "${WORKDIR}/aseprite"
  git fetch --tags origin
  cd "${WORKDIR}"
fi

# Checkout requested tag/commit
cd "${WORKDIR}/aseprite"
git clean -fdx
git submodule foreach --recursive git clean -xfd || true
git fetch --depth=1 --no-tags origin "${ASEPRITE_VERSION}":refs/remotes/origin/"${ASEPRITE_VERSION}" || true
git -c advice.detachedHead=false switch --detach "${ASEPRITE_VERSION}" || git checkout "${ASEPRITE_VERSION}" || true
git submodule update --init --recursive
cd "${WORKDIR}"

# Determine SKIA version (aseprite/laf/misc/skia-tag.txt if present, otherwise fallback similar to windows logic)
if [ -f "aseprite/laf/misc/skia-tag.txt" ]; then
  SKIA_VERSION=$(cat aseprite/laf/misc/skia-tag.txt)
else
  if [[ "${ASEPRITE_VERSION}" == *beta* ]]; then
    SKIA_VERSION="m124-08a5439a6b"
  else
    SKIA_VERSION="m102-861e4743af"
  fi
fi
echo "Using SKIA_VERSION=${SKIA_VERSION}"

# Download prebuilt Skia (Linux) release for the chosen tag
SKIA_DIR="${WORKDIR}/skia-${SKIA_VERSION}"
SKIA_ZIP="Skia-Linux-Release-x64.zip"
SKIA_URL="https://github.com/aseprite/skia/releases/download/${SKIA_VERSION}/${SKIA_ZIP}"

if [ ! -d "${SKIA_DIR}" ]; then
  echo "Downloading Skia from ${SKIA_URL}"
  mkdir -p "${SKIA_DIR}"
  curl -fsSL "${SKIA_URL}" -o "${WORKDIR}/${SKIA_ZIP}"
  unzip -o "${WORKDIR}/${SKIA_ZIP}" -d "${SKIA_DIR}"
  rm -f "${WORKDIR}/${SKIA_ZIP}"
else
  echo "Skia already present at ${SKIA_DIR}"
fi

# Prepare build directory and run CMake
mkdir -p "${WORKDIR}/aseprite/build"
cd "${WORKDIR}/aseprite/build"

cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DLAF_BACKEND=skia \
  -DSKIA_DIR="${SKIA_DIR}" \
  -DSKIA_LIBRARY_DIR="${SKIA_DIR}/out/Release-x64" \
  -DSKIA_LIBRARY="${SKIA_DIR}/out/Release-x64/libskia.a" \
  -G Ninja \
  ..

ninja aseprite

# Package output similar to windows script: create aseprite-<tag> with exe and data
cd "${WORKDIR}"
OUTDIR="aseprite-${ASEPRITE_VERSION}"
rm -rf "${OUTDIR}"
mkdir -p "${OUTDIR}"
echo "# This file is here so Aseprite behaves as a portable program" > "${OUTDIR}/aseprite.ini"
cp -r "aseprite/docs" "${OUTDIR}/docs" 2>/dev/null || true
cp -r "aseprite/build/bin/aseprite" "${OUTDIR}/" 2>/dev/null || cp -r "aseprite/build/bin/aseprite" "${OUTDIR}/" 2>/dev/null || true
cp -r "aseprite/build/bin/data" "${OUTDIR}/data" 2>/dev/null || true

# If running inside GitHub Actions, move to github/ and expose output variable
if [ -n "${GITHUB_WORKFLOW:-}" ]; then
  mkdir -p github
  mv "${OUTDIR}" github/
  echo "ASEPRITE_VERSION=${ASEPRITE_VERSION}" >> "${GITHUB_OUTPUT:-/dev/null}" || true
fi

echo "Done. Packaged: ${OUTDIR}"