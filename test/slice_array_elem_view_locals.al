## #1181 — `[Slice(u8); N]` elements given as byte-slice view LOCALS store each local's {ptr, len},
## and an index into an element reads its byte. Expected exit 23: `t[1].len` = 2, `t[0][2]` = 3.
## The parent refused the element read.
main := fn() -> u64 {
  a : [u8; 3] = [1, 2, 3]
  b : [u8; 2] = [4, 5]
  x := a[0..3]
  y := b[0..2]
  t : [Slice(u8); 2] = [x, y]
  u64(t[1].len) * 10 + u64(t[0][2])
}
## expect: run 23
