#!/usr/bin/env python3
"""Benchmark Time to First Token (TTFT) and Tokens Per Second (TPS) against Colibrì server."""
import json
import time
import urllib.request

URL = "http://127.0.0.1:8000/v1/chat/completions"
MODEL = "glm-5.2-colibri"

PROMPTS = [
    ("Short prompt (10 tokens)", "What is the capital of France? Answer in one word."),
    ("Medium prompt (~50 tokens)", "Explain how a binary search algorithm works in 2 concise sentences. Be direct and clear."),
    ("Code prompt (~100 tokens)", "Write a Python function to check if a string is a palindrome. Include docstring and type hints."),
]

def benchmark_stream(name, prompt, max_tokens=30):
    body = {
        "model": MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "stream": True,
        "max_tokens": max_tokens,
        "temperature": 0.1,
    }
    
    req = urllib.request.Request(
        URL,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    
    t_start = time.perf_counter()
    t_first_token = None
    tokens = []
    
    with urllib.request.urlopen(req, timeout=120) as resp:
        for line in resp:
            line = line.decode("utf-8").strip()
            if not line.startswith("data: "):
                continue
            data_str = line[6:]
            if data_str == "[DONE]":
                break
            try:
                data = json.loads(data_str)
                delta = data["choices"][0]["delta"].get("content", "")
                if delta:
                    if t_first_token is None:
                        t_first_token = time.perf_counter()
                    tokens.append(delta)
            except Exception:
                continue
                
    t_end = time.perf_counter()
    
    num_tokens = len(tokens)
    ttft = (t_first_token - t_start) if t_first_token else 0.0
    gen_time = (t_end - t_first_token) if t_first_token else 0.0
    tps = (num_tokens - 1) / gen_time if gen_time > 0 and num_tokens > 1 else 0.0
    total_time = t_end - t_start
    full_text = "".join(tokens).strip()
    
    print(f"\n==================================================")
    print(f"Test: {name}")
    print(f"Prompt: \"{prompt}\"")
    print(f"Response: \"{full_text}\"")
    print(f"--------------------------------------------------")
    print(f"  Prompt Prefill Latency (TTFT) : {ttft:.3f} s")
    print(f"  Tokens Generated              : {num_tokens} tokens")
    print(f"  Generation Time               : {gen_time:.3f} s")
    print(f"  Pure Generation Speed         : {tps:.2f} tok/s")
    print(f"  Total End-to-End Latency      : {total_time:.3f} s")
    print(f"==================================================")

if __name__ == "__main__":
    for name, p in PROMPTS:
        benchmark_stream(name, p)
