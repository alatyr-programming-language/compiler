## e2e (COMPTIME `match typeinfo(T) { <kind> => … }` — kind-dispatch, the sibling of `comptime if
## (match typeinfo(T){…})`). Parsed into `Stmt::CompMatch`; the lower EVALUATES T's KIND in a mono
## instance and emits ONLY the matching arm (Struct/Enum/Array/Scalar, else `_`). derive's `eq`/`lt`
## use this form. Here: `kind(Pt,…)` → Struct arm (1), `kind(E,…)` → Enum arm (2), `kind(u64,39)` →
## the `_` arm (`u64(v)` = 39). 1 + 2*10 + 39 = 60.
Pt := struct { x : u64, y : u64 }
E := enum { A(u64), B(u64) }
kind := fn(T : type, v : T) -> u64 {
  comptime match typeinfo(T) {
    Struct(_) => { return 1 }
    Enum(_) => { return 2 }
    _ => { return u64(v) }
  }
}
main := fn() -> u64 {
  kind(Pt, Pt(x = 1, y = 2)) + kind(E, E.A(5)) * 10 + kind(u64, 39)
}
