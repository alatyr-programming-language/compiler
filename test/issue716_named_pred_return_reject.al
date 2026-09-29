## Issue #716 / Comptime §7.1, CT-4 — a NAMED predicate whose body is a lone `return <expr>` (rather than
## a trailing expression) gates a generic `when`-bound, and the bound is FALSE for `Big` (24 bytes). The
## instantiation must be refused. On the parent it was accepted and ran to 42: the body reader
## `guard_stmt_ret_expr` matched `deref(stmt_p(Stmt, bs))`, which the lowering compared against tag 0
## (`Stmt::Assign`), so a real `return` read as "not foldable" and the guard was silently dropped.
Big := struct { a : u64, b : u64, c : u64 }
is_small := fn(T : type) -> bool { return size(T) <= 8 }
pick := fn(T : type, x : u64) -> u64 when is_small(T) { x }
main := fn() -> u64 {
  pick(Big, 42)
}
