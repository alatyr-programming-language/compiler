## e2e — issue #447: a `match` whose scrutinee is a NESTED enum place (`o.inner.t`) must dispatch on
## the enum DISCRIMINANT, in EVERY `match` form, and must carry the PAYLOAD words with it.
##
## `try_field_enum_scrut`'s local branch was reached through `field_var_scrut`, which recognises only
## `Field(Var, f)` — one level. A chain whose base is ITSELF a field never resolved, so the scrutinee
## fell into the INTEGER path where an enum pattern arm carries no scalar literal (`am.lit` is 0):
## every arm compared the scrutinee against 0, so only a discriminant-0 variant could ever match.
## Unlike #396 this hit ALL FOUR spellings, because the fourth one — bind the field to a local first —
## failed for a SECOND reason: `field_read_agg` was depth-1 too, so `x := o.inner.t` reserved a SCALAR
## slot. Its word 0 (the discriminant) was right, which is why `x == Tag.Green` answered correctly and
## made the defect look like a `match` bug alone; the PAYLOAD words were never copied at all.
##
## The failure is read in every way it can fail, because "the first arm won", "no arm matched" and
## "the payload came back zero" are DIFFERENT defects and one exit code cannot name three mechanisms:
##   * `tail_form(Tag.Green)` writes the discriminant-0 variant FIRST, so a compare-against-0 dispatch
##     falls through every arm and lands on the wildcard;
##   * `reordered(Tag.Red)` writes `Green` FIRST, so the same dispatch makes the FIRST ARM win;
##   * `no_wild(Tag.Blue)` has no wildcard, so an unmatched match delivers the `movq $0` fallback;
##   * `pay_*` return a two-word payload, so a discriminant that dispatches over a stale payload is a
##     different number again from a discriminant that dispatches wrong.
## Each of those carries its own exit code, so the number the parent returns NAMES the mechanism.
##
## `Outer.lead` sits BEFORE `inner`, so the cumulative word offset is non-zero: a resolver that
## forgot to accumulate would read `lead` (7) rather than the enum and is a distinct wrong number.
##
## Measured on x86_64: parent (7ed9ffd) exits 51, this tree exits 42.
## `run_x86` for the working answer: aarch64/riscv64/wat have no enum-match lowering at all, so this
## shape is a fail-loud trap there BEFORE and AFTER — the three rows in `scripts/e2e.sh` assert that
## exact status rather than merely "nonzero".
##
## A BY-REFERENCE struct root (`fn(o : Outer) { match o.inner.t … }`) is NOT here: it is a located
## reject on the parent AND on this tree, held in place by
## `test/issue447_nested_enum_place_byref_reject.al`. Lifting that fence is a separate measurement.
Tag := enum { Red, Green, Blue, Amber, Violet }
Pay := enum { A(u64), B(u64, u64) }

Inner := struct { t : Tag }
Outer := struct { lead : u64, inner : Inner }
Mid := struct { pad : u64, inner : Inner }
Deep := struct { mid : Mid }
Holder := struct { t : Tag }

PBox := struct { p : Pay }
POuter := struct { head : u64, b : PBox }

## the discriminant-0 variant is written FIRST: a compare-against-0 dispatch matches no arm.
tail_form := fn(v : Tag) -> u64 {
  o := Outer(lead = 7, inner = Inner(t = v))
  match o.inner.t { Red => 11, Green => 22, Blue => 33, Amber => 44, Violet => 55, _ => 91 }
}

## `Green` is written FIRST: a compare-against-0 dispatch takes THIS arm for every scrutinee.
reordered := fn(v : Tag) -> u64 {
  o := Outer(lead = 7, inner = Inner(t = v))
  match o.inner.t { Green => 22, Red => 11, Blue => 33, Amber => 44, Violet => 55, _ => 91 }
}

## no wildcard: an unmatched tail value-match delivers the `movq $0` no-arm fallback.
no_wild := fn(v : Tag) -> u64 {
  o := Outer(lead = 7, inner = Inner(t = v))
  match o.inner.t { Red => 11, Green => 22, Blue => 33, Amber => 44, Violet => 55 }
}

value_form := fn(v : Tag) -> u64 {
  o := Outer(lead = 7, inner = Inner(t = v))
  y := match o.inner.t { Red => 11, Green => 22, Blue => 33, Amber => 44, Violet => 55, _ => 91 }
  y
}

stmt_form := fn(v : Tag) -> u64 {
  o := Outer(lead = 7, inner = Inner(t = v))
  match o.inner.t { Red => { return 11 } Green => { return 22 } Blue => { return 33 } Amber => { return 44 } Violet => { return 55 } }
  return 91
}

bound_form := fn(v : Tag) -> u64 {
  o := Outer(lead = 7, inner = Inner(t = v))
  x := o.inner.t
  match x { Red => 11, Green => 22, Blue => 33, Amber => 44, Violet => 55, _ => 91 }
}

## three levels, so the walk is a recursion and not a special-cased second hop.
deep_form := fn(v : Tag) -> u64 {
  d := Deep(mid = Mid(pad = 7, inner = Inner(t = v)))
  match d.mid.inner.t { Red => 11, Green => 22, Blue => 33, Amber => 44, Violet => 55, _ => 91 }
}

## the PAYLOAD must bind through the materialized nested place — `Pay` is three words wide, so a
## dispatch that copies only the discriminant answers with a stale payload rather than a wrong arm.
pay_tail := fn(x : Pay) -> u64 {
  po := POuter(head = 7, b = PBox(p = x))
  match po.b.p { A(v) => v, B(v, w) => v + w }
}

pay_bound := fn(x : Pay) -> u64 {
  po := POuter(head = 7, b = PBox(p = x))
  q := po.b.p
  match q { A(v) => v, B(v, w) => v + w }
}

## CONTROL — the same nested read compared with `==` was already correct on the parent, which is what
## proved the VALUE reaches the local and only the `match` dispatch was wrong.
cmp_control := fn(v : Tag) -> u64 {
  o := Outer(lead = 7, inner = Inner(t = v))
  x := o.inner.t
  if x == Tag.Red { return 11 }
  if x == Tag.Green { return 22 }
  if x == Tag.Blue { return 33 }
  if x == Tag.Amber { return 44 }
  if x == Tag.Violet { return 55 }
  return 91
}

## CONTROL — the ONE-LEVEL place is #396's shape and must not regress.
one_level := fn(v : Tag) -> u64 {
  h := Holder(t = v)
  match h.t { Red => 11, Green => 22, Blue => 33, Amber => 44, Violet => 55, _ => 91 }
}

main := fn() -> u64 {
  a := tail_form(Tag.Green)
  if a == 11 { return 50 }            ## the FIRST arm won
  if a == 91 { return 51 }            ## no arm matched: the wildcard won
  if a == 7 { return 52 }             ## the word offset was not accumulated: `lead` was read
  if a != 22 { return 53 }

  b := reordered(Tag.Red)
  if b == 22 { return 54 }            ## the FIRST arm won
  if b == 91 { return 55 }            ## no arm matched: the wildcard won
  if b != 11 { return 56 }

  c := no_wild(Tag.Blue)
  if c == 0 { return 57 }             ## no arm matched: the `movq $0` fallback
  if c == 11 { return 58 }            ## the FIRST arm won
  if c != 33 { return 59 }

  d := value_form(Tag.Green)
  if d == 11 { return 60 }
  if d == 91 { return 61 }
  if d != 22 { return 62 }

  e := stmt_form(Tag.Green)
  if e == 11 { return 63 }
  if e == 91 { return 64 }
  if e != 22 { return 65 }

  f := bound_form(Tag.Green)
  if f == 11 { return 66 }
  if f == 91 { return 67 }
  if f != 22 { return 68 }

  g := deep_form(Tag.Green)
  if g == 11 { return 69 }
  if g == 91 { return 70 }
  if g == 7 { return 71 }
  if g != 22 { return 72 }

  i := pay_tail(Pay.B(3, 4))
  if i == 3 { return 76 }             ## the FIRST arm won (A's single payload word)
  if i == 0 { return 77 }             ## the payload words were not materialized
  if i != 7 { return 78 }

  j := pay_bound(Pay.B(3, 4))
  if j == 3 { return 79 }
  if j == 0 { return 80 }
  if j != 7 { return 81 }

  if cmp_control(Tag.Green) != 22 { return 82 }
  if one_level(Tag.Green) != 22 { return 83 }
  if one_level(Tag.Red) != 11 { return 84 }

  ## every variant of the nested shape, so a dispatch that happens to be right for one discriminant
  ## is not mistaken for a working dispatch.
  if tail_form(Tag.Red) != 11 { return 85 }
  if tail_form(Tag.Blue) != 33 { return 86 }
  if tail_form(Tag.Amber) != 44 { return 87 }
  if tail_form(Tag.Violet) != 55 { return 88 }
  if deep_form(Tag.Violet) != 55 { return 89 }
  if pay_tail(Pay.A(9)) != 9 { return 90 }
  42
}
