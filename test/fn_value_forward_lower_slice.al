## FN-VALUE residual: forwarding a function value through a second wrapper.
## The direct and forwarded paths both validate the computed value; a code
## pointer accidentally passed as a Slice (or a Slice passed as the code
## pointer) must not become a silent normal exit.
byte_slice := fn(data : ptr(mut u8), length : usize) -> Slice(u8) {
  Slice(u8)(ptr = data, len = length)
}

measure := fn(src : Slice(u8), dst : Slice(u8)) -> u64 { src.len + dst.len }

roundtrip := fn(
  f : fn(Slice(u8), Slice(u8)) -> u64,
  src : Slice(u8),
  dst : Slice(u8),
) -> u64 { f(src, dst) }

wrapper := fn(p : Slice(u8), q : Slice(u8)) -> u64 {
  roundtrip(measure, p, q)
}

main := fn() -> u64 {
  mut a : [u8; 2] = [1, 2]
  mut b : [u8; 3] = [3, 4, 5]
  x := byte_slice(ptr(a[0]), 2)
  y := byte_slice(ptr(b[0]), 3)
  direct := roundtrip(measure, x, y)
  forwarded := wrapper(x, y)
  if direct == 5 and forwarded == 5 { 42 } else { 0 }
}
