## §8 @packed struct passed BY VALUE as a PARAMETER (spec Types §8). An aggregate argument travels by
## REFERENCE (the caller hands over its word-0 address), so the callee's slot for `p : Pk` is `is_ref`
## and used to fail the packed-LOCAL gate (`ek == 2 and not is_ref`): every field fell to the word-sized
## `movq 8*index(%rax)` read of a BYTE-precise block. `p.b` (byte 1) and `p.c` (byte 3) read 0 and `p.a`
## read the whole first word — a SILENT WRONG VALUE, while the SAME `p.b` on the caller's local read 20.
## The caller's storage is the packed byte layout, so the callee reads at the cumulative byte offset with
## a correctly-SIZED load. Values are chosen so a truncated / mis-offset load cannot coincide: b = 300
## needs 2 bytes, c = 100000 needs 4. Also covers the SECOND hop (a by-ref packed param re-passed to
## another fn, so the pointer is threaded rather than freshly `leaq`ed) and the `q := p` whole-value copy
## (which reads the packed bytes as words and must still round-trip). Returns 42.
Pk := @packed struct { a : u8, b : u16, c : u32, d : u64 }

## second hop: `p` here is a by-ref packed param that was itself re-passed from another by-ref param
deeper := fn(p : Pk) -> u64 {
  if u64(p.a) != 10 { return 11 }
  if u64(p.b) != 300 { return 12 }
  if u64(p.c) != 100000 { return 13 }
  if p.d != 7 { return 14 }
  0
}

take := fn(p : Pk) -> u64 {
  ## byte-precise reads directly off the by-value (by-ref) param
  if u64(p.a) != 10 { return 1 }
  if u64(p.b) != 300 { return 2 }
  if u64(p.c) != 100000 { return 3 }
  if p.d != 7 { return 4 }
  ## the whole-value copy still round-trips (the packed bytes are copied word-wise)
  q := p
  if u64(q.b) != 300 { return 5 }
  if u64(q.c) != 100000 { return 6 }
  ## re-pass the by-ref param onward
  deeper(p)
}

main := fn() -> u64 {
  p := Pk(a = 10, b = 300, c = 100000, d = 7)
  if size(Pk) != 15 { return 20 }
  r := take(p)
  if r != 0 { return r }
  ## the caller's own reads are unchanged by the call
  if u64(p.b) != 300 { return 21 }
  42
}
