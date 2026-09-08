## Types §9.1 (#564) — an integer literal outside the target type's range is a COMPILE ERROR through
## the conversion-constructor spelling `T(v)` as well as through an annotation. §9.2 names `T(v)` as
## one of the two forms that refine a literal's type, so `u8(300)` is §9.1's literal-in-context case:
## "a literal outside the target type's range is a compile error (I11), never a silent wrap."
## Measured on the parent, this program compiled clean on all four backends and RAN TO 44 (= 300-256).
main := fn() -> u64 {
  n : u8 = u8(300)
  u64(n)
}
