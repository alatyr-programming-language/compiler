## e2e — IR-38 (#1786 cause 4): `deref(q)` read WHOLE where `q` is a local whose declaration spells no
## type. The pointee is the type sema recorded for the `deref` node (docs/ir.md §3.8 item 8), resolved to
## the layout the builder uses; with no record the read is refused, never guessed (D6).
##   * `q := get(p)`: an inferred local holding a call's `ptr(mut S)`;
##   * `q := ptr(s)`: an inferred local holding the address of a struct local.
## A read is a COPY (Memory §4.3): the write through `p` after it leaves `v` as read. The enum pointee
## is in `test/ir38_deref_recorded_enum.al`. Each check answers its own code when it fails; 42 when all
## held.
S := struct { a : u64, b : u64 }

get := fn(p : ptr(mut S)) -> ptr(mut S) { p }

via_call := fn(p : ptr(mut S)) -> u64 {
  q := get(p)
  v := deref(q)
  p.a = 90
  v.a * 10 + v.b
}
via_addr := fn(k : u64) -> u64 {
  s := S(a = k, b = 4)
  q := ptr(s)
  v := deref(q)
  v.a + v.b
}

main := fn() -> u64 {
  mut s := S(a = 3, b = 5)
  if via_call(ptr(mut s)) != 35 { return 1 }
  if s.a != 90 { return 2 }
  if via_addr(3) != 7 { return 3 }
  42
}
## expect: run 42
