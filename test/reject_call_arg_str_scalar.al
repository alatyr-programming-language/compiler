## TYP-6 / Functions §2.3 — a call ARGUMENT must be assignable to its PARAMETER under the same
## Types §4.2/§4.3 lattice as an annotated binding. `f("nope")` for `f(n : u64)` returned 112
## SILENTLY (`check` rc 0, no diagnostic, a built binary with a wrong value): `check_expr`'s Call
## arm DOES compare the argument against `callee_param_ty`, but its arm list is the NON-EXHAUSTIVE,
## REORDERED one, so a StrLit argument came back tag 0 = UNKNOWN and unknown is compatible with
## everything. No **widen**/**narrow**/**numeric**/**brand**/**reinterpret** class connects `str`
## to an integer, and a `str` literal is not an untyped literal that takes its type from context
## (§3.4 is about integer/float literals) — so this has no conforming reading. Located at line 3.
f := fn(n : u64) -> u64 { return n }

main := fn() -> u64 { return f("nope") }
