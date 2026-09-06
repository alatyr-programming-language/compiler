## Issue #449 — a struct's ENUM-typed field as a COMPARISON operand on the WASM backend.
##
## §8 delivers an enum BY REFERENCE. On wasm an enum LOCAL's slot IS its `{disc, payload…}` block,
## while an enum PARAM and a struct's enum FIELD hold a POINTER to one. The wat compare arm already
## refuses to `i64.eq` such a by-reference operand — that is why `x := Tag.Green ; x == Tag.Green`
## is a loud trap and not a guess — but its operand test scanned a bare `Var` only, and its own note
## claimed a FIELD operand "already yields a loaded scalar". For an ENUM-typed field that load yields
## the block ADDRESS, so `h.t == Tag.Green` compared the field's block against a freshly materialised
## literal block. Two distinct addresses: every arm false, no arm right, and the program fell through
## to a value no variant carries. A valid module, a normal exit, the wrong number.
##
## Every outcome carries its OWN code — none is reused for two different things (#386):
##    42  every probe read the right variant                            (due on x86_64)
##    51  the DIRECT `h.t == …` read a DIFFERENT variant
##    52  the DIRECT `h.t == …` matched NO variant at all
##    53  the BOUND `x := h.t` read a DIFFERENT variant
##    54  the BOUND `x := h.t` matched NO variant at all
##    55  the PARAMETER-fed `Holder(t = v)` read a DIFFERENT variant
##    56  the PARAMETER-fed `Holder(t = v)` matched NO variant at all
##    57  the WIDE `Wide(p = Pay.B(7))` field compared EQUAL to the variant it does NOT hold
##    58  the WIDE `Wide(p = Pay.A)` field compared UNEQUAL to the variant it DOES hold
##   134  the wasm `(unreachable)` trap — a by-reference compare the backend refuses to guess at
##   133  the aarch64/riscv64 `brk`/`ebreak` trap on the same bare aggregate comparison
##
## Measured on parent 8370bd2: x86_64 42, wasm 52, aarch64 133, riscv64 133.
## The wide probe is deliberately LAST: on wasm the wide field compare is already a trap on the
## parent, so leading with it would hide the silent one behind a loud one.

Tag := enum { Red, Green, Blue }
Pay := enum { A, B(u64) }
Holder := struct { t : Tag }
Wide := struct { p : Pay }

## The field's value arrives through a BY-REFERENCE enum parameter rather than a literal.
probe_param := fn(v : Tag) -> u64 {
  h := Holder(t = v)
  if h.t == Tag.Red { return 55 }
  if h.t == Tag.Blue { return 55 }
  mut seen := false
  if h.t == Tag.Green { seen = true }
  if not seen { return 56 }
  return 0
}

main := fn() -> u64 {
  h := Holder(t = Tag.Green)

  ## 1 — the DIRECT field read
  if h.t == Tag.Red { return 51 }
  if h.t == Tag.Blue { return 51 }
  mut seen1 := false
  if h.t == Tag.Green { seen1 = true }
  if not seen1 { return 52 }

  ## 2 — the field read BOUND to a local first
  x := h.t
  if x == Tag.Red { return 53 }
  if x == Tag.Blue { return 53 }
  mut seen2 := false
  if x == Tag.Green { seen2 = true }
  if not seen2 { return 54 }

  ## 3 — the same shape fed through a parameter
  r := probe_param(Tag.Green)
  if r != 0 { return r }

  ## 4 — an enum WIDER than one word: the field holds {disc, payload}, not a single scalar. Both
  ## directions are read, so neither answer can be produced by a comparison that is simply stuck.
  w := Wide(p = Pay.B(7))
  y := w.p
  if y == Pay.A { return 57 }
  z := Wide(p = Pay.A)
  mut seen4 := false
  if z.p == Pay.A { seen4 = true }
  if not seen4 { return 58 }

  return 42
}
