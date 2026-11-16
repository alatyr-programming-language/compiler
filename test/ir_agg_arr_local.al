## IR #1705: a fixed array local of STRUCT elements, `[P; N]`, is one frame object, element `i` at byte
## `i * stride` (Types §6.4), its elements places (Memory §1.6). `P` is padded (`u8` then `u32`: size 8,
## alignment 4), so a stride taken as a word or as the unpadded field sum lands on the wrong element.
## Covered: the typed literal, a field read at a literal and at a runtime index, `xs[i].f = v`,
## `xs[i] = P(...)`, `xs[i] = q`, a whole-element read that must not alias the array, `xs.len`, a copy of
## the whole array that must not alias it, and `xs = [...]`.
P := struct { a : u8, b : u32 }
main := fn() -> u64 {
  mut xs : [P; 3] = [P(a = 1, b = 10), P(a = 2, b = 20), P(a = 3, b = 30)]
  mut i : usize = 2
  mut r : u64 = 0
  r = r + u64(xs[1].b)                    ## 20   literal index, field at offset 4
  r = r + u64(xs[i].a)                    ## 23   runtime index, element 2
  e := xs[1]                              ## a copy of (2, 20)
  xs[1].b = 7                             ## field write through a literal index
  xs[i].a = 9                             ## field write through a runtime index
  if e.b != 20 { return 1 }               ## the copy does not alias the element
  if xs[1].b != 7 { return 2 }
  if xs[2].a != 9 or xs[2].b != 30 { return 3 }
  ys := xs                                ## a copy of the whole array
  xs[0] = P(a = 4, b = 5)                 ## element write from a literal
  q := P(a = 6, b = 8)
  i = 1
  xs[i] = q                               ## element write from a variable, runtime index
  if ys[0].a != 1 or ys[1].b != 7 { return 4 }  ## the array copy does not alias
  if xs[0].b != 5 or xs[1].a != 6 { return 5 }
  r = r + u64(xs.len)                     ## 26
  xs = [P(a = 11, b = 12), xs[0], P(a = 13, b = 14)]  ## the old xs[0] read before the store
  if xs[1].a != 4 or xs[2].b != 14 { return 6 }
  r + u64(xs[0].b) + u64(xs[1].b) - 1     ## 26 + 12 + 5 - 1 = 42
}
## expect: run 42
