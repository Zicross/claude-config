"""gemma-delegate: transport + guardrails for delegating code to local Gemma.
Stdlib only. Logic is importable; main() is the CLI entry."""
import argparse, json, math, os, sys, tomllib, urllib.error, urllib.request

DEFAULTS = {"num_ctx": 16384, "num_predict": 2048, "temperature": 0.1, "keep_alive": "20m"}
MODEL_DEFAULTS = {"quality": "gemma4:12b", "fast": "gemma4", "qwen3": "qwen3:8b"}
CHINESE_MARKERS = ("qwen", "minimax", "deepseek")


class DelegateError(Exception):
    def __init__(self, message, exit_code):
        super().__init__(message)
        self.exit_code = exit_code


def load_config(env, config_path):
    data = {}
    if config_path and os.path.exists(config_path):
        with open(config_path, "rb") as f:
            data = tomllib.load(f)
    endpoints = dict(data.get("endpoints", {}))
    models = {**MODEL_DEFAULTS, **data.get("models", {})}
    defaults = {**DEFAULTS, **data.get("defaults", {})}
    # env overrides for endpoints
    if env.get("GEMMA_DELEGATE_LAPTOP"):
        endpoints["laptop"] = env["GEMMA_DELEGATE_LAPTOP"]
    if env.get("GEMMA_DELEGATE_QWEN3"):
        endpoints["qwen3"] = env["GEMMA_DELEGATE_QWEN3"]
    if not endpoints.get("laptop"):
        raise DelegateError(
            "No laptop endpoint configured. Set [endpoints].laptop in "
            "~/.config/gemma-delegate/config.toml or GEMMA_DELEGATE_LAPTOP.", exit_code=2)
    return {"endpoints": endpoints, "models": models, "defaults": defaults}


def is_chinese_model(tag):
    t = tag.lower()
    return any(m in t for m in CHINESE_MARKERS)


def resolve_model(tier, model_override, models):
    if model_override:
        return model_override
    if tier not in ("quality", "fast"):
        raise DelegateError(f"unknown tier {tier!r}", exit_code=2)
    return models[tier]


def enforce_sensitivity(project, model):
    # Fail-safe: anything not explicitly 'generic' is treated as sensitive.
    if project != "generic" and is_chinese_model(model):
        raise DelegateError(
            f"REFUSED: project={project!r} is sensitive; model {model!r} is "
            f"Chinese-origin. REVENANT work must never go to qwen3/MiniMax/DeepSeek.",
            exit_code=3)


def estimate_tokens(text):
    return math.ceil(len(text) / 3.5)


def ensure_context_fit(prompt, num_ctx, reserve):
    need = estimate_tokens(prompt) + reserve
    if need > num_ctx:
        raise DelegateError(
            f"Prompt ~{estimate_tokens(prompt)} tok + {reserve} reserve exceeds "
            f"num_ctx={num_ctx}. Raise --num-ctx, chunk, or trim --files.", exit_code=4)


def build_prompt(task, files_content):
    if files_content:
        return f"{task}\n\n--- FILES ---\n{files_content}"
    return task


def build_payload(model, system, prompt, num_ctx, num_predict, temperature, keep_alive):
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    return {
        "model": model, "messages": messages,
        "think": False, "stream": False, "keep_alive": keep_alive,
        "options": {"num_ctx": num_ctx, "num_predict": num_predict, "temperature": temperature},
    }


def check_truncation(resp):
    if resp.get("done_reason") == "length":
        raise DelegateError(
            "Output was TRUNCATED (done_reason=length). Re-run with a larger "
            "--num-predict; do not trust this partial output.", exit_code=7)


def post_chat(endpoint, payload, timeout):
    """Network boundary. Raises urllib.error.URLError on failure."""
    req = urllib.request.Request(
        endpoint.rstrip("/") + "/api/chat",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def read_files(paths):
    chunks = []
    for p in paths:
        with open(p, "r", encoding="utf-8") as f:
            chunks.append(f"# file: {p}\n{f.read()}")
    return "\n\n".join(chunks)


def delegate(task, project, tier, model_override, files, num_ctx, num_predict,
             system, config, transport=None, timeout=600):
    # Resolve at call time (NOT a default arg) so tests can monkeypatch post_chat
    # and main() picks up the module-level name.
    if transport is None:
        transport = post_chat
    model = resolve_model(tier, model_override, config["models"])
    enforce_sensitivity(project, model)            # guard the primary model
    prompt = build_prompt(task, read_files(files) if files else "")
    ensure_context_fit(prompt, num_ctx, reserve=num_predict)
    payload = build_payload(model, system, prompt, num_ctx, num_predict,
                            config["defaults"]["temperature"], config["defaults"]["keep_alive"])
    try:
        resp = transport(config["endpoints"]["laptop"], payload, timeout)
    except (urllib.error.URLError, ConnectionError, TimeoutError, OSError):
        if project != "generic":
            raise DelegateError(
                "Laptop unreachable and project is sensitive — qwen3 fallback is "
                "forbidden. Claude must do this work itself.", exit_code=6)
        qendpoint = config["endpoints"].get("qwen3")
        qmodel = config["models"]["qwen3"]
        if not qendpoint:
            raise DelegateError("Laptop down and no qwen3 endpoint configured.", exit_code=5)
        enforce_sensitivity(project, qmodel)       # generic → allowed
        payload["model"] = qmodel
        try:
            resp = transport(qendpoint, payload, timeout)
        except (urllib.error.URLError, ConnectionError, TimeoutError, OSError):
            raise DelegateError("Laptop and qwen3 both unreachable.", exit_code=5)
    check_truncation(resp)
    return resp


def _config_path(env):
    return env.get("GEMMA_DELEGATE_CONFIG") or os.path.expanduser(
        "~/.config/gemma-delegate/config.toml")


def main(argv=None):
    ap = argparse.ArgumentParser(prog="gemma-delegate")
    ap.add_argument("--task", help="task text (or pass on stdin)")
    ap.add_argument("--project", choices=["revenant", "generic"], default="revenant",
                    help="sensitivity context; default 'revenant' (fail-safe)")
    ap.add_argument("--tier", choices=["quality", "fast"], default="quality")
    ap.add_argument("--model", default=None, help="explicit model override")
    ap.add_argument("--files", nargs="*", default=[])
    ap.add_argument("--num-ctx", type=int, default=None)
    ap.add_argument("--num-predict", type=int, default=None)
    ap.add_argument("--system", default=None)
    ap.add_argument("--raw", action="store_true", help="print full JSON")
    args = ap.parse_args(argv)
    task = args.task if args.task is not None else sys.stdin.read()
    if not task.strip():
        print("error: empty task (pass --task or stdin)", file=sys.stderr)
        return 2
    try:
        config = load_config(os.environ, _config_path(os.environ))
        num_ctx = args.num_ctx or config["defaults"]["num_ctx"]
        num_predict = args.num_predict or config["defaults"]["num_predict"]
        resp = delegate(task=task, project=args.project, tier=args.tier,
                        model_override=args.model, files=args.files, num_ctx=num_ctx,
                        num_predict=num_predict, system=args.system, config=config)
    except DelegateError as e:
        print(f"gemma-delegate: {e}", file=sys.stderr)
        return e.exit_code
    if args.raw:
        print(json.dumps(resp, indent=2))
    else:
        print(resp.get("message", {}).get("content", ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
