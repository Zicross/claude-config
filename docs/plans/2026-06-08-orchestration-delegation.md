# Orchestration & Delegation Methodology — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the global orchestration/delegation methodology — a `gemma-delegate` CLI, an eval harness, a skill, and CLAUDE.md rules — so the host Claude can safely delegate implementation to local Gemma models.

**Architecture:** A dependency-free Python CLI (`gemma-delegate`) does transport + guardrails (model tiering, fail-safe sensitivity guard, context-fit + truncation checks, fallback). A pytest suite covers it with the network mocked. An eval harness (productionized from the design-time prototype, hardened with `setrlimit`) selects/regression-gates models. A skill + CLAUDE.md block wire it into Claude's behavior. Everything lives under one skill dir so the existing `skills/` symlink deploys it; live config stays outside the repo.

**Tech Stack:** Python 3.14 stdlib only (`argparse`, `urllib.request`, `tomllib`, `json`, `resource`, `subprocess`); pytest; bash for deploy/smoke. Target repo: `claude-config` (this repo), branch `feat/orchestration-delegation`.

**Spec:** `docs/specs/2026-06-08-orchestration-delegation-methodology-design.md`

**Paths (under `claude/skills/delegating-to-local-models/`):**
- `bin/gemma_delegate.py` — importable logic (all functions; `main()`).
- `bin/gemma-delegate` — executable shim that runs the module.
- `bin/gemma-delegate.toml.example` — committed placeholder config.
- `tests/test_gemma_delegate.py` — Layer A unit tests (network mocked).
- `eval/sandbox.py`, `eval/tasks.py`, `eval/run_eval.py` — Layer B harness.
- `SKILL.md` — the playbook.
- Live config (NOT in repo): `~/.config/gemma-delegate/config.toml` or env vars.

---

## Task 0: Hygiene & scaffolding

**Files:**
- Create: `.gitignore` entry, dir skeleton, `bin/gemma-delegate.toml.example`

- [ ] **Step 1: Create the skill directory skeleton**

```bash
cd /opt/claude-config
mkdir -p claude/skills/delegating-to-local-models/{bin,tests,eval}
```

- [ ] **Step 2: Add gitignore protection for live config**

Append to `/opt/claude-config/.gitignore`:

```
# Local delegation config holds real network endpoints — never commit.
**/gemma-delegate.toml
!**/gemma-delegate.toml.example
**/gemma-delegate*.local.toml
```

- [ ] **Step 3: Write the committed example config (placeholders only)**

Create `claude/skills/delegating-to-local-models/bin/gemma-delegate.toml.example`:

```toml
# Copy to ~/.config/gemma-delegate/config.toml and fill in real values.
# This .example is committed; the real config is NOT (it has live endpoints).

[endpoints]
# Laptop running Gemma over Ollama (e.g. "http://<tailnet-ip>:11434")
laptop = "http://LAPTOP_HOST:11434"
# Host running qwen3 (generic-only fallback)
qwen3  = "http://QWEN3_HOST:11434"

[models]
quality = "gemma4:12b"
fast    = "gemma4"
qwen3   = "qwen3:8b"

[defaults]
num_ctx     = 16384
num_predict = 2048
temperature = 0.1
keep_alive  = "20m"
```

- [ ] **Step 4: Verify the deploy flow won't copy live config into the repo**

Run: `grep -n "SYMLINK_ITEMS\|cp -r\|rsync" /opt/claude-config/deploy-claude-config.sh /opt/claude-config/sync.sh`
Expected: confirm `skills` is symlinked (not copied) so a live `config.toml` placed in `~/.config` never enters the repo tree. Note findings in the commit message.

- [ ] **Step 5: Commit**

```bash
cd /opt/claude-config
git add .gitignore claude/skills/delegating-to-local-models/bin/gemma-delegate.toml.example
git commit -m "chore(orchestration): scaffold skill dir + gitignore live config"
```

---

## Task 1: Config loading

**Files:**
- Create: `bin/gemma_delegate.py`
- Test: `tests/test_gemma_delegate.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_gemma_delegate.py
import importlib.util, pathlib, pytest
_spec = importlib.util.spec_from_file_location(
    "gemma_delegate",
    pathlib.Path(__file__).parent.parent / "bin" / "gemma_delegate.py")
gd = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(gd)


def test_load_config_file_then_env_override(tmp_path):
    cfg = tmp_path / "config.toml"
    cfg.write_text(
        '[endpoints]\nlaptop="http://lap:11434"\nqwen3="http://q:11434"\n'
        '[models]\nquality="gemma4:12b"\nfast="gemma4"\nqwen3="qwen3:8b"\n'
        '[defaults]\nnum_ctx=16384\nnum_predict=2048\ntemperature=0.1\nkeep_alive="20m"\n')
    c = gd.load_config(env={}, config_path=cfg)
    assert c["endpoints"]["laptop"] == "http://lap:11434"
    assert c["models"]["quality"] == "gemma4:12b"
    assert c["defaults"]["num_ctx"] == 16384
    # env overrides the laptop endpoint
    c2 = gd.load_config(env={"GEMMA_DELEGATE_LAPTOP": "http://env:1"}, config_path=cfg)
    assert c2["endpoints"]["laptop"] == "http://env:1"


def test_load_config_missing_laptop_endpoint_raises(tmp_path):
    cfg = tmp_path / "none.toml"  # does not exist
    with pytest.raises(gd.DelegateError) as e:
        gd.load_config(env={}, config_path=cfg)
    assert e.value.exit_code == 2
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/ -x -q`
Expected: FAIL (module/`load_config` not defined).

- [ ] **Step 3: Write minimal implementation**

```python
# bin/gemma_delegate.py
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/ -x -q`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add claude/skills/delegating-to-local-models/bin/gemma_delegate.py claude/skills/delegating-to-local-models/tests/test_gemma_delegate.py
git commit -m "feat(gemma-delegate): config loading with env override + fail-safe missing-endpoint error"
```

---

## Task 2: Model resolution + fail-safe sensitivity guard

**Files:**
- Modify: `bin/gemma_delegate.py`
- Test: `tests/test_gemma_delegate.py`

- [ ] **Step 1: Write the failing tests**

```python
def test_is_chinese_model():
    assert gd.is_chinese_model("qwen3:8b") is True
    assert gd.is_chinese_model("MiniMax-M2") is True
    assert gd.is_chinese_model("deepseek-coder") is True
    assert gd.is_chinese_model("gemma4:12b") is False


def test_resolve_model_tier_and_override():
    models = gd.MODEL_DEFAULTS
    assert gd.resolve_model("quality", None, models) == "gemma4:12b"
    assert gd.resolve_model("fast", None, models) == "gemma4"
    assert gd.resolve_model("quality", "gemma4:26b", models) == "gemma4:26b"


def test_sensitivity_revenant_refuses_chinese():
    with pytest.raises(gd.DelegateError) as e:
        gd.enforce_sensitivity("revenant", "qwen3:8b")
    assert e.value.exit_code == 3


def test_sensitivity_defaults_and_allows():
    # default project is revenant (fail-safe) — caller passes it explicitly in main()
    gd.enforce_sensitivity("revenant", "gemma4:12b")   # allowed, no raise
    gd.enforce_sensitivity("generic", "qwen3:8b")      # generic may use qwen3
```

- [ ] **Step 2: Run to verify fail**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/ -k "model or sensitivity" -q`
Expected: FAIL (names not defined).

- [ ] **Step 3: Implement**

Append to `bin/gemma_delegate.py`:

```python
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
```

- [ ] **Step 4: Run to verify pass**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/ -k "model or sensitivity" -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A claude/skills/delegating-to-local-models
git commit -m "feat(gemma-delegate): model resolution + fail-safe sensitivity guard"
```

---

## Task 3: Prompt assembly, token estimate, context-fit check

**Files:**
- Modify: `bin/gemma_delegate.py`
- Test: `tests/test_gemma_delegate.py`

- [ ] **Step 1: Write the failing tests**

```python
def test_estimate_tokens_and_fit():
    assert gd.estimate_tokens("x" * 350) == pytest.approx(100, abs=2)
    gd.ensure_context_fit("short prompt", num_ctx=16384, reserve=2048)  # ok
    with pytest.raises(gd.DelegateError) as e:
        gd.ensure_context_fit("x" * 100000, num_ctx=4096, reserve=2048)
    assert e.value.exit_code == 4


def test_build_payload_shape():
    p = gd.build_payload("gemma4:12b", "SYS", "do X", num_ctx=8192,
                         num_predict=500, temperature=0.1, keep_alive="20m")
    assert p["model"] == "gemma4:12b"
    assert p["think"] is False and p["stream"] is False
    assert p["options"]["num_ctx"] == 8192
    assert p["messages"][0]["role"] == "system"
    assert p["messages"][-1]["content"] == "do X"
```

- [ ] **Step 2: Run to verify fail**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/ -k "fit or payload" -q`
Expected: FAIL.

- [ ] **Step 3: Implement**

Append:

```python
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
```

- [ ] **Step 4: Run to verify pass**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/ -k "fit or payload" -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A claude/skills/delegating-to-local-models
git commit -m "feat(gemma-delegate): prompt assembly + token estimate + context-fit guard"
```

---

## Task 4: Truncation detection

**Files:**
- Modify: `bin/gemma_delegate.py`
- Test: `tests/test_gemma_delegate.py`

- [ ] **Step 1: Write the failing test**

```python
def test_truncation_detection():
    gd.check_truncation({"done_reason": "stop", "message": {"content": "ok"}})  # no raise
    with pytest.raises(gd.DelegateError) as e:
        gd.check_truncation({"done_reason": "length", "message": {"content": "half"}})
    assert e.value.exit_code == 7
```

- [ ] **Step 2: Run to verify fail**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/ -k truncation -q`
Expected: FAIL.

- [ ] **Step 3: Implement**

Append:

```python
def check_truncation(resp):
    if resp.get("done_reason") == "length":
        raise DelegateError(
            "Output was TRUNCATED (done_reason=length). Re-run with a larger "
            "--num-predict; do not trust this partial output.", exit_code=7)
```

- [ ] **Step 4: Run to verify pass**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/ -k truncation -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A claude/skills/delegating-to-local-models
git commit -m "feat(gemma-delegate): truncation detection via done_reason"
```

---

## Task 5: Transport + fallback orchestration (network injected)

**Files:**
- Modify: `bin/gemma_delegate.py`
- Test: `tests/test_gemma_delegate.py`

- [ ] **Step 1: Write the failing tests**

```python
def _cfg():
    return {"endpoints": {"laptop": "http://lap", "qwen3": "http://q"},
            "models": dict(gd.MODEL_DEFAULTS), "defaults": dict(gd.DEFAULTS)}


def test_delegate_success():
    def fake(endpoint, payload, timeout):
        return {"done_reason": "stop", "message": {"content": "RESULT"},
                "_endpoint": endpoint, "_model": payload["model"]}
    out = gd.delegate(task="do X", project="revenant", tier="quality",
                      model_override=None, files=[], num_ctx=8192, num_predict=500,
                      system=None, config=_cfg(), transport=fake)
    assert out["message"]["content"] == "RESULT"
    assert out["_endpoint"] == "http://lap" and out["_model"] == "gemma4:12b"


def test_delegate_revenant_unreachable_exits_6():
    def down(endpoint, payload, timeout):
        raise urllib.error.URLError("unreachable")
    with pytest.raises(gd.DelegateError) as e:
        gd.delegate(task="x", project="revenant", tier="quality", model_override=None,
                    files=[], num_ctx=8192, num_predict=500, system=None,
                    config=_cfg(), transport=down)
    assert e.value.exit_code == 6  # never falls back to qwen3


def test_delegate_generic_falls_back_to_qwen3():
    calls = []
    def transport(endpoint, payload, timeout):
        calls.append((endpoint, payload["model"]))
        if endpoint == "http://lap":
            raise urllib.error.URLError("laptop down")
        return {"done_reason": "stop", "message": {"content": "Q"}}
    out = gd.delegate(task="x", project="generic", tier="quality", model_override=None,
                      files=[], num_ctx=8192, num_predict=500, system=None,
                      config=_cfg(), transport=transport)
    assert out["message"]["content"] == "Q"
    assert calls[0][0] == "http://lap"
    assert calls[1] == ("http://q", "qwen3:8b")  # swapped endpoint AND model


def test_delegate_generic_all_down_exits_5():
    def down(endpoint, payload, timeout):
        raise urllib.error.URLError("down")
    with pytest.raises(gd.DelegateError) as e:
        gd.delegate(task="x", project="generic", tier="quality", model_override=None,
                    files=[], num_ctx=8192, num_predict=500, system=None,
                    config=_cfg(), transport=down)
    assert e.value.exit_code == 5
```

- [ ] **Step 2: Run to verify fail**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/ -k delegate -q`
Expected: FAIL.

- [ ] **Step 3: Implement**

Append:

```python
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
```

- [ ] **Step 4: Run to verify pass**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/ -k delegate -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A claude/skills/delegating-to-local-models
git commit -m "feat(gemma-delegate): transport + REVENANT-safe fallback orchestration"
```

---

## Task 6: CLI (`main`) + exit codes

**Files:**
- Modify: `bin/gemma_delegate.py`
- Test: `tests/test_gemma_delegate.py`

- [ ] **Step 1: Write the failing tests**

```python
def test_main_success_prints_content(monkeypatch, capsys, tmp_path):
    cfg = tmp_path / "c.toml"
    cfg.write_text('[endpoints]\nlaptop="http://lap"\nqwen3="http://q"\n')
    monkeypatch.setenv("GEMMA_DELEGATE_CONFIG", str(cfg))
    monkeypatch.setattr(gd, "post_chat",
        lambda e, p, t: {"done_reason": "stop", "message": {"content": "HELLO"}})
    rc = gd.main(["--task", "hi", "--project", "generic"])
    assert rc == 0
    assert "HELLO" in capsys.readouterr().out


def test_main_sensitivity_refusal_exit_3(monkeypatch, tmp_path):
    cfg = tmp_path / "c.toml"; cfg.write_text('[endpoints]\nlaptop="http://lap"\n')
    monkeypatch.setenv("GEMMA_DELEGATE_CONFIG", str(cfg))
    rc = gd.main(["--task", "x", "--project", "revenant", "--model", "qwen3:8b"])
    assert rc == 3  # default project revenant + explicit chinese model
```

- [ ] **Step 2: Run to verify fail**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/ -k main -q`
Expected: FAIL.

- [ ] **Step 3: Implement**

Append:

```python
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
```

- [ ] **Step 4: Run to verify pass + full suite green**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/ -q`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add -A claude/skills/delegating-to-local-models
git commit -m "feat(gemma-delegate): CLI entry, argparse, stdin, exit codes"
```

---

## Task 7: Executable shim + live smoke

**Files:**
- Create: `bin/gemma-delegate`
- Test: manual live smoke (env-gated)

- [ ] **Step 1: Write the shim**

Create `bin/gemma-delegate`:

```bash
#!/usr/bin/env bash
# Thin launcher so the callable name is `gemma-delegate`; logic lives in the module.
exec python3 "$(dirname "$(readlink -f "$0")")/gemma_delegate.py" "$@"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x claude/skills/delegating-to-local-models/bin/gemma-delegate`

- [ ] **Step 3: Live smoke (requires real config + laptop up)**

Create `~/.config/gemma-delegate/config.toml` from the example with real endpoints, then:
Run:
```bash
echo "Write a python one-liner that reverses a string." | \
  ./claude/skills/delegating-to-local-models/bin/gemma-delegate --tier fast --project generic
```
Expected: prints a reversed-string snippet; exit 0. (If laptop down: exit 5 for generic, clean message.)

- [ ] **Step 4: Verify sensitivity refusal end-to-end**

Run:
```bash
echo x | ./claude/skills/delegating-to-local-models/bin/gemma-delegate --project revenant --model qwen3:8b; echo "exit=$?"
```
Expected: refusal message on stderr, `exit=3`.

- [ ] **Step 5: Commit**

```bash
git add -A claude/skills/delegating-to-local-models
git commit -m "feat(gemma-delegate): executable shim + verified live smoke"
```

---

## Task 8: Layer-B eval harness (productionized + hardened)

**Files:**
- Create: `eval/sandbox.py`, `eval/tasks.py`, `eval/run_eval.py`
- Test: `tests/test_sandbox.py`

The logic comes from the design-time prototype (`/tmp/deleg_eval/`). The NEW requirement is the `setrlimit` + network-off hardening from spec §11.

- [ ] **Step 1: Write the failing sandbox test**

```python
# tests/test_sandbox.py
import importlib.util, pathlib
_s = importlib.util.spec_from_file_location(
    "sandbox", pathlib.Path(__file__).parent.parent / "eval" / "sandbox.py")
sb = importlib.util.module_from_spec(_s); _s.loader.exec_module(sb)


def test_checks_pass_and_fail():
    code = "def add(a,b):\n    return a+b\n"
    res = sb.run_checks(code, ["assert add(2,3)==5", "assert add(2,3)==6"], timeout=20)
    assert res == [True, False]


def test_infinite_loop_is_killed():
    code = "def add(a,b):\n    while True:\n        pass\n"
    res = sb.run_checks(code, ["assert add(1,1)==2"], timeout=5)
    assert res == [False]  # timed out → check fails, harness survives
```

- [ ] **Step 2: Run to verify fail**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/test_sandbox.py -q`
Expected: FAIL.

- [ ] **Step 3: Implement the hardened sandbox**

Create `eval/sandbox.py`:

```python
"""Run model-generated code against checks under resource limits + no network.
Trusted-source threat model: guards against ACCIDENTAL runaway, not adversary."""
import json, os, resource, subprocess, sys, tempfile

_LIMITS = {
    resource.RLIMIT_CPU: (10, 10),                 # seconds of CPU
    resource.RLIMIT_AS: (2 * 1024**3, 2 * 1024**3),  # 2 GB address space
    resource.RLIMIT_NPROC: (64, 64),               # fork-bomb guard
    resource.RLIMIT_FSIZE: (16 * 1024**2, 16 * 1024**2),  # 16 MB writes
}

_RUNNER = r'''
import json, sys
ns = {}
try:
    exec(open(sys.argv[1]).read(), ns)
except Exception as e:
    print(json.dumps({"import_error": repr(e)})); sys.exit(0)
out = []
for c in json.load(open(sys.argv[2])):
    try:
        exec(c, dict(ns)); out.append(True)
    except Exception:
        out.append(False)
print(json.dumps(out))
'''


def _preexec():
    for k, v in _LIMITS.items():
        try:
            resource.setrlimit(k, v)
        except (ValueError, OSError):
            pass


def run_checks(code, checks, timeout=30):
    with tempfile.TemporaryDirectory() as wd:
        sol = os.path.join(wd, "sol.py"); open(sol, "w").write(code)
        chk = os.path.join(wd, "checks.json"); open(chk, "w").write(json.dumps(checks))
        run = os.path.join(wd, "run.py"); open(run, "w").write(_RUNNER)
        # network-off wrapper if available; minimal env (no secrets)
        base = [sys.executable, run, sol, chk]
        cmd = (["unshare", "-rn"] + base) if _unshare_works() else base
        env = {"PATH": "/usr/bin:/bin", "HOME": wd}
        try:
            p = subprocess.run(cmd, cwd=wd, env=env, capture_output=True, text=True,
                               timeout=timeout, preexec_fn=_preexec)
            data = json.loads(p.stdout.strip().splitlines()[-1]) if p.stdout.strip() else []
        except (subprocess.TimeoutExpired, json.JSONDecodeError, IndexError):
            return [False] * len(checks)
        if isinstance(data, dict):  # import_error
            return [False] * len(checks)
        return data


_UNSHARE_OK = None
def _unshare_works():
    # Probe ACTUAL functionality once — `unshare` may exist but user namespaces
    # can be disabled, in which case it errors and would fail every check.
    global _UNSHARE_OK
    if _UNSHARE_OK is None:
        from shutil import which
        if which("unshare") is None:
            _UNSHARE_OK = False
        else:
            try:
                p = subprocess.run(["unshare", "-rn", "true"],
                                   capture_output=True, timeout=5)
                _UNSHARE_OK = (p.returncode == 0)
            except Exception:
                _UNSHARE_OK = False
    return _UNSHARE_OK
```

(If `unshare` is unavailable/disabled the sandbox still applies `setrlimit` + timeout;
network-off is best-effort. Document this degradation in `eval/run_eval.py` output.)

- [ ] **Step 4: Run to verify pass**

Run: `python3 -m pytest claude/skills/delegating-to-local-models/tests/test_sandbox.py -q`
Expected: PASS.

- [ ] **Step 5: Port tasks + runner from prototype**

Create `eval/tasks.py` (copy the task list from the design-time prototype `/tmp/deleg_eval/run_eval.py` + `run_eval_blind.py`: each task = `{id, symbol, prompt, checks:[...]}`) and `eval/run_eval.py` (a runner that, per model in a configurable list, calls `gemma_delegate.post_chat`, extracts code, calls `sandbox.run_checks`, and prints a scorecard). Reuse `gemma_delegate.post_chat` for the HTTP call so there is one transport.

- [ ] **Step 6: Commit**

```bash
git add -A claude/skills/delegating-to-local-models
git commit -m "feat(eval): hardened Layer-B harness (setrlimit + network-off) + tasks"
```

---

## Task 9: The skill (`SKILL.md`)

**Files:**
- Create: `claude/skills/delegating-to-local-models/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Frontmatter `name: delegating-to-local-models`, `description:` triggering on "entering orchestrator mode / delegating implementation to a local model". Body covers: the orchestrator loop (PLAN→IDENTIFY→DELEGATE→REVIEW→INTEGRATE→VERIFY), the model policy table (12B default / 8B fast / 26B dormant), the sensitivity guard, the **absolute** `gemma-delegate` invocation path, common flags, exit-code meanings (3=refused, 4=overflow, 5=all-down, 6=revenant-takeover, 7=truncated) and how Claude should react to each, and the "never commit unreviewed output" invariant. No network addresses (spec §4a).

- [ ] **Step 2: Sanity-check the skill loads**

Run: `python3 -c "import pathlib,re; t=pathlib.Path('claude/skills/delegating-to-local-models/SKILL.md').read_text(); assert t.startswith('---') and 'name:' in t and 'description:' in t; print('frontmatter ok')"`
Expected: `frontmatter ok`.

- [ ] **Step 3: Commit**

```bash
git add -A claude/skills/delegating-to-local-models
git commit -m "docs(skill): delegating-to-local-models playbook"
```

---

## Task 10: CLAUDE.md managed block

**Files:**
- Modify: `claude/CLAUDE.md`

- [ ] **Step 1: Append a NEW delimited block (do NOT touch the substrate block)**

Add to the end of `claude/CLAUDE.md`:

```markdown
<!-- BEGIN orchestration-delegation (managed; do not merge into substrate block) -->
## Orchestration & delegation (global)

You operate in one of two modes, chosen per task (announce which; user overrides):
- **All-in-one** — plan and implement yourself. Default when uncertain, and for
  subtle/ambiguous/architectural work.
- **Orchestrator** — delegate implementation to local Gemma via `gemma-delegate`,
  then REVIEW and INTEGRATE. **On entering orchestrator mode, invoke the
  `delegating-to-local-models` skill.**

Hard rule: **never send REVENANT-related work to a Chinese-origin model**
(qwen3/MiniMax/DeepSeek). `gemma-delegate --project` defaults to the safe branch.
Never commit unreviewed model output.
<!-- END orchestration-delegation -->
```

- [ ] **Step 2: Verify the substrate block is untouched and a sync round-trips cleanly**

Run:
```bash
grep -c "BEGIN meta-engineering substrate" claude/CLAUDE.md   # expect 1
grep -c "BEGIN orchestration-delegation" claude/CLAUDE.md      # expect 1
bash sync.sh --dry-run 2>/dev/null || echo "review sync.sh behavior manually"
```
Expected: both counts 1; confirm sync does not strip/reformat the new block.

- [ ] **Step 3: Commit**

```bash
git add claude/CLAUDE.md
git commit -m "feat(claude-md): orchestration-delegation managed block + skill trigger"
```

---

## Task 11: Deploy, end-to-end smoke, cleanup

**Files:**
- None (operational)

- [ ] **Step 1: Run the Codex/GPT-5.4 critique debt (if CLI now available)**

Per spec §14, run the independent Codex critique on the spec + code and fold any findings before deploy. If still unavailable, record that it remains pending.

- [ ] **Step 2: Deploy via the normal flow**

Run: `bash deploy-claude-config.sh` (or the project's standard deploy). Confirm the skill (and its `bin/gemma-delegate`) is reachable at `~/.claude/skills/delegating-to-local-models/bin/gemma-delegate`.

- [ ] **Step 3: End-to-end orchestrator smoke**

Delegate a real small task through the deployed path; confirm review-then-integrate works and the output is sound.

- [ ] **Step 4: Remove the orphaned `gemma4-coder` model**

Run (over the Ollama API, real endpoint from local config):
```bash
curl -s -X DELETE "$LAPTOP/api/delete" -d '{"model":"gemma4-coder"}'
```
Expected: removed (it was a 26B-based artifact from design; no longer needed).

- [ ] **Step 5: Final commit + prepare merge**

```bash
git add -A && git commit -m "chore(orchestration): deploy + cleanup orphaned gemma4-coder" || true
```
Then hand back for the merge-to-master + push decision (public repo — requires user go).

---

## Self-review notes

- **Spec coverage:** modes (Task 10), gemma-delegate transport+guardrails (Tasks 1–7),
  fail-safe sensitivity (Task 2,6,7), context/truncation guardrails (Tasks 3,4),
  fallback semantics (Task 5), eval harness + hardening (Task 8), skill (Task 9),
  CLAUDE.md trigger (Task 10), hygiene/public-repo (Task 0), deploy + cleanup +
  Codex debt (Task 11). All §-sections mapped.
- **Type consistency:** `DelegateError(message, exit_code)`, `config` dict shape
  (`endpoints`/`models`/`defaults`), and `delegate(...)` signature are identical
  across Tasks 1–6.
- **Exit codes (single source):** 2 usage, 3 sensitivity-refusal, 4 context-overflow,
  5 all-endpoints-down, 6 REVENANT-takeover, 7 truncated.
