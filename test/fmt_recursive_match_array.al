## fmt regression — an array-fill expression in a value-match arm reaches recursive `emit_fmt_expr`
## through `emit_fmt_arms`. The formatter must keep this seed-safe: the element is read through the
## loop-local `ga`, while the fill condition only cuts the shared walk short. The old
## `fh := deref(arg_p(al_e))` binding inside an `if` in this match arm crashed before it could emit.
main := fn() -> u64 {
  xs := match 0 {
    0 => [42; 3],
    _ => [0, 0, 0],
  }
  return xs[0]
}
