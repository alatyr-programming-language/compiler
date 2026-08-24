## The entry module for the MOD-9 static-link e2e. `add1` lives in `stub.c`, compiled to a local
## archive `libstub.a` by the harness and absorbed statically (`libs = [Lib(name = "stub")]`, the
## default LinkMode.static; `linker_flags = ["-L<dir>"]` points `ld` at the archive). add1(41) = 42.
add1 := @extern @abi(c) fn(a : i64) -> i64

main := fn() -> u64 {
  return u64(add1(41))
}
