## e2e/fmt — a `comptime for <v> in typeinfo(X).fields|.variants` header keeps ITS OWN `X`.
## `Stmt::CompFor` stores only the loop-var span, the fields/variants flag, the body and `next` (the
## seed's AST-node word budget), so the ITERATED TYPE is lost — the same gap the LOWER closes with
## `compfor_iter_arg`. fmt substituted the enclosing fn's TYPE-PARAMETER instead, which was wrong
## twice over: inside a generic fn `typeinfo(B)` came back as `typeinfo(T)` — a SILENT rewrite to a
## different type — and at top level, where there is no type-param at all, fmt REFUSED the whole file
## (`comptime_typeinfo_arg`). Both spellings are pinned here, over types with DIFFERENT member counts
## so a substitution changes the answer instead of hiding in it.
## `main`'s two headers use a concrete type at TOP LEVEL, where no type-param is in scope at all.
A := struct { a : u64, b : u64 }
B := struct { p : u64, q : u64, r : u64 }
E := enum { X, Y, Z, W }

## inside a generic instance, iterate B (3 fields) — NOT the instance type A (2 fields)
cross := fn(T : type, v : T) -> u64 {
  mut d : u64 = 0
  comptime for f in typeinfo(B).fields {
    d = d + 1
  }
  return d
}

## the same header over the fn's OWN type-param, which must keep naming `T`
own := fn(T : type, v : T) -> u64 {
  mut d : u64 = 0
  comptime for f in typeinfo(T).fields {
    d = d + 1
  }
  return d
}

main := fn() -> u64 {
  mut top : u64 = 0
  comptime for f in typeinfo(A).fields {
    top = top + 1
  }
  mut ev : u64 = 0
  comptime for v in typeinfo(E).variants {
    ev = ev + 1
  }
  x := A(a = 1, b = 2)
  if top != 2 { return 1 }
  if ev != 4 { return 2 }
  if cross(A, x) != 3 { return 3 }
  if own(A, x) != 2 { return 4 }
  return 42
}
