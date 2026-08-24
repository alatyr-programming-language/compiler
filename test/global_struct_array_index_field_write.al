## e2e — indexed field WRITE on a mutable STRUCT-array global (`ARR[i].x = 40`). Stores into .data at
## LABEL + i*stride*8 + fieldidx*8 (ascending, runtime index). After the write ARR[0]={40,1}, so
## ARR[0].x + ARR[0].y + ARR[1].x = 40 + 1 + 1 = 42.
Pt := struct { x : u64, y : u64 }
mut ARR := [Pt(x = 10, y = 1), Pt(x = 1, y = 0)]
main := fn() -> u64 {
  mut i := 0
  ARR[i].x = 40
  ARR[i].x + ARR[0].y + ARR[1].x
}
