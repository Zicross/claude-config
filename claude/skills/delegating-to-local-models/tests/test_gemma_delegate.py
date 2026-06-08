import importlib.util, pathlib, pytest, urllib.error
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


def test_truncation_detection():
    gd.check_truncation({"done_reason": "stop", "message": {"content": "ok"}})  # no raise
    with pytest.raises(gd.DelegateError) as e:
        gd.check_truncation({"done_reason": "length", "message": {"content": "half"}})
    assert e.value.exit_code == 7


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
