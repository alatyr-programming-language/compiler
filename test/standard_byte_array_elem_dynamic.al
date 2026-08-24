## Focused P1-CLAYOUT S3(d) seam: a mutable standard-byte-tier aggregate array.
## The runtime index must use the element's byte stride for both whole-element assignment and
## subsequent field/byte-element places. The source's expected result is 42; every failure below
## returns a distinct value below 126 so a backend run is diagnostic rather than a truncated value.
Leaf := struct { a : u16, b : u16 }
Elem := struct { data : [u8; 4], inner : Leaf }
main := fn() -> u64 {
  mut xs : [Elem; 2]
  xs[0] = Elem(data = [1, 2, 3, 4], inner = Leaf(a = 20, b = 22))
  xs[1] = Elem(data = [5, 6, 7, 8], inner = Leaf(a = 24, b = 26))
  mut i := 1
  xs[i] = Elem(data = [5, 6, 7, 8], inner = Leaf(a = 30, b = 33))

  if u64(xs[0].data[3]) != 4 { return 1 }
  if u64(xs[0].inner.b) != 22 { return 2 }
  if u64(xs[1].data[0]) != 5 { return 3 }
  if u64(xs[i].inner.a) != 30 { return 4 }

  xs[i].inner.b = 35
  if u64(xs[1].inner.b) != 35 { return 5 }
  xs[0].data[1] = 9
  if u64(xs[0].data[1]) != 9 { return 6 }
  if u64(xs[1].inner.b) != 35 { return 7 }
  42
}
