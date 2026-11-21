## IR-37 (#1786): a struct with an aggregate field (a struct, an `Option`, an enum) beside narrow
## scalars, reached through a pointer. Since IR-39 the shared IR lays out such a pointee when every
## child is in the WORD-tier image, but `I` holds a field narrower than a word, so this one is still
## refused (`expr Deref: struct pointee with a sub-word scalar in a nested aggregate field`). `get`,
## `put` and `whole` are therefore left to each target's legacy emitter; the program must still answer
## the spec's value. `I` keeps a word-wide field: x86_64's legacy constructor drops a nested struct whose
## fields are all narrower than a word (#1792).
I := struct { q : u8, r : i64 }
E := enum { A, B(u64) }
S := struct { a : u8, i : I, o : Option(u64), e : E, c : i16 }
put := fn(p : ptr(mut S), v : i16) { deref(p).c = v }
get := fn(p : ptr(S)) -> i16 { deref(p).c }
whole := fn(p : ptr(S)) -> u64 {
  v : S = deref(p)
  if v.a != 1 or v.i.q != 2 or v.i.r != -3 or v.c != -9 { return 1 }
  0
}
main := fn() -> u64 {
  mut s := S(a = 1, i = I(q = 2, r = -3), o = Option(u64).Some(4), e = E.B(5), c = 6)
  put(ptr(mut s), -9)
  if get(ptr(s)) != -9 { return 1 }
  if whole(ptr(s)) != 0 { return 2 }
  if s.a != 1 or s.i.r != -3 { return 3 }
  42
}
## expect: run 42
