## e2e (#1283) - Types §9.1 / Declarations §3.4: the TARGET PLACE is an integer literal's context, so
## a `=` re-assignment is judged for representability exactly as the annotated binding is. `x : u8 = 300`
## was already refused; `x = 300` into the same `u8` place was ACCEPTED and the place then held 300 -
## "a literal outside the target type's range is a compile error (I11), never a silent wrap". Located at
## the assignment (line 10). Measured on main `aab6ce1a`: check rc 0, run rc 5 (`y == 300` held).
main := fn() -> u64 {
  mut x : u8 = 1
  x = 200
  if u64(x) != 200 { return 1 }
  x = 300
  u64(x)
}
## expect: reject "type mismatch" "at line 10"
