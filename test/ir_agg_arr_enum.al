## IR #1705: a fixed array local of ENUM elements, and an UNANNOTATED array literal of struct literals,
## both one frame object of `N * stride` bytes (Types §6.4). The enum array is built zeroed first, then
## element by element; `xs[i] = v` evaluates the index, then the value, then checks the index.
Shape := enum { Dot, Line(u32), Box(u16, u16) }
Pt := struct { x : u16, y : u16 }
area := fn(s : Shape) -> u64 {
  match s {
    Shape::Dot => { 1 }
    Shape::Line(n) => { u64(n) }
    Shape::Box(w, h) => { u64(w) * u64(h) }
  }
}
main := fn() -> u64 {
  mut ss : [Shape; 3] = [Shape.Dot, Shape.Line(5), Shape.Box(2, 3)]
  mut r : u64 = 0
  mut k : usize = 0
  loop {
    if k == ss.len { break }
    r = r + area(ss[k])                   ## 1 + 5 + 6 = 12
    k = k + 1
  }
  k = 0
  ss[k] = Shape.Box(4, 5)                 ## 20
  ss[2] = ss[1]                           ## 5
  r = r + area(ss[0]) + area(ss[2])       ## 12 + 20 + 5 = 37
  ps := [Pt(x = 1, y = 2), Pt(x = 3, y = 4)]
  mut j : usize = 1
  r + u64(ps[j].x) + u64(ps[0].y) - u64(ps.len) + 2   ## 37 + 3 + 2 - 2 + 2 = 42
}
## expect: run 42
