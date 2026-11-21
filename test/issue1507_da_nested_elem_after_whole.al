## #1507: `root.array[i].field = v` after a whole-element write `root.array[j] = …` to the same array
## field. The first leaf write of element `i` discharges the element's own definite-assignment marker
## and expands it into one marker per field; writing every field then initializes `p` completely, so
## reading it whole is well-formed (Type System §9.4, field-sensitive definite assignment). The checker
## used to discharge that marker with a call passing seven arguments to a five-parameter function, so
## the marker stayed behind and `q := p` was refused as `unbound name`. Only element 1 is read: the
## value of the whole-element store itself is #1825.
Inner := struct { v : u64, w : u64 }
Outer := struct { xs : [Inner; 2] }
main := fn() -> u64 {
  mut p : Outer
  p.xs[0] = Inner(v = 1, w = 2)
  p.xs[1].v = 19
  p.xs[1].w = 20
  q := p
  return q.xs[1].v + q.xs[1].w + 3
}
## expect: run 42
