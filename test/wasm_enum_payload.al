Opt := enum { None, Some(u64) }
main := fn() -> u64 {
  o := Opt.Some(42)
  match o {
    Opt::None => 0
    Opt::Some(x) => x
  }
}
