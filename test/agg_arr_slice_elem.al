## e2e — a range-slice VIEW over an AGGREGATE-ELEMENT array. `s := ps[1..3]` inherits the base array's
## element stride, so `s[j]` addresses element (view-start + j*stride) and `s[j].f` reads its field.
## The view deliberately starts at element 1, so a slice that ignored the aggregate stride (advancing
## by ONE word instead of the struct's width) would read a neighbouring element's field — every field
## holds a distinct non-zero value, so that shows up in the answer. A runtime index is used for one
## read and a constant for the others. Returns 18.
Pt := struct { x : u64, y : u64 }
main := fn() -> u64 {
  ps := [Pt(x = 1, y = 2), Pt(x = 3, y = 4), Pt(x = 5, y = 6), Pt(x = 7, y = 8)]
  s := ps[1..3]                          ## the view is {Pt(3,4), Pt(5,6)}
  mut j := 1
  s[j].y + s[0].x + s[0].y + s[1].x      ## 6 + 3 + 4 + 5 = 18
}
