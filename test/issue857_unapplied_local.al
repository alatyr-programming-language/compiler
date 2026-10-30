## Issue #857 / Comptime §10 + Types §6.2 — a bare type function in a LOCAL annotation (`x : Option = …`) is not a
## `type`; it was accepted and compiled.
main := fn() -> u64 {
  x : Option = Option(u64).None
  0
}
## expect: reject "type function `Option` is not a type until it is applied" "at line 4 in issue857_unapplied_local"
