## IR-37 (#1786): a BYTE-tier struct (a direct `[u8; N]` field puts it in the §6.1 byte layout,
## `lower_layout::layout_kind`) reached through a pointer, with narrow fields of both signednesses. The
## shared IR does not lay such a pointee out (`expr Deref: @packed or byte-layout struct pointee`):
## x86_64's legacy emitter reads and writes `deref(p).f` at the §6.1 offsets, but writes `p.f = v` at
## the word offset (#1790), so the legacy readers do not agree on one layout. Every function here is
## therefore left to its target's legacy emitter, through the `deref(p).f` form; the program must still
## answer the spec's value.
S := struct { x : u8, buf : [u8; 3], y : u32, z : i16, w : i8 }
put := fn(p : ptr(mut S)) {
  deref(p).y = 4000000000
  deref(p).z = -300
  deref(p).w = -7
}
chk := fn(p : ptr(S)) -> u64 {
  if deref(p).y != 4000000000 { return 1 }
  if deref(p).z != -300 { return 2 }
  if deref(p).w != -7 { return 3 }
  if deref(p).x != 1 { return 4 }
  0
}
main := fn() -> u64 {
  mut s := S(x = 1, buf = [2, 3, 4], y = 5, z = 6, w = 7)
  put(ptr(mut s))
  r := chk(ptr(s))
  if r != 0 { return r }
  if s.buf[0] != 2 or s.buf[2] != 4 or s.y != 4000000000 { return 5 }
  42
}
## expect: run 42
