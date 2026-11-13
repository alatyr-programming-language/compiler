- **A `Vec` element read as `v[i]`, `v.at(i)` or `v[a..b]` keeps its whole struct, `str` or enum value on
  x86_64 (#987).** The legacy lowerer typed the result of an auto-ref generic call only from explicit
  type arguments, so `e := v[0]; e.fd` read 0, `s := v[1]` lost its length, and a struct or enum
  element passed straight to a function segfaulted. The lowerer now completes the omitted type
  arguments into the explicit, module-qualified call before it types the result. Fifteen container
  matrix cells move from CRASH to OK, including the five `v.at(i)` cells of #1256.
