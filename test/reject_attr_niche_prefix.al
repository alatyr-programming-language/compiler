## e2e (reject) — `@niche(producer)` (Types §8 / §6.2) declares an invalid bit-pattern an enclosing
## enum may fold into. The lower reads NO user-written niche: `lower_layout::is_niche_folded`
## recognizes exactly `Option(ptr(T))` from the type itself, by the pointer's own null pattern. So a
## user-declared niche producer has no lowering and must fail loud rather than be accepted as a no-op.
## This spelling used to die as a bare `parse error` pointing nowhere.
@niche(0)
N := u64
main := fn() -> u64 {
  return 3
}
