## #726 / Types §4.2, §4.3 — a `bool` LOCAL is not a `u64` argument: `bool` to an integer is the
## numeric class, always explicit. `reject_call_arg_bool_num` refuses the literal spelling `f(true)`;
## the parent accepted this one and ran it to 1, because `check_expr` answered UNKNOWN for a scalar
## local, so the argument compare never saw the `bool` the binding recorded. `f(u64(b))` conforms.
f := fn(n : u64) -> u64 { return n }

main := fn() -> u64 {
  b := true
  return f(b)
}
