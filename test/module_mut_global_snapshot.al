## e2e — SNAPSHOT a mutable struct global into a local (`p := STATE`). Unlike a const copy (which
## copies compile-time init values), this copies the global's CURRENT `.data` words at the copy point,
## and `p` is thereafter INDEPENDENT: a later write to the global does not touch `p`. Here STATE.x is
## set to 40, `p` snapshots {40, 2}, then STATE.x is clobbered to 999 — `p` keeps 40. Returns 40+2 = 42.
Pt := struct { x : u64, y : u64 }
mut STATE := Pt(x = 1, y = 2)
main := fn() -> u64 {
  STATE.x = 40
  p := STATE
  STATE.x = 999
  p.x + p.y
}
