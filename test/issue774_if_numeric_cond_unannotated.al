## e2e — issue #774, the UNANNOTATED owner: `p := 10` took the default `i64` (Types §9.1) and is no
## more truthy than an annotated `u64` (Control Flow §4). Measured on the parent (`origin/main`
## `2d6e05f4`, native x86_64): check 0, build 0, answered 1.
main := fn() -> u64 {
  mut p := 10
  if p { return 1 }
  return 42
}
## expect: reject "a bare numeric condition is ill-formed at line 6 in issue774_if_numeric_cond_unannotated"
