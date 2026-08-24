## A `str` literal is the two-word {ptr, len} value; a `ptr(T)` is one word. **reinterpret** is the
## only class that could relate them and it requires EQUAL bit width, so not even an explicit
## `bitcast` spells this — there is nothing an implicit conversion could be a lossless subset of.
main := fn() -> u64 {
  p : ptr(u8) = "nope"
  return 0
}
