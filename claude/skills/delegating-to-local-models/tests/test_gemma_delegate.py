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
