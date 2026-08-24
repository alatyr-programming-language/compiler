## e2e — Comptime §5.1/§5.5: `typeinfo(X)` must read ITS OWN argument. The `CompFor` AST node drops the
## argument at parse time (the seed's AST-node word budget), so the unroll keyed off the monomorph
## INSTANCE type instead: a concrete `typeinfo(S)` at top level (no instance at all) unrolled ZERO
## times, and `typeinfo(B)` inside an `A` instance unrolled over A's members. Both silent. The lower now
## recovers the argument by SOURCE-SCAN and resolves it through the instance's type-param bindings.
## Also locks the `.variants` STATEMENT form, which had no emit branch at all and unrolled 0 times.
A := struct { a : u64, b : u64 }
B := struct { p : u64, q : u64, r : u64, s : u64 }
E := enum { X, Y, Z }
## inside an `A` instance, iterate B — not the instance type
cross := fn(T : type, v : T) -> u64 {
  mut d : u64 = 0
  comptime for f in typeinfo(B).fields { d = d + 1 }
  return d
}
main := fn() -> u64 {
  mut top : u64 = 0
  comptime for f in typeinfo(A).fields { top = top + 1 }      ## concrete type at TOP LEVEL → 2
  mut ev : u64 = 0
  comptime for v in typeinfo(E).variants { ev = ev + 1 }      ## statement-form .variants → 3
  x := A(a = 1, b = 2)
  ## 2 + 3 + 4 = 9; kind test on a concrete type at top level (was: NEITHER branch emitted)
  mut k : u64 = 0
  comptime if (match typeinfo(E) { Enum(_) => true; _ => false }) { k = 33 } else { k = 100 }
  return top + ev + cross(A, x) + k
}
