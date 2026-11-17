## #1719 — a call to a program-declared fn named like a prelude intrinsic, with an argument that
## declaration does not accept. Whether `len` here shadows the prelude's `len` or joins its overload set
## is undecided (spec#166): under shadowing the call is ill-formed (a `str` is not a `u64`), under
## overloading it is the prelude's `len` and answers 42. It is never a call of `len(x : u64)` on the
## str's first word, which is what it compiled to after #1434 (native x86_64: an address-dependent
## value, 86 when measured, no diagnostic; the parent 263da9f6 answered 42 through the intrinsic).
## Until spec#166 is decided it is refused, at the argument.
len := fn(x : u64) -> u64 { x }
main := fn() -> u64 {
  s := "abcd"
  len(s) + 38
}
## expect: reject "type mismatch" "at line 11"
