## #1303 — the structural `hash` (Stdlib appendix §2.6: `Hash` is consistent with `Eq`) of an enum value.
## Inside `base::derive`, the enum arm's bare `hash(p)` matched the module's concrete one-parameter
## overload for a `str` by arity alone, so a `u64` payload was passed as a `{ptr, len}` view and hashed
## as bytes behind that address; a unit variant binds no payload at all. NON-VACUOUS: on the parent
## `da18fef2` (x86_64) this program stops with SIGSEGV (rc 139). Each case must hash equal values alike.
E0 := enum { Red, Green, Blue }
EN := enum { A(u64), C }
ES := enum { S(str), N }
pick := fn(k : u64) -> E0 {
  if k == 0 { return E0.Red }
  if k == 1 { return E0.Green }
  E0.Blue
}
main := fn() -> u64 {
  ## a payload-free enum, from a literal and through a call
  if hash(E0, E0.Green) != hash(E0, E0.Green) { return 10 }
  if hash(E0, pick(1)) != hash(E0, E0.Green) { return 11 }
  ## a payload variant and a unit variant of one enum
  if hash(EN, EN.A(7)) != hash(EN, EN.A(7)) { return 12 }
  if hash(EN, EN.A(7)) == hash(EN, EN.A(8)) { return 13 }
  if hash(EN, EN.C) != hash(EN, EN.C) { return 14 }
  ## a library enum instance
  if hash(Option(u64), Option(u64).Some(3)) != hash(Option(u64), Option(u64).Some(3)) { return 15 }
  if hash(Option(u64), Option(u64).Some(3)) == hash(Option(u64), Option(u64).Some(4)) { return 16 }
  ## a `str` still reaches the content hash: two views of equal bytes hash alike
  s : str = "ab"
  t : str = "ab"
  if hash(str, s) != hash(str, t) { return 17 }
  ## a `str` payload hashes its contents through the generic arm
  if hash(ES, ES.S(s)) != hash(ES, ES.S(t)) { return 18 }
  if hash(ES, ES.S(s)) == hash(ES, ES.S("ac")) { return 19 }
  42
}
## expect: run 42
