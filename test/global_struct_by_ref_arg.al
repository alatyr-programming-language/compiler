## e2e — a mutable struct GLOBAL passed BY REFERENCE as an ordinary aggregate argument. A global's
## .data is ascending but the by-ref ABI is down-growing, so emit_arg materializes the global into a
## down-growing agg-temp first, then passes that address. Covers both a user fn (sum(S)) and a print
## Display hole. sum(S) = 40 + 2 = 42.
Pt := struct { x : u64, y : u64 }
mut S := Pt(x = 40, y = 2)
sum := fn(p : Pt) -> u64 { p.x + p.y }
main := fn() -> u64 {
  std::fmt::print("S {}\n", S)
  sum(S)
}
