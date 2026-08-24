## §8 FURTHER-NESTED aggregate sub-field read from a @packed struct (spec Types §8) — `r.mid.inner.c`,
## a scalar TWO levels deep inside a nested-struct field of a packed struct, plus the whole aggregate
## field passed BY-REFERENCE to a fn (`sumit(r.mid.inner)`). The aggregate field `mid` sits at an
## 8-aligned byte offset (the word-model emitters store it there); the nested chain resolves through
## the word-model slot layout inside it. Returns r.tag + sumit(r.mid.inner) = 5 + (15 + 22) = 42.
Deep := struct { c : u64, d : u64 }
Mid  := struct { inner : Deep }
Rec  := @packed struct { tag : u8, @offset(8) mid : Mid }

sumit := fn(p : Deep) -> u64 { p.c + p.d }

main := fn() -> u64 {
  r := Rec(tag = 5, mid = Mid(inner = Deep(c = 15, d = 22)))
  if r.mid.inner.c != 15 { return 1 }        ## further-nested (2-deep) scalar sub-field read
  if r.mid.inner.d != 22 { return 2 }        ## further-nested (2-deep) scalar sub-field read
  by := sumit(r.mid.inner)                    ## whole aggregate field passed BY-REFERENCE
  if by != 37 { return 3 }
  u64(r.tag) + by
}
