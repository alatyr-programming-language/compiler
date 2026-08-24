## TYP-6 / Types §4.2 — a BOOLEAN literal argument against a NUMERIC parameter. `bool` is a distinct
## kernel type, not a numeric domain; the relation to an integer is the **numeric** class (domain
## change), which is ALWAYS explicit (§4.3) — `f(u64(b))` is the spelling that conforms. `f(true)`
## built and returned 1 silently. (The mirror, `f(42)` into a `bool` parameter, was already rejected:
## an `Expr::Num` argument is one of the few forms `check_expr`'s reordered arm list does dispatch.)
f := fn(n : u64) -> u64 { return n }

main := fn() -> u64 { return f(true) }
