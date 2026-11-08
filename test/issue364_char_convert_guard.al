## Issue #364 — a checked `char(n)` must reach the code-point guard of the library conversion-constructor
## that §4.6 gives it. It did not: the lower short-circuited every brand construction ahead of `@convert`
## dispatch, so the site reinterpreted and the guard was dead code.
##
## Measured on the PARENT `c00eae90`, native x86_64 (omen), with the committed seed `alatyr 0.2.21`
## (`seed/alatyr -o <bin> <file>.al && ./<bin>`, `ulimit -c 0`):
##   char(1114112) -> run rc=42 stderr=[]   (the defect: past Unicode's last code point, silently)
##   char(55296)   -> run rc=42 stderr=[]   (the defect: a surrogate, silently)
## so the program ran to its last line and answered the value the guard was there to refuse.
##
## WITH THE FIX this site denotes `base::char::to_char`: Types §4.6 (v1.8.0, l.338) — "An in-scope
## `@convert` therefore precedes the brand crossing to a branded target: §4.2's "cost: zero" states what
## that crossing *costs*, and a cost statement does not settle which operation a site denotes — where a
## conversion matches, the site denotes the conversion" — and l.341 names this very site: "So `char(n)` —
## `char` being a brand over `u32` with the prelude's `@convert` in scope — runs that conversion, whose
## code-point validity check is library code under `comptime if verify.checked` (§4.5, CT-11)". The guard
## runs and the program fails there; it never reaches the `42`. The failure is through `panic` (exit 1,
## message on fd 2), NOT the specified `trap()` (Stdlib appendix §3.2, l.313: the check "fails through
## `trap()` like the built-in narrowing guard (§4.1)"): `trap()` is not a callable prelude identifier yet
## and #1427 holds that, exactly as `chariter_invalid_ff` is a `run_x86 … 1` row for the same reason. The
## row is x86_64-scoped because the twins resolve a callee by name and have no lowering for `panic`;
## their rows for this program are the corpus's to record.
##
## The valid code points are checked FIRST and each owns a distinct early-return code, so a `1` from fd 2
## reading `invalid code point` is the only way this program can end: a broken valid path would answer 101,
## 102, 103, 104 or 105 instead, and an unfixed guard answers 42.
ch := base::char

main := fn() -> u64 {
  ## Valid code points through the SAME conversion: 'A', U+00E9 (2-byte UTF-8) and U+1F600 (4-byte).
  a := char(65)
  if u32(a) != 65 { return 101 }
  e := char(233)
  if u32(e) != 233 { return 102 }
  g := char(128512)
  if u32(g) != 128512 { return 103 }
  ## Unicode's last valid code point, the boundary just below the refused one.
  t := char(1114111)
  if u32(t) != 1114111 { return 104 }
  ## The library folding still routes through the conversion (`to_lower` builds `char(n + 32)`).
  if u32(ch::to_lower(char(65))) != 97 { return 105 }

  ## Past this line the program is REFUSED. Stdlib appendix §3.2 (v1.8.0, l.311): `char(n)` is "a
  ## library conversion-constructor (`@convert`, §4.6) whose code-point validity check (≤ 0x10FFFF, not a
  ## surrogate; I11) is library code" — 1114112 is one above 0x10FFFF, so the guard fires and this `42`
  ## is never reached.
  c := char(1114112)
  if u32(c) == 1114112 { return 42 }
  7
}
## expect(x86_64): run 1
