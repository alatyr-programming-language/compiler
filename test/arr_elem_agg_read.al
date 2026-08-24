## e2e — READ side of a LOCAL struct-element array: word-1 field read (`arr[i].b`) and whole-element
## copy (`x := arr[i]` copies BOTH words). A locking guard for the reads that back the write fixes.
Rec := struct { a : i64, b : i64 }
main := fn() -> u64 {
  arr : [Rec; 4] = [Rec(a = 100, b = 1), Rec(a = 20, b = 21), Rec(a = 0, b = 0), Rec(a = 0, b = 0)]
  x := arr[1]                            ## whole-element copy (both words: 20, 21)
  b0 := arr[0].b                         ## word-1 field read of a different element (1)
  u64(x.a + x.b + b0)                    ## 20 + 21 + 1 = 42
}
