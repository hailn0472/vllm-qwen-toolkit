#!/usr/bin/env bash
# Dừng LibreChat và vLLM server chạy nền (dữ liệu chat vẫn giữ nguyên).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
parse_common_args "$@"
load_config
source "$TOOLKIT_DIR/lib/server.sh"
source "$TOOLKIT_DIR/lib/librechat.sh"

stop_librechat
stop_server
