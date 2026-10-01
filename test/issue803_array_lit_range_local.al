## Issue #803 / Types §9.1 — an array literal's elements take their type from the context `[u8; 2]`,
## and a literal outside that type's range is a compile error, never a silent wrap. The parent
## accepted this binding and `a[1]` read 44 (300 mod 256).
main := fn() -> u64 {
  a : [u8; 2] = [1, 300]
  return u64(a[1])
}
