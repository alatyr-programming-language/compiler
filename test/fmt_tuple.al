## `alatyr fmt` fixture — the TUPLE spellings, plus a `mut` struct FIELD. Every form here shares its
## AST node with an ARRAY form, so fmt has to read the written bracket back out of the source or it
## silently rewrites the program: a tuple LITERAL `(3, 4)` and a tuple TYPE in expression position
## (the tuple type supplied to `cnt`) are both `Expr::ArrayLit`, exactly as `[3, 4]` is; a component read
## `p.0`, a
## nested one `t.1.0`, and the write `t.1.0 = v` are all `Index(base, Num(N, 0, 0))`, exactly as
## `p[0]` is; and `a.0[2]` mixes a `.N` step with a real `[i]` step in one chain. `S`'s `mut x` is
## recorded nowhere in the AST either — CT-6 `Field.mutable` re-reads it from source, so dropping the
## marker changes what `count_mut` returns. Returns 42 iff every value survived the reformat.
S := struct { mut x : u64, y : u64 }

count_mut := fn(T : type) -> u64 {
  mut n : u64 = 0
  comptime for f in typeinfo(T).fields {
    if f.mutable { n = n + 1 }
  }
  n
}

cnt := fn(T : type) -> u64 {
  mut acc : u64 = 0
  comptime for i in 0..typeinfo(T).n {
    acc = acc + 1
  }
  return acc
}

main := fn() -> u64 {
  p : (u64, u64) = (3, 4)
  if p.0 != 3 { return 1 }
  if p.1 != 4 { return 2 }
  mut t := (10, (99, 88))
  t.1.0 = 20
  t.1.1 = 12
  if t.0 != 10 { return 3 }
  if t.1.0 != 20 { return 4 }
  if t.1.1 != 12 { return 5 }
  mut a : ([u8; 4], u64) = ([1, 2, 3, 4], 9)
  a.0[2] = 7
  if a.0[0] != 1 { return 6 }
  if a.0[2] != 7 { return 7 }
  if a.1 != 9 { return 8 }
  if count_mut(S) != 1 { return 9 }
  if cnt((u64, u64)) != 2 { return 10 }
  42
}
