## e2e — an ENUM-valued mutable global (`mut STATE := Color.Green(40)`). Laid out in .data as
## [disc, payload…, pad] ascending (disc + 1..max_arity payload words); `s := STATE` snapshots those
## words into a local enum, and a `match s { Color::Variant(n) => … }` (note the `::` variant-pattern
## syntax) reads it. Green's disc + payload 40 → 40 + 2 = 42.
Color := enum { Red, Green(u64), Blue }
mut STATE := Color.Green(40)
main := fn() -> u64 {
  s := STATE
  match s {
    Color::Green(n) => { n + 2 }
    Color::Red => { 0 }
    Color::Blue => { 1 }
  }
}
