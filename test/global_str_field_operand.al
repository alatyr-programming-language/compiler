## Issue #20 / Types §9.4 — a `str` field must remain a two-word value when it
## is an operand of `str_eq`. This covers a direct module-level global field and
## a nested local field chain (plus global/by-ref/const controls). The correct
## result is 42; the parent compiler returned 63 because every field became an
## empty string.
S := struct { name : str }
I := struct { name : str }
O := struct { q : I }
mut G := S(name = "Alice")
mut GP := O(q = I(name = "Bo"))
CG := S(name = "Clare")
CP := O(q = I(name = "Dora"))

check_nested := fn(p : O) -> u64 {
  if str_eq(p.q.name, "Bo") { return 1 }
  0
}

main := fn() -> u64 {
  p := O(q = I(name = "Bo"))
  mut bad : u64 = 0
  if not str_eq(G.name, "Alice") { bad += 1 }
  if not str_eq(p.q.name, "Bo") { bad += 2 }
  if not str_eq(GP.q.name, "Bo") { bad += 4 }
  if check_nested(p) == 0 { bad += 8 }
  if not str_eq(CG.name, "Clare") { bad += 16 }
  if not str_eq(CP.q.name, "Dora") { bad += 32 }
  if bad == 0 { return 42 }
  bad
}
