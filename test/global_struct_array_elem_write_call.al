## e2e — whole-element WRITE into a mutable STRUCT-array GLOBAL from a struct-RETURNING CALL
## (`GS[i] = mk(…)`). The call has no frame home, so its returned words land in the down-growing
## agg-temp block first and are then copied into `.data` element i — the same two-step the struct
## LITERAL form uses. Was the same silent no-op as the VAR form. A WIDE (>7-word SRET) call is
## deliberately NOT covered: it stays fail-loud. 45. (x86_64: the riscv64 backend `ebreak`s on a
## call RHS here, so this fixture TRAPS — never runs wrong — on that sweep.)
Pt := struct { x : u64, y : u64, z : u64 }

mut GS := [Pt(x = 1, y = 2, z = 3), Pt(x = 4, y = 5, z = 6)]

mk := fn(b : u64) -> Pt {
  Pt(x = b, y = b + 1, z = b + 2)
}

main := fn() -> u64 {
  GS[0] = mk(10)
  if GS[0].x != 10 { return 1 }
  if GS[0].y != 11 { return 2 }
  if GS[0].z != 12 { return 3 }
  mut i : u64 = 1
  GS[i] = mk(3)
  if GS[1].x != 3 { return 4 }
  if GS[1].z != 5 { return 5 }
  GS[0].x + GS[0].y + GS[0].z + GS[1].x + GS[1].y + GS[1].z   ## 33 + 12 = 45
}
