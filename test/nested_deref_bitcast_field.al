## P0 / Memory §§1.6, 4.3, 4.6: a pointer bitcast to a standard-layout
## struct may be dereferenced before walking multiple field hops. The inner
## struct starts at byte 8 and b at byte 10; a word-tier offset (72 here)
## silently read the wrong location instead of the required byte offset.
Inner := struct { a : u16, b : u16 }
Elem := struct { data : [u8; 8], inner : Inner }

main := fn() -> u64 {
  mut o := Elem(data = [1,2,3,4,5,6,7,8], inner = Inner(a = 20, b = 42))
  return deref(bitcast(ptr(Elem), ptr(o))).inner.b
}
