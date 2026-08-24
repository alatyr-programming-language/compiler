## A VALUE-yielding match arm that declares a nested local then yields it — unblocked by tree-wide
## local slots (was "works only if the arm declares no new local"). Some(20) -> 20*2=40, +2 = 42.
Opt := enum { None, Some(u64) }
main := fn() -> u64 {
  o := Opt.Some(20)
  match o {
    Opt::Some(n) => {
      doubled := n * 2
      doubled + 2
    }
    Opt::None => { 0 }
  }
}
