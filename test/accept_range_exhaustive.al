## sema/§5.4 — a `u8` scalar match whose ranges cover the ENTIRE finite domain [0,255] is exhaustive
## and MUST be accepted (no `_` needed). `check` returns 0.
main := fn() -> u64 {
  n : u8 = 200
  r := match n { 0..=127 => 1 ; 128..=255 => 2 }
  return r
}
