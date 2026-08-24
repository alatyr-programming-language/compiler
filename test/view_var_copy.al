## e2e — REGRESSION LOCK for a SILENT MISCOMPILE: a plain Var-to-Var copy of a 2-word `{ptr, len}`
## VIEW (`str` / `Slice(T)`, Types §9.4 / §7.2) DROPPED the view. `t := s` fell through every
## aggregate branch of the `Stmt::Assign` lowering — `var_agg_info` reports ek 0 for a str slot (ek 4)
## and a slice slot (ek 5) — and landed on the generic SCALAR store: the destination was reserved as
## ONE word and only word 0 was written. `t.len` then read the neighbouring slot (0), and for a str /
## slice PARAM source — whose slot holds a POINTER to the caller's pair, not the pair itself — even
## the stored DATA POINTER was that block address. Both silent; both present on the frozen seed too.
##
## Why `Slice(u8)` / `Slice(u32)` params were CORRECT while `Slice(u64)` was not: `bind_param` only
## recognizes an element in its `known_scalar_slice` set (`u64`/`usize`/`i64`/`isize`/`f64`, plus
## `str`/struct/enum) as a real ek-5 slice VIEW. Any other element width falls through to the
## base-name binding, where `Slice` resolves to the NOMINAL library struct (`lib/base/slice.al`) and
## the param binds as an ordinary 2-word STRUCT (ek 2) — whose plain struct-var copy path was already
## correct. So the accident of NOT being recognized as a view is exactly what saved the narrow widths.
##
## The fix routes a view-Var RHS through `emit_str_pair` + `emit_pair_field_store` (the pair
## materializer/store the str-FIELD path already used) and reserves the destination as a 2-word view.
## Values: every check returns its own code; 42 = all shapes correct.

B := struct { v : str }
P := struct { x : u64, y : u64 }

## a `str` PARAM copy — the LENGTH word
slen := fn(s : str) -> u64 {
  t := s
  return u64(t.len)
}

## a `str` PARAM copy — the DATA POINTER (was the caller's pair address, so this read garbage)
sbyte := fn(s : str) -> u64 {
  t := s
  return u64(bytes(t)[1])
}

## a `Slice(u64)` PARAM copy — the broken element width (a recognized ek-5 view)
len64 := fn(s : Slice(u64)) -> u64 {
  t := s
  return u64(t.len)
}

## a `Slice(u32)` PARAM copy — CORRECT before the fix (binds as the nominal `Slice` struct); must STAY correct
len32 := fn(s : Slice(u32)) -> u64 {
  t := s
  return u64(t.len)
}

## a `Slice(u8)` PARAM copy — likewise correct before the fix; must STAY correct
len8 := fn(s : Slice(u8)) -> u64 {
  t := s
  return u64(t.len)
}

main := fn() -> u64 {
  ## (1) a `str` LOCAL copy — `t.len` read 0
  s := "hello"
  t := s
  if u64(t.len) != 5 { return 1 }
  ## (2) copy-then-INDEX — the copy is a real str local, so `t[i]` indexes its own bytes
  if u64(t[1]) != 101 { return 2 }
  ## (3) a `str` PARAM copy — the length AND the data pointer were both wrong
  if slen("hello") != 5 { return 3 }
  if sbyte("hello") != 101 { return 4 }
  ## (4) a `Slice(u64)` LOCAL copy
  a : [4]u64 = [10, 20, 30, 40]
  v := a[0..4]
  w := v
  if u64(w.len) != 4 { return 5 }
  if w[2] != 30 { return 6 }
  ## (5) a `Slice(u64)` PARAM copy
  if len64(a[0..3]) != 3 { return 7 }
  ## (6) the NARROW element widths — correct BEFORE the fix, must stay correct
  b : [3]u32 = [1, 2, 3]
  c : [2]u8 = [1, 2]
  if len32(b[0..3]) != 3 { return 8 }
  if len8(c[0..2]) != 2 { return 9 }
  ## (7) the FIELD-sourced copy `h := g.v` has its OWN dedicated path — it was already correct
  g := B(v = "hello")
  h := g.v
  if u64(h.len) != 5 { return 10 }
  ## (8) a plain-STRUCT copy must stay correct (this is not the view representation)
  p := P(x = 3, y = 4)
  q := p
  if q.x + q.y != 7 { return 11 }
  return 42
}
