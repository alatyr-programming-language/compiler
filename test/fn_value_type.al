## e2e (FN-10 — the first-class FUNCTION-VALUE TYPE `fn(T…) -> R`). A function value is a one-word
## CODE ADDRESS for a non-capturing top-level fn: it can be BOUND to a typed binding, PASSED to a
## higher-order fn, STORED in a struct field, and CALLED (`f(args)` = one indirect `call *%reg`).
## This test exercises all four over the nameless type spelling `fn(u64, u64) -> u64` (FN-10: a
## parameter entry is a direction + a TYPE, with NO name):
##   1. BIND + CALL   — `op : fn(u64, u64) -> u64 = add`, then `op(a, b)` (indirect through a slot).
##   2. PASS + CALL   — `apply2(dif, x, y)` passes `dif` as a fn-value param and calls it there.
##   3. STORE + CALL  — a struct field `Ops.op : fn(u64, u64) -> u64` holds a fn value; `o.op(a, b)`
##                      calls indirectly through the field.
## Two distinct top-level fns (`add`/`dif`) prove the binding carries a real VALUE (the code
## address), not the name. 32 + 8 + 2 = 42.  (`dif`, not `sub`: `sub` is a reserved slice builtin.)
add := fn(a : u64, b : u64) -> u64 { return a + b }
dif := fn(a : u64, b : u64) -> u64 { return a - b }

## A higher-order fn: its parameter is a fn VALUE typed `fn(u64, u64) -> u64` (the all-`in` common
## case) — it is called indirectly through the passed code pointer.
apply2 := fn(f : fn(u64, u64) -> u64, x : u64, y : u64) -> u64 { return f(x, y) }

## A struct that STORES a fn value in a field (FN-10: a fn-value type is a `type-atom`, valid as a
## field type — one code-address word).
Ops := struct { op : fn(u64, u64) -> u64, base : u64 }

main := fn() -> u64 {
  ## 1. bind a fn value to a typed binding, then call it indirectly. add(30, 2) = 32.
  op : fn(u64, u64) -> u64 = add
  r1 := op(30, 2)
  ## 2. pass a fn value to a higher-order fn + call it there. dif(9, 1) = 8.
  r2 := apply2(dif, 9, 1)
  ## 3. store a fn value in a struct field + call through the field. add(1, 1) = 2.
  o := Ops(op = add, base = 100)
  r3 := o.op(1, 1)
  ## 32 + 8 + 2 = 42.
  return r1 + r2 + r3
}
