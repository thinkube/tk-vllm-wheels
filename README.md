# tk-vllm-wheels

Pre-built vLLM wheels for DGX Spark GB10 (Blackwell sm_121a).

This repository provides vLLM wheels with community patches for DGX Spark GB10 support.

## Current Support

- ✅ **ARM64**: DGX Spark GB10 (Blackwell sm_121a)
- ⏳ **x86-64**: RTX 20/30/40/50 series (planned)

## Installation

```bash
pip install https://github.com/thinkube/tk-vllm-wheels/releases/download/v0.11.1rc5/vllm-0.11.1rc6.dev0+g2918c1b49.d20251112.cu130-cp312-cp312-linux_aarch64.whl
```

## Patches Included

### CMakeLists.txt - Blackwell sm_121a Support

vLLM 0.11.1rc5's CMakeLists.txt has CUDA 13.0-specific architecture lists that only include `12.0f` (SM100) but not `12.1a` (Blackwell GB10). We patch:

- **CUTLASS_MOE_DATA_ARCHS**: Critical for Mixture of Experts models
- **SCALED_MM_ARCHS**: Scaled matrix multiplication kernels
- **FP4_ARCHS**: FP4 quantization support
- **MLA_ARCHS**: Multi-Level Attention kernels

Each is patched to add `12.1a` to the CUDA 13.0 branch.

### pyproject.toml

Fixed license field for setuptools compatibility (`license = {file = "LICENSE"}`).

Based on community solution: [github.com/eelbaz/dgx-spark-vllm-setup](https://github.com/eelbaz/dgx-spark-vllm-setup)

## Requirements

- Python 3.12
- CUDA 13.0+
- PyTorch 2.5.1+
- ARM64 architecture (DGX Spark GB10)

## Building Wheels

```bash
./build.sh
```

## Usage in Thinkube

This wheel is automatically used by Thinkube's vllm-base image.

## License

Apache 2.0

### Attribution

- **Upstream vLLM**: Copyright vLLM contributors
- **DGX Spark patches**: Community contribution (see github.com/eelbaz/dgx-spark-vllm-setup)
- **tk-vllm build scripts and packaging**: Copyright 2025 Alejandro Martínez Corriá and the Thinkube contributors

All code is licensed under Apache License 2.0.
