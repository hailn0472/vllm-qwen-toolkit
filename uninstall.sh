#!/usr/bin/env bash
# Gỡ cài đặt. Mặc định chỉ xoá venv; --all xoá toàn bộ INSTALL_DIR (gồm cả model đã tải).
# uv (~/.local/bin/uv), Docker, image Docker và gói apt không bị đụng tới.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
parse_common_args "$@"
load_config

ALL=0
[[ " ${REST_ARGS[*]} " == *" --all "* ]] && ALL=1

case "$INSTALL_DIR" in
  ""|/|"$HOME"|"$HOME/") die "INSTALL_DIR không an toàn để xoá: '$INSTALL_DIR'" ;;
esac

if [[ $ALL == 1 ]]; then
  [[ -d "$INSTALL_DIR" ]] || { log_ok "Không có $INSTALL_DIR"; exit 0; }
  log_info "Sẽ xoá: $INSTALL_DIR ($(du -sh "$INSTALL_DIR" 2>/dev/null | cut -f1))"
  confirm "Xoá TOÀN BỘ (venv + model + log + LibreChat và lịch sử chat)?" || die "Đã huỷ"
  source "$TOOLKIT_DIR/lib/server.sh"
  source "$TOOLKIT_DIR/lib/librechat.sh"
  stop_server
  if librechat_installed && command -v docker >/dev/null 2>&1; then
    lc_compose down --volumes --remove-orphans || true
  fi
  rm -rf -- "${INSTALL_DIR:?}"
  log_ok "Đã xoá $INSTALL_DIR"
else
  [[ -d "$VENV_DIR" ]] || { log_ok "Không có venv tại $VENV_DIR"; exit 0; }
  confirm "Xoá venv $VENV_DIR? (model vẫn giữ lại)" || die "Đã huỷ"
  rm -rf -- "${VENV_DIR:?}"
  log_ok "Đã xoá venv. Model vẫn ở $INSTALL_DIR/models"
fi
