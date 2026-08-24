## SOUNDNESS (TYP-6, the REVERSE of reject_agg_arg_scalar_param): passing a bare SCALAR literal
## to a parameter declared as a user AGGREGATE (`f(42)` with `f := fn(p : S)`) is a type error. A naive
## emit-time net could NOT reject this (it needs post-overload resolution, which sema has), so it is
## caught in sema on the build path — a non-zero build rc is the acceptable fail-loud outcome. Registered
## with `build_reject` in scripts/e2e.sh.
S := struct { a : u64, b : u64 }
f := fn(p : S) -> u64 { return p.a + p.b }
main := fn() -> u64 {
  return f(42)
}
