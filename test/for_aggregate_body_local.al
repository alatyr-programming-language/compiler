## e2e (#1321) — `for x in xs` over aggregate elements visits every element when the body binds a
## local (Control Flow §6). x86_64 kept the hidden loop index at `slot(x) + stride`, the slot of the
## body's first local, so the local's store reset the index and the loop ran once. Each check returns
## its own code; 42 is a pass.
P := struct { a : u64, b : u64 }
E := enum { N, W(u64, u64) }

mut G : [P; 2] = [P(a = 5, b = 0), P(a = 6, b = 0)]

main := fn() -> u64 {
  ps := [P(a = 3, b = 1), P(a = 4, b = 2)]
  ## a struct-element slice view
  qs := ps[0..2]
  mut t : u64 = 0
  for p in qs {
    pa : u64 = p.a
    t += pa
  }
  if t != 7 { return 1 }
  ## a struct-element array
  mut u : u64 = 0
  for p in ps {
    pb : u64 = p.b
    u += pb
  }
  if u != 3 { return 2 }
  ## an enum-element slice view
  es := [E.W(1, 2), E.N, E.W(3, 4)]
  vs := es[0..3]
  mut n : u64 = 0
  for e in vs {
    one : u64 = 1
    n += one
  }
  if n != 3 { return 3 }
  ## a struct-element global array
  mut g : u64 = 0
  for p in G {
    ga : u64 = p.a
    g += ga
  }
  if g != 11 { return 4 }
  42
}
