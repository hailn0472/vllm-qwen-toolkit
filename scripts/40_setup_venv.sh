#!/usr/bin/env bash
# Bước 4: tạo venv bằng uv (Python managed) và cài vLLM.
# Tham số: --recreate  xoá venv cũ và tạo lại
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_config

RECREATE=0
[[ "${1:-}" == "--recreate" ]] && RECREATE=1

command -v uv >/dev/null 2>&1 || die "Chưa có uv — chạy bước cài uv trước (scripts/30_install_uv.sh)"
mkdir -p "$INSTALL_DIR"

log_step "Môi trường Python $PYTHON_VERSION tại $VENV_DIR"
if [[ -x "$VENV_DIR/bin/python" ]]; then
  cur="$("$VENV_DIR/bin/python" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || echo "?")"
  if [[ $RECREATE == 1 || "$cur" != "$PYTHON_VERSION"* ]]; then
    log_warn "Xoá venv cũ (Python $cur)"
    rm -rf -- "${VENV_DIR:?}"
  else
    log_ok "Dùng lại venv hiện có (Python $cur)"
  fi
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  uv python install "$PYTHON_VERSION"
  uv venv "$VENV_DIR" --python "$PYTHON_VERSION" --managed-python --seed
  log_ok "Đã tạo venv"
fi

log_step "Cài vLLM (torch backend: $TORCH_BACKEND)"
vllm_spec="vllm"
[[ -n "$VLLM_VERSION" ]] && vllm_spec="vllm==$VLLM_VERSION"
read -r -a extra_pkgs <<< "$EXTRA_PIP_PACKAGES"

uv pip install --python "$VENV_DIR/bin/python" --torch-backend="$TORCH_BACKEND" \
  "$vllm_spec" "huggingface_hub[hf_xet]" openai "${extra_pkgs[@]}"

log_step "Xác minh gói đã cài"
"$VENV_DIR/bin/python" - <<'PY'
import importlib.metadata as md
import torch

for pkg in ("vllm", "torch", "transformers", "triton", "huggingface_hub", "openai"):
    try:
        print(f"       {pkg:<16} {md.version(pkg)}")
    except md.PackageNotFoundError:
        print(f"       {pkg:<16} (không có)")
print(f"       torch CUDA build {torch.version.cuda}")
PY
log_ok "vLLM đã cài xong"
