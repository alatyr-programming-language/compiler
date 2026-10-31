Opt := enum { None, Some(u64) }
main := fn() -> u64 {
  o := Opt.Some(42)
  match o {
    Opt::None => 0
    Opt::Some(x) => x
  }
}
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
