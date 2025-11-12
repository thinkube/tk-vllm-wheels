# tk-vllm Wheels

Pre-built tk-vllm wheels for Thinkube with DGX Spark GB10 patches.

## What is tk-vllm?

`tk-vllm` is a branded distribution of vLLM with community patches for DGX Spark GB10 (Blackwell architecture).

## Current Support

- ✅ **ARM64**: DGX Spark GB10 (Blackwell sm_121a)
- ⏳ **x86-64**: RTX 20/30/40/50 series (planned)

## Installation

```bash
pip install https://github.com/thinkube/tk-vllm-wheels/releases/download/v0.11.1rc5/tk_vllm-0.11.1rc5+thinkube-cp312-cp312-linux_aarch64.whl
```

## Patches Included

1. **CMakeLists.txt**: Added sm_121a to MOE kernel support
2. **pyproject.toml**: Fixed license field for setuptools compatibility
3. **setup.py**: Changed package name to tk-vllm

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
