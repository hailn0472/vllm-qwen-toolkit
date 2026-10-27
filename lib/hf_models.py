#!/usr/bin/env python3
"""
Liệt kê model Qwen trên Hugging Face để chọn, rồi tạo profile cho model được chọn.
Được gọi từ menu.sh (mục 5). Chỉ dùng thư viện chuẩn của Python.

Kết quả: ghi tên profile đã chọn vào file --out. Thoát mã 1 nếu người dùng huỷ hoặc lỗi.
"""

import argparse
import json
import math
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PIPELINES = {"text-generation", "image-text-to-text"}   # bỏ embedding, TTS, ASR, ảnh...
SKIP_TAGS = {"gguf", "mlx", "onnx"}                     # định dạng vLLM không chạy trực tiếp
DTYPE_BYTES = {"F64": 8, "F32": 4, "I32": 4, "U32": 4, "I64": 8, "BF16": 2, "F16": 2,
               "I16": 2, "F8_E4M3": 1, "F8_E5M2": 1, "I8": 1, "U8": 1, "BOOL": 1}
EXPAND = ["downloads", "safetensors", "pipeline_tag", "gated", "createdAt", "trendingScore", "tags"]
SORTS = {"d": ("downloads", "lượt tải"), "t": ("trendingScore", "xu hướng"), "m": ("createdAt", "mới nhất")}
PAGE_SIZE = 20
DEFAULT_MAX_MODEL_LEN = 32768


# -----------------------------------------------------------------------------
# Hugging Face API
# -----------------------------------------------------------------------------
def hf_base() -> str:
    return (os.environ.get("HF_ENDPOINT") or "https://huggingface.co").rstrip("/")


def hf_get(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": "vllm-qwen-toolkit"})
    if os.environ.get("HF_TOKEN"):
        req.add_header("Authorization", f"Bearer {os.environ['HF_TOKEN']}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def expand_query() -> list[tuple[str, str]]:
    return [("expand[]", e) for e in EXPAND]


def fetch_author_models(author: str) -> list[dict]:
    query = urllib.parse.urlencode([("author", author), ("limit", "1000")] + expand_query())
    models = hf_get(f"{hf_base()}/api/models?{query}")
    return [m for m in models if usable(m)]


def fetch_model(repo_id: str) -> dict:
    query = urllib.parse.urlencode(expand_query())
    return hf_get(f"{hf_base()}/api/models/{repo_id}?{query}")


def fetch_max_context(repo_id: str) -> int | None:
    """Đọc max_position_embeddings từ config.json (model đa phương thức để trong text_config)."""
    try:
        cfg = hf_get(f"{hf_base()}/{repo_id}/resolve/main/config.json")
    except (urllib.error.URLError, ValueError, TimeoutError):
        return None
    for section in (cfg, cfg.get("text_config") or {}, cfg.get("llm_config") or {}):
        if isinstance(section.get("max_position_embeddings"), int):
            return section["max_position_embeddings"]
    return None


def usable(m: dict) -> bool:
    if m.get("pipeline_tag") not in PIPELINES:
        return False
    tags = {t.lower() for t in m.get("tags", [])}
    name = m["id"].lower()
    return not (tags & SKIP_TAGS or "gguf" in name or "mlx" in name)


# -----------------------------------------------------------------------------
# Thông tin hiển thị
# -----------------------------------------------------------------------------
def size_gb(m: dict) -> float | None:
    params = (m.get("safetensors") or {}).get("parameters") or {}
    if not params:
        return None
    return sum(n * DTYPE_BYTES.get(dtype, 2) for dtype, n in params.items()) / 1024**3


def fmt_params(m: dict) -> str:
    total = (m.get("safetensors") or {}).get("total")
    if not total:
        return "?"
    return f"{total / 1e9:.1f}B" if total < 1e11 else f"{total / 1e9:.0f}B"


def fmt_downloads(n: int) -> str:
    if n >= 1_000_000:
        return f"{n / 1e6:.1f}M"
    if n >= 1_000:
        return f"{n / 1e3:.0f}K"
    return str(n)


def model_dir(models_dir: Path, repo_id: str) -> Path:
    # Cùng quy tắc với default_model_dir() trong lib/common.sh
    org, name = repo_id.split("/", 1)
    return models_dir / (name if org.lower() == "qwen" else repo_id.replace("/", "--"))


def fits(m: dict, vram_gb: float) -> str:
    size = size_gb(m)
    if size is None or vram_gb <= 0:
        return "?"
    # weights + ~10% overhead + tối thiểu vài GB KV cache, trong 90% VRAM
    return "✓" if size * 1.1 + 4 <= vram_gb * 0.9 else "✗"


def print_table(items: list[dict], page: int, args, sort_key: str, keyword: str) -> None:
    pages = max(1, math.ceil(len(items) / PAGE_SIZE))
    start = page * PAGE_SIZE
    print()
    print(f"Model {args.author} trên Hugging Face — {len(items)} model"
          f"{f' khớp “{keyword}”' if keyword else ''} | sắp xếp: {SORTS[sort_key][1]} | "
          f"trang {page + 1}/{pages} | GPU: {args.vram_gb:.0f} GB")
    print(f"{'#':>4}  {'Model':<46} {'Tham số':>8} {'~GB':>6} {'Tải/30n':>8}  {'Ngày tạo':<10}  "
          f"{'Vừa GPU':<7} Ghi chú")
    print("-" * 112)
    for i, m in enumerate(items[start:start + PAGE_SIZE], start=start + 1):
        size = size_gb(m)
        notes = []
        if m.get("gated"):
            notes.append("cần HF_TOKEN")
        if m.get("pipeline_tag") == "image-text-to-text":
            notes.append("đa phương thức")
        if (model_dir(args.models_dir, m["id"]) / ".download_complete").exists():
            notes.append("ĐÃ TẢI")
        print(f"{i:>4}  {m['id'][:46]:<46} {fmt_params(m):>8} "
              f"{(f'{size:.1f}' if size else '?'):>6} {fmt_downloads(m.get('downloads', 0)):>8}  "
              f"{(m.get('createdAt') or '')[:10]:<10}  {fits(m, args.vram_gb):^7} {', '.join(notes)}")
    print("-" * 112)
    print("Nhập SỐ để chọn | n/p: trang sau/trước | s <từ khoá>: lọc (vd: s 3.8 27b), s: bỏ lọc")
    print("d/t/m: sắp xếp theo lượt tải/xu hướng/mới nhất | <org>/<repo>: nhập trực tiếp | q: quay lại")


# -----------------------------------------------------------------------------
# Chọn model
# -----------------------------------------------------------------------------
def pick(all_models: list[dict], args) -> dict | None:
    sort_key, keyword, page = "d", "", 0
    while True:
        terms = keyword.lower().split()
        items = [m for m in all_models if all(t in m["id"].lower() for t in terms)]
        field = SORTS[sort_key][0]
        empty = "" if field == "createdAt" else 0
        items.sort(key=lambda m: m.get(field) or empty, reverse=True)
        page = max(0, min(page, math.ceil(len(items) / PAGE_SIZE) - 1))
        print_table(items, page, args, sort_key, keyword)

        cmd = input("Chọn: ").strip()
        low = cmd.lower()
        if low in ("q", "0", ""):
            return None
        if low == "n":
            page += 1
        elif low == "p":
            page -= 1
        elif low in SORTS:
            sort_key, page = low, 0
        elif low == "s" or low.startswith("s "):
            keyword, page = cmd[2:].strip(), 0
        elif cmd.isdigit():
            idx = int(cmd) - 1
            if 0 <= idx < len(items):
                return items[idx]
            print(f"Không có số {cmd}")
        elif "/" in cmd:
            try:
                return fetch_model(cmd)
            except urllib.error.HTTPError as exc:
                print(f"Không lấy được {cmd}: HTTP {exc.code} (sai tên, hoặc repo private/gated cần HF_TOKEN)")
            except urllib.error.URLError as exc:
                print(f"Lỗi mạng: {exc.reason}")
        else:
            print(f"Lệnh không hợp lệ: {cmd}")


def free_disk_gb(path: Path) -> float:
    while not path.exists():
        path = path.parent
    return shutil.disk_usage(path).free / 1024**3


def confirm(m: dict, args) -> bool:
    size = size_gb(m)
    target = model_dir(args.models_dir, m["id"])
    print()
    print(f"  Model       : {m['id']}  (https://huggingface.co/{m['id']})")
    print(f"  Loại        : {m.get('pipeline_tag') or '?'} | tham số: {fmt_params(m)} | "
          f"dung lượng ~{f'{size:.1f}' if size else '?'} GB")
    print(f"  Lưu tại     : {target}")
    print(f"  Ổ đĩa trống : {free_disk_gb(args.models_dir):.0f} GB")
    if m.get("gated") and not os.environ.get("HF_TOKEN"):
        print("  [WARN] Model gated: cần chấp nhận license trên trang model và đặt HF_TOKEN")
    if fits(m, args.vram_gb) == "✗":
        print(f"  [WARN] Model có thể KHÔNG vừa {args.vram_gb:.0f} GB VRAM của 1 GPU")
    if size and size + 5 > free_disk_gb(args.models_dir):
        print("  [WARN] Ổ đĩa có thể không đủ chỗ")
    if not (m.get("safetensors") or {}).get("parameters"):
        print("  [WARN] Repo không có thông tin safetensors — có thể không chạy được với vLLM")
    ans = input("Tạo profile và tải model này? [Y/n] ").strip().lower()
    return ans in ("", "y", "yes")


# -----------------------------------------------------------------------------
# Tạo profile
# -----------------------------------------------------------------------------
def existing_profile(repo_id: str, dirs: list[Path]) -> str | None:
    pattern = re.compile(rf'^MODEL_ID="{re.escape(repo_id)}"', re.M | re.I)
    for d in dirs:
        for f in sorted(d.glob("*.env")) if d.is_dir() else []:
            if pattern.search(f.read_text(encoding="utf-8")):
                return f.stem
    return None


def needs_reasoning_parser(name: str) -> bool:
    # Qwen3.5+ và Qwen3 bản hybrid/Thinking sinh <think>...</think>; Instruct-2507, Coder thì không
    if re.search(r"qwen3\.\d", name, re.I):
        return True
    if re.search(r"instruct|coder|embedding|reranker", name, re.I):
        return False
    return bool(re.match(r"qwen3-[\d.]+b", name, re.I)) or "thinking" in name.lower()


def make_profile(m: dict, args) -> str:
    repo_id = m["id"]
    found = existing_profile(repo_id, [args.builtin_dir, args.user_dir])
    if found:
        print(f"Đã có profile '{found}' cho {repo_id} — dùng lại")
        return found

    org, name = repo_id.split("/", 1)
    slug = (name if org.lower() == "qwen" else f"{org}--{name}").lower()
    slug = re.sub(r"[^a-z0-9._-]+", "-", slug)

    size = size_gb(m)
    max_ctx = fetch_max_context(repo_id)
    max_model_len = min(max_ctx, DEFAULT_MAX_MODEL_LEN) if max_ctx else DEFAULT_MAX_MODEL_LEN
    min_vram = math.ceil(size * 1.1 + 4) if size else 0
    min_disk = math.ceil(size + 5) if size else 20
    gpu_util = "0.90" if size and size > 30 else "0.85"
    serve_args = "--reasoning-parser qwen3" if needs_reasoning_parser(name) else ""

    args.user_dir.mkdir(parents=True, exist_ok=True)
    path = args.user_dir / f"{slug}.env"
    path.write_text(
        f"# Profile tạo tự động từ menu (mục 5) lúc {time.strftime('%Y-%m-%d %H:%M')}\n"
        f"# https://huggingface.co/{repo_id} — context tối đa của model: {max_ctx or 'không rõ'}\n"
        f"# Có thể sửa tay các giá trị dưới đây.\n"
        f'MODEL_ID="{repo_id}"\n'
        f'SERVED_MODEL_NAME="${{SERVED_MODEL_NAME:-{slug}}}"\n\n'
        f'MAX_MODEL_LEN="${{MAX_MODEL_LEN:-{max_model_len}}}"\n'
        f'GPU_MEMORY_UTILIZATION="${{GPU_MEMORY_UTILIZATION:-{gpu_util}}}"\n'
        f'ENABLE_THINKING="${{ENABLE_THINKING:-false}}"\n\n'
        f"MIN_VRAM_GB={min_vram}\n"
        f"MIN_DISK_GB={min_disk}\n\n"
        f'EXTRA_SERVE_ARGS="${{EXTRA_SERVE_ARGS:-{serve_args}}}"\n',
        encoding="utf-8",
    )
    print(f"Đã tạo profile '{slug}': {path}")
    return slug


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--author", default="Qwen")
    p.add_argument("--vram-gb", type=float, default=0)
    p.add_argument("--models-dir", type=Path, required=True)
    p.add_argument("--builtin-dir", type=Path, required=True)
    p.add_argument("--user-dir", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    args = p.parse_args()

    print(f"Đang lấy danh sách model {args.author} từ {hf_base()} ...")
    try:
        models = fetch_author_models(args.author)
    except (urllib.error.URLError, TimeoutError) as exc:
        print(f"Không lấy được danh sách model: {exc}")
        return 1

    try:
        while True:
            chosen = pick(models, args)
            if chosen is None:
                return 1
            if confirm(chosen, args):
                break
        args.out.write_text(make_profile(chosen, args), encoding="utf-8")
        return 0
    except (KeyboardInterrupt, EOFError):
        print()
        return 1


if __name__ == "__main__":
    sys.exit(main())
