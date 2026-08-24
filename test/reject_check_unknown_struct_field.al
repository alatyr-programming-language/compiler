## TYP-8 check/build parity: an unknown named struct field must be rejected
## during check just as it is during build.
S := struct { x : u64 }
main := fn() -> u64 {
  s := S(unknown = 42)
  s.x
}
