## Regression — a scalar element write through a pointer-derived struct array field.
## The parser must preserve `deref(p).arr[i] = v` as an IndexAssign whose base is the
## dereferenced struct field; lowering must emit both this writer and its caller.
S := struct { pad : u64, arr : [u64; 2] }

write_arr := fn(p : ptr(mut S), i : u64, v : u64) {
  deref(p).arr[i] = v
}

main := fn() -> u64 {
  mut s := S(pad = 2, arr = [0, 0])
  write_arr(ptr(mut s), 1, 40)
  u64(s.pad + s.arr[1])
}
