## e2e — the READ-ONLY base::slice functional toolkit + base::cmp min/max/clamp (now pub). Over a
## Slice(u64) BOUND TO A LOCAL (`s := arr[0..5]`, then passed to each fn — the slice-local-as-arg len
## truncation is now fixed): len/reduce(sum)/count_if/any/all/contains/find/first/last, using fn-value
## predicates/comparators (Memory §6). cmp is scalar. Returns 42 iff all exact.
sl := base::slice
cm := base::cmp

is_even := fn(x : u64) -> bool { x - (x / 2) * 2 == 0 }
add := fn(acc : u64, x : u64) -> u64 { acc + x }
is_four := fn(x : u64) -> bool { x == 4 }

opt_is := fn(o : Option(u64), want : u64) -> bool {
  match o { Option::Some(v) => { v == want } Option::None => { false } }
}
opt_usz_is := fn(o : Option(usize), want : usize) -> bool {
  match o { Option::Some(v) => { v == want } Option::None => { false } }
}

main := fn() -> u64 {
  arr : [u64; 5] = [3, 1, 4, 1, 5]
  s := arr[0..5]                                   ## a slice LOCAL, passed to each toolkit fn below

  if sl::len(u64, s) != 5 { return 1 }
  if sl::reduce(u64, u64, s, 0, add) != 14 { return 2 }
  if not sl::any(u64, s, is_even) { return 3 }
  if sl::all(u64, s, is_even) { return 4 }
  if not sl::contains(u64, s, 4) { return 5 }
  if sl::contains(u64, s, 9) { return 6 }
  if sl::count_if(u64, s, is_even) != 1 { return 7 }
  fi := sl::find(u64, s, is_four)
  if not opt_usz_is(fi, 2) { return 8 }
  f := sl::first(u64, s)
  if not opt_is(f, 3) { return 9 }
  l := sl::last(u64, s)
  if not opt_is(l, 5) { return 10 }

  if cm::min(u64, 3, 5) != 3 { return 11 }
  if cm::max(u64, 3, 5) != 5 { return 12 }
  if cm::clamp(u64, 10, 0, 7) != 7 { return 13 }
  if cm::clamp(u64, 4, 0, 7) != 4 { return 14 }
  return 42
}
