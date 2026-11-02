Opt := enum { None, Some(u64) }
main := fn() -> u64 {
  o := Opt.Some(40)
  mut r : u64 = 0
  match o {
    Opt::None => { r = 1 }
    Opt::Some(x) => { r = x + 2 }
  }
  return r
}
## expect(aarch64): run 42
## expect(riscv64): run 42
## expect(wasm): run 42
