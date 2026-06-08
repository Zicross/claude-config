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
