#!/usr/bin/env bash
# Bước 6: kiểm tra GPU trong PyTorch và chạy thử inference offline với model local.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_config
require_venv
require_model

log_step "Kiểm tra PyTorch / CUDA trong venv"
"$VENV_DIR/bin/python" "$TOOLKIT_DIR/examples/env_info.py"

log_step "Chạy thử vLLM offline với $MODEL_ID"
"$VENV_DIR/bin/python" "$TOOLKIT_DIR/examples/offline_inference.py" \
  --max-tokens 128 \
  --prompt "Xin chào! Hãy giới thiệu ngắn gọn về bản thân bằng tiếng Việt."
log_ok "Smoke test thành công"
