## fmt — a typed local binding `name : T = v` re-emits WITH its `: T` annotation (was dropped to
## `name := v`), while an untyped `:=` binding stays `:=` (§5 tooling). Idempotent + still runs: 42.
main := fn() -> u64 {
  a : u64 = 40
  b := 2
  return a + b
}
