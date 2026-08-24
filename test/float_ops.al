## e2e: f64 across the language surface — struct fields, array elements, comparison (incl. the
## ordered/NaN semantics), and a comparison-driven accumulation loop. Expected process exit: 42.
##   p.a + p.b      = 2.5 + 1.5 = 4.0        -> 4   (float STRUCT FIELDS in arithmetic)
##   xs[0] + xs[1]  = 6.0 + 2.5 = 8.5        -> 8   (float ARRAY ELEMENTS)
##   loop: add 0.5 while acc < 10.0          -> 10  (float COMPARISON drives the loop; 20 iters)
##   ordered/NaN compares contribute                -> 20  (see `flags` below)
##   total                                           = 42
P := struct { a : f64, b : f64 }

main := fn() -> u64 {
  p : P = P(a = 2.5, b = 1.5)
  fields : u64 = u64(p.a + p.b)                 ## 4

  xs : [f64; 2] = [6.0, 2.5]
  elems : u64 = u64(xs[0] + xs[1])              ## 8

  mut acc : f64 = 0.0
  while acc < 10.0 { acc = acc + 0.5 }
  loopv : u64 = u64(acc)                        ## 10

  ## ordered + NaN comparison flags: a<b, b>=b, a==a true; NaN relations all false except `!=`.
  a : f64 = 1.0
  b : f64 = 2.0
  z : f64 = 0.0
  nanv : f64 = z / z
  mut flags : u64 = 0
  if a < b { flags = flags + 1 }                ## +1
  if b >= b { flags = flags + 1 }               ## +1
  if a == a { flags = flags + 1 }               ## +1
  if nanv == nanv { flags = flags + 100 }       ## NOT taken (NaN == NaN is false)
  if nanv < a { flags = flags + 100 }           ## NOT taken (ordered, NaN)
  if nanv != a { flags = flags + 17 }           ## +17 (!= is true for NaN)

  return fields + elems + loopv + flags         ## 4 + 8 + 10 + 20 = 42
}
