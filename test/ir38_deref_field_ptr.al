## e2e — IR-38 (#1786 cause 4): `deref(h.p)` read WHOLE where the pointer is a struct FIELD. A field is
## not a declaration the operand names, so the pointee is the one sema recorded for the `deref` node: the
## field's declared `ptr(S)` (docs/ir.md §3.8 item 8).
##   * `h.p` of a struct value `h : H`;
##   * `hp.p` through `hp : ptr(H)` (auto-deref, Modules §2).
## The enum pointee is in `test/ir38_deref_recorded_enum.al`. Each check answers its own code when it
## fails; 42 when all held.
S := struct { a : u64, b : u64 }
H := struct { p : ptr(S), k : u64 }

by_value := fn(h : H) -> u64 {
  v := deref(h.p)
  v.a + v.b + h.k
}
by_ptr := fn(hp : ptr(H)) -> u64 {
  v := deref(hp.p)
  v.a * 10 + v.b
}

main := fn() -> u64 {
  mut s := S(a = 4, b = 2)
  mut h := H(p = ptr(s), k = 36)
  if by_ptr(ptr(h)) != 42 { return 1 }
  if by_value(h) != 42 { return 2 }
  42
}
## expect: run 42
