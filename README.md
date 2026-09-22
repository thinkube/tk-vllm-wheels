# tk-vllm-wheels

Pre-compiled [vLLM](https://github.com/vllm-project/vllm) wheels for NVIDIA DGX Spark (arm64, sm_121 Blackwell GB10).

## What it does

Official vLLM releases don't include pre-built aarch64 wheels. This repo builds vLLM from source with `TORCH_CUDA_ARCH_LIST=12.1a` and publishes the wheel as a [GitHub Release](https://github.com/thinkube/tk-vllm-wheels/releases), one release per vLLM version, with a `checksums.txt` (SHA-256) beside the wheel.

- `build.sh` builds one wheel on a DGX Spark and writes it to `./dist/`.
- The releases hold the wheels. The repository holds only the build script.

## How it reaches a user

The wheel is a release file used by an image build of the core platform in [thinkube](https://github.com/thinkube/thinkube). When the Thinkube installer builds the base images (`core/harbor-images/14_build_base_images.yaml`), the `vllm-base` image (`core/harbor-images/base-images/vllm-base.Containerfile.j2`) installs the wheel of the release named by `TK_VLLM_VERSION` (today `0.23.0`) on arm64, with `torch==2.11.0` from the CUDA 13.0 PyTorch index. On amd64 the same image installs `vllm` from PyPI instead. The image is built from the CUDA 13.0 base image already mirrored in the platform's Harbor registry. The vLLM optional component ([tkt-vllm-gradio](https://github.com/thinkube/tkt-vllm-gradio)) is built on `vllm-base`. The wheel is not installed on its own.

The vLLM wheel contains only Apache 2.0 licensed code — CUDA/cuDNN are linked dynamically at runtime, not bundled in the wheel.

## Versions

| Release | vLLM | PyTorch | CUDA | Patches |
|---------|------|---------|------|---------|
| v0.23.0 | 0.23.0 (upstream commit 0fc695fc6; version string 0.23.1.dev0) | 2.11.0 | 13.0 | None (sm_121 upstream). DFlash, NVFP4 and `VLLM_FLASHINFER_AUTOTUNE_CACHE_DIR` present |
| v0.20.0 | 0.20.0 (version string 0.20.1.dev0) | 2.11.0 | 13.0 | None (sm_121 upstream) |
| v0.19.1 | 0.19.1 | 2.10.0 | 13.0 | None (sm_121 upstream) |
| v0.11.1rc5 | 0.11.1rc5 | 2.9.0 | 13.0 | Blackwell CMake + gencode |

The version string of a wheel is set by setuptools-scm from the upstream checkout. The PyTorch version of v0.23.0 is the one `vllm-base` pins to match the wheel's ABI.

Since v0.19.0, vLLM has native sm_121 support ([PR #38126](https://github.com/vllm-project/vllm/pull/38126)) — no patches required.

## Build details

| Parameter | Value |
|-----------|-------|
| Architecture | aarch64 (arm64) |
| CUDA compute | sm_121 (Blackwell GB10) |
| CUDA toolkit | 13.0 (`CUDA_HOME=/usr/local/cuda-13.0`) |
| Python | 3.12 |
| PyTorch | 2.11.0 (from `https://download.pytorch.org/whl/cu130`) |
| TORCH_CUDA_ARCH_LIST | 12.1a |
| VLLM_TARGET_DEVICE | cuda |
| MAX_JOBS | number of cores minus 2 (all cores when there are 4 or fewer) |

`build.sh` runs vLLM's `use_existing_torch.py`, so the wheel is built against the installed PyTorch, and builds with `pip wheel --no-build-isolation --no-deps`.

## Working on it

### Build on DGX Spark

`build.sh` must run on arm64 (aarch64). It installs system packages with `sudo apt-get` and installs `uv` if it is missing.

```bash
# Default version (v0.20.0)
./build.sh

# Specific version
./build.sh v0.23.0

# Force rebuild everything
./build.sh v0.23.0 --force
```

The build takes ~1-2 hours. Output goes to `./dist/`: the wheel and `checksums.txt`. The work directory is `/tmp/tk-vllm-build`.

### Upload a release

```bash
cd dist
gh release create v0.23.0 --repo thinkube/tk-vllm-wheels \
    --title "vLLM v0.23.0 — arm64 sm_121" \
    --notes "Pre-compiled vLLM wheel for DGX Spark (aarch64, sm_121, CUDA 13.0, Python 3.12)." \
    vllm-*.whl checksums.txt
```

To use a new release, change `TK_VLLM_VERSION` and the wheel file name in `vllm-base.Containerfile.j2`, and the `torch==` pin if the PyTorch version changed.

## License

Apache License 2.0. See [LICENSE](LICENSE).

### Attribution

- **Upstream vLLM**: Copyright vLLM contributors
- **Build scripts and packaging**: Copyright 2025 Alejandro Martínez Corriá and the Thinkube contributors

All code is licensed under Apache License 2.0.
