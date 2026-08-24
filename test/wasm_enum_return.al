Opt := enum { Some(u64), None }
make := fn() -> Opt { return Opt.Some(42) }
main := fn() -> u64 {
  o := make()
  return match o { Opt::Some(x) => x, _ => 0 }
}
