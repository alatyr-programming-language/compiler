- **The shared IR's niche-folded `Option(ptr(T))` shape now asks that the absent variant was seen
  (#1687).** The builder takes the one-word folded layout — no discriminant, `None` the all-zero word,
  `Some(p)` the pointer itself (Types §6.2/§8, Memory §4.2) — only for the shape that claim rests on:
  exactly two variants, one carrying discriminant 0 with no components and the other exactly one. It
  asked that the discriminant-0 variant carry no components by reading back a counter left at zero, which
  answers zero both when that variant was seen with no components and when no variant carried discriminant
  0 at all; the second answer passed the guard and folded a type whose null pattern is not its absent case.
  The variant is now counted explicitly and required to have been seen. No program the compiler accepts
  today reaches the difference — the prelude's `Option` puts `None` first, at discriminant 0 — so every
  build is unchanged; the guard now means what its prose says, one declaration before it could fire.
