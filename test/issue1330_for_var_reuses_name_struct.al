## #1330 — an iterable `for` whose loop var reuses a name bound earlier in the function, in a sibling
## scope that has ended (Declarations §6.1 allows it), iterates every element (Control Flow §6) and
## leaves the other locals alone. The loop's hidden index was read at the loop var's slot + 1, which is
## the slot of the local bound right after the EARLIER `p`: here `w`.
## NON-VACUOUS: on the parent da8f96af (native x86_64, tree Stage1) this answers 2 (`w` overwritten),
## on x86_64 and on aarch64, riscv64 and wasm alike.
P := struct { a : u64, b : u64 }
main := fn() -> u64 {
  ps := [P(a = 1, b = 2), P(a = 3, b = 4), P(a = 5, b = 6)]
  c := ps[0]
  if c.a == 1 {
    p := P(a = 9, b = 9)
    if p.a != 9 { return 9 }
  }
  w : u64 = 1000
  mut t : u64 = 0
  for p in ps {
    pa : u64 = p.a
    t += pa
  }
  if t != 9 { return 1 }
  if w != 1000 { return 2 }
  42
}
## expect: run 42
