#!/usr/bin/env python3
"""In thông tin môi trường: Python, PyTorch, CUDA, GPU, vLLM. Thoát mã 1 nếu không dùng được GPU."""

import importlib.metadata as md
import sys


def pkg_version(name: str) -> str:
    try:
        return md.version(name)
    except md.PackageNotFoundError:
        return "(không có)"


def main() -> int:
    print(f"Python        : {sys.version.split()[0]} ({sys.executable})")
    for pkg in ("vllm", "torch", "transformers", "triton", "flashinfer-python"):
        print(f"{pkg:<14}: {pkg_version(pkg)}")

    import torch

    print(f"torch CUDA    : {torch.version.cuda}")
    if not torch.cuda.is_available():
        print("[FAIL] PyTorch không thấy GPU. Kiểm tra driver (nvidia-smi) và bản torch CUDA.")
        return 1

    arch_list = torch.cuda.get_arch_list()
    print(f"Kernel arch   : {' '.join(arch_list)}")

    ok = True
    for i in range(torch.cuda.device_count()):
        prop = torch.cuda.get_device_properties(i)
        free, total = torch.cuda.mem_get_info(i)
        sm = f"sm_{prop.major}{prop.minor}"
        print(
            f"GPU {i}         : {prop.name} | {sm} | "
            f"VRAM trống {free / 1024**3:.1f}/{total / 1024**3:.1f} GB"
        )
        if sm not in arch_list:
            # Thiếu kernel native -> lỗi "no kernel image is available for execution on the device"
            print(f"[WARN] Bản torch này không có kernel {sm}. Thử TORCH_BACKEND=cu128 hoặc cu130.")
            ok = False

    # Phép nhân ma trận nhỏ để chắc chắn GPU chạy được thật
    x = torch.randn(4096, 4096, device="cuda", dtype=torch.bfloat16)
    (x @ x).sum().item()
    torch.cuda.synchronize()
    print("[ OK ] Tính toán thử trên GPU (bf16 matmul) thành công")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
