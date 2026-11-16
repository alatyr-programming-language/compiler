## #1711: the compiler's own `src/ast.al` order, `Some` first (the prelude's is `None` first).
pub Option := fn(T : type) -> type { enum { Some(T), None } }
