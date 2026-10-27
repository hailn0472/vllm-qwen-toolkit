#!/usr/bin/env python3
"""
Ví dụ chạy vLLM offline (không cần server) với model đã tải về máy.

Chạy qua toolkit (tự nạp cấu hình profile):
    bash test.sh
    bash test.sh --prompt "Viết hàm Python tính số Fibonacci" --max-tokens 1024
    bash test.sh --thinking

Hoặc chạy trực tiếp bằng venv:
    ~/vllm-qwen/venv/bin/python examples/offline_inference.py --model ~/vllm-qwen/models/Qwen3.5-4B
"""

import argparse
import os
import sys
import time

DEFAULT_PROMPTS = [
    "Xin chào! Hãy giới thiệu ngắn gọn về bản thân bằng tiếng Việt.",
    "Giải thích vLLM là gì và PagedAttention giúp tăng tốc thế nào, trong 3 câu.",
    "Viết hàm Python kiểm tra một số có phải số nguyên tố không.",
]


def env_bool(name: str, default: bool = False) -> bool:
    return os.environ.get(name, str(default)).strip().lower() in ("1", "true", "yes", "on")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Chạy thử vLLM offline với model local")
    p.add_argument("--model", default=os.environ.get("MODEL_DIR"),
                   help="Thư mục model local (mặc định: $MODEL_DIR)")
    p.add_argument("--prompt", action="append",
                   help="Prompt cần hỏi, có thể lặp lại nhiều lần để chạy batch")
    p.add_argument("--max-tokens", type=int, default=512)
    p.add_argument("--max-model-len", type=int, default=int(os.environ.get("MAX_MODEL_LEN", 8192)))
    p.add_argument("--gpu-memory-utilization", type=float,
                   default=float(os.environ.get("GPU_MEMORY_UTILIZATION", 0.85)))
    p.add_argument("--tensor-parallel-size", type=int, default=1)
    p.add_argument("--thinking", action=argparse.BooleanOptionalAction,
                   default=env_bool("ENABLE_THINKING"),
                   help="Bật chế độ suy nghĩ (thinking) của Qwen")
    p.add_argument("--enforce-eager", action=argparse.BooleanOptionalAction,
                   default=env_bool("ENFORCE_EAGER"),
                   help="Tắt CUDA graph (khởi động nhanh hơn, dùng khi gặp lỗi/treo lúc capture graph)")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    if not args.model or not os.path.isdir(args.model):
        print(f"Không tìm thấy thư mục model: {args.model!r}. Dùng --model hoặc chạy qua test.sh")
        return 1

    # Import sau khi parse để --help chạy nhanh
    from vllm import LLM, SamplingParams

    # Thiết lập tiết kiệm VRAM lấy từ profile (để trống = mặc định của vLLM)
    engine_kwargs = {}
    if env_bool("LANGUAGE_MODEL_ONLY"):
        engine_kwargs["language_model_only"] = True
    for env_name, key in (("MAX_NUM_SEQS", "max_num_seqs"),
                          ("MAX_NUM_BATCHED_TOKENS", "max_num_batched_tokens")):
        if os.environ.get(env_name):
            engine_kwargs[key] = int(os.environ[env_name])

    llm = LLM(
        model=args.model,
        max_model_len=args.max_model_len,
        gpu_memory_utilization=args.gpu_memory_utilization,
        tensor_parallel_size=args.tensor_parallel_size,
        enforce_eager=args.enforce_eager,
        **engine_kwargs,
    )

    # Tham số sampling khuyến nghị của Qwen cho từng chế độ
    if args.thinking:
        sampling = SamplingParams(temperature=0.6, top_p=0.95, top_k=20, max_tokens=args.max_tokens)
    else:
        sampling = SamplingParams(temperature=0.7, top_p=0.8, top_k=20, max_tokens=args.max_tokens)

    prompts = args.prompt or DEFAULT_PROMPTS
    conversations = [[{"role": "user", "content": p}] for p in prompts]

    start = time.perf_counter()
    outputs = llm.chat(
        conversations,
        sampling,
        chat_template_kwargs={"enable_thinking": args.thinking},
    )
    elapsed = time.perf_counter() - start

    generated = 0
    for prompt, out in zip(prompts, outputs):
        completion = out.outputs[0]
        generated += len(completion.token_ids)
        print("=" * 80)
        print(f"PROMPT : {prompt}")
        print("-" * 80)
        print(completion.text.strip())
    print("=" * 80)
    print(f"{len(prompts)} prompt | {generated} token sinh ra | {elapsed:.2f}s | "
          f"{generated / elapsed:.1f} token/s (cả batch)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
