## #1243 — an array literal of calls returning a THREE-word struct, an `Option(u64)` and a `str`. Each
## call result is stored whole at its element's block, so every word reads back:
## (2 + 20 + 200) - 100 + 4 + (3 - 2) - 100 = 27.
P3 := struct { a : u64, b : u64, c : u64 }
mk := fn(k : u64) -> P3 { P3(a = k, b = k * 10, c = k * 100) }
opt := fn(k : u64) -> Option(u64) { if k == 0 { Option.None } else { Option.Some(k) } }
name := fn(k : u64) -> str { if k == 0 { "ab" } else { "xyz" } }
main := fn() -> u64 {
  ps := [mk(1), mk(2)]
  q := ps[1]
  os := [opt(0), opt(4)]
  ss := [name(0), name(1)]
  mut r : u64 = q.a + q.b + q.c - ps[0].c
  match os[1] {
    Option.Some(v) => { r = r + v }
    Option.None => { r = r + 1000 }
  }
  match os[0] {
    Option.Some(v) => { r = r + 1000 + v }
    Option.None => { r = r + 0 }
  }
  r = r + ss[1].len - ss[0].len
  r - 100
}
## expect: run 27
