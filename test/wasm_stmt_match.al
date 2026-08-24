Opt := enum { None, Some(u64) }
main := fn() -> u64 {
  o := Opt.Some(40)
  mut r := 0
  match o {
    Opt::None => { r = 1 }
    Opt::Some(x) => { r = x + 2 }
  }
  return r
}
