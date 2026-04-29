#!/bin/bash
# Copyright 2025 Alejandro Martínez Corriá and the Thinkube contributors
# SPDX-License-Identifier: Apache-2.0

# Build vLLM wheel for DGX Spark GB10 (ARM64, sm_121)
# Run on: DGX Spark GB10 (ARM64/aarch64)
#
# Usage: ./build.sh [version] [--force]
#   version: vLLM version tag (default: v0.19.1)
#   --force: rebuild all components from scratch

set -euo pipefail

VLLM_VERSION="${1:-v0.20.0}"
if [ "$VLLM_VERSION" = "--force" ]; then
    VLLM_VERSION="v0.20.0"
    FORCE_REBUILD=true
else
    FORCE_REBUILD=false
    if [ "${2:-}" = "--force" ]; then
        FORCE_REBUILD=true
    fi
fi

BUILD_DIR="/tmp/tk-vllm-build"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"

echo "=== Building vLLM ${VLLM_VERSION} wheel for DGX Spark GB10 ==="
echo "Build directory: ${BUILD_DIR}"
echo "Output: ${DIST_DIR}"
echo ""

if [ "$(uname -m)" != "aarch64" ]; then
    echo "ERROR: This script must run on ARM64 (aarch64)"
    exit 1
fi

if [ "$FORCE_REBUILD" = true ] && [ -d "${BUILD_DIR}" ]; then
    echo "Removing previous build directory (--force)..."
    rm -rf "${BUILD_DIR}"
fi

mkdir -p "${BUILD_DIR}" "${DIST_DIR}"
cd "${BUILD_DIR}"

# System dependencies
echo ""
echo "=== Installing system dependencies ==="
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-dev \
    python3.12-venv \
    python3-pip \
    git \
    build-essential \
    ninja-build \
    cmake \
    wget \
    curl

# Install uv
if ! command -v uv &>/dev/null; then
    echo ""
    echo "=== Installing uv ==="
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="$HOME/.local/bin:$PATH"

# Virtual environment
if [ ! -d "${BUILD_DIR}/venv" ] || [ "$FORCE_REBUILD" = true ]; then
    echo ""
    echo "=== Creating virtual environment ==="
    uv venv --python 3.12 "${BUILD_DIR}/venv"
fi
source "${BUILD_DIR}/venv/bin/activate"

uv pip install pip

# Environment
export CUDA_HOME=/usr/local/cuda-13.0
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"
export TORCH_CUDA_ARCH_LIST="12.1a"
export VLLM_TARGET_DEVICE=cuda

# PyTorch version matching vLLM's requirements
PYTORCH_VERSION="2.11.0"
if python -c "import torch; assert torch.__version__.startswith('${PYTORCH_VERSION}')" 2>/dev/null && [ "$FORCE_REBUILD" = false ]; then
    echo ""
    echo "=== PyTorch ${PYTORCH_VERSION}+cu130 already installed, skipping ==="
else
    echo ""
    echo "=== Installing PyTorch ${PYTORCH_VERSION} ==="
    uv pip install \
        "torch==${PYTORCH_VERSION}" \
        --index-url https://download.pytorch.org/whl/cu130
fi

# Build dependencies (from vLLM's requirements/build.txt)
echo ""
echo "=== Installing build dependencies ==="
uv pip install \
    "cmake>=3.26.1" \
    ninja \
    "packaging>=24.2" \
    wheel \
    "setuptools>=77.0.3,<81.0.0" \
    "setuptools-scm>=8" \
    "jinja2>=3.1.6" \
    regex \
    build \
    "protobuf>=5.29.6"

# Clone vLLM
echo ""
echo "=== Cloning vLLM ${VLLM_VERSION} ==="
if [ -d "${BUILD_DIR}/vllm" ]; then
    rm -rf "${BUILD_DIR}/vllm"
fi
git clone --depth 1 --branch "${VLLM_VERSION}" \
    https://github.com/vllm-project/vllm.git
cd vllm

# No patches needed — sm_121 support is upstream since v0.19.0 (PR #38126)

echo ""
echo "=== Preparing build ==="
python use_existing_torch.py
if [ -f requirements/build.txt ]; then
    pip install -r requirements/build.txt
elif [ -f requirements/build/cuda.txt ]; then
    pip install -r requirements/build/cuda.txt
fi

TOTAL_CORES=$(nproc)
MAX_JOBS=$(( TOTAL_CORES > 4 ? TOTAL_CORES - 2 : TOTAL_CORES ))
export MAX_JOBS

echo ""
echo "=== Building wheel (MAX_JOBS=${MAX_JOBS}, ~1-2 hours) ==="
pip wheel --no-build-isolation --no-deps --wheel-dir "${DIST_DIR}" .

echo ""
echo "=== Generating checksums ==="
cd "${DIST_DIR}"
sha256sum vllm-*.whl > checksums.txt

WHEEL_FILE=$(ls vllm-*.whl)

echo ""
echo "=== Build complete! ==="
echo "Wheel: ${DIST_DIR}/${WHEEL_FILE}"
echo "Checksum: ${DIST_DIR}/checksums.txt"
echo ""
echo "To create a release:"
echo "  cd ${DIST_DIR}"
echo "  gh release create ${VLLM_VERSION} --repo thinkube/tk-vllm-wheels \\"
echo "    --title 'vLLM ${VLLM_VERSION} — arm64 sm_121' \\"
echo "    --notes 'Pre-compiled vLLM wheel for DGX Spark (aarch64, sm_121, CUDA 13.0, Python 3.12).' \\"
echo "    ${WHEEL_FILE} checksums.txt"
