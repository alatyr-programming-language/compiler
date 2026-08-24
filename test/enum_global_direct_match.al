## e2e — matching an ENUM global DIRECTLY (`match STATE`, no `s := STATE` copy). The global has no frame
## slot, so the match materializes its .data words into the scratch temp first, then dispatches — in
## both statement and tail position. Green(40) → 40 + 2 = 42.
Color := enum { Red, Green(u64), Blue }
mut STATE := Color.Green(40)
main := fn() -> u64 {
  match STATE {
    Color::Green(n) => { n + 2 }
    Color::Red => { 0 }
    Color::Blue => { 1 }
  }
}
