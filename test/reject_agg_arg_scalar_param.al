## SOUNDNESS NET (TYP-6 sibling / D69): passing a user AGGREGATE (struct/enum) argument to a builtin
## SCALAR parameter used to silently miscompile — the call read the aggregate's word 0 as if it were
## the scalar (`f(s)` returned garbage: rc=201). The compiler must instead FAIL LOUD at build time.
## A non-zero build rc is the acceptable outcome; a valid binary with a wrong result is the forbidden
## silent miscompile. Registered with `build_reject` in scripts/e2e.sh.
S := struct { a : u64, b : u64 }
f := fn(x : u64) -> u64 { return x + 1 }
main := fn() -> u64 {
  s := S(a = 41, b = 99)
  return f(s)
}
