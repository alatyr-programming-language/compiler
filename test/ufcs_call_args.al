## e2e (gap-2 blocker A — UFCS on a NON-EMPTY-parens call receiver). `mkp(40, 2).sum()` — the
## receiver `mkp(40, 2)` is a call with ARGS. Previously `is_generic_enum_ctor` treated ANY
## `ident(…).name(…)` as a generic-enum-ctor `Result(T,E).Ok(x)`, rewriting the base to `Var("mkp")`
## and DROPPING the call's args → miscompile. The two-pass driver now pre-collects every enum-type
## name (kind-3 decls) across all modules (module order is getdents, so a decls-so-far check is
## unsound) and threads the table into `PC`; the rewrite fires only when the head IS a known enum
## type. `mkp` is a function, not an enum → `mkp(40,2)` parses as a Call, `.sum()` as UFCS on that
## call result (which rides `emit_arg`'s aggregate-call-by-ref path). No enum in this program at all —
## the NULL-vs-empty table sentinel distinguishes "no pre-scan" from "pre-scan found zero enums", so a
## no-enum program is handled correctly too. `40 + 2` = 42.
Pair := struct { a : u64, b : u64 }
mkp := fn(a : u64, b : u64) -> Pair { Pair(a = a, b = b) }
sum := fn(p : Pair) -> u64 { p.a + p.b }
main := fn() -> u64 {
  mkp(40, 2).sum()
}
