## e2e (comma-separated EXPRESSION-match arms — `match x { a => v, b => v, _ => v }`). The
## expression-match arm loop consumed only `;` as an arm separator; a `,` (the natural int/str-match
## syntax) parked the parser on the comma and it desynced into UNBOUNDED p_factor recursion — a
## compiler stack-overflow CRASH. Now the arm loop consumes both `;` and `,`. Exercises: an INTEGER
## expression-match bound to a local (`r := match n {…}`), an integer match on a LITERAL scrutinee,
## and a comma-separated STR-literal match — all with `,` separators, in value position.
classify := fn(s : str) -> u64 {
  return match s { "fn" => 10, "return" => 20, _ => 1 }
}
pick := fn(n : u64) -> u64 {
  r := match n { 1 => 5, 2 => 7, 3 => 9, _ => 0 }
  return r
}
main := fn() -> u64 {
  ## integer expression-match, comma arms, bound to a local
  a := pick(2)          ## 7
  b := pick(3)          ## 9
  z := pick(99)         ## 0 (wildcard)
  ## integer match on a LITERAL scrutinee (comma arms)
  lit := match 3 { 1 => 100, 3 => 6, _ => 0 }   ## 6
  ## comma-separated str-literal match in value position
  s := classify("fn") + classify("x")           ## 10 + 1 = 11
  a + b + z + lit + s + 9                        ## 7 + 9 + 0 + 6 + 11 + 9 = 42
}
