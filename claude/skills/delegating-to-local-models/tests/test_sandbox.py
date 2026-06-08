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
