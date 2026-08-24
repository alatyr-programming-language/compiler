## e2e — whole-element WRITE to a mutable STRUCT-array global (`ARR[i] = Pt(...)`). The struct value is
## built in the down-growing agg-temp, then its `stride` words are copied into .data element i
## (ascending: base LABEL+i*stride*8, word k at +k*8). After the write ARR[0]={40,1}, so
## ARR[0].x + ARR[0].y + ARR[1].x = 40 + 1 + 1 = 42.
Pt := struct { x : u64, y : u64 }
mut ARR := [Pt(x = 10, y = 1), Pt(x = 1, y = 0)]
main := fn() -> u64 {
  mut i := 0
  ARR[i] = Pt(x = 40, y = 1)
  ARR[i].x + ARR[i].y + ARR[1].x
}
