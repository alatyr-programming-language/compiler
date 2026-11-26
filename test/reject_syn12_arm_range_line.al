## e2e — Grammar §2.6 continuing tokens (SYN-12, spec 1.12.0; #1910). `..` is not a continuing token (a
## range whose lower bound is omitted can begin an expression), so the arm `0` and the line `..5 => 1`
## are not one range pattern `0..5`: the arm `0` has no `=>`. The parser used to join the two lines and
## accept the program; it now refuses it, located at the `..`.
pick := fn(x : u64) -> u64 {
  match x {
    0
    ..5 => 1
    _ => 2
  }
}

main := fn() -> u64 {
  pick(3)
}
## expect: reject "does not continue the previous line" "at line 8"
