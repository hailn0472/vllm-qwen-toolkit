#!/usr/bin/env bash
# Hàm dùng chung cho mọi script trong toolkit. Chỉ source, không chạy trực tiếp.

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Màu: bật khi stdout là terminal, hoặc khi script cha đã quyết định (TOOLKIT_COLOR=1)
if [[ "${TOOLKIT_COLOR:-}" == 1 || ( -z "${TOOLKIT_COLOR:-}" && -t 1 ) ]]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""; C_RESET=""
fi

log_step() { echo; echo "${C_BOLD}${C_BLUE}==> $*${C_RESET}"; }
log_info() { echo "       $*"; }
log_ok()   { echo "${C_GREEN}[ OK ]${C_RESET} $*"; }
log_warn() { echo "${C_YELLOW}[WARN]${C_RESET} $*"; }
log_fail() { echo "${C_RED}[FAIL]${C_RESET} $*"; }
die()      { log_fail "$*" >&2; exit 1; }

# version_ge A B -> đúng nếu A >= B (so sánh kiểu 12.8 / 570.86.10)
version_ge() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$2" ]]
}

# Hỏi y/N. Tự đồng ý nếu ASSUME_YES=1, tự từ chối nếu không có terminal.
confirm() {
  [[ "${ASSUME_YES:-0}" == 1 ]] && return 0
  [[ -t 0 ]] || return 1
  local ans
  read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

# Profile có sẵn nằm trong toolkit; profile tạo từ menu (mục 5) nằm trong $INSTALL_DIR/profiles
profile_files() {
  local f
  for f in "$TOOLKIT_DIR"/profiles/*.env ${USER_PROFILE_DIR:+"$USER_PROFILE_DIR"/*.env}; do
    [[ -f "$f" ]] && echo "$f"
  done
}

list_profiles() {
  local f names=()
  while read -r f; do names+=("$(basename "$f" .env)"); done < <(profile_files)
  echo "${names[*]}"
}

find_profile_file() {
  local f
  for f in "$TOOLKIT_DIR/profiles/$1.env" ${USER_PROFILE_DIR:+"$USER_PROFILE_DIR/$1.env"}; do
    [[ -f "$f" ]] && { echo "$f"; return 0; }
  done
  return 1
}

# Thư mục weights: Qwen/Qwen3.5-4B -> models/Qwen3.5-4B, org khác -> models/org--repo (tránh trùng tên)
default_model_dir() {
  local id="$1" org="${1%%/*}"
  if [[ "${org,,}" == qwen ]]; then
    echo "$INSTALL_DIR/models/${id##*/}"
  else
    echo "$INSTALL_DIR/models/${id//\//--}"
  fi
}

# Rút gọn đường dẫn trong $HOME thành ~ cho dễ đọc
short_path() { echo "${1/#$HOME/\~}"; }

# Tách các tham số chung (--profile, -y). Phần còn lại nằm trong mảng REST_ARGS.
parse_common_args() {
  REST_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        [[ -n "${2:-}" ]] || die "--profile cần tên profile. Có: $(list_profiles)"
        export TOOLKIT_PROFILE="$2"; shift 2 ;;
      --profile=*) export TOOLKIT_PROFILE="${1#*=}"; shift ;;
      -y|--yes) export ASSUME_YES=1; shift ;;
      *) REST_ARGS+=("$1"); shift ;;
    esac
  done
}

# Nạp config.env -> config.local.env -> profile.
# Thứ tự chọn profile: --profile > profile đã cài gần nhất > DEFAULT_PROFILE.
load_config() {
  # shellcheck source=../config.env
  source "$TOOLKIT_DIR/config.env"
  if [[ -f "$TOOLKIT_DIR/config.local.env" ]]; then
    # shellcheck disable=SC1091
    source "$TOOLKIT_DIR/config.local.env"
  fi

  INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
  VENV_DIR="$INSTALL_DIR/venv"
  LOG_DIR="$INSTALL_DIR/logs"
  USER_PROFILE_DIR="$INSTALL_DIR/profiles"
  LIBRECHAT_DIR="$INSTALL_DIR/librechat"   # compose, .env, dữ liệu MongoDB (phải nằm trên ext4/xfs)

  local profile="${TOOLKIT_PROFILE:-}"
  if [[ -z "$profile" && -f "$INSTALL_DIR/.active_profile" ]]; then
    profile="$(<"$INSTALL_DIR/.active_profile")"
  fi
  profile="${profile:-$DEFAULT_PROFILE}"

  local profile_file
  profile_file="$(find_profile_file "$profile")" \
    || die "Không có profile '$profile'. Các profile hiện có: $(list_profiles)"
  # shellcheck disable=SC1090
  source "$profile_file"
  PROFILE="$profile"
  MODEL_DIR="${MODEL_DIR:-$(default_model_dir "$MODEL_ID")}"
  ENFORCE_EAGER="${ENFORCE_EAGER:-false}"   # true = tắt CUDA graph (tiết kiệm VRAM, hợp GPU nhỏ)
  LANGUAGE_MODEL_ONLY="${LANGUAGE_MODEL_ONLY:-false}"   # true = bỏ phần xử lý ảnh/video của model đa phương thức
  MAX_NUM_SEQS="${MAX_NUM_SEQS:-}"                       # trống = mặc định của vLLM
  MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-}"

  export PATH="$HOME/.local/bin:$PATH"   # nơi installer của uv đặt binary
  export HF_HOME="${HF_HOME:-$INSTALL_DIR/hf-cache}"
  [[ -n "$HF_TOKEN" ]] && export HF_TOKEN
  [[ -n "$HF_ENDPOINT" ]] && export HF_ENDPOINT
  export TOOLKIT_PROFILE="$PROFILE"
  export INSTALL_DIR VENV_DIR MODEL_DIR MODEL_ID SERVED_MODEL_NAME PROFILE USER_PROFILE_DIR \
         MAX_MODEL_LEN GPU_MEMORY_UTILIZATION ENABLE_THINKING ENFORCE_EAGER \
         LANGUAGE_MODEL_ONLY MAX_NUM_SEQS MAX_NUM_BATCHED_TOKENS HOST PORT API_KEY
}

model_downloaded() { [[ -f "$MODEL_DIR/.download_complete" ]]; }

require_venv() {
  [[ -x "$VENV_DIR/bin/python" ]] || die "Chưa có venv tại $VENV_DIR. Chạy trước: bash install.sh"
}

require_model() {
  model_downloaded || die "Chưa tải model $MODEL_ID vào $MODEL_DIR. Chạy: bash install.sh --profile $PROFILE"
}
