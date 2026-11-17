## #1711: the compiler's own `src/ast.al` order, `Some` first (the prelude's is `None` first).
pub Option := fn(T : type) -> type { enum { Some(T), None } }
## Compiled alone (the corpus walk), this module file is a program with no entry declaration,
## which is a Codegen-stage diagnostic before the linker (Manifest §3.2, TOOL-12).
## expect: reject
