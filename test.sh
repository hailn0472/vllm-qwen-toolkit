#!/usr/bin/env bash
# Chạy examples/offline_inference.py với model của profile hiện tại.
# Tham số khác được chuyển thẳng cho script Python, ví dụ:
#   bash test.sh --prompt "Viết thơ về Hà Nội" --max-tokens 256 --thinking
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
parse_common_args "$@"
load_config
require_venv
require_model
exec "$VENV_DIR/bin/python" "$TOOLKIT_DIR/examples/offline_inference.py" "${REST_ARGS[@]}"
