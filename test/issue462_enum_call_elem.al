## issue #462, the POINTER-RELATIVE twin — the same enum-returning-call field feed, written into an
## ARRAY ELEMENT at a RUNTIME index (`xs[i] = Boxed(p = mk(), n = 9)`). That destination goes through
## `emit_*_store_payload_atptr` rather than `..._at`: the base address lives at the top of the stack and
## is re-read per word. Its scalar fallback stored ONE return register and reported ONE word, exactly as
## the frame-relative twin did, so aarch64 answered a clean, silent 31 here — the field AFTER the enum
## field, written one word too early — while x86_64's struct-literal writer dropped the store outright
## and matched the wrong arm.
##
## This file is separate from `issue462_enum_call_field.al` because riscv64 refuses this shape for an
## UNRELATED reason (its whole-element aggregate write is fail-loud here), BEFORE and AFTER, and folding
## it into the main fixture would trap that file at 133 on riscv64 and cost it every exit code it
## measures. The riscv64 row below asserts that refusal EXACTLY — 133, i.e. 128 + SIGTRAP — not merely
## "nonzero", so a later widening of that path cannot turn it into an unmeasured silent emission.
##
## Codes, each naming one observable:
##   31   the field AFTER the enum field is wrong (the mis-sized store; aarch64's parent answer)
##   32   the OTHER variant's arm won (x86_64's parent answer — nothing was stored at all)
##   33   the right arm won, payload word 0 read 0 — never delivered
##   34   the right arm won, payload word 0 read some THIRD value
##   35   the right arm won, payload word 1 read 0
##   36   the right arm won, payload word 1 read some THIRD value
##   37   NO arm matched — the wildcard won
##   38   the UNTOUCHED neighbouring element was disturbed by the write
## All pass -> 42. Parent 43093e5: x86_64 32, aarch64 31, riscv64 133, wasm 134. This tree: 42, 42,
## 133, 134.

Pay := enum { A(u64), B(u64, u64) }
Boxed := struct { p : Pay, n : u64 }

mkb := fn() -> Pay { Pay.B(5, 6) }

chk_b := fn(v : u64, w : u64, z0 : u64, o0 : u64, z1 : u64, o1 : u64) -> u64 {
  if v != 5 {
    if v == 0 { return z0 }
    return o0
  }
  if w != 6 {
    if w == 0 { return z1 }
    return o1
  }
  0
}

elem_write := fn() -> u64 {
  mut xs := [Boxed(p = Pay.A(1), n = 1), Boxed(p = Pay.A(2), n = 2)]
  i := 0
  xs[i] = Boxed(p = mkb(), n = 9)
  b := xs[0]
  t := xs[1]
  if b.n != 9 { return 31 }
  if t.n != 2 { return 38 }
  match b.p { A(v) => 32, B(v, w) => chk_b(v, w, 33, 34, 35, 36), _ => 37 }
}

main := fn() -> u64 {
  r := elem_write()
  if r != 0 { return r }
  42
}
