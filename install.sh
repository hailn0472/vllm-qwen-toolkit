#!/usr/bin/env bash
# Cài tự động vLLM + model Qwen trên Ubuntu.
# Cách dùng: bash install.sh [--profile <tên>] [-y] [tuỳ chọn khác, xem --help]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<EOF
Cách dùng: bash install.sh [tuỳ chọn]

  --profile <tên>    Chọn model (có: $(list_profiles))
  -y, --yes          Tự đồng ý mọi câu hỏi (cài gói apt...)
  --skip-check       Bỏ qua bước kiểm tra yêu cầu
  --skip-model       Không tải model (chỉ cài vLLM)
  --skip-test        Không chạy thử sau khi cài
  --skip-librechat   Không cài Docker + LibreChat (web UI)
  --force-download   Tải/kiểm tra lại model kể cả khi đã có
  --recreate-venv    Xoá venv cũ và cài lại từ đầu
  -h, --help         Hiện trợ giúp

Ví dụ:
  bash install.sh                          # profile mặc định (Qwen3.5-4B)
  bash install.sh --profile qwen3.5-0.8b   # GPU nhỏ (4 GB)
  bash install.sh --profile qwen3.8-27b -y # model chính 27B
  INSTALL_DIR=/data/llm bash install.sh    # đổi thư mục cài
EOF
}

parse_common_args "$@"
SKIP_CHECK=0; SKIP_MODEL=0; SKIP_TEST=0; SKIP_LIBRECHAT=0; FORCE_DOWNLOAD=0; RECREATE_VENV=0
for arg in "${REST_ARGS[@]}"; do
  case "$arg" in
    --skip-check)     SKIP_CHECK=1 ;;
    --skip-model)     SKIP_MODEL=1 ;;
    --skip-test)      SKIP_TEST=1 ;;
    --skip-librechat) SKIP_LIBRECHAT=1 ;;
    --force-download) FORCE_DOWNLOAD=1 ;;
    --recreate-venv)  RECREATE_VENV=1 ;;
    -h|--help)        usage; exit 0 ;;
    *)                usage; die "Tham số không hợp lệ: $arg" ;;
  esac
done
export SKIP_MODEL

load_config
mkdir -p "$INSTALL_DIR" "$LOG_DIR"
echo "$PROFILE" > "$INSTALL_DIR/.active_profile"

# Ghi log ra file, giữ màu nếu đang chạy trong terminal
[[ -t 1 ]] && export TOOLKIT_COLOR=1
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "${C_BOLD}=================================================================${C_RESET}"
echo "${C_BOLD} vLLM + Qwen toolkit — cài đặt${C_RESET}"
echo "  Profile     : $PROFILE ($MODEL_ID)"
echo "  Thư mục cài : $INSTALL_DIR"
echo "  Log         : $LOG_FILE"
echo "${C_BOLD}=================================================================${C_RESET}"

run_step() {
  local script="$1"; shift
  bash "$TOOLKIT_DIR/scripts/$script" "$@" || die "Bước $script thất bại. Xem log: $LOG_FILE"
}

START_TIME=$SECONDS
run_step 10_system_deps.sh
if [[ $SKIP_CHECK == 0 ]]; then run_step 20_check_requirements.sh; fi
run_step 30_install_uv.sh
if [[ $RECREATE_VENV == 1 ]]; then run_step 40_setup_venv.sh --recreate; else run_step 40_setup_venv.sh; fi
if [[ $SKIP_MODEL == 0 ]]; then
  if [[ $FORCE_DOWNLOAD == 1 ]]; then run_step 50_download_model.sh --force; else run_step 50_download_model.sh; fi
  if [[ $SKIP_TEST == 0 ]]; then run_step 60_smoke_test.sh; fi
fi
if [[ $SKIP_LIBRECHAT == 0 ]]; then
  run_step 70_install_docker.sh
  run_step 80_setup_librechat.sh
fi

elapsed=$((SECONDS - START_TIME))
log_step "HOÀN TẤT sau $((elapsed / 60)) phút $((elapsed % 60)) giây"
cat <<EOF
  uv         : $(command -v uv)
  venv/vLLM  : $VENV_DIR
  Weights    : $MODEL_DIR

  Bật vLLM + web UI  : bash start.sh         (LibreChat tại http://localhost:$LIBRECHAT_PORT)
  Dừng tất cả        : bash stop.sh
  Chạy thử offline   : bash test.sh
  Chỉ bật API server : bash serve.sh          (OpenAI API tại http://$HOST:$PORT/v1)
  Gọi thử server     : bash chat.sh --prompt "Xin chào"
  Kích hoạt venv tay : source $VENV_DIR/bin/activate
EOF
