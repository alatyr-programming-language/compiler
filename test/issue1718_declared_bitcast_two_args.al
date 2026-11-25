## #1718 — a program that declares `bitcast` calls that declaration. `bitcast` is a prelude identifier,
## not a keyword (Grammar §2.3), and a module-level fn of the name joins its overload set (Declarations
## §6.1); `(u64, u64)` with two integer literals is accepted by the declaration, so this is 10 + 32.
## NON-VACUOUS: on the parent da8f96af (native x86_64, tree Stage1) every backend answers 34: the parser
## built the reinterpret of `2` from the spelling `bitcast(` before any declaration was known.
bitcast := fn(a : u64, b : u64) -> u64 { a }
main := fn() -> u64 {
  bitcast(10, 2) + 32
}
## expect: run 42
