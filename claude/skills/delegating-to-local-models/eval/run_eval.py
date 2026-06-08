"""Layer-B eval runner: call a local model, score generated code with the sandbox.

Usage:
    GEMMA_DELEGATE_LAPTOP=http://192.168.1.x:11434 python3 run_eval.py
    python3 run_eval.py --endpoint http://192.168.1.x:11434 --models gemma4:12b gemma4:26b

The endpoint must be an Ollama-compatible API base URL (no path; /api/chat is appended
by post_chat).  Do NOT hardcode a real IP — pass it via the env var or --endpoint flag.

Sandbox degradation note: if `unshare -rn` is unavailable or disabled (user namespaces
off), the sandbox falls back to setrlimit + timeout only — network isolation is NOT
applied.  The startup banner reports which mode is active.
"""
import argparse, importlib.util, json, pathlib, re, sys, time

# ---------------------------------------------------------------------------
# Module-loading helpers (bin/ is not a package, so we use importlib)
# ---------------------------------------------------------------------------

def _load_module(name, rel_path_from_here):
    """Load a .py file by path relative to this file's directory."""
    p = pathlib.Path(__file__).parent / rel_path_from_here
    spec = importlib.util.spec_from_file_location(name, p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# Load sandbox from the same eval/ directory.
_sandbox = _load_module("sandbox", "sandbox.py")
run_checks = _sandbox.run_checks
_unshare_works = _sandbox._unshare_works

# Load post_chat from bin/gemma_delegate.py (the ONE transport — do not duplicate).
_gd = _load_module("gemma_delegate", "../bin/gemma_delegate.py")
post_chat = _gd.post_chat

# Load task list from tasks.py (same eval/ directory).
_tasks_mod = _load_module("tasks", "tasks.py")
TASKS = _tasks_mod.TASKS

# ---------------------------------------------------------------------------
# Code extraction (port of extract_code from prototype)
# ---------------------------------------------------------------------------

def extract_code(text):
    """Pull the first/only fenced code block; fall back to raw text."""
    blocks = re.findall(r"```(?:python)?\s*\n(.*?)```", text, re.DOTALL)
    if blocks:
        return "\n\n".join(b.strip() for b in blocks)
    return text  # assume raw code


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def _build_payload(model, prompt, opts):
    return {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "think": False, "stream": False, "keep_alive": "30m",
        "options": opts,
    }


def run_eval(endpoint, models, opts=None, verbose=True):
    """Run all tasks across all models; return per-model result dicts."""
    if opts is None:
        opts = {"num_ctx": 8192, "num_predict": 1500, "temperature": 0.1}

    all_results = {}
    for model in models:
        all_results[model] = []
        if verbose:
            print(f"\n##### {model} #####", flush=True)
        for task in TASKS:
            payload = _build_payload(model, task["prompt"], opts)
            t0 = time.time()
            try:
                resp = post_chat(endpoint, payload, timeout=600)
            except Exception as exc:
                if verbose:
                    print(f"  {task['id']:22} CALL-ERROR {exc}", flush=True)
                all_results[model].append({
                    "id": task["id"], "passed": 0,
                    "total": len(task["checks"]), "wall": 0.0,
                })
                continue
            wall = time.time() - t0
            content = resp.get("message", {}).get("content", "")
            code = extract_code(content)
            results = run_checks(code, task["checks"], timeout=30)
            passed = sum(1 for x in results if x)
            total = len(task["checks"])
            if verbose:
                mark = "PASS" if passed == total else f"{passed}/{total}"
                print(f"  {task['id']:22} {mark:8} {wall:5.1f}s", flush=True)
            all_results[model].append({
                "id": task["id"], "passed": passed,
                "total": total, "wall": wall,
                "checks": results,
            })
    return all_results


def print_scorecard(all_results):
    """Print a per-model scorecard to stdout."""
    print("\n\n===== SCORECARD =====")
    header = f"{'model':20} {'tasks-full':12} {'checks':14} {'avg-s':8}"
    print(header)
    for model, results in all_results.items():
        total_tasks = len(results)
        full_tasks = sum(1 for r in results if r["passed"] == r["total"])
        total_checks = sum(r["total"] for r in results)
        passed_checks = sum(r["passed"] for r in results)
        timed = [r["wall"] for r in results if r["wall"] > 0]
        avg_s = sum(timed) / len(timed) if timed else 0.0
        print(
            f"{model:20} {f'{full_tasks}/{total_tasks}':12} "
            f"{f'{passed_checks}/{total_checks}':14} {avg_s:8.1f}"
        )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    ap = argparse.ArgumentParser(
        description="Layer-B eval: score local model code generation via sandbox."
    )
    ap.add_argument(
        "--endpoint",
        default=None,
        help=(
            "Ollama API base URL, e.g. http://192.168.1.x:11434. "
            "Falls back to GEMMA_DELEGATE_LAPTOP env var."
        ),
    )
    ap.add_argument(
        "--models", nargs="+",
        default=["gemma4:12b"],
        help="Model tag(s) to evaluate (default: gemma4:12b).",
    )
    ap.add_argument(
        "--num-ctx", type=int, default=8192,
        help="Context window tokens (default: 8192).",
    )
    ap.add_argument(
        "--num-predict", type=int, default=1500,
        help="Max output tokens (default: 1500).",
    )
    ap.add_argument(
        "--temperature", type=float, default=0.1,
        help="Sampling temperature (default: 0.1).",
    )
    ap.add_argument(
        "--out", default=None,
        help="Write JSON results to this file path (optional).",
    )
    args = ap.parse_args()

    import os
    endpoint = args.endpoint or os.environ.get("GEMMA_DELEGATE_LAPTOP")
    if not endpoint:
        print(
            "error: no endpoint. Pass --endpoint or set GEMMA_DELEGATE_LAPTOP.",
            file=sys.stderr,
        )
        sys.exit(2)

    # Sandbox mode banner
    if _unshare_works():
        print("Sandbox: network-off isolation ACTIVE (unshare -rn)")
    else:
        print(
            "Sandbox: DEGRADED — unshare unavailable or disabled; "
            "applying setrlimit + timeout only (no network isolation)."
        )

    opts = {
        "num_ctx": args.num_ctx,
        "num_predict": args.num_predict,
        "temperature": args.temperature,
    }
    results = run_eval(endpoint, args.models, opts=opts, verbose=True)
    print_scorecard(results)

    if args.out:
        with open(args.out, "w") as f:
            json.dump(results, f, indent=2)
        print(f"\nResults written to {args.out}")
