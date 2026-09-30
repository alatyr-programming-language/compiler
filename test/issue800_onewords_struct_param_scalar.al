## Issue #800, the same root cause outside enum payloads. A one-word struct parameter used where its
## single word is the whole value was read as the POINTER its by-reference slot holds, not the value
## behind it. On the parent this program built cleanly and exited 2: `s == t` compared the two
## addresses (false for equal structs). The whole-struct store into a struct FIELD (`w.inner = s`)
## and through a pointer (`deref(p) = s`) stored the address too, answering 3 and 4 once the first
## check is fixed alone.
S1 := struct { k1 : u64 }
W := struct { inner : S1, z : u64 }
same := fn(s : S1, t : S1) -> bool { return s == t }
into_field := fn(s : S1) -> u64 {
  mut w : W = W(inner = S1(k1 = 0), z = 0)
  w.inner = s
  w.inner.k1
}
through_ptr := fn(s : S1) -> u64 {
  mut t : S1 = S1(k1 = 0)
  p := ptr(mut t)
  deref(p) = s
  deref(p).k1
}
main := fn() -> u64 {
  if same(S1(k1 = 7), S1(k1 = 7)) == false { return 2 }
  if into_field(S1(k1 = 12)) != 12 { return 3 }
  if through_ptr(S1(k1 = 13)) != 13 { return 4 }
  42
}
