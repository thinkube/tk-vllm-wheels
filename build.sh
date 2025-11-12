#!/bin/bash
# Copyright 2025 Alejandro Martínez Corriá and the Thinkube contributors
# SPDX-License-Identifier: Apache-2.0

# Build tk-vllm wheel for DGX Spark GB10 (ARM64)
# Run on: DGX Spark GB10 (ARM64/aarch64)

set -e

VLLM_VERSION="v0.11.1rc5"
BUILD_DIR="/tmp/tk-vllm-build"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command line arguments
FORCE_REBUILD=false
if [ "$1" == "--force" ]; then
    FORCE_REBUILD=true
    echo "Force rebuild enabled - will rebuild all components"
fi

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

# Clean previous build only if --force specified
if [ "$FORCE_REBUILD" = true ] && [ -d "${BUILD_DIR}" ]; then
    echo "Removing previous build directory (--force specified)..."
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
    scons \
    wget \
    curl

# Install uv for better dependency management
if [ ! -f "$HOME/.local/bin/uv" ]; then
    echo ""
    echo "=== Installing uv ==="
    curl -LsSf https://astral.sh/uv/install.sh | sh
else
    echo ""
    echo "=== uv already installed, skipping ==="
fi
export PATH="$HOME/.local/bin:$PATH"

# Create virtual environment
if [ ! -d "${BUILD_DIR}/venv" ] || [ "$FORCE_REBUILD" = true ]; then
    echo ""
    echo "=== Creating virtual environment ==="
    uv venv --python 3.12 ${BUILD_DIR}/venv
else
    echo ""
    echo "=== Virtual environment already exists, reusing ==="
fi
source ${BUILD_DIR}/venv/bin/activate

# Set environment variables
export CUDA_HOME=/usr/local/cuda-13.0
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}"
export TRITON_PTXAS_PATH="${CUDA_HOME}/bin/ptxas"
export TORCH_CUDA_ARCH_LIST="12.1a"
export VLLM_TARGET_DEVICE=cuda

# Check if PyTorch is already installed
if python -c "import torch; assert torch.__version__ == '2.9.0+cu130'" 2>/dev/null && [ "$FORCE_REBUILD" = false ]; then
    echo ""
    echo "=== PyTorch 2.9.0+cu130 already installed, skipping ==="
else
    echo ""
    echo "=== Installing PyTorch 2.9.0 (pinned version for vLLM 0.11.1rc5) ==="
    uv pip install \
        torch==2.9.0 \
        torchvision==0.24.0 \
        torchaudio==2.9.0 \
        --index-url https://download.pytorch.org/whl/cu130
fi

# Check if build dependencies are installed
if python -c "import cmake, ninja, setuptools_scm" 2>/dev/null && [ "$FORCE_REBUILD" = false ]; then
    echo ""
    echo "=== Build dependencies already installed, skipping ==="
else
    echo ""
    echo "=== Installing build dependencies ==="
    uv pip install \
        cmake>=3.26.1 \
        ninja \
        packaging>=24.2 \
        wheel \
        "setuptools>=77.0.3,<80.0.0" \
        setuptools-scm>=8 \
        jinja2>=3.1.6 \
        regex \
        build
fi

# Check if Triton is already built
if [ -d "${BUILD_DIR}/triton" ] && python -c "import triton; assert 'git' in triton.__version__" 2>/dev/null && [ "$FORCE_REBUILD" = false ]; then
    echo ""
    echo "=== Triton already built and installed, skipping (use --force to rebuild) ==="
else
    echo ""
    echo "=== Cloning and building Triton (main branch) ==="
    if [ -d "${BUILD_DIR}/triton" ]; then
        rm -rf "${BUILD_DIR}/triton"
    fi
    git clone https://github.com/triton-lang/triton.git
    cd triton
    uv pip install -r python/requirements.txt
    uv pip install -e .
    cd "${BUILD_DIR}"
fi

echo ""
echo "=== Cloning vLLM ${VLLM_VERSION} ==="
# Always rebuild vLLM (remove old build if exists)
if [ -d "${BUILD_DIR}/vllm" ]; then
    rm -rf "${BUILD_DIR}/vllm"
fi
git clone https://github.com/vllm-project/vllm.git
cd vllm
git checkout ${VLLM_VERSION}
git submodule update --init --recursive

echo ""
echo "=== Applying Thinkube patches for Blackwell sm_121a support ==="

# Apply Blackwell patches using sed script
echo "Patching CMakeLists.txt for Blackwell sm_121a support..."
sed -i -f "${SCRIPT_DIR}/patches/blackwell.sed" CMakeLists.txt

# Fix pyproject.toml license field
echo "Patching pyproject.toml for setuptools compatibility..."
sed -i 's/license = {text = "Apache 2.0"}/license = {file = "LICENSE"}/' pyproject.toml

echo "All patches applied successfully"

echo ""
echo "=== Building wheel (this may take a while) ==="
MAX_JOBS=8 python3 setup.py bdist_wheel

echo ""
echo "=== Wheel built successfully! ==="
ls -lh dist/

# Generate checksum
cd dist
sha256sum vllm-*.whl > checksums.txt

WHEEL_FILE=$(ls vllm-*.whl)

echo ""
echo "=== Build complete! ==="
echo "Wheel: ${BUILD_DIR}/vllm/dist/${WHEEL_FILE}"
echo "Checksum: ${BUILD_DIR}/vllm/dist/checksums.txt"
echo ""
echo "Next step:"
echo "  cd ${BUILD_DIR}/vllm/dist"
echo "  gh release create ${VLLM_VERSION} --repo thinkube/tk-vllm-wheels --title 'tk-vllm ${VLLM_VERSION}' --notes 'tk-vllm for DGX Spark GB10 (ARM64)' ${WHEEL_FILE} checksums.txt"
