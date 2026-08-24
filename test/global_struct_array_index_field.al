## e2e — direct indexed field read on a mutable STRUCT-array global (`ARR[i].x`). Element i's fields sit
## ascending in .data at LABEL + i*stride*8 + fieldidx*8; the Field(Index(...)) read computes that address
## and loads. Runtime index. ARR[0].x=40, ARR[0].y=1, ARR[1].x=1 → 40+1+1 = 42.
Pt := struct { x : u64, y : u64 }
mut ARR := [Pt(x = 40, y = 1), Pt(x = 1, y = 0)]
main := fn() -> u64 {
  mut i := 0
  ARR[i].x + ARR[0].y + ARR[1].x
}
