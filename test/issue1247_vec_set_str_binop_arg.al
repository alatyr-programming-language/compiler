## e2e / issue #1247 — a `str`-returning call passed DIRECTLY as an argument, over a binary operand.
##
## The program is valid (Stdlib: `vec::set(T, v, i, x)` replaces element `i`; Expressions: a call is an
## expression). The compiler crashed on it. `emit_arg`'s "str-returning call passed directly as an
## argument" branch (`src/lower.al:4780`) called `emit_struct_value(e, sb, cx, a)` and omitted the
## trailing `in out nl` of its five-parameter signature. Because `emit_struct_value` is declared LATER
## in the file, sema never arity-checked the forward reference, so `nl` reached the callee as a NULL
## pointer. It stayed dormant until the argument `val(i + 100)` routed its `+` to an overloaded
## operator: `emit_gas` -> `emit_inline_binop` -> `emit_inline_body`, whose first act is `iend := nl` —
## a load through the null pointer, and the compiler died with SIGSEGV (exit 139, no diagnostic). That
## is why the issue's reduction holds: `same(val(i), val(i + 1))` builds (no `str`-call argument in a
## `while` over the `Vec(str)` instance), and changing either line alone still crashes.
##
## Each check owns a code from 10 up; 42 means all held. The read-back compares CONTENT through
## `same`, so a wrong element is a located code, never a silent pass.
##
## Parent 58a80376 (x86_64, omen): the BUILD crashes — `alatyr -o x.bin` exits 139 with no diagnostic.
vec := alloc::vec
sys_mmap := @abi(syscall) fn(num : usize, addr : usize, len : usize, prot : usize, flags : usize, fd : usize, off : usize) -> isize
val := fn(k : u64) -> str {
  m := k % 4
  if m == 0 { return "alpha" }
  if m == 1 { return "" }
  if m == 2 { return "gamma-delta-epsilon" }
  "z"
}
same := fn(x : str, y : str) -> bool { x == y }
## a str-call over a binary operand in a `return`: `emit_str_pair`'s path (`src/lower.al:6942`)
wrap := fn(k : u64) -> str { return val(k + 1) }

main := fn() -> u64 {
  r := unchecked sys_mmap(std::sysno::MMAP, 0, 1048576, 3, 34, bitcast(usize, 0 - 1), 0)
  mut ar := arena_over(unchecked bitcast(ptr(mut bits8), bitcast(usize, r)), 1048576)
  mut v := vec::new(str, ptr(ar))

  ## fill: the `str` argument is a plain call, so this loop alone builds
  mut i : u64 = 0
  while i < 20 {
    p := vec::push(str, v, val(i))
    i += 1
  }

  ## overwrite: the `str` argument is a str-returning call over a BINARY operand — the crash site
  i = 0
  while i < 20 {
    vec::set(str, v, i, val(i + 100))
    i += 1
  }

  ## read back by content, so every element must be the one `set` wrote
  i = 0
  while i < 20 {
    if not same(vec::at(str, ptr(v), i), val(i + 100)) { return 10 }
    i += 1
  }

  ## the same shape outside a loop, once at each `str` length the cell produces
  mut w := vec::new(str, ptr(ar))
  q0 := vec::push(str, w, val(7 + 100))
  q1 := vec::push(str, w, val(6 + 100))
  if not same(vec::at(str, ptr(w), 0), val(107)) { return 11 }
  if not same(vec::at(str, ptr(w), 1), val(106)) { return 12 }

  ## the second dropped argument, in `emit_str_pair` (`src/lower.al:6942`): str-calls over a binary
  ## operand as the operands of `==` (#1414's reduction) and in a `return`. With only `:4780` fixed
  ## the build still dies (rc 139); the alias `vec` above is part of the condition.
  i = 0
  while i < 20 { if val(i) == val(i + 1) { return 13 } i += 1 }
  mut eq : u64 = 0
  i = 0
  while i < 20 { if val(i) == val(i + 4) { eq += 1 } i += 1 }
  if eq != 20 { return 14 }
  i = 0
  while i < 20 {
    if not same(wrap(i), val(i + 1)) { return 15 }
    i += 1
  }

  return 42
}
## expect: run 42
