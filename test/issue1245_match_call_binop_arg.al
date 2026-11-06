## e2e / issue #1245 — `match` whose SCRUTINEE is a call with a binary-expression argument.
##
## The program is valid (Expressions: `match` on any expression of enum type; Functions §5.1 supplies
## every argument). The compiler crashed on it: `emit_match_stmt` stages a call-returned enum through
## `emit_enum_value(scrut, sb, cx, a, nl)`, and both of its call sites in the call-scrutinee branch
## (`src/lower.al:25475`, `:25478`) omitted the trailing `in out nl`. Because `emit_enum_value` is
## declared LATER in the file, sema's arity check never fired on the forward reference, so `nl` reached
## the callee as a NULL pointer. It stayed dormant until the argument `i + 5` routed to an overloaded
## operator: `emit_gas` → `emit_inline_binop` → `emit_inline_body`, whose first act is `iend := nl` —
## a load through the null pointer, and the compiler died with SIGSEGV (exit 139, no diagnostic).
##
## Each check owns a code from 10 up; 42 means all held. (1) is the issue's own repro. (2) is a second
## binary shape, so the fix is not tied to `+`. (3) takes the `None` side, so a route that always
## answered `Some` is caught. (4) is the control the issue reports as already working: the same call
## bound to a local first, which reaches `emit_enum_value` through a `Var`, not a `Call`.
##
## Parent 58a80376 (x86_64, omen): the BUILD crashes — `alatyr -o x.bin` exits 139 with no diagnostic.
g := fn(x : u64) -> Option(u64) { Option(u64).Some(x) }
gn := fn(x : u64) -> Option(u64) { Option(u64).None }

main := fn() -> u64 {
  mut i : u64 = 2
  mut ok : u64 = 0

  ## (1) the issue's repro — the scrutinee is the call, its argument a binary expression
  match g(i + 5) {
    Option::Some(x) => { if x != 7 { return 10 } }
    Option::None => { return 11 }
  }

  ## (2) a second binary shape over the same local: `i * 3 + 1` is 7
  match g(i * 3 + 1) {
    Option::Some(x) => { if x != 7 { return 12 } }
    Option::None => { return 13 }
  }

  ## (3) the `None` side of the same shape
  match gn(i + 5) {
    Option::Some(x) => { return 14 }
    Option::None => { ok = 1 }
  }
  if ok != 1 { return 15 }

  ## (4) control — the same call bound to a local first (the path that already worked)
  o := g(i + 5)
  match o {
    Option::Some(x) => { if x != 7 { return 16 } }
    Option::None => { return 17 }
  }

  return 42
}
## expect: run 42
