## e2e (reject) — `@abi(value)` is a CALLING-CONVENTION attribute on a FUNCTION (Functions §6; Types §8
## is explicit that it is "never a type's data layout"), and the grammar spells it in VALUE position
## next to the `fn-sig` it applies to (Grammar §3.11 `extern-decl`, §3.6 `abi-attr`). In
## declaration-prefix position it prefixes the BINDING, and every `@abi` recovery in the compiler
## (`is_syscall` in the parser, `fn_is_naked` in the lower) reads the value position only.
## This already failed — but as a bare `parse error` pointing nowhere, because the prefix loop simply
## stopped and the declaration-name parse then hit the `@`. It now says what is wrong and where.
@abi(syscall)
w := fn(nr : u64, fd : u64) -> i64
main := fn() -> u64 {
  return 3
}
