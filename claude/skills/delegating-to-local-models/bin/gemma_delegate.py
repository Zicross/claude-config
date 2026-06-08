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
