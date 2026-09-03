## e2e (#405) — a str LITERAL is a VALUE, not a place. Taking the address of a literal element
## has no frame home to address; the generic element-address path used to resolve the nameless
## base to frame slot 0 and hand back a pointer INTO THE CALLER'S FRAME, so the deref below read
## a live local (104) instead of 97 — a silent wrong value with no diagnostic. Lower now stops at
## the address request. The diagnostic wording is asserted by the harness, not quoted here.
main := fn() -> u64 {
  p := ptr("abc"[0])
  return u64(deref(p))
}
