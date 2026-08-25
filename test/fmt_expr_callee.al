## §5 fmt (FN-6) — a call through an EXPRESSION CALLEE round-trips. `Expr::Call` carries its callee as a
## NAME SPAN, so `fs[0](10)` is represented as an ORDINARY call whose ARGUMENT 0 IS the callee expression,
## with the name span BORROWED from the callee chain's root variable (`fs`) and the site recorded in
## `ast::ecallee_mark`. fmt did not know that and rendered the node LITERALLY as `fs(fs[0], 10)` — a
## DIFFERENT program, and a silent one (it still built and ran, to another value). Locked here: the four
## spellings (element / runtime index / struct-field array / parenthesized) plus an ORDINARY call in the
## same file, so the disambiguation is exercised in both directions.
##   first function-value call 10 + second function-value call 10 + runtime-index call 10 +
##   parenthesized call 10 + add1(9) 10 + t.fs[j](3) loop 10
##   + ops[0](4, 6) 10 + id(ops[1](14, 4)) 10 = 80
add1 := fn(x : u64) -> u64 {
  return x + 1
}

dbl := fn(x : u64) -> u64 {
  return x * 2
}

add := fn(a : u64, b : u64) -> u64 {
  return a + b
}

sub := fn(a : u64, b : u64) -> u64 {
  return a - b
}

id := fn(x : u64) -> u64 {
  return x
}

Tbl := struct {
  fs : [fn(u64) -> u64; 2],
}

main := fn() -> u64 {
  fs : [fn(u64) -> u64; 2] = [add1, dbl]
  ops : [fn(u64, u64) -> u64; 2] = [add, sub]
  r1 := fs[0](9)
  r2 := fs[1](5)
  mut r3 : u64 = 0
  mut i : u64 = 0
  while i < 2 {
    r3 = r3 + fs[i](3)
    i = i + 1
  }
  r4 := (fs[0])(9)
  r5 := add1(9)
  t := Tbl(fs = [add1, dbl])
  mut r6 : u64 = 0
  mut j : u64 = 0
  while j < 2 {
    r6 = r6 + t.fs[j](3)
    j = j + 1
  }
  r7 := ops[0](4, 6)
  r8 := id(ops[1](14, 4))
  return r1 + r2 + r3 + r4 + r5 + r6 + r7 + r8
}
