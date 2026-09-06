## Issue #449's CONTROL — the enum-typed struct field read that ALREADY answers on wasm and must go
## on answering. The #449 fix narrows one COMPARISON operand test; it must not touch the value the
## field itself delivers, and this fixture is the assertion that says so: the same `h.t` read is
## handed to a function taking `Tag` by reference and dispatched there, with no `==` anywhere.
##
## If the field read ever stopped delivering a usable enum block — the failure a broader fix would
## have caused — this program would answer 61 or 62 instead of 42, on wasm as loudly as on x86_64.
##
##   42  the field read reached the callee as the variant that was stored   (due)
##   61  it arrived as a DIFFERENT variant
##   62  it arrived as no variant at all
##  133  the aarch64/riscv64 `brk`/`ebreak` trap (no lowering for this shape on either)
##
## Measured on parent 8370bd2 AND on this tree: x86_64 42, wasm 42, aarch64 133, riscv64 133.

Tag := enum { Red, Green, Blue }
Holder := struct { t : Tag }

## `v` is a BY-REFERENCE enum parameter; `match` on it is the wasm path that already works.
use := fn(v : Tag) -> u64 {
  match v {
    Tag.Red => { return 61 }
    Tag.Green => { return 42 }
    Tag.Blue => { return 61 }
  }
  return 62
}

main := fn() -> u64 {
  h := Holder(t = Tag.Green)
  use(h.t)
}
