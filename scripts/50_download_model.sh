#!/usr/bin/env bash
# Bước 5: tải model từ Hugging Face về thư mục local (tự resume nếu bị ngắt).
# Tham số: --force  tải/kiểm tra lại kể cả khi đã đánh dấu hoàn tất
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_config
require_venv

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

log_step "Tải model $MODEL_ID → $MODEL_DIR"
if model_downloaded && [[ $FORCE == 0 ]]; then
  log_ok "Model đã có sẵn ($(du -sh "$MODEL_DIR" | cut -f1)) — bỏ qua"
  exit 0
fi

mkdir -p "$MODEL_DIR"
rm -f "$MODEL_DIR/.download_complete"
export HF_XET_HIGH_PERFORMANCE=1

"$VENV_DIR/bin/python" - "$MODEL_ID" "$MODEL_DIR" <<'PY'
import os
import sys

from huggingface_hub import snapshot_download

repo_id, local_dir = sys.argv[1], sys.argv[2]
path = snapshot_download(
    repo_id=repo_id,
    local_dir=local_dir,
    token=os.environ.get("HF_TOKEN") or None,
)
print(f"       Đã tải về: {path}")
PY

[[ -f "$MODEL_DIR/config.json" ]] || die "Thiếu config.json trong $MODEL_DIR — tải lỗi?"
compgen -G "$MODEL_DIR/*.safetensors" >/dev/null || die "Không thấy file *.safetensors trong $MODEL_DIR"

date -Iseconds > "$MODEL_DIR/.download_complete"
log_ok "Tải xong model ($(du -sh "$MODEL_DIR" | cut -f1))"
