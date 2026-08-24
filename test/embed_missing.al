## build_reject — `embed` FAILS LOUD on a missing / unopenable file (Comptime §2.4): the build must
## error (non-zero rc), never bake a silently-empty byte array. `embed_strlit` opens the path at parse
## time and `panic`s when `open(2)` returns < 0. Wired as `build_reject` (asserts a non-zero build rc).
main := fn() -> u64 {
  e := embed("test/no_such_embed_file_zzz.bin")
  return e.len
}
