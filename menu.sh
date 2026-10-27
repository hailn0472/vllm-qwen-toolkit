#!/usr/bin/env bash
# Menu tương tác: chọn từng bước cài đặt / chạy model.
# Cách dùng: bash menu.sh [--profile <tên>]
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

[[ -t 0 && -t 1 ]] || die "menu.sh cần chạy trong terminal. Để cài không tương tác dùng: bash install.sh -y"

parse_common_args "$@"

# Giá trị người dùng tự đặt qua env cho các biến của profile -> giữ lại khi đổi profile
PROFILE_VARS=(MODEL_ID SERVED_MODEL_NAME MAX_MODEL_LEN GPU_MEMORY_UTILIZATION ENABLE_THINKING ENFORCE_EAGER LANGUAGE_MODEL_ONLY MAX_NUM_SEQS MAX_NUM_BATCHED_TOKENS EXTRA_SERVE_ARGS MODEL_DIR)
declare -A USER_OVERRIDES=()
for v in "${PROFILE_VARS[@]}"; do
  [[ -v $v ]] && USER_OVERRIDES[$v]="${!v}"
done

load_config
export TOOLKIT_COLOR=1   # script con vẫn có màu khi output đi qua tee
export PYTHONUNBUFFERED=1

source "$TOOLKIT_DIR/lib/server.sh"
source "$TOOLKIT_DIR/lib/librechat.sh"
MENU_LOG="$LOG_DIR/menu-$(date +%Y%m%d).log"

# Ctrl+C chỉ dừng lệnh đang chạy (tiến trình con), không thoát menu
trap 'echo' INT

# =============================================================================
# Tiện ích
# =============================================================================
pause() { echo; read -r -p "Nhấn Enter để quay lại menu..." _ || true; }

# ask <biến> <câu hỏi> [mặc định]
ask() {
  local ans
  read -r -p "$2${3:+ [$3]}: " ans || true
  printf -v "$1" '%s' "${ans:-${3:-}}"
}

# ask_yn <câu hỏi> [y|n mặc định] -> 0 nếu đồng ý
ask_yn() {
  local def="${2:-n}" hint="[y/N]" ans
  [[ "$def" == y ]] && hint="[Y/n]"
  read -r -p "$1 $hint " ans || true
  ans="${ans:-$def}"
  [[ "$ans" =~ ^[Yy]$ ]]
}

# Chạy một bước cài đặt, ghi log vào $MENU_LOG
run_step() {
  local script="$1"; shift
  mkdir -p "$LOG_DIR"
  echo "##### $(date '+%F %T') $script $*" >> "$MENU_LOG"
  bash "$TOOLKIT_DIR/$script" "$@" 2>&1 | tee -a "$MENU_LOG"
  local rc=${PIPESTATUS[0]}
  echo
  if (( rc == 0 )); then log_ok "Xong"; else log_fail "Bước lỗi (mã $rc). Log: $MENU_LOG"; fi
  return "$rc"
}

vllm_version() {
  local d
  for d in "$VENV_DIR"/lib/python*/site-packages/vllm-*.dist-info; do
    if [[ -d "$d" ]]; then d="${d##*/vllm-}"; echo "${d%.dist-info}"; return; fi
  done
}

vllm_pkg_dir() {
  local d
  for d in "$VENV_DIR"/lib/python*/site-packages/vllm; do
    [[ -d "$d" ]] && { echo "$d"; return; }
  done
}

dir_size() { [[ -e "$1" ]] && du -sh "$1" 2>/dev/null | cut -f1; }

ok_mark()  { echo "${C_GREEN}✓${C_RESET} $*"; }
bad_mark() { echo "${C_RED}✗${C_RESET} $*"; }

server_status() {
  local pid
  if pid="$(server_pid)"; then
    if server_ready; then ok_mark "đang chạy :$PORT (PID $pid)"; else echo "${C_YELLOW}…${C_RESET} đang khởi động (PID $pid)"; fi
  elif server_ready; then
    ok_mark "đang chạy :$PORT (bật ngoài menu)"
  else
    echo "tắt"
  fi
}

need_venv()  { [[ -x "$VENV_DIR/bin/vllm" ]] || { log_fail "Chưa cài vLLM — chọn mục 4 trước"; return 1; }; }
need_model() { model_downloaded || { log_fail "Chưa tải model $MODEL_ID — chọn mục 5 trước"; return 1; }; }

# Server chạy nền chiếm VRAM -> hỏi dừng trước khi chạy thứ khác dùng GPU
ensure_gpu_free() {
  server_pid >/dev/null || return 0
  log_warn "API server đang chạy nền và chiếm VRAM."
  if ask_yn "Dừng server trước khi tiếp tục?" y; then stop_server; fi
}

# =============================================================================
# Server chạy nền
# =============================================================================
start_server() {
  need_venv && need_model || return 1
  if server_pid >/dev/null || server_ready; then
    log_info "Server đã chạy rồi: $(server_status)"
    return 0
  fi
  local extra_str extra=()
  log_info "Tham số mặc định: --max-model-len $MAX_MODEL_LEN --gpu-memory-utilization $GPU_MEMORY_UTILIZATION $EXTRA_SERVE_ARGS"
  [[ "$ENFORCE_EAGER" == true ]] || log_info "Gợi ý thêm: --enforce-eager (nếu treo khi capture CUDA graph)"
  ask extra_str "Thêm tham số cho vllm serve (Enter để bỏ qua)"
  read -r -a extra <<< "$extra_str"
  start_server_bg "${extra[@]}"
}

librechat_status() {
  if ! librechat_installed; then
    bad_mark "chưa cài"
  elif librechat_ready; then
    ok_mark "đang chạy → $LIBRECHAT_URL"
  else
    echo "tắt"
  fi
}

action_librechat_install() {
  run_step scripts/70_install_docker.sh && run_step scripts/80_setup_librechat.sh
}

# Bật cả vLLM lẫn LibreChat
action_librechat_start() {
  librechat_installed || { log_fail "Chưa cài LibreChat — chọn mục 16 trước"; return 1; }
  if ! server_ready; then
    start_server || return 1
    server_ready || { log_warn "vLLM chưa sẵn sàng — LibreChat bật nhưng chưa có model để chat"; }
  fi
  start_librechat
  log_info "Lần đầu: mở $LIBRECHAT_URL, bấm Sign up tạo tài khoản (tài khoản đầu tiên là admin)"
}

action_librechat_log() {
  librechat_installed || { log_info "Chưa cài LibreChat"; return 0; }
  log_info "Đang theo dõi log LibreChat — Ctrl+C để quay lại"
  lc_compose logs -f --tail 50 api
}

# =============================================================================
# Các mục menu
# =============================================================================
action_setup_venv() {
  command -v uv >/dev/null 2>&1 || { log_fail "Chưa có uv — chọn mục 3 trước"; return 1; }
  local args=()
  if [[ -x "$VENV_DIR/bin/python" ]]; then
    log_info "venv đã có tại $VENV_DIR (vLLM: $(vllm_version))"
    ask_yn "Xoá venv cũ và cài lại từ đầu? (chọn N để chỉ cập nhật/cài bổ sung)" n && args=(--recreate)
  fi
  ensure_gpu_free
  run_step scripts/40_setup_venv.sh "${args[@]}"
}

action_download() {
  need_venv || return 1
  local choice status="chưa tải"
  model_downloaded && status="đã tải"
  echo "  1) Tải model của profile hiện tại: $MODEL_ID ($status)"
  echo "  2) Chọn model Qwen khác từ danh sách trên Hugging Face"
  echo "  0) Quay lại"
  ask choice "Chọn" 1
  case "$choice" in
    1) download_current_model ;;
    2) pick_hf_model && download_current_model ;;
  esac
}

download_current_model() {
  local args=()
  if model_downloaded; then
    log_info "Model đã có tại $MODEL_DIR ($(dir_size "$MODEL_DIR"))"
    ask_yn "Kiểm tra / tải lại model?" n || return 0
    args=(--force)
  fi
  log_info "Weights sẽ lưu tại: $MODEL_DIR"
  run_step scripts/50_download_model.sh "${args[@]}"
}

# Hiện danh sách model Qwen trên HF, tạo profile cho model được chọn rồi chuyển sang profile đó
pick_hf_model() {
  local out vram_mb new
  vram_mb="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | sort -n | tail -n1)"
  out="$(mktemp)"
  "$VENV_DIR/bin/python" "$TOOLKIT_DIR/lib/hf_models.py" \
    --author Qwen \
    --vram-gb "$(( ${vram_mb:-0} / 1024 ))" \
    --models-dir "$INSTALL_DIR/models" \
    --builtin-dir "$TOOLKIT_DIR/profiles" \
    --user-dir "$USER_PROFILE_DIR" \
    --out "$out"
  local rc=$?
  new="$(cat "$out" 2>/dev/null)"
  rm -f "$out"
  (( rc == 0 )) && [[ -n "$new" ]] || { log_info "Không chọn model nào"; return 1; }
  echo
  switch_profile "$new"
}

# Đổi profile ngay trong menu (nạp lại cấu hình, lưu làm profile mặc định)
switch_profile() {
  unset "${PROFILE_VARS[@]}"
  for v in "${!USER_OVERRIDES[@]}"; do export "$v=${USER_OVERRIDES[$v]}"; done
  export TOOLKIT_PROFILE="$1"
  load_config
  mkdir -p "$INSTALL_DIR"
  echo "$PROFILE" > "$INSTALL_DIR/.active_profile"
  log_ok "Đang dùng profile $PROFILE ($MODEL_ID)"
  log_info "Weights: $MODEL_DIR"
  server_pid >/dev/null && log_warn "Server nền vẫn đang chạy model cũ — dừng (10) rồi bật lại (9)"
  return 0
}

action_test() {
  need_venv && need_model || return 1
  ensure_gpu_free
  local prompt max_tokens args=()
  echo "Chạy examples/offline_inference.py — mỗi lần chạy sẽ load lại model (khoảng 1–3 phút)."
  ask prompt "Prompt (Enter = 3 prompt mẫu)"
  ask max_tokens "Số token tối đa" 512
  [[ -n "$prompt" ]] && args+=(--prompt "$prompt")
  args+=(--max-tokens "$max_tokens")
  if ask_yn "Bật chế độ thinking?" n; then args+=(--thinking); else args+=(--no-thinking); fi
  local eager_def=n
  [[ "$ENFORCE_EAGER" == true ]] && eager_def=y
  if ask_yn "Tắt CUDA graph (--enforce-eager, load nhanh hơn, tốn ít VRAM hơn)?" "$eager_def"; then
    args+=(--enforce-eager)
  else
    args+=(--no-enforce-eager)
  fi
  echo
  bash "$TOOLKIT_DIR/test.sh" "${args[@]}"
}

action_chat() {
  need_venv || return 1
  if ! server_ready; then
    if server_pid >/dev/null; then
      log_warn "Server đang khởi động, chờ thêm hoặc xem log ở mục 11"
      return 1
    fi
    ask_yn "Server chưa chạy. Bật server ngay?" y || return 0
    start_server || return 1
    server_ready || return 1
  fi
  echo
  bash "$TOOLKIT_DIR/chat.sh" --interactive
}

action_server_log() {
  [[ -f "$SERVER_LOG" ]] || { log_info "Chưa có log server"; return 0; }
  log_info "Đang theo dõi $SERVER_LOG — Ctrl+C để quay lại"
  tail -n 50 -f "$SERVER_LOG"
}

action_profile() {
  local names=() f i=1 choice mark status id dir src
  echo "Chọn model (* = đang dùng). Thêm model khác: mục 5 → 2"
  while read -r f; do
    names+=("$(basename "$f" .env)")
    id="$(grep -m1 '^MODEL_ID=' "$f" | cut -d'"' -f2)"
    dir="$(default_model_dir "$id")"
    mark=" "; [[ "${names[-1]}" == "$PROFILE" ]] && mark="*"
    status="chưa tải"; [[ -f "$dir/.download_complete" ]] && status="đã tải $(dir_size "$dir")"
    src=""; [[ "$f" == "$USER_PROFILE_DIR"/* ]] && src="[tự tạo]"
    printf ' %s %2d) %-28s %-36s %-14s %s\n' "$mark" "$i" "${names[-1]}" "$id" "$status" "$src"
    i=$((i + 1))
  done < <(profile_files)
  echo "    0) Quay lại"
  ask choice "Chọn"
  [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#names[@]} )) || return 0

  switch_profile "${names[$((choice - 1))]}"
  model_downloaded || log_info "Model này chưa tải — chọn mục 5 để tải"
}

action_info() {
  log_step "Cấu hình hiện tại"
  # printf căn lề theo byte nên lệch với chữ có dấu -> tự căn theo số ký tự
  kv() {
    local LC_ALL=C.UTF-8   # để ${#} đếm ký tự, không đếm byte (kể cả khi SSH với LANG=C)
    while (( $# >= 2 )); do
      printf '  %s%*s %s\n' "$1" $((24 - ${#1})) "" "${2:-(chưa có)}"
      shift 2
    done
  }
  kv \
    "Profile" "$PROFILE" \
    "Model" "$MODEL_ID" \
    "Python venv" "$PYTHON_VERSION" \
    "vLLM" "${VLLM_VERSION:-mới nhất} (đã cài: $(vllm_version))" \
    "Torch backend" "$TORCH_BACKEND" \
    "MAX_MODEL_LEN" "$MAX_MODEL_LEN" \
    "GPU_MEMORY_UTILIZATION" "$GPU_MEMORY_UTILIZATION" \
    "ENABLE_THINKING" "$ENABLE_THINKING" \
    "ENFORCE_EAGER" "$ENFORCE_EAGER" \
    "Server" "$HOST:$PORT (tên model API: $SERVED_MODEL_NAME)" \
    "Tham số serve thêm" "${EXTRA_SERVE_ARGS:-(không)}" \
    "API_KEY" "$([[ -n "$API_KEY" ]] && echo "đã đặt" || echo "(không)")" \
    "HF_TOKEN" "$([[ -n "$HF_TOKEN" ]] && echo "đã đặt" || echo "(không)")" \
    "LibreChat" "$LIBRECHAT_IMAGE → $LIBRECHAT_URL"
  echo "  Sửa: config.env, $(short_path "$(find_profile_file "$PROFILE")") hoặc tạo config.local.env"

  log_step "Thư mục"
  local uv_bin=""
  command -v uv >/dev/null 2>&1 && uv_bin="$(command -v uv)"
  kv \
    "Toolkit" "$TOOLKIT_DIR" \
    "Thư mục cài" "$INSTALL_DIR" \
    "uv (chương trình)" "${uv_bin:-(chưa cài)}" \
    "uv cache" "$([[ -n "$uv_bin" ]] && uv cache dir 2>/dev/null)" \
    "uv Python" "$([[ -n "$uv_bin" ]] && uv python dir 2>/dev/null)" \
    "venv" "$VENV_DIR" \
    "vLLM (package)" "$(vllm_pkg_dir)" \
    "vllm (lệnh)" "$([[ -x "$VENV_DIR/bin/vllm" ]] && echo "$VENV_DIR/bin/vllm")" \
    "Weights model hiện tại" "$MODEL_DIR" \
    "Tất cả model" "$INSTALL_DIR/models" \
    "Hugging Face cache" "$HF_HOME" \
    "Profile tự tạo" "$USER_PROFILE_DIR" \
    "LibreChat (dữ liệu)" "$LIBRECHAT_DIR" \
    "Log" "$LOG_DIR"

  log_step "GPU"
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=index,name,driver_version,memory.used,memory.total,utilization.gpu,temperature.gpu \
      --format=csv,noheader 2>/dev/null | sed 's/^/  /'
  else
    echo "  Không có nvidia-smi"
  fi

  log_step "Dung lượng"
  local d
  for d in "$VENV_DIR" "$INSTALL_DIR"/models/*; do
    [[ -e "$d" ]] && printf '  %-8s %s\n' "$(dir_size "$d")" "$(short_path "$d")"
  done
  df -h "$INSTALL_DIR" 2>/dev/null | awk 'NR==2{print "  Ổ đĩa còn trống: " $4}'
  # uv cache có thể rất lớn/nhiều file nên không đo (du chậm); dọn bằng: uv cache clean
  echo "  (uv cache không tính ở trên — xem: du -sh \"\$(uv cache dir)\", dọn: uv cache clean)"
}

action_uninstall() {
  local choice
  echo "  1) Chỉ xoá venv (giữ model)"
  echo "  2) Xoá toàn bộ $INSTALL_DIR (venv + model + log)"
  echo "  0) Quay lại"
  ask choice "Chọn"
  case "$choice" in
    1) stop_server; bash "$TOOLKIT_DIR/uninstall.sh" ;;
    2) bash "$TOOLKIT_DIR/uninstall.sh" --all ;;
  esac
}

# =============================================================================
# Vòng lặp menu
# =============================================================================
show_menu() {
  local uv_s vllm_s model_s v
  if command -v uv >/dev/null 2>&1; then
    uv_s="$(ok_mark "$(uv --version | awk '{print $2}')")  → $(short_path "$(command -v uv)")"
  else
    uv_s="$(bad_mark "chưa cài")  → sẽ cài vào ~/.local/bin/uv"
  fi
  v="$(vllm_version)"
  if [[ -n "$v" ]]; then
    vllm_s="$(ok_mark "$v")  → $(short_path "$VENV_DIR")"
  else
    vllm_s="$(bad_mark "chưa cài")  → sẽ cài vào $(short_path "$VENV_DIR")"
  fi
  if model_downloaded; then
    model_s="$(ok_mark "đã tải $(dir_size "$MODEL_DIR")")  → $(short_path "$MODEL_DIR")"
  else
    model_s="$(bad_mark "chưa tải")  → sẽ lưu tại $(short_path "$MODEL_DIR")"
  fi

  clear
  cat <<EOF
${C_BOLD}==================================================================${C_RESET}
${C_BOLD}  vLLM + Qwen Toolkit${C_RESET}
${C_BOLD}==================================================================${C_RESET}
  Profile     : ${C_BOLD}$PROFILE${C_RESET} ($MODEL_ID)
  Thư mục cài : $(short_path "$INSTALL_DIR")
  uv          : $uv_s
  vLLM        : $vllm_s
  Weights     : $model_s
  vLLM server : $(server_status)
  LibreChat   : $(librechat_status)
------------------------------------------------------------------
 ${C_BOLD}CÀI ĐẶT${C_RESET}
   1) Kiểm tra yêu cầu hệ thống
   2) Cài gói hệ thống (curl, gcc...)
   3) Cài / cập nhật uv
   4) Tạo venv + cài vLLM
   5) Tải model (chọn từ danh sách Qwen trên Hugging Face)
   6) Chạy smoke test
   7) Cài tự động toàn bộ (1 → 6 + 16)
 ${C_BOLD}SỬ DỤNG${C_RESET}
   8) Chạy thử offline (code mẫu Python)
   9) Bật API server (chạy nền)
  10) Dừng API server
  11) Xem log server
  12) Chat với model qua API server
 ${C_BOLD}KHÁC${C_RESET}
  13) Đổi model (profile)
  14) Xem cấu hình & GPU
  15) Gỡ cài đặt
 ${C_BOLD}WEB UI (LIBRECHAT)${C_RESET}
  16) Cài Docker + LibreChat
  17) Bật vLLM + LibreChat
  18) Dừng LibreChat
  19) Xem log LibreChat
   0) Thoát
------------------------------------------------------------------
EOF
}

while true; do
  show_menu
  read -r -p "Chọn: " choice || exit 0
  echo
  case "$choice" in
    1)  run_step scripts/20_check_requirements.sh ;;
    2)  run_step scripts/10_system_deps.sh ;;
    3)  run_step scripts/30_install_uv.sh ;;
    4)  action_setup_venv ;;
    5)  action_download ;;
    6)  need_model && { ensure_gpu_free; run_step scripts/60_smoke_test.sh; } ;;
    7)  ensure_gpu_free; bash "$TOOLKIT_DIR/install.sh" ;;
    8)  action_test ;;
    9)  start_server ;;
    10) stop_server ;;
    11) action_server_log ;;
    12) action_chat ;;
    13) action_profile ;;
    14) action_info ;;
    15) action_uninstall ;;
    16) action_librechat_install ;;
    17) action_librechat_start ;;
    18) stop_librechat ;;
    19) action_librechat_log ;;
    0|q|Q)
      if pid="$(server_pid)"; then
        log_info "API server vẫn chạy nền (PID $pid). Dừng sau bằng menu mục 10 hoặc: kill -- -$pid"
      fi
      librechat_ready && log_info "LibreChat vẫn chạy ($LIBRECHAT_URL). Dừng: mục 18 hoặc bash stop.sh"
      exit 0 ;;
    "") continue ;;
    *)  log_warn "Lựa chọn không hợp lệ: $choice" ;;
  esac
  pause
done
