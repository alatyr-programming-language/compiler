## e2e — Grammar §2.6 continuing tokens (SYN-12, spec 1.12.0; #1910). `..` is not a continuing token, so
## a `for` header whose range tail starts the next line is not one header: `for i in 0` ends at the
## newline and has no `{`. The parser used to join the lines into `0..5`; it now refuses, located.
main := fn() -> u64 {
  mut s : i64 = 0
  for i in 0
  ..5 {
    s += i
  }
  u64(s) + 32
}
## expect: reject "does not continue the previous line" "at line 7"
