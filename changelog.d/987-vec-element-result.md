- **A `Vec` element read as `v[i]`, `v.at(i)` or `v[a..b]` keeps its whole struct, `str` or enum value on
  x86_64 (#987).** The legacy lowerer typed the result of an auto-ref generic call only from explicit
  type arguments, so `e := v[0]; e.fd` read 0, `s := v[1]` lost its length, and a struct or enum
  element passed straight to a function segfaulted. The lowerer now completes the omitted type
  arguments into the explicit, module-qualified call before it types the result, for a callee
  declared in the standard library's `alloc::vec` (asked by module identity, so a package's own
  `src/alloc__vec.al` is not taken for it) and an element type that is a scalar, `str` or a uniquely named
  non-generic struct or enum; any other call keeps its earlier behaviour. Fifteen container
  matrix cells move from CRASH to OK, including the five `v.at(i)` cells of #1256.
- **A source file is the standard library only when it sits under the compiler's own `lib/` (#987,
  #655).** Both `check`'s trust and the lowerer's stdlib test used to accept any path containing
  `/lib/` outside the package's source root. On a direct multi-file build a user file such as
  `mm/lib/badmod.al` was therefore skipped by `check`, so an unbound name in it failed only at the
  linker. It is now checked like any other user module, and the error names its line.
