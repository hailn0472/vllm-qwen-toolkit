#!/usr/bin/env bash
# Bật vLLM OpenAI-compatible server cho model của profile hiện tại.
# Tham số khác được chuyển thẳng cho `vllm serve`, ví dụ:
#   bash serve.sh --profile qwen3.8-27b
#   PORT=9000 MAX_MODEL_LEN=65536 bash serve.sh --enforce-eager
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
parse_common_args "$@"
load_config
require_venv
require_model

cmd=(
  "$VENV_DIR/bin/vllm" serve "$MODEL_DIR"
  --served-model-name "$SERVED_MODEL_NAME"
  --host "$HOST"
  --port "$PORT"
  --max-model-len "$MAX_MODEL_LEN"
  --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION"
)
[[ -n "$API_KEY" ]] && cmd+=(--api-key "$API_KEY")
[[ "$ENFORCE_EAGER" == true ]] && cmd+=(--enforce-eager)
[[ "$LANGUAGE_MODEL_ONLY" == true ]] && cmd+=(--language-model-only)
[[ -n "$MAX_NUM_SEQS" ]] && cmd+=(--max-num-seqs "$MAX_NUM_SEQS")
[[ -n "$MAX_NUM_BATCHED_TOKENS" ]] && cmd+=(--max-num-batched-tokens "$MAX_NUM_BATCHED_TOKENS")
read -r -a extra <<< "$EXTRA_SERVE_ARGS"
cmd+=("${extra[@]}" "${REST_ARGS[@]}")

log_step "Khởi động vLLM server: $MODEL_ID (tên API: $SERVED_MODEL_NAME)"
log_info "API : http://$HOST:$PORT/v1   (Ctrl+C để dừng)"
log_info "Lệnh: ${cmd[*]}"
exec "${cmd[@]}"
