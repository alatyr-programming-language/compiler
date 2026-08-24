## Declarations §3.1 — an annotated binding's initializer must be ASSIGNABLE to the declared type.
## No class of the Types §4.2 conversion lattice connects `str` (a two-word {ptr,len}) to an integer,
## so this is ill-formed and must be a LOCATED reject — it used to pass `check` with rc 0 and NO
## output while the built program returned a silent wrong value.
main := fn() -> u64 {
  x : u64 = "nope"
  return x
}
