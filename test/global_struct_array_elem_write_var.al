## e2e — whole-element WRITE into a mutable STRUCT-array GLOBAL from a struct VARIABLE (`GS[i] = q`),
## the shape the LITERAL form (`GS[i] = Pt(…)`) already covered and the LOCAL-array form (`xs[i] = q`)
## already covered, but which on the global was a SILENT NO-OP: the global name has no frame slot, so
## the write fell through to the generic `emit_index_addr` tail, resolved to slot 0, and stored ONE
## word at a bogus %rbp offset — the store vanished and the ORIGINAL `.data` words read back.
## Covers a CONSTANT index and a RUNTIME index, all three words of a 3-word element, and the
## untouched neighbour. 93 - 30 = 63 on x86_64 and riscv64 alike (rv64 implements this shape, so a
## MATCH here is agreement between two independent backends).
Pt := struct { x : u64, y : u64, z : u64 }

mut GS := [Pt(x = 1, y = 2, z = 3), Pt(x = 4, y = 5, z = 6), Pt(x = 7, y = 8, z = 9)]

main := fn() -> u64 {
  q := Pt(x = 30, y = 31, z = 32)
  ## CONSTANT index — every word of the source struct must land
  GS[0] = q
  if GS[0].x != 30 { return 1 }
  if GS[0].y != 31 { return 2 }
  if GS[0].z != 32 { return 3 }
  ## RUNTIME index — the same store scaled by the element stride
  mut i : u64 = 2
  r := Pt(x = 10, y = 11, z = 12)
  GS[i] = r
  if GS[2].x != 10 { return 4 }
  if GS[2].y != 11 { return 5 }
  if GS[2].z != 12 { return 6 }
  ## the untouched middle element is intact (the writes were element-local, not overlapping)
  if GS[1].x != 4 { return 7 }
  if GS[1].y != 5 { return 8 }
  if GS[1].z != 9 - 3 { return 9 }
  ## the source locals were read, not aliased
  if q.x != 30 { return 10 }
  if r.z != 12 { return 11 }
  GS[0].x + GS[0].y + GS[0].z + GS[2].x + GS[2].y + GS[2].z - 30    ## 93 + 33 - 30 = 96
}
