#!/usr/bin/env bash
# Gọi thử server đang chạy (bash serve.sh) qua OpenAI API.
# Tham số khác được chuyển cho examples/openai_client.py, ví dụ:
#   bash chat.sh --prompt "Thủ đô của Việt Nam là gì?" --thinking
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
parse_common_args "$@"
load_config
require_venv
exec "$VENV_DIR/bin/python" "$TOOLKIT_DIR/examples/openai_client.py" "${REST_ARGS[@]}"
