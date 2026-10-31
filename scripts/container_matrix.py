#!/usr/bin/env python3
"""The container matrix (#1124): element shape x container x operation, generated and run.

Each cell is one program under target/ that stores known values in a library container, reads them
back and exits 42 only if every read equals what was stored. A failed check exits with its own code
in 10..99 (never 42), so a wrong value is told apart from a trap. The programs are generated, never
committed: this script is their only source.

  container_matrix.py --gen DIR                 write every cell's program into DIR
  container_matrix.py --run CC DIR [--jobs N]   generate, build each cell with CC, run it, print one
                                                verdict line per cell, then the summary
  container_matrix.py --gate CC DIR             --run, then hold the verdicts against the deviations
                                                list (scripts/container-matrix.deviations.tsv)
  container_matrix.py --self-test CC DIR        prove --gate can fail: a planted defect must turn it red

Verdicts, one line per cell: `OK`, `WRONG <check>`, `TRAP 132`, `CRASH <rc>`, `REFUSED <first error line>`.
  OK       the program exited 42: every read equalled what was stored
  WRONG    the program exited with a check code (10..99): a read differed from what was stored
  TRAP     the program stopped on the checked-failure instruction, the language's only trap (per-arch
           appendix §2, CG-13: `ud2` on x86_64, which the kernel reports as SIGILL, rc 132)
  CRASH    the program stopped any other way: another signal (a segfault is 139), a timeout, or an exit
           code that is neither 42 nor a check code. The spec defines no such failure (I11), so it is
           a defect, never a trap (#1277)
  REFUSED  the compiler did not build the program (a located rejection or a compiler failure)

The gate (x86_64): every WRONG, CRASH and REFUSED cell needs a row in the deviations list naming an
open issue, and every row must still reproduce (same cell, same verdict), so the fix that makes a cell
pass deletes its row. A TRAP is a recorded outcome, never a failure on its own: a checked bounds
failure is the specified answer of some cells (an out-of-range index).
"""
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
DEVIATIONS = os.path.join(HERE, "container-matrix.deviations.tsv")
# The exit status of the language's trap on x86_64: `ud2` raises SIGILL (4), and the shell's and
# subprocess's convention is 128 + the signal. Every other way to stop is a CRASH (#1277).
TRAP_RC = 128 + 4
N = 20  # elements stored per cell: more than every container's initial capacity, so the cells grow

PRELUDE = """\
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
"""

ARENA = """\
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 1048576, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 1048576)
"""

# ---------------------------------------------------------------------------------------------------
# Element shapes. Each gives its type `T`, top-level declarations, `val(k)` (a known value per key k,
# distinct over a key's residues) and `same(x, y)` (field-wise equality written out, so the check does
# not lean on a derive the cell is not about). `hashable` marks the shapes the hashmap takes as a key.
# ---------------------------------------------------------------------------------------------------
SHAPES = {}


def shape(name, ty, val, same="x == y", decls="", hashable=True):
    SHAPES[name] = dict(ty=ty, val=val, same=same, decls=decls, hashable=hashable)


shape("u8", "u8", "u8(150 + k % 100)")
shape("u16", "u16", "u16(60000 + k % 5000)")
shape("u32", "u32", "u32(4000000000 + k % 100000)")
shape("u64", "u64", "k * 1000000007 + 9")
shape("i8", "i8", "0 - i8(k % 100) - 20")
shape("i64", "i64", "0 - i64(k) * 1000000007 - 5")
shape("bool", "bool", "k % 3 == 1")
shape("f64", "f64", "f64(k) * 1.5 + 0.25", hashable=False)
shape("char", "char",
      """{
  m := k % 4
  if m == 0 { return char(97) }
  if m == 1 { return char(945) }
  if m == 2 { return char(8364) }
  char(128512)
}""")
shape("str", "str",
      """{
  m := k % 4
  if m == 0 { return "alpha" }
  if m == 1 { return "" }
  if m == 2 { return "gamma-delta-epsilon" }
  "z"
}""")
shape("struct1", "S1", "S1(a = k * 3 + 1)", "x.a == y.a", "S1 := struct { a : u64 }\n")
shape("struct2", "S2", "S2(a = k * 5 + 2, b = u32(4000000000 + k % 1000))", "x.a == y.a and x.b == y.b",
      "S2 := struct { a : u64, b : u32 }\n")
shape("struct3", "S3", "S3(a = k * 7 + 3, b = 0 - k, c = u8(200 + k % 50))",
      "x.a == y.a and x.b == y.b and x.c == y.c", "S3 := struct { a : u64, b : u64, c : u8 }\n")
shape("enum0", "E0",
      """{
  m := k % 3
  if m == 0 { return E0.Red }
  if m == 1 { return E0.Green }
  E0.Blue
}""", "e0tag(x) == e0tag(y)",
      """E0 := enum { Red, Green, Blue }
e0tag := fn(e : E0) -> u64 {
  match e {
    E0::Red => { return 1 }
    E0::Green => { return 2 }
    E0::Blue => { return 3 }
  }
}
""")
shape("enumN", "EN",
      """{
  m := k % 3
  if m == 0 { return EN.A(k * 11 + 1) }
  if m == 1 { return EN.B(u8(k % 200), 0 - i64(k) - 9) }
  EN.C
}""", "enkey(x) == enkey(y) and enb(x) == enb(y)",
      # Two keys, not one sum: a negative i64 payload bitcast to u64 plus anything overflows, and
      # checked arithmetic traps (that trap was the control cell's own defect, not the compiler's).
      """EN := enum { A(u64), B(u8, i64), C }
enkey := fn(e : EN) -> u64 {
  match e {
    EN::A(x) => { return x * 4 + 1 }
    EN::B(b, c) => { return u64(b) * 4 + 2 }
    EN::C => { return 3 }
  }
}
enb := fn(e : EN) -> i64 {
  match e {
    EN::A(x) => { return 0 }
    EN::B(b, c) => { return c }
    EN::C => { return 0 }
  }
}
""")
shape("option_u64", "Option(u64)",
      """{
  if k % 4 == 0 { return Option(u64).None }
  Option(u64).Some(k * 13 + 7)
}""", "optkey(x) == optkey(y)",
      """optkey := fn(o : Option(u64)) -> u64 {
  match o {
    Option::Some(v) => { return v * 2 + 1 }
    Option::None => { return 0 }
  }
}
""")
shape("option_ptr", "Option(ptr(u64))",
      """{
  if k % 4 == 0 { return Option(ptr(u64)).None }
  Option(ptr(u64)).Some(unchecked bitcast(ptr(u64), usize(4096 + k * 8)))
}""", "optpkey(x) == optpkey(y)",
      """optpkey := fn(o : Option(ptr(u64))) -> usize {
  match o {
    Option::Some(p) => { return unchecked bitcast(usize, p) }
    Option::None => { return 1 }
  }
}
""")
shape("brand", "Br", "Br(k * 17 + 4)", "u64(x) == u64(y)", "Br := brand(u64)\n")
shape("array3", "[u32; 3]", "[u32(k), u32(k % 1000) * 7 + 1, u32(4000000000 + k % 1000)]",
      "x[0] == y[0] and x[1] == y[1] and x[2] == y[2]", hashable=False)


def shape_src(sh):
    s = SHAPES[sh]
    ty = s["ty"]
    val = s["val"]
    body = val if val.startswith("{") else "{ " + val + " }"
    return (s["decls"]
            + f"val := fn(k : u64) -> {ty} {body}\n"
            + f"same := fn(x : {ty}, y : {ty}) -> bool {{ {s['same']} }}\n")


# ---------------------------------------------------------------------------------------------------
# Operations. Each is the body of `main` after the arena, as a template over `T` (the element type).
# Check codes: every `return` in a body is a distinct code in 10..99.
# ---------------------------------------------------------------------------------------------------
FILL_VEC = f"""\
  mut v := vec::new(T, ptr(ar))
  mut i : u64 = 0
  while i < {N} {{
    p := vec::push(T, v, val(i))
    i += 1
  }}
"""

OPS = {}


def op(container, name, body, needs=None):
    OPS[(container, name)] = dict(body=body, needs=needs)


# The control: no container. A shape whose control is not OK says nothing about the containers.
op("none", "control", f"""\
  mut i : u64 = 0
  while i < {N} {{
    x := val(i)
    if not same(x, val(i)) {{ return 10 }}
    if not same(pass(x), val(i)) {{ return 11 }}
    i += 1
  }}
  mut y := val(3)
  y = val(5)
  if not same(y, val(5)) {{ return 12 }}
""")

op("vec", "push_at", FILL_VEC + f"""\
  i = 0
  while i < {N} {{
    if not same(vec::at(T, ptr(v), i), val(i)) {{ return 10 }}
    i += 1
  }}
""")
op("vec", "len", FILL_VEC + f"""\
  if vec::len(T, ptr(v)) != {N} {{ return 10 }}
  q := vec::pop(T, v)
  if vec::len(T, ptr(v)) != {N - 1} {{ return 11 }}
""")
op("vec", "index_read", FILL_VEC + f"""\
  i = 0
  while i < {N} {{
    if not same(v[i], val(i)) {{ return 10 }}
    i += 1
  }}
""")
op("vec", "index_write", FILL_VEC + f"""\
  i = 0
  while i < {N} {{
    k := i + 100
    v[i] = val(k)
    i += 1
  }}
  i = 0
  while i < {N} {{
    k := i + 100
    if not same(vec::at(T, ptr(v), i), val(k)) {{ return 10 }}
    i += 1
  }}
""")
op("vec", "set", FILL_VEC + f"""\
  i = 0
  while i < {N} {{
    k := i + 100
    vec::set(T, v, i, val(k))
    i += 1
  }}
  i = 0
  while i < {N} {{
    k := i + 100
    if not same(vec::at(T, ptr(v), i), val(k)) {{ return 10 }}
    i += 1
  }}
""")
op("vec", "try_at", FILL_VEC + f"""\
  i = 0
  while i < {N} {{
    o1 := vec::try_at(T, ptr(v), i)
    match o1 {{
      Option::Some(x) => {{ if not same(x, val(i)) {{ return 10 }} }}
      Option::None => {{ return 11 }}
    }}
    i += 1
  }}
  o2 := vec::try_at(T, ptr(v), {N})
  match o2 {{
    Option::Some(x) => {{ return 12 }}
    Option::None => {{}}
  }}
""")
op("vec", "get", FILL_VEC + f"""\
  i = 0
  while i < {N} {{
    o3 := vec::get(T, ptr(v), i)
    match o3 {{
      Option::Some(x) => {{ if not same(x, val(i)) {{ return 10 }} }}
      Option::None => {{ return 11 }}
    }}
    i += 1
  }}
  o4 := vec::get(T, ptr(v), {N})
  match o4 {{
    Option::Some(x) => {{ return 12 }}
    Option::None => {{}}
  }}
""")
op("vec", "pop", FILL_VEC + f"""\
  i = {N}
  while i > 0 {{
    i -= 1
    o5 := vec::pop(T, v)
    match o5 {{
      Option::Some(x) => {{ if not same(x, val(i)) {{ return 10 }} }}
      Option::None => {{ return 11 }}
    }}
  }}
  o6 := vec::pop(T, v)
  match o6 {{
    Option::Some(x) => {{ return 12 }}
    Option::None => {{}}
  }}
""")
op("vec", "grow", f"""\
  mut v := vec::with_capacity(T, ptr(ar), 1)
  mut i : u64 = 0
  while i < {N} {{
    p := vec::push(T, v, val(i))
    i += 1
  }}
  if vec::len(T, ptr(v)) != {N} {{ return 10 }}
  i = 0
  while i < {N} {{
    if not same(vec::at(T, ptr(v), i), val(i)) {{ return 11 }}
    i += 1
  }}
""")
op("vec", "for_in", FILL_VEC + f"""\
  i = 0
  for x in vec::iter(T, ptr(v)) {{
    if not same(x, val(i)) {{ return 10 }}
    i += 1
  }}
  if i != {N} {{ return 11 }}
""")
op("vec", "range", FILL_VEC + f"""\
  s := v[3..9]
  if s.len != 6 {{ return 10 }}
  i = 0
  while i < 6 {{
    k := i + 3
    if not same(s[i], val(k)) {{ return 11 }}
    i += 1
  }}
  t := vec::index_range(T, ptr(v), 0, {N})
  if t.len != {N} {{ return 12 }}
  if not same(t[{N - 1}], val({N - 1})) {{ return 13 }}
""")
op("vec", "ufcs", FILL_VEC + f"""\
  if v.len() != {N} {{ return 10 }}
  i = 0
  while i < {N} {{
    if not same(v.at(i), val(i)) {{ return 11 }}
    i += 1
  }}
  p := v.push(val(77))
  if not same(v.at({N}), val(77)) {{ return 12 }}
""")

FILL_DQ = f"""\
  mut d := deque::deque(T, ptr(ar), 2)
  mut i : u64 = 0
  while i < {N} {{
    p := deque::push_back(T, d, val(i))
    i += 1
  }}
"""
op("deque", "push_back_at", FILL_DQ + f"""\
  if deque::dq_len(T, ptr(d)) != {N} {{ return 10 }}
  i = 0
  while i < {N} {{
    o7 := deque::dq_at(T, ptr(d), i)
    match o7 {{
      Option::Some(x) => {{ if not same(x, val(i)) {{ return 11 }} }}
      Option::None => {{ return 12 }}
    }}
    i += 1
  }}
""")
op("deque", "push_front", f"""\
  mut d := deque::deque(T, ptr(ar), 2)
  mut i : u64 = 0
  while i < {N} {{
    p := deque::push_front(T, d, val(i))
    i += 1
  }}
  i = 0
  while i < {N} {{
    o8 := deque::dq_at(T, ptr(d), i)
    k := {N - 1} - i
    match o8 {{
      Option::Some(x) => {{ if not same(x, val(k)) {{ return 10 }} }}
      Option::None => {{ return 11 }}
    }}
    i += 1
  }}
""")
op("deque", "pop_front", FILL_DQ + f"""\
  i = 0
  while i < {N} {{
    o9 := deque::pop_front(T, d)
    match o9 {{
      Option::Some(x) => {{ if not same(x, val(i)) {{ return 10 }} }}
      Option::None => {{ return 11 }}
    }}
    i += 1
  }}
  o10 := deque::pop_front(T, d)
  match o10 {{
    Option::Some(x) => {{ return 12 }}
    Option::None => {{}}
  }}
""")
op("deque", "pop_back", FILL_DQ + f"""\
  i = {N}
  while i > 0 {{
    i -= 1
    o11 := deque::pop_back(T, d)
    match o11 {{
      Option::Some(x) => {{ if not same(x, val(i)) {{ return 10 }} }}
      Option::None => {{ return 11 }}
    }}
  }}
""")
op("deque", "front_back", FILL_DQ + f"""\
  o12 := deque::front(T, ptr(d))
  match o12 {{
    Option::Some(x) => {{ if not same(x, val(0)) {{ return 10 }} }}
    Option::None => {{ return 11 }}
  }}
  o13 := deque::back(T, ptr(d))
  match o13 {{
    Option::Some(x) => {{ if not same(x, val({N - 1})) {{ return 12 }} }}
    Option::None => {{ return 13 }}
  }}
""")

op("hashmap", "value", f"""\
  mut m := hashmap::new(u64, T, ptr(ar))
  mut i : u64 = 0
  while i < {N} {{
    key := i * 31 + 5
    p := hashmap::insert(u64, T, ptr(m), ar, key, val(i))
    i += 1
  }}
  if hashmap::len(u64, T, ptr(m), ar) != {N} {{ return 10 }}
  i = 0
  while i < {N} {{
    key := i * 31 + 5
    o14 := hashmap::get(u64, T, ptr(m), ar, key)
    match o14 {{
      Option::Some(x) => {{ if not same(x, val(i)) {{ return 11 }} }}
      Option::None => {{ return 12 }}
    }}
    i += 1
  }}
  o15 := hashmap::remove(u64, T, ptr(m), ar, 5)
  match o15 {{
    Option::Some(x) => {{ if not same(x, val(0)) {{ return 13 }} }}
    Option::None => {{ return 14 }}
  }}
  o16 := hashmap::get(u64, T, ptr(m), ar, 5)
  match o16 {{
    Option::Some(x) => {{ return 15 }}
    Option::None => {{}}
  }}
""")
op("hashmap", "key", f"""\
  mut m := hashmap::new(T, u64, ptr(ar))
  mut i : u64 = 0
  while i < {N} {{
    p := hashmap::insert(T, u64, ptr(m), ar, val(i), i)
    i += 1
  }}
  i = 0
  while i < {N} {{
    o17 := hashmap::get(T, u64, ptr(m), ar, val(i))
    match o17 {{
      Option::Some(x) => {{ if not same(val(x), val(i)) {{ return 10 }} }}
      Option::None => {{ return 11 }}
    }}
    if not hashmap::contains(T, u64, ptr(m), ar, val(i)) {{ return 12 }}
    i += 1
  }}
""", needs="hashable")


def cells():
    for (cont, opn), o in sorted(OPS.items()):
        for sh in SHAPES:
            if o["needs"] and not SHAPES[sh][o["needs"]]:
                continue
            yield f"{cont}.{opn}.{sh}", cont, opn, sh


def program(cont, opn, sh):
    ty = SHAPES[sh]["ty"]
    imports = {"vec": "vec := alloc::vec\n", "deque": "deque := alloc::deque\n",
               "hashmap": "hashmap := alloc::hashmap\n"}.get(cont, "")
    body = OPS[(cont, opn)]["body"].replace("(T,", f"({ty},").replace(", T,", f", {ty},") \
        .replace(", T)", f", {ty})")
    return (f"## generated by scripts/container_matrix.py (#1124): cell {cont}.{opn}.{sh}\n"
            + imports + PRELUDE + shape_src(sh)
            + f"pass := fn(x : {ty}) -> {ty} {{ x }}\n"
            + "main := fn() -> u64 {\n" + ARENA + body + "  42\n}\n")


def gen(d):
    os.makedirs(d, exist_ok=True)
    out = []
    for cid, cont, opn, sh in cells():
        p = os.path.join(d, cid + ".al")
        with open(p, "w") as f:
            f.write(program(cont, opn, sh))
        out.append((cid, p))
    return out


def run_cell(cc, cid, src, timeout=20):
    # `alatyr build` writes a file's artifact to <target-dir>/debug/<stem>; one target dir per cell, so
    # parallel builds never share one.
    stem = os.path.basename(src)[:-3]
    td = src[:-3] + ".td"
    exe = os.path.join(td, "debug", stem)
    try:
        b = subprocess.run([cc, "build", "-q", "--target-dir", td, src], capture_output=True, text=True,
                           timeout=120)
    except subprocess.TimeoutExpired:
        return cid, "REFUSED compiler timeout"
    if b.returncode < 0 or b.returncode >= 128:
        rc = 128 - b.returncode if b.returncode < 0 else b.returncode
        return cid, f"REFUSED compiler crash rc {rc}"
    if b.returncode != 0 or not os.path.exists(exe):
        lines = [l for l in (b.stderr + b.stdout).splitlines() if l.strip()]
        first = next((l for l in lines if "error" in l.lower() or "selfhost" in l.lower()),
                     lines[0] if lines else f"rc {b.returncode}")
        return cid, "REFUSED " + first.strip()[:160].replace("\t", " ")
    try:
        r = subprocess.run([exe], capture_output=True, timeout=timeout)
        rc = r.returncode
    except subprocess.TimeoutExpired:
        return cid, "CRASH timeout"
    if rc < 0:
        rc = 128 - rc
    if rc == 42:
        return cid, "OK"
    if 10 <= rc <= 99:
        return cid, f"WRONG {rc}"
    if rc == TRAP_RC:
        return cid, f"TRAP {rc}"
    return cid, f"CRASH {rc}"


def run(cc, d, jobs):
    srcs = gen(d)
    with ThreadPoolExecutor(max_workers=jobs) as ex:
        res = list(ex.map(lambda a: run_cell(cc, *a), srcs))
    for cid, v in res:
        print(f"cell {cid}\t{v}")
    counts = {}
    for _, v in res:
        k = v.split()[0]
        counts[k] = counts.get(k, 0) + 1
    print("container matrix: cells=%d " % len(res)
          + " ".join(f"{k}={counts.get(k, 0)}" for k in ("OK", "WRONG", "TRAP", "CRASH", "REFUSED")))
    return dict(res)


def load_deviations(path):
    rows = {}
    with open(path) as f:
        for ln, line in enumerate(f, 1):
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 4 or not parts[3].startswith("#") or not parts[3][1:].isdigit():
                raise SystemExit(f"{path}:{ln}: want `backend<TAB>cell<TAB>verdict<TAB>#issue`, got {line!r}")
            be, cid, verdict, issue = parts
            if not (verdict == "REFUSED" or (verdict.startswith("WRONG ") and verdict[6:].isdigit())
                    or (verdict.startswith("CRASH ") and (verdict[6:].isdigit() or verdict[6:] == "timeout"))):
                raise SystemExit(f"{path}:{ln}: the verdict is `WRONG <code>`, `CRASH <rc>` or `REFUSED`, "
                                 f"got {verdict!r}")
            if (be, cid) in rows:
                raise SystemExit(f"{path}:{ln}: duplicate row for {be} {cid}")
            rows[(be, cid)] = (verdict, issue)
    return rows


# The verdicts the gate holds: each needs a row under an open issue. A TRAP and an OK are not held.
HELD = ("WRONG", "CRASH", "REFUSED")
HELD_WITH_CODE = ("WRONG", "CRASH")


def key(v):
    """What a row holds of a verdict: `WRONG <code>`, `CRASH <rc>` or `REFUSED`. A refusal's message is
    for the reader and is not held: it carries absolute paths (the linker's) and changes with unrelated
    wording."""
    parts = v.split()
    return " ".join(parts[:2]) if parts[0] in HELD_WITH_CODE else parts[0]


def hold(res, rows, backend="x86_64"):
    """The gate's rule. Returns the failure lines (empty = green)."""
    bad = []
    for cid, v in sorted(res.items()):
        kind = v.split()[0]
        row = rows.get((backend, cid))
        if kind in HELD:
            if row is None:
                bad.append(f"UNLISTED {cid}: {v} (file it, then add `{backend}\t{cid}\t{key(v)}\t#N`)")
            elif row[0] != key(v):
                bad.append(f"CHANGED {cid}: listed `{row[0]}` ({row[1]}), observed `{v}`")
        elif row is not None:
            bad.append(f"STALE {cid}: listed `{row[0]}` ({row[1]}), observed `{v}` - the fix deletes its row")
    for (be, cid), (verdict, issue) in sorted(rows.items()):
        if be == backend and cid not in res:
            bad.append(f"UNKNOWN {cid}: listed `{verdict}` ({issue}) but no such cell")
    return bad


def gate(cc, d, jobs, dev_path=DEVIATIONS):
    res = run(cc, d, jobs)
    bad = hold(res, load_deviations(dev_path))
    if not res:
        bad.append("NO CELLS: the generator produced nothing, and nothing compared is not green")
    for b in bad:
        print("FAIL " + b)
    if bad:
        print(f"*** container matrix: RED ({len(bad)} failure(s)) ***")
        return 1
    print("*** container matrix: GREEN ***")
    return 0


def self_test(cc, d, jobs):
    """A planted defect must turn the gate red, and the healthy cells it planted beside must not."""
    fails = 0

    def expect(name, cond):
        nonlocal fails
        print(("ok   " if cond else "FAIL ") + "container matrix self-test: " + name)
        fails += 0 if cond else 1

    # 1. The rule over verdicts, on planted results.
    rows = {("x86_64", "vec.at.u8"): ("WRONG 10", "#1")}
    expect("an unlisted WRONG fails", any(b.startswith("UNLISTED") for b in hold({"vec.x.u8": "WRONG 10"}, {})))
    expect("an unlisted REFUSED fails", any(b.startswith("UNLISTED") for b in hold({"vec.x.u8": "REFUSED e"}, {})))
    expect("a listed REFUSED passes whatever its message",
           hold({"vec.r.u8": "REFUSED /abs/path ld: x"}, {("x86_64", "vec.r.u8"): ("REFUSED", "#1")}) == [])
    expect("a listed WRONG passes", hold({"vec.at.u8": "WRONG 10"}, rows) == [])
    expect("a listed cell now OK is STALE", any(b.startswith("STALE") for b in hold({"vec.at.u8": "OK"}, rows)))
    expect("a listed cell with another verdict fails",
           any(b.startswith("CHANGED") for b in hold({"vec.at.u8": "WRONG 11"}, rows)))
    expect("a row naming no cell fails", any(b.startswith("UNKNOWN") for b in hold({}, rows)))
    expect("TRAP and OK pass unlisted", hold({"a": "TRAP 132", "b": "OK"}, {}) == [])
    # A crash is a defect, never the specified trap (#1277): an OK cell that starts to segfault, time out
    # or exit with no check code must turn the gate red unless a row lists it under an open issue.
    expect("an unlisted CRASH (a segfault) fails",
           any(b.startswith("UNLISTED") for b in hold({"vec.at.u8": "CRASH 139"}, {})))
    expect("an unlisted CRASH (a timeout) fails",
           any(b.startswith("UNLISTED") for b in hold({"vec.at.u8": "CRASH timeout"}, {})))
    expect("a listed CRASH passes", hold({"vec.at.u8": "CRASH 139"}, {("x86_64", "vec.at.u8"): ("CRASH 139", "#1")}) == [])
    expect("a listed CRASH that now traps is STALE (the fix deletes its row)",
           any(b.startswith("STALE") for b in hold({"vec.at.u8": "TRAP 132"},
                                                     {("x86_64", "vec.at.u8"): ("CRASH 139", "#1")})))

    # 2. The runner end to end: a planted program that stores a value and reads back another must come
    #    out WRONG, its healthy twin OK, and a program that does not build REFUSED.
    os.makedirs(d, exist_ok=True)
    plants = {
        "plant.wrong": PRELUDE + "main := fn() -> u64 {\n  x : u64 = 7\n  if x + 1 != 7 { return 10 }\n  42\n}\n",
        "plant.ok": PRELUDE + "main := fn() -> u64 {\n  x : u64 = 7\n  if x != 7 { return 10 }\n  42\n}\n",
        "plant.refused": "main := fn() -> u64 { undefined_name_1124 }\n",
        # A healthy cell that segfaults (a load from the unmapped page 8): a crash, never a trap (#1277).
        "plant.crash": PRELUDE + "main := fn() -> u64 {\n  p := unchecked bitcast(ptr(u64), usize(8))\n"
                       "  if deref(p) == 7 { return 10 }\n  42\n}\n",
        # A checked overflow on a value the compiler cannot fold: the specified trap (`ud2`).
        "plant.trap": PRELUDE + "inc := fn(x : u8) -> u8 { x + 1 }\nmain := fn() -> u64 {\n"
                      "  if inc(u8(255)) == 0 { return 10 }\n  42\n}\n",
    }
    got = {}
    for cid, src in plants.items():
        p = os.path.join(d, cid + ".al")
        with open(p, "w") as f:
            f.write(src)
        got[cid] = run_cell(cc, cid, p)[1]
    expect(f"planted wrong read is WRONG (got {got['plant.wrong']})", got["plant.wrong"] == "WRONG 10")
    expect(f"planted healthy program is OK (got {got['plant.ok']})", got["plant.ok"] == "OK")
    expect(f"planted non-building program is REFUSED (got {got['plant.refused']})",
           got["plant.refused"].startswith("REFUSED"))
    expect("the planted WRONG fails the gate", hold({"plant.wrong": got["plant.wrong"]}, {}) != [])
    expect(f"planted segfault is CRASH 139, not a trap (got {got['plant.crash']})", got["plant.crash"] == "CRASH 139")
    expect("the planted segfault fails the gate", hold({"plant.crash": got["plant.crash"]}, {}) != [])
    expect(f"planted checked overflow is TRAP 132 (got {got['plant.trap']})", got["plant.trap"] == "TRAP 132")

    # 3. The committed list parses and every row names a generated cell.
    names = {cid for cid, *_ in cells()}
    rows = load_deviations(DEVIATIONS)
    unknown = [cid for (_, cid) in rows if cid not in names]
    expect(f"every deviations row names a generated cell ({len(rows)} rows)", not unknown)
    print(f"container matrix self-test: {fails} failed")
    return 1 if fails else 0


def main(argv):
    jobs = os.cpu_count() or 4
    if "--jobs" in argv:
        i = argv.index("--jobs")
        jobs = int(argv[i + 1])
        del argv[i:i + 2]
    if len(argv) == 3 and argv[1] == "--gen":
        print(f"container matrix: generated {len(gen(argv[2]))} cells")
        return 0
    if len(argv) == 4 and argv[1] == "--run":
        run(argv[2], argv[3], jobs)
        return 0
    if len(argv) == 4 and argv[1] == "--gate":
        return gate(argv[2], argv[3], jobs)
    if len(argv) == 4 and argv[1] == "--self-test":
        return self_test(argv[2], argv[3], jobs)
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
