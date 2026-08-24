pub first_line_api := fn() -> u64 { helper() }
## `decl_is_pub` also required WHITESPACE before `pub`, which the FIRST declaration of the FIRST
## module never has: `driver::compile_program` appends every module NAME and then every module SOURCE
## into ONE buffer with no separator, so the byte before that `pub` is the tail of a module name — an
## identifier byte, not whitespace. So the declaration on line 1 above read as NON-`pub` and was
## emitted as a LOCAL symbol (`t api__first_line_api`), unlinkable by a consumer of this library.
## Measured before the fix: `t api__first_line_api`. After: `T api__first_line_api`.
helper := fn() -> u64 { 42 }
