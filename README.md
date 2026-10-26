# tk-vllm-wheels

Pre-compiled [vLLM](https://github.com/vllm-project/vllm) wheels for NVIDIA DGX Spark (arm64, sm_121 Blackwell GB10).

## What it does

Official vLLM releases don't include pre-built aarch64 wheels. This repo builds vLLM from source with `TORCH_CUDA_ARCH_LIST=12.1a` and publishes the wheel as a [GitHub Release](https://github.com/thinkube/tk-vllm-wheels/releases), one release per vLLM version, with a `checksums.txt` (SHA-256) beside the wheel.

- `build.sh` builds one wheel on a DGX Spark and writes it to `./dist/`.
- The releases hold the wheels. The repository holds only the build script.

## How it reaches a user

The wheel is a release file used by an image build of the core platform in [thinkube](https://github.com/thinkube/thinkube). When the Thinkube installer builds the base images (`core/harbor-images/14_build_base_images.yaml`), the `vllm-base` image (`core/harbor-images/base-images/vllm-base.Containerfile.j2`) installs the wheel of the release named by `vllm_version` in `14_build_base_images.yaml` (today `0.23.0`) on arm64, with `torch==2.11.0` from the CUDA 13.0 PyTorch index. On amd64 the same image installs `vllm` from PyPI instead. The image is built from the CUDA 13.0 base image already mirrored in the platform's Harbor registry. The vLLM optional component ([tkt-vllm-gradio](https://github.com/thinkube/tkt-vllm-gradio)) is built on `vllm-base`. The wheel is not installed on its own.

The vLLM wheel contains only Apache 2.0 licensed code — CUDA/cuDNN are linked dynamically at runtime, not bundled in the wheel.

## Standalone use

Standalone use is not supported. The wheels are built and tested only as part of the Thinkube platform. The licence lets you use them anywhere, but issues and questions about using a wheel outside Thinkube are not answered.

## Versions

| Release | vLLM | PyTorch | CUDA | Patches |
|---------|------|---------|------|---------|
| v0.22.1-nv26.03 (arm64 and amd64 wheels) | 0.22.1 (version string 0.22.2.dev0), built with `--existing-torch` on `nvcr.io/nvidia/pytorch:26.03-py3`; the amd64 wheel compiled for the container's GPU list, 7.5 to 12.0+PTX | 2.11.0a0 (NVIDIA's build, nv26.3) | 13.2 | `register_opaque_type` called without `hoist` where that PyTorch has no such keyword (`patch-hoist.diff` in the release). For training environments on NVIDIA's container, such as llebre's; the wheel of v0.23.0 does not import there. 0.22.1 is the newest vLLM that builds on this PyTorch: 0.23 needs `torch::stable::Tensor::layout` (`csrc/libtorch_stable/cuda_view.cu`), which it lacks |
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
# Default version (v0.23.0)
./build.sh

# Specific version
./build.sh v0.23.0

# Force rebuild everything
./build.sh v0.23.0 --force

# Against the PyTorch already installed, inside NVIDIA's PyTorch container:
# a clone of this repository mounted at /work, the wheel lands in ./dist
docker run --rm --gpus all -v "$PWD:/work" -w /work nvcr.io/nvidia/pytorch:26.03-py3 \
    bash build.sh v0.22.1 --existing-torch
```

The GPU is needed only for the import check at the end of the build: with Docker, `docker run --gpus all ...` and the NVIDIA runtime, as on DGX OS; with Podman, `--device nvidia.com/gpu=all` once `nvidia-ctk cdi generate` has written the device spec. `--existing-torch` builds on the PyTorch of the environment it runs in instead of installing one: for NVIDIA's PyTorch containers, whose PyTorch is a build of its own, so that the wheel imports there. It installs no system packages (the container has the compilers), uses the container's CUDA toolkit, and when that PyTorch lacks `register_opaque_type`'s `hoist` keyword it patches vLLM's one call to it and writes the diff beside the wheel. Such a release is tagged with the container's release after the vLLM version, `v0.22.1-nv26.03`, and holds one wheel per architecture: the same command on an amd64 machine builds the x86-64 wheel for the GPUs of the container's `TORCH_CUDA_ARCH_LIST` (7.5 to 12.0+PTX in NVIDIA's), or Ampere to Blackwell where none is set; on arm64 the wheel is always for the GB10.

The build takes ~1-2 hours. Output goes to `./dist/`: the wheel and `checksums.txt`. The work directory is `/tmp/tk-vllm-build`.

### Upload a release

```bash
cd dist
gh release create v0.23.0 --repo thinkube/tk-vllm-wheels \
    --title "vLLM v0.23.0 — arm64 sm_121" \
    --notes "Pre-compiled vLLM wheel for DGX Spark (aarch64, sm_121, CUDA 13.0, Python 3.12)." \
    vllm-*.whl checksums.txt
```

To use a new release, change `vllm_version` and `vllm_arm64_wheel` in `14_build_base_images.yaml`, and the `torch==` pin in `vllm-base.Containerfile.j2` if the PyTorch version changed. The `vllm-base` image tag starts with `vllm_version`, so a new version builds a new image tag.

## License

Apache License 2.0. See [LICENSE](LICENSE).

### Attribution

- **Upstream vLLM**: Copyright vLLM contributors
- **Build scripts and packaging**: Copyright 2025 Alejandro Martínez Corriá and the Thinkube contributors

All code is licensed under Apache License 2.0.
