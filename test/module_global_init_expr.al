## e2e — mutable global INITIALIZERS are comptime-evaluated, not just bare literals: arithmetic and
## module-const references fold to the `.data` `.quad`. Exercises scalar, struct-field, and
## array-element initializer expressions:
##   G = BASE*2 = 20 ; S = Pt(BASE+5=15, 3) ; T = [BASE-6=4, 0]. Returns 20+15+3+4 = 42.
Pt := struct { x : u64, y : u64 }
BASE := 10
mut G := BASE * 2
mut S := Pt(x = BASE + 5, y = 3)
mut T := [BASE - 6, 0 - 0]
main := fn() -> u64 {
  G + S.x + S.y + T[0]
}
