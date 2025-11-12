#!/bin/bash
# Copyright 2025 Alejandro Martínez Corriá and the Thinkube contributors
# SPDX-License-Identifier: Apache-2.0

# Build tk-vllm wheel for DGX Spark GB10 (ARM64)
# Run on: DGX Spark GB10 (ARM64/aarch64)

set -e

VLLM_VERSION="v0.11.1rc5"
BUILD_DIR="/tmp/tk-vllm-build"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Building tk-vllm wheel for DGX Spark GB10 ==="
echo "vLLM version: ${VLLM_VERSION}"
echo "Build directory: ${BUILD_DIR}"
echo ""

# Check we're on ARM64
if [ "$(uname -m)" != "aarch64" ]; then
    echo "ERROR: This script must run on ARM64 (aarch64)"
    echo "Current architecture: $(uname -m)"
    exit 1
fi

# Clean previous build
if [ -d "${BUILD_DIR}" ]; then
    echo "Removing previous build directory..."
    rm -rf "${BUILD_DIR}"
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Install system dependencies
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
    wget \
    curl

# Install uv for better dependency management
echo ""
echo "=== Installing uv ==="
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

# Create virtual environment
echo ""
echo "=== Creating virtual environment ==="
uv venv --python 3.12 ${BUILD_DIR}/venv
source ${BUILD_DIR}/venv/bin/activate

# Set environment variables
export CUDA_HOME=/usr/local/cuda-13.0
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}"
export TRITON_PTXAS_PATH="${CUDA_HOME}/bin/ptxas"
export TORCH_CUDA_ARCH_LIST="12.1a"

echo ""
echo "=== Installing PyTorch 2.9.0 (pinned version for vLLM 0.11.1rc5) ==="
uv pip install \
    torch==2.9.0 \
    torchvision==0.24.0 \
    torchaudio==2.9.0

echo ""
echo "=== Installing build dependencies ==="
uv pip install \
    cmake>=3.26.1 \
    ninja \
    packaging>=24.2 \
    wheel \
    "setuptools>=77.0.3,<80.0.0"

echo ""
echo "=== Cloning and building Triton (main branch) ==="
git clone https://github.com/triton-lang/triton.git
cd triton/python
uv pip install -e .
cd "${BUILD_DIR}"

echo ""
echo "=== Cloning vLLM ${VLLM_VERSION} ==="
git clone https://github.com/vllm-project/vllm.git
cd vllm
git checkout ${VLLM_VERSION}
git submodule update --init --recursive

echo ""
echo "=== Applying Thinkube patches ==="

# Apply patches from repository
if [ -f "${SCRIPT_DIR}/patches/cmakelists.patch" ]; then
    echo "Applying CMakeLists.txt patch..."
    patch -p1 < "${SCRIPT_DIR}/patches/cmakelists.patch"
else
    echo "Using sed for CMakeLists.txt..."
    sed -i 's/set(SCALED_MM_ARCHS.*/set(SCALED_MM_ARCHS "8.0;8.6;8.9;9.0;12.0f;12.1a")/' CMakeLists.txt
fi

if [ -f "${SCRIPT_DIR}/patches/pyproject.patch" ]; then
    echo "Applying pyproject.toml patch..."
    patch -p1 < "${SCRIPT_DIR}/patches/pyproject.patch"
else
    echo "Using sed for pyproject.toml..."
    sed -i 's/license = {text = "Apache 2.0"}/license = {file = "LICENSE"}/' pyproject.toml
fi

if [ -f "${SCRIPT_DIR}/patches/setup.patch" ]; then
    echo "Applying setup.py patch..."
    patch -p1 < "${SCRIPT_DIR}/patches/setup.patch"
else
    echo "Using sed for setup.py..."
    sed -i 's/name="vllm"/name="tk-vllm"/' setup.py
fi

echo ""
echo "=== Building wheel (this may take a while) ==="
MAX_JOBS=8 python3 setup.py bdist_wheel

echo ""
echo "=== Wheel built successfully! ==="
ls -lh dist/

# Generate checksum
cd dist
sha256sum tk_vllm-*.whl > checksums.txt

WHEEL_FILE=$(ls tk_vllm-*.whl)

echo ""
echo "=== Build complete! ==="
echo "Wheel: ${BUILD_DIR}/vllm/dist/${WHEEL_FILE}"
echo "Checksum: ${BUILD_DIR}/vllm/dist/checksums.txt"
echo ""
echo "Next step:"
echo "  cd ${BUILD_DIR}/vllm/dist"
echo "  gh release create ${VLLM_VERSION} --repo thinkube/tk-vllm-wheels --title 'tk-vllm ${VLLM_VERSION}' --notes 'tk-vllm for DGX Spark GB10 (ARM64)' ${WHEEL_FILE} checksums.txt"
