## ROADMAP §4 typed-slice: slicing a raw scalar array `[u64; N]` yields a TYPED slice view — `s[i]`
## reads ELEMENTS (stride-aware through the data pointer), not bytes, and `s.len` is the runtime
## length. Previously `xs[0..3]` bound a str byte-view, so `s[i]` mis-read / segfaulted.
main := fn() -> u64 {
  xs := [10, 20, 12, 99]
  s := xs[0..3]                               ## {10, 20, 12}, len 3
  mut acc : u64 = 0
  for i in 0..s.len { acc = acc + s[i] }      ## 10 + 20 + 12 = 42
  t := xs[1..4]                               ## {20, 12, 99} — exercises lo != 0
  guard := t[0] + t[1] + t[2] - 131           ## 20 + 12 + 99 - 131 = 0
  ## a FLOAT-element slice reads through the xmm path (element kind propagated to the slice).
  fs : [f64; 3] = [1.5, 2.5, 3.0]
  fv := fs[0..3]
  fguard := u64(fv[0] + fv[1] + fv[2]) - 7    ## 1.5 + 2.5 + 3.0 = 7.0 → 0
  ## a slice is a VIEW: writing through it mutates the backing array. `w[1] = …` stores to ws[1].
  mut ws : [u64; 3] = [1, 2, 3]
  w := ws[0..3]
  w[1] = w[1] + 40
  wguard := ws[1] - 42                        ## ws[1] became 2 + 40 = 42 → 0
  return acc + guard + fguard + wguard
}
