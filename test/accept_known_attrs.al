## e2e — the ACCEPT sibling covering the §2.3 BUILT-IN families in declaration-prefix position:
## layout (`@packed`/`@align`), codegen (`@inline`), storage (`@section`). None of these may be
## turned away by the unknown-attribute check, and the layout ones must still be HONOURED (the
## sizes below), not merely tolerated.
@packed
Pk := struct { a : u8, b : u32 }

@align(16)
Al := struct { a : u8 }

@inline
helper := fn(x : i64) -> i64 {
  return x + 1
}

@section("mysec")
mut G : i64 = 1

main := fn() -> i64 {
  if Pk.size() != 5 { return 1 }
  if Al.align() != 16 { return 2 }
  if helper(0) != 1 { return 3 }
  return 42
}
