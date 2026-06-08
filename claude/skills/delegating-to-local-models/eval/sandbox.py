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
