## Issue #805 / Control Flow §5.1/§5.4 — a `char` is a scalar scrutinee, and a literal-only arm list
## cannot cover its values without a `_`. The parent built this and `f('z')` delivered 0.
f := fn(c : char) -> u64 {
  r := match c { 'a' => { 1 }; 'b' => { 41 } }
  return r
}
main := fn() -> u64 { return f('a') + f('z') }
