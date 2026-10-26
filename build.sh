#!/bin/bash
# Copyright 2025 Alejandro Martínez Corriá and the Thinkube contributors
# SPDX-License-Identifier: Apache-2.0

# Build vLLM wheel for DGX Spark GB10 (ARM64, sm_121)
# Run on: DGX Spark GB10 (ARM64/aarch64)
#
# Usage: ./build.sh [version] [--force] [--existing-torch]
#   version: vLLM version tag (default: $DEFAULT_VLLM_VERSION)
#   --force: rebuild all components from scratch
#   --existing-torch: build against the PyTorch already installed in this
#       environment instead of installing PyTorch from PyTorch's CUDA index;
#       on amd64 as well, where the wheel covers Ampere to Blackwell.
#       For NVIDIA's PyTorch containers (nvcr.io/nvidia/pytorch), whose
#       PyTorch is a build of its own: a wheel built on PyTorch's index does
#       not import there. The venv then sees the environment's packages, the
#       CUDA toolkit is the environment's, and system packages are not
#       installed (the container has the compilers; cmake and ninja come
#       from pip). A PyTorch 2.11 build without register_opaque_type's hoist
#       keyword (NVIDIA 26.03) gets vLLM's one call to it patched to try
#       without.

set -euo pipefail

DEFAULT_VLLM_VERSION="v0.23.0"

VLLM_VERSION="$DEFAULT_VLLM_VERSION"
FORCE_REBUILD=false
EXISTING_TORCH=false
for arg in "$@"; do
    case "$arg" in
        --force) FORCE_REBUILD=true ;;
        --existing-torch) EXISTING_TORCH=true ;;
        --*) echo "unknown option: $arg" >&2; exit 2 ;;
        *) VLLM_VERSION="$arg" ;;
    esac
done

BUILD_DIR="/tmp/tk-vllm-build"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"

echo "=== Building vLLM ${VLLM_VERSION} wheel for DGX Spark GB10 ==="
echo "Build directory: ${BUILD_DIR}"
echo "Output: ${DIST_DIR}"
echo "PyTorch: $([ "$EXISTING_TORCH" = true ] && echo "the environment's" || echo "2.11.0 from PyTorch's CUDA 13.0 index")"
echo ""

ARCH="$(uname -m)"
if [ "$ARCH" != "aarch64" ] && [ "$EXISTING_TORCH" = false ]; then
    echo "ERROR: This script must run on ARM64 (aarch64); on another architecture give --existing-torch"
    exit 1
fi

if [ "$FORCE_REBUILD" = true ] && [ -d "${BUILD_DIR}" ]; then
    echo "Removing previous build directory (--force)..."
    rm -rf "${BUILD_DIR}"
fi

mkdir -p "${BUILD_DIR}" "${DIST_DIR}"
cd "${BUILD_DIR}"

# System dependencies: on a machine of your own. In a container that already
# holds the compilers (--existing-torch), nothing is installed.
if [ "$EXISTING_TORCH" = false ]; then
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
fi

# Virtual environment
if [ "$EXISTING_TORCH" = true ]; then
    # The environment's packages, PyTorch among them, stay visible
    if [ ! -d "${BUILD_DIR}/venv" ] || [ "$FORCE_REBUILD" = true ]; then
        echo ""
        echo "=== Creating virtual environment on the environment's packages ==="
        python3 -m venv --system-site-packages "${BUILD_DIR}/venv"
    fi
    source "${BUILD_DIR}/venv/bin/activate"
    PIP="pip install"
else
    if ! command -v uv &>/dev/null; then
        echo ""
        echo "=== Installing uv ==="
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
    export PATH="$HOME/.local/bin:$PATH"
    if [ ! -d "${BUILD_DIR}/venv" ] || [ "$FORCE_REBUILD" = true ]; then
        echo ""
        echo "=== Creating virtual environment ==="
        uv venv --python 3.12 "${BUILD_DIR}/venv"
    fi
    source "${BUILD_DIR}/venv/bin/activate"
    uv pip install pip
    PIP="uv pip install"
fi

# Environment
if [ "$EXISTING_TORCH" = true ]; then
    export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
else
    export CUDA_HOME=/usr/local/cuda-13.0
fi
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"
# The GPUs the wheel is compiled for. On arm64 the GB10 only, whatever the
# environment says (NVIDIA's containers set a list without 12.1a). On amd64,
# the environment's TORCH_CUDA_ARCH_LIST when set (NVIDIA's containers set
# 7.5 to 12.0+PTX, the GPUs their PyTorch is built for), else Ampere to Blackwell.
if [ "$ARCH" = "aarch64" ]; then
    export TORCH_CUDA_ARCH_LIST="12.1a"
elif [ -z "${TORCH_CUDA_ARCH_LIST:-}" ]; then
    export TORCH_CUDA_ARCH_LIST="8.0;8.6;8.9;9.0;10.0;12.0"
fi
echo "GPU architectures: ${TORCH_CUDA_ARCH_LIST}"
export VLLM_TARGET_DEVICE=cuda

# PyTorch version matching vLLM's requirements
PYTORCH_VERSION="2.11.0"
if [ "$EXISTING_TORCH" = true ]; then
    echo ""
    echo "=== Using the environment's PyTorch ==="
    python -c "import torch; print(f'PyTorch {torch.__version__}, CUDA {torch.version.cuda}')"
elif python -c "import torch; assert torch.__version__.startswith('${PYTORCH_VERSION}')" 2>/dev/null && [ "$FORCE_REBUILD" = false ]; then
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
$PIP \
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

# No patches needed for sm_121 — support is upstream since v0.19.0 (PR #38126).
# A PyTorch build without register_opaque_type's hoist keyword gets vLLM's
# one call to it (vllm/utils/torch_utils.py) made to try without.
if ! python - <<'EOF'
import inspect
from torch._library.opaque_object import register_opaque_type
raise SystemExit(0 if "hoist" in inspect.signature(register_opaque_type).parameters else 1)
EOF
then
    echo ""
    echo "=== Patching: this PyTorch's register_opaque_type has no hoist keyword ==="
    python - <<'EOF'
path = "vllm/utils/torch_utils.py"
s = open(path).read()
old = 'register_opaque_type(LayerName, typ="value", hoist=True)'
new = ('try:\n        register_opaque_type(LayerName, typ="value", hoist=True)\n'
       '    except TypeError:  # a PyTorch build without the hoist keyword\n'
       '        register_opaque_type(LayerName, typ="value")')
assert s.count(old) == 1, f"{path}: the register_opaque_type call is not where this patch expects it"
open(path, "w").write(s.replace(old, new))
EOF
    git diff > "${DIST_DIR}/patch-hoist.diff"
fi

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
echo "=== Checking the wheel imports on this PyTorch ==="
pip install --no-deps "${DIST_DIR}"/vllm-*.whl
# from outside the source tree, so that the installed wheel is what imports
(cd / && python -c "import torch, vllm, vllm._C; print(f'vllm {vllm.__version__} imports on PyTorch {torch.__version__}')")

echo ""
echo "=== Generating checksums ==="
cd "${DIST_DIR}"
sha256sum vllm-*.whl > checksums.txt
cat checksums.txt
