## #1434 — a program that DECLARES `align` had its call claimed by the name-keyed intrinsic arm of the
## legacy x86_64 lowering (`emit_gas`), which a function reaches when the shared IR refuses it — here the
## `f64` literal (NotYet FloatLit). NON-VACUOUS on the parent 263da9f6 (native x86_64, tree Stage1): the
## program answers **40**: `align(10)` was folded as the layout query of a type. A declared name is a
## call to that declaration (Grammar §2.3: built-ins are prelude identifiers, not keywords; Declarations
## §6.1: the inner declaration wins). The call shape fits no prelude signature of the name, so it answers
## the same under a shadowing or an overloading reading.
align := fn(x : u64) -> u64 { x }
main := fn() -> u64 {
  f : f64 = 1.5
  if f < 1.0 { return 1 }
  align(10) + 32
}
## expect: run 42
