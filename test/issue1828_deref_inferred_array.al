## Issue #1828 — a whole fixed array copied out of a pointer into an INFERRED local, `t := deref(p)` over
## `p : ptr([u64; 2])`. Memory §4.3: `deref(p)` in value context loads the place it denotes; Types §6.4
## makes `[T; N]` a value of `N` contiguous elements, so `t` is a `[u64; 2]` holding both elements, and its
## `.len` is 2. x86_64 sized `t` as one word: copying it on into `v : [u64; 2]` repeated the one word, and
## `t.len` read a frame slot nothing wrote; `t[1]` was refused as indexing a scalar local. With `p` a
## PARAMETER, `t` was bound as a slice view: element 0 taken as its data pointer, element 1 as its length
## (`t.len` answered 4 here, and `t[1]` faulted). aarch64, riscv64 and wasm trapped; they refuse the copy
## at compile time, located, until they copy it (#1811).
## Due 42: 30 + 4 from the words copied on through `t`, 2 from `t.len`, 4 from `t[1]`, 2 from the
## parameter's `t.len`.
## spec: Memory §4.3; Types §6.4
copy_on := fn(h : usize) -> u64 {
  p : ptr([u64; 2]) = unchecked bitcast(ptr([u64; 2]), h)
  t := deref(p)
  v : [u64; 2] = t
  v[0] + v[1]
}
len_of := fn(h : usize) -> u64 {
  p : ptr([u64; 2]) = unchecked bitcast(ptr([u64; 2]), h)
  t := deref(p)
  t.len
}
second := fn(h : usize) -> u64 {
  p : ptr([u64; 2]) = unchecked bitcast(ptr([u64; 2]), h)
  t := deref(p)
  t[1]
}
param_len := fn(p : ptr([u64; 2])) -> u64 {
  t := deref(p)
  t.len
}
main := fn() -> u64 {
  mut arr : [u64; 2] = [30, 4]
  h := unchecked bitcast(usize, ptr(arr))
  copy_on(h) + len_of(h) + second(h) + param_len(ptr(arr))
}
## expect: run 42
