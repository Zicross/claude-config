"""Eval task definitions for the Layer-B delegation harness.

Each task is a dict with:
  id      - unique identifier
  symbol  - primary symbol to look for in model output (function or class name)
  prompt  - the coding challenge sent to the model
  checks  - list of check strings; each is exec'd independently against a FRESH
            copy of the model's namespace.  Stateful sequences (e.g. shared setup
            or helper lambdas) are kept together in one multi-line check string so
            they run as a unit.

Sources:
  - run_eval.py        : 6 tasks (merge_intervals, roman_to_int, lru_cache,
                         parse_query_string, flatten, is_balanced)
  - run_eval_blind.py  : 5 tasks (longctx_bugfix, constraint_price,
                         constraint_passwd, ambiguous_snake, longout_matrix)

Conversion notes (ref → checks):
  merge_intervals : kept as ONE multi-line check — the ref defines a `norm`
                    lambda used by every assert, so all asserts share setup state.
  lru_cache       : kept as ONE multi-line check — sequential put/get calls build
                    on shared `c` instance; splitting would break ordering semantics.
  roman_to_int    : split into individual checks (each assert is self-contained).
  parse_query_string: split (each assert independent).
  flatten         : split (each assert independent).
  is_balanced     : split (each assert independent).
  blind tasks     : checks lists copied directly from run_eval_blind.py.
"""

# ---- long-context bugfix: distractor module with one buggy needle ----
_distractors = "\n".join(
    f"def func_{i:03d}(x):\n    return x * {i} + {i % 7}\n" for i in range(150)
)
_needle = (
    "def chunk_list(lst, size):\n"
    "    # splits lst into consecutive chunks of length `size`; final chunk may be shorter.\n"
    "    result = []\n"
    "    for i in range(0, len(lst) - size + 1, size):\n"
    "        result.append(lst[i:i+size])\n"
    "    return result\n"
)
_module = _distractors[:3000] + "\n" + _needle + "\n" + _distractors[3000:]

TASKS = [
    # ------------------------------------------------------------------
    # From run_eval.py (6 tasks)
    # ------------------------------------------------------------------
    {
        "id": "merge_intervals",
        "symbol": "merge_intervals",
        "prompt": (
            "Write a Python function `merge_intervals(intervals)` that takes a list of "
            "(start,end) closed-interval tuples, merges all overlapping OR touching intervals "
            "((1,3) and (3,5) merge), and returns them as a list sorted by start. Handle empty "
            "input, unsorted input, and nested intervals. Return ONLY Python code."
        ),
        # STATEFUL: the `norm` lambda is defined once and used by all asserts.
        # Kept as a single multi-line check so `norm` is in scope for every assertion.
        "checks": [
            (
                "norm = lambda r: [tuple(x) for x in r]\n"
                "assert norm(merge_intervals([])) == []\n"
                "assert norm(merge_intervals([(1,3),(3,5)])) == [(1,5)]\n"
                "assert norm(merge_intervals([(5,8),(1,3),(2,6)])) == [(1,8)]\n"
                "assert norm(merge_intervals([(1,10),(2,5),(6,7)])) == [(1,10)]\n"
                "assert norm(merge_intervals([(1,2),(4,5)])) == [(1,2),(4,5)]"
            ),
        ],
    },
    {
        "id": "roman_to_int",
        "symbol": "roman_to_int",
        "prompt": (
            "Write a Python function `roman_to_int(s: str) -> int` that converts a Roman numeral "
            "string to an integer (supporting subtractive notation like IV, IX, XL, XC, CD, CM). "
            "Return ONLY Python code."
        ),
        # INDEPENDENT: each assert is fully self-contained.
        "checks": [
            'assert roman_to_int("III") == 3',
            'assert roman_to_int("IV") == 4',
            'assert roman_to_int("IX") == 9',
            'assert roman_to_int("LVIII") == 58',
            'assert roman_to_int("MCMXCIV") == 1994',
        ],
    },
    {
        "id": "lru_cache",
        "symbol": "LRUCache",
        "prompt": (
            "Write a Python class `LRUCache` with `__init__(self, capacity)`, "
            "`get(self, key) -> int` (return -1 if absent), and `put(self, key, value)`. "
            "It must evict the least-recently-used item when over capacity. get and put both "
            "count as 'using' a key. Return ONLY Python code."
        ),
        # STATEFUL: sequential put/get calls on a shared `c` instance; splitting would
        # produce wrong results (each check would start with a fresh empty cache).
        "checks": [
            (
                "c = LRUCache(2)\n"
                "c.put(1,1); c.put(2,2)\n"
                "assert c.get(1) == 1\n"
                "c.put(3,3)\n"
                "assert c.get(2) == -1\n"
                "c.put(4,4)\n"
                "assert c.get(1) == -1\n"
                "assert c.get(3) == 3\n"
                "assert c.get(4) == 4"
            ),
        ],
    },
    {
        "id": "parse_query_string",
        "symbol": "parse_query_string",
        "prompt": (
            "Write a Python function `parse_query_string(s: str) -> dict` that parses a URL "
            "query string into a dict mapping each key to a LIST of its values in order. "
            "Repeated keys accumulate (a=1&a=3 -> {'a':['1','3']}). URL-decode percent-escapes "
            "(%20 -> space). Empty string -> {}. Return ONLY Python code."
        ),
        # INDEPENDENT: each assert stands alone.
        "checks": [
            'assert parse_query_string("a=1&b=2&a=3") == {"a":["1","3"], "b":["2"]}',
            'assert parse_query_string("") == {}',
            'assert parse_query_string("k=a%20b") == {"k":["a b"]}',
        ],
    },
    {
        "id": "flatten",
        "symbol": "flatten",
        "prompt": (
            "Write a Python function `flatten(nested)` that flattens an arbitrarily-deeply-nested "
            "list of integers into a single flat list, preserving order. Return ONLY Python code."
        ),
        # INDEPENDENT: each assert stands alone.
        "checks": [
            "assert flatten([1,[2,[3,4],5]]) == [1,2,3,4,5]",
            "assert flatten([]) == []",
            "assert flatten([[],[1],[[2]]]) == [1,2]",
        ],
    },
    {
        "id": "is_balanced",
        "symbol": "is_balanced",
        "prompt": (
            "Write a Python function `is_balanced(s: str) -> bool` that returns True iff the "
            "brackets (), [], {} in s are correctly balanced and nested. Ignore non-bracket chars. "
            "Empty string is balanced. Return ONLY Python code."
        ),
        # INDEPENDENT: each assert stands alone.
        "checks": [
            'assert is_balanced("()[]{}") is True',
            'assert is_balanced("(]") is False',
            'assert is_balanced("") is True',
            'assert is_balanced("([{}])") is True',
            'assert is_balanced("(()") is False',
        ],
    },
    # ------------------------------------------------------------------
    # From run_eval_blind.py (5 tasks)
    # `symbols` (plural) normalized to single `symbol` (first/only entry).
    # `checks` lists copied directly — they already use the correct format.
    # ------------------------------------------------------------------
    {
        "id": "longctx_bugfix",
        "symbol": "chunk_list",
        "prompt": (
            "Below is a Python module containing many functions. Exactly one function, "
            "`chunk_list(lst, size)`, is BUGGY. Its spec: split `lst` into consecutive chunks "
            "of length `size`; the final chunk may be shorter; if `size <= 0` raise ValueError. "
            "Find it and return ONLY the corrected `chunk_list` function (no other functions).\n\n"
            "```python\n" + _module + "\n```"
        ),
        "checks": [
            "assert chunk_list([1,2,3,4,5],2) == [[1,2],[3,4],[5]]",
            "assert chunk_list([1,2,3,4],2) == [[1,2],[3,4]]",
            "assert chunk_list([],3) == []",
            "r=False\ntry:\n chunk_list([1],0)\nexcept ValueError:\n r=True\nassert r",
            "r=False\ntry:\n chunk_list([1],-2)\nexcept ValueError:\n r=True\nassert r",
        ],
    },
    {
        "id": "constraint_price",
        "symbol": "price_after_tax",
        "prompt": (
            "Implement `price_after_tax(amount, rate=0.0)` honoring ALL of these rules: "
            "(1) if amount is None, raise TypeError; "
            "(2) if amount is a numeric string like '100', coerce to float; if it's a non-numeric string, raise ValueError; "
            "(3) if amount < 0 or rate < 0, raise ValueError; "
            "(4) compute amount*(1+rate) and round to 2 decimals; "
            "(5) always return a float. Return ONLY Python code."
        ),
        "checks": [
            "assert price_after_tax(100, 0.07) == 107.0",
            "assert price_after_tax('100', 0.1) == 110.0",
            "assert isinstance(price_after_tax(50), float)",
            "r=False\ntry:\n price_after_tax(None)\nexcept TypeError:\n r=True\nassert r",
            "r=False\ntry:\n price_after_tax(-5)\nexcept ValueError:\n r=True\nassert r",
            "r=False\ntry:\n price_after_tax('abc')\nexcept ValueError:\n r=True\nassert r",
        ],
    },
    {
        "id": "constraint_passwd",
        "symbol": "validate_password",
        "prompt": (
            "Implement `validate_password(pw) -> list[str]` returning error codes (empty list if valid). "
            "Rules, and you MUST return codes in EXACTLY this order when multiple apply: "
            "length < 8 -> 'too_short'; no uppercase letter -> 'no_upper'; no lowercase letter -> 'no_lower'; "
            "no digit -> 'no_digit'; no character from !@#$%^&* -> 'no_special'; contains any whitespace -> 'has_space'. "
            "Return ONLY Python code."
        ),
        "checks": [
            "assert validate_password('Abcdef1!') == []",
            "assert validate_password('abc') == ['too_short','no_upper','no_digit','no_special']",
            "assert validate_password('ABCDEFG1!') == ['no_lower']",
            "assert validate_password('Abcdef 1!') == ['has_space']",
            "assert validate_password('Abcdefgh') == ['no_digit','no_special']",
        ],
    },
    {
        "id": "ambiguous_snake",
        "symbol": "to_snake_case",
        "prompt": (
            "Implement `to_snake_case(s: str) -> str` that converts camelCase, PascalCase, kebab-case, "
            "and space-separated strings into snake_case, handling acronyms reasonably. Return ONLY Python code."
        ),
        "checks": [
            "assert to_snake_case('camelCase') == 'camel_case'",
            "assert to_snake_case('PascalCase') == 'pascal_case'",
            "assert to_snake_case('kebab-case') == 'kebab_case'",
            "assert to_snake_case('hello world') == 'hello_world'",
            "assert to_snake_case('already_snake') == 'already_snake'",
            "assert to_snake_case('getHTTPResponse') in ('get_http_response','get_h_t_t_p_response')",
        ],
    },
    {
        "id": "longout_matrix",
        "symbol": "Matrix",
        "prompt": (
            "Implement a `Matrix` class with: `__init__(self, rows)` (rows is a list of equal-length lists); "
            "`.shape` property -> (n_rows, n_cols); `.transpose()` -> new Matrix; "
            "`__eq__` comparing contents; `__add__` doing elementwise add (raise ValueError on shape mismatch); "
            "`__mul__` doing matrix multiplication (raise ValueError on incompatible shapes). Return ONLY Python code."
        ),
        "checks": [
            "assert Matrix([[1,2],[3,4]]).shape == (2,2)",
            "assert Matrix([[1,2],[3,4]]).transpose() == Matrix([[1,3],[2,4]])",
            "assert (Matrix([[1,2]]) + Matrix([[3,4]])) == Matrix([[4,6]])",
            "assert (Matrix([[1,2],[3,4]]) * Matrix([[1,0],[0,1]])) == Matrix([[1,2],[3,4]])",
            "r=False\ntry:\n Matrix([[1,2]]) + Matrix([[1,2,3]])\nexcept ValueError:\n r=True\nassert r",
            "r=False\ntry:\n Matrix([[1,2]]) * Matrix([[1,2]])\nexcept ValueError:\n r=True\nassert r",
        ],
    },
]
