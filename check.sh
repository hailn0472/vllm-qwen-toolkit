#!/usr/bin/env bash
# Chỉ kiểm tra yêu cầu hệ thống, không cài gì. Cách dùng: bash check.sh [--profile <tên>]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
parse_common_args "$@"
load_config
exec bash "$TOOLKIT_DIR/scripts/20_check_requirements.sh"
