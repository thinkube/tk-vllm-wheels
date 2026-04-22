# tk-vllm-wheels

Pre-compiled [vLLM](https://github.com/vllm-project/vllm) wheels for NVIDIA DGX Spark (arm64, sm_121 Blackwell GB10).

Official vLLM releases don't include pre-built aarch64 wheels. This repo builds vLLM from source with `TORCH_CUDA_ARCH_LIST=12.1a` and publishes the wheel as a GitHub Release.

## Download

Grab the latest wheel from [Releases](https://github.com/thinkube/tk-vllm-wheels/releases).

## Versions

| Release | vLLM | PyTorch | CUDA | Patches |
|---------|------|---------|------|---------|
| v0.19.1 | 0.19.1 | 2.10.0 | 13.0 | None (sm_121 upstream) |
| v0.11.1rc5 | 0.11.1rc5 | 2.9.0 | 13.0 | Blackwell CMake + gencode |

Since v0.19.0, vLLM has native sm_121 support ([PR #38126](https://github.com/vllm-project/vllm/pull/38126)) — no patches required.

## Build on DGX Spark

```bash
# Default version (v0.19.1)
./build.sh

# Specific version
./build.sh v0.19.1

# Force rebuild everything
./build.sh v0.19.1 --force
```

The build takes ~1-2 hours. Output goes to `./dist/`.

## Upload a release

```bash
cd dist
gh release create v0.19.1 --repo thinkube/tk-vllm-wheels \
    --title "vLLM v0.19.1 — arm64 sm_121" \
    --notes "Pre-compiled vLLM wheel for DGX Spark (aarch64, sm_121, CUDA 13.0, Python 3.12)." \
    vllm-*.whl checksums.txt
```

## How thinkube uses this

During installation, thinkube builds a runtime image locally:

```dockerfile
FROM registry.cmxela.com/library/cuda:13.0.0-devel-ubuntu24.04
RUN pip install https://github.com/thinkube/tk-vllm-wheels/releases/download/v0.19.1/vllm-....whl
```

The CUDA base image is already mirrored in the user's Harbor registry. The vLLM wheel contains only Apache 2.0 licensed code — CUDA/cuDNN are linked dynamically at runtime, not bundled in the wheel.

## Build details

| Parameter | Value |
|-----------|-------|
| Architecture | aarch64 (arm64) |
| CUDA compute | sm_121 (Blackwell GB10) |
| CUDA toolkit | 13.0 |
| Python | 3.12 |
| PyTorch | 2.10.0 |
| TORCH_CUDA_ARCH_LIST | 12.1a |

## License

Apache 2.0

### Attribution

- **Upstream vLLM**: Copyright vLLM contributors
- **Build scripts and packaging**: Copyright 2025 Alejandro Martínez Corriá and the Thinkube contributors

All code is licensed under Apache License 2.0.
