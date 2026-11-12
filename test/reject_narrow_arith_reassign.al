## e2e (#1283) - the same place, the same rule, reached through comptime arithmetic: `x = 200 + 100`
## into a `u8` is the exact sum 300, not representable in `u8`, so it fails where it is written
## (Comptime §2.6) exactly as the declaration `K : u8 = 200 + 100` already does. Measured on main
## `aab6ce1a`: check rc 0, run rc 5 - the place held 300 in a `u8`.
main := fn() -> u64 {
  mut x : u8 = 1
  x = 200 + 100
  u64(x)
}
## expect: reject "comptime overflow" "at line 7"
