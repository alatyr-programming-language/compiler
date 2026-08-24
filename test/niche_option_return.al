## §8 @niche — a folded `Option(ptr(T))` as a fn RETURN and as a PARAM. `mk` returns `Option(ptr(u64))`,
## delivered as ONE folded word in %rax (Some(p)=p, None=0) — not the 2-register enum convention (a folded
## return type is not recognized as an enum, so it needs its own dispatch in both return paths). `get`
## takes the folded Option(ptr) as a param and matches it. Also exercises `o := mk(...)` binding a 1-word
## folded slot for the call result. s = deref(mk(ptr(v))) = 42; n = get(None) = 0; 42 + 0 = 42.
mk := fn(x : ptr(u64)) -> Option(ptr(u64)) { return Option(ptr(u64)).Some(x) }
get := fn(o : Option(ptr(u64))) -> u64 { return match o { Some(p) => deref(p) None => 0 } }
main := fn() -> u64 {
  mut v : u64 = 42
  o := mk(ptr(v))
  s := get(o)
  n := get(Option(ptr(u64)).None)
  return s + n
}
