## e2e — issue #469. A bare comparison operator whose operand is an aggregate CONSTRUCTOR EXPRESSION
## (a struct literal `P(x = …)` or a payload-carrying variant construction `E.V(…)` / `Option.Some(…)`)
## must compare COMPONENTWISE, exactly as it already does over two by-value aggregate LOCALS.
##
## Stdlib §2.6 (`spec/160-appendix-stdlib.md:118-132`): `eq(in a : T, in b : T) -> bool`, "default =
## componentwise field equality", derived structurally over `typeinfo(T)`. Comptime §5.5
## (`spec/30-comptime.md:337-357`) spells the enum case normatively: the SAME variant compares the
## whole payload by RECURSING with the operator (`return pa == pb`), a DIFFERENT variant is
## `return false`. `spec/160-appendix-stdlib.md:710` makes deriving `eq`/`lt`/`hash` structurally a
## conformance requirement, and `design/decisions/comptime.md:192-194` rejects a discriminant-only /
## raw-byte compare — so neither "compare the tag alone" nor "refuse the form" is available.
##
## THE DEFECT. `lib/base/derive.al:39-46` is a correct transcription of §5.5 and is NOT the problem.
## The routing GATE was `agg_value_var_words(l) > 1 and agg_value_var_words(r) > 1`, and
## `agg_value_var_words` reads a frame SLOT — it answers non-zero only for a `Var`. A constructor
## expression is not a `Var`, so the gate declined for it and the operand fell through to the scalar
## comparison, where a multi-word aggregate in a scalar value position materializes as the CONSTANT
## `$0`. The parent's own GAS for `P(x = 5, y = 7) == P(x = 5, y = 9)` is
## `pushq $0` / `movq $0, %rbx` / `popq %rax` / `cmpq %rbx, %rax` / `sete %al` — two DIFFERENT values
## compared as `$0 == $0`, answering EQUAL. Where one side was a local, that side loaded its real
## word 0 and was compared against `$0`, answering NOT EQUAL for two identical values.
##
## Both directions of wrongness were live, on structs, `Option` and payload enums alike, and TWO
## shapes answered correctly BY ACCIDENT (`$0 == $0` for two equal literals) — so those two are
## checked here too: the point is that they now answer through `base::derive::eq`, not that they
## happen to agree. Probes 62 and 57 are those two.
##
## Every probe has its OWN exit code and the first wrong one is returned immediately, so a partial
## fix names the class it missed rather than hiding inside one summed number (no alias encoding —
## a wrongly-EQUAL answer and a wrongly-UNEQUAL answer never share a code). All codes are < 126.
##
## THE PROBE ORDER IS LOAD-BEARING, for the non-x86 backends. The LOCAL-against-a-construction
## shapes come FIRST because the wat backend already REFUSES those (`(unreachable)`, exit 134), so
## wasm reaches a loud trap before it can reach the two literal-against-literal shapes it answers
## silently WRONG (`Pay.B(7,7) == Pay.B(7,7)` → "not equal", `P(5,7) == P(5,7)` → "not equal", both
## measured identically on the parent and on this tree — `wat_is_agg_place` carries the same
## `Var`-only blind spot and compares two freshly allocated scratch-block ADDRESSES). That is issue
## #511, not this one, and it is why there is deliberately NO `run_wat` row here: a gate row would
## record a wrong wasm answer as expected. aarch64 and riscv64 `brk`/`ebreak` on the whole shape.
##
##   51  e == Pay.B(7,7), e the same value   answered NOT equal   (enum local vs construction)
##   52  probe(in e : Pay): e == Pay.B(7,7)  answered NOT equal   (by-reference PARAM vs construction)
##   53  p == P(x=5,y=7), p the same value   answered NOT equal   (struct local vs construction)
##   54  o == Option.Some(1), o the same      answered NOT equal   (a GENERIC enum local)
##   55  p <  P(x=5,y=9)                      answered NOT less    (lexicographic ordering)
##   56  P(x=5,y=9) >  p                      answered NOT greater (the swapped ordering)
##   57  Pay.B(7,7) == Pay.B(7,7)             answered NOT equal   (equal payloads)
##   58  Pay.B(7,7) == Pay.B(9,9)             answered EQUAL       (same variant, payloads differ)
##   59  Pay.A(1)   == Pay.B(1,1)             answered EQUAL       (different variants)
##   60  Pay.B(7,7) != Pay.B(9,9)             answered false       (the `!=` direction)
##   61  E.A(1) == E.A(2)                     answered EQUAL       (a ONE-component payload)
##   62  P(5,7) == P(5,7)                     answered NOT equal   (struct literal vs equal literal)
##   63  P(5,7) == P(5,9)                     answered EQUAL       (struct literal vs differing one)
##   64  Q(P(5,7),9) == Q(P(5,7),9)           answered NOT equal   (a NESTED struct literal)
##   65  Q(P(5,7),9) == Q(P(5,8),9)           answered EQUAL       (nested difference in word 1)
##   66  Option.Some(1) == Option.Some(1)     answered NOT equal
##   67  Option.Some(1) == Option.Some(2)     answered EQUAL
##   68  Option.None    == Option.Some(5)     answered EQUAL       (nullary vs payload variant)
##
## CONTROLS — paths that were ALREADY correct and must not move. A regression in one of these is the
## expensive failure mode of a routing change, so each gets its own code as well.
##
##   71  two enum LOCALS, equal payloads       answered NOT equal
##   72  two enum LOCALS, payloads differ      answered EQUAL
##   73  two struct LOCALS, all fields equal    answered NOT equal
##   74  two struct LOCALS, word 1 differs      answered EQUAL
##   75  Tag.Red == Tag.Red   (payload-FREE)    answered NOT equal
##   76  Tag.Red == Tag.Green (payload-FREE)    answered EQUAL
##   77  t == Tag.Green, t bound to Tag.Red     answered EQUAL
##   78  t == Tag.Red,   t bound to Tag.Red     answered NOT equal
##   79  a plain scalar `==` no longer answers  (the widened gate must not swallow it)
##
## Parent 495cc51: 51 — `e == Pay.B(7,7)` answers NOT equal for an `e` bound to that very value, the
## issue's own second measurement. This tree: 42.

P := struct { x : u64, y : u64 }
Q := struct { a : P, b : u64 }
Pay := enum { A(u64), B(u64, u64) }
E := enum { A(u64), B(u64) }
Tag := enum { Red, Green, Blue }

## The by-reference PARAM operand shape: `e` is a `Pay` param, the right operand a construction.
probe_param := fn(in e : Pay) -> bool { e == Pay.B(7, 7) }

main := fn() -> u64 {
  ## --- a LOCAL or PARAM against a construction (wasm refuses these — see the note above) --------
  e := Pay.B(7, 7)
  if e == Pay.B(7, 7) {} else { return 51 }
  if probe_param(Pay.B(7, 7)) {} else { return 52 }
  p := P(x = 5, y = 7)
  if p == P(x = 5, y = 7) {} else { return 53 }
  o := Option.Some(1)
  if o == Option.Some(1) {} else { return 54 }
  if p < P(x = 5, y = 9) {} else { return 55 }
  if P(x = 5, y = 9) > p {} else { return 56 }

  ## --- payload-carrying enum, BOTH operands constructions -------------------------------------
  if Pay.B(7, 7) == Pay.B(7, 7) {} else { return 57 }
  if Pay.B(7, 7) == Pay.B(9, 9) { return 58 }
  if Pay.A(1) == Pay.B(1, 1) { return 59 }
  if Pay.B(7, 7) != Pay.B(9, 9) {} else { return 60 }
  if E.A(1) == E.A(2) { return 61 }

  ## --- struct literals ------------------------------------------------------------------------
  if P(x = 5, y = 7) == P(x = 5, y = 7) {} else { return 62 }
  if P(x = 5, y = 7) == P(x = 5, y = 9) { return 63 }

  ## --- a NESTED struct literal: the top-level derive re-enters `eq` for field `a` --------------
  if Q(a = P(x = 5, y = 7), b = 9) == Q(a = P(x = 5, y = 7), b = 9) {} else { return 64 }
  if Q(a = P(x = 5, y = 7), b = 9) == Q(a = P(x = 5, y = 8), b = 9) { return 65 }

  ## --- `Option`, the most-used enum in the language, and a GENERIC one -------------------------
  if Option.Some(1) == Option.Some(1) {} else { return 66 }
  if Option.Some(1) == Option.Some(2) { return 67 }
  if Option.None == Option.Some(5) { return 68 }

  ## --- CONTROLS: already-correct paths ---------------------------------------------------------
  f := Pay.B(7, 7)
  g := Pay.B(9, 9)
  if e == f {} else { return 71 }
  if e == g { return 72 }
  q := P(x = 5, y = 7)
  r := P(x = 5, y = 8)
  if p == q {} else { return 73 }
  if p == r { return 74 }
  if Tag.Red == Tag.Red {} else { return 75 }
  if Tag.Red == Tag.Green { return 76 }
  t := Tag.Red
  if t == Tag.Green { return 77 }
  if t == Tag.Red {} else { return 78 }
  n : u64 = 5
  if n == 5 {} else { return 79 }

  return 42
}
