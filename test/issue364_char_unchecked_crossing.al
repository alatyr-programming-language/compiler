## Issue #364, the CT-11 control — `unchecked char(n)` yields the raw value, and does so by running the
## SAME operation the checked site runs. The fix makes every `char(n)` site denote the library conversion
## (`base::char::to_char`); this fixture pins the half of that rule the fix must NOT overreach.
##
## Types §4.6 (v1.8.0, l.345): "The step is selected **checked or unchecked alike**: `unchecked` drops the
## guard inside the operation the site denotes, and never substitutes a different one: each guarded
## operation takes its **hardware-defined** behaviour, the same operation and never another (CG-7), and the
## guard itself is absent by CT-11 — a caller's scope choosing another operation would change a value
## (I1, I11)". So this is NOT the builtin brand crossing taken instead of the conversion: `to_char` is
## called here too, and it is its own body that thins — the guard sits behind `comptime if verify.checked`
## and the body ends in `unchecked bitcast(char, n)`, so inside `unchecked` "the body is an identity
## crossing and costs nothing" (l.344, Stdlib appendix §3.2 l.311).
##
## Measured on the PARENT `c00eae90`, native x86_64 (omen), committed seed `alatyr 0.2.21`: run rc=42 —
## it passes there too, for the wrong reason, because nothing reached the conversion at all. It is kept
## because after the fix it passes for the RIGHT reason: the conversion is in scope and selected at every
## site, checked or unchecked, and only its guard is absent here. If the fix dropped the whole conversion
## outside `unchecked`, or kept the guard inside it, this program answers 101/102/103 or dies, and says so.
##
## The block form `unchecked { … }` is the same grant in statement position (Grammar §3.7, `unchecked-region
## ::= "unchecked" ( expr | block )`), so both spellings are exercised. Cross-backend: the twins reach this
## path through `driver::d_convert_expr` → `lower::twin_convert_callee`, which likewise does not consult
## the mode.
ch := base::char

main := fn() -> u64 {
  ## Out of range and a surrogate, both refused when checked (§3.2), both raw here.
  a := unchecked char(1114112)
  if u32(a) != 1114112 { return 101 }
  b := unchecked char(55296)
  if u32(b) != 55296 { return 102 }
  ## The statement-block spelling of the same grant (Grammar §3.7).
  mut cp : u32 = 0
  unchecked {
    c := char(1114113)
    cp = u32(c)
  }
  if cp != 1114113 { return 103 }
  ## A valid code point is unaffected either way — the checked and unchecked sites agree on it.
  d := char(65)
  if u32(d) != 65 { return 104 }
  42
}
## expect: run 42
