## Issue #414 / Declarations §6.2 — the modifier does not buy a second binding. `comptime x := 5`
## followed by `x := 7` in the SAME statement list is the sequential shape `test/issue268_comptime_rebind.al`
## used to spell before #414; §6.2 admits exactly one exception (function overloading by signature,
## Functions §1.4 / FN-7) and a comptime binding is not it. #268's own subject — the comptime binding
## carrying its real value rather than 0 — is unaffected and stays measured by that fixture.
seq := fn() -> u64 {
  comptime x := 5
  x := 7
  return x
}

main := fn() -> u64 { return seq() }
