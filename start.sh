#!/usr/bin/env bash
# Bật toàn bộ: vLLM server (chạy nền) + LibreChat, rồi in địa chỉ web.
# Cách dùng: bash start.sh [--profile <tên>] [tham số thêm cho vllm serve...]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
parse_common_args "$@"
load_config
source "$TOOLKIT_DIR/lib/server.sh"
source "$TOOLKIT_DIR/lib/librechat.sh"
require_venv
require_model
echo "$PROFILE" > "$INSTALL_DIR/.active_profile"

log_step "vLLM: $MODEL_ID (tên API: $SERVED_MODEL_NAME)"
start_server_bg "${REST_ARGS[@]}" || die "vLLM chưa sẵn sàng — LibreChat sẽ không có model để chat"

log_step "LibreChat"
start_librechat

ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
cat <<EOF

  Mở trình duyệt : $LIBRECHAT_URL${ip:+   (máy khác trong mạng: http://$ip:$LIBRECHAT_PORT)}
  Lần đầu        : bấm "Sign up" tạo tài khoản (tài khoản đầu tiên là admin)
  vLLM API       : http://$(local_host):$PORT/v1
  Log vLLM       : tail -f $SERVER_LOG
  Log LibreChat  : bash librechat.sh logs
  Dừng tất cả    : bash stop.sh
EOF
