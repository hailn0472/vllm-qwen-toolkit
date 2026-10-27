#!/usr/bin/env bash
# Quản lý riêng LibreChat (không đụng tới vLLM).
# Cách dùng: bash librechat.sh up|down|restart|logs|status|update
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
parse_common_args "$@"
load_config
source "$TOOLKIT_DIR/lib/librechat.sh"

librechat_installed || die "Chưa cài LibreChat — chạy: bash install.sh (hoặc bash scripts/80_setup_librechat.sh)"

case "${REST_ARGS[0]:-status}" in
  up)      start_librechat ;;
  down)    stop_librechat ;;
  restart) stop_librechat; start_librechat ;;
  logs)    lc_compose logs -f --tail 100 api ;;
  status)  lc_compose ps
           if librechat_ready; then log_ok "Web: $LIBRECHAT_URL"; else log_info "Web chưa chạy"; fi ;;
  update)  bash "$TOOLKIT_DIR/scripts/80_setup_librechat.sh" && lc_compose up -d ;;
  *)       die "Lệnh không hợp lệ: ${REST_ARGS[0]}. Dùng: up|down|restart|logs|status|update" ;;
esac
