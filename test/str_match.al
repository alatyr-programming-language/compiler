## e2e — STR-LITERAL match patterns (§5.4): `match <str> { "fn" => …, _ => … }`. The scrutinee is a
## `str` value; each non-wildcard arm's pattern is a string literal, dispatched by BYTE-COMPARE
## (`str_eq`) rather than an integer value compare. Exercises BOTH forms: a value-match (bare-arm,
## tail-return position) in `kw`, and a statement-match (block-body) in `main`. Returns 42.
## `src/` uses `contains(str, table, w)` for keyword classification (never a str-match), so this is
## fixpoint-neutral.

## value-match (tail-return): classify a keyword to a small code (0 = not a keyword).
kw := fn(w : str) -> u64 {
  match w {
    "fn" => 1
    "let" => 2
    "return" => 3
    _ => 0
  }
}

main := fn() -> u64 {
  ## value-match arms + wildcard
  a := kw("fn")
  b := kw("let")
  c := kw("return")
  d := kw("nope")
  ## a=1, b=2, c=3, d=0
  mut ok : bool = a == 1 and b == 2 and c == 3 and d == 0

  ## statement-match with block bodies + wildcard
  w := "let"
  mut r : u64 = 0
  match w {
    "fn" => { r = 10 }
    "let" => { r = 30 }
    _ => { r = 99 }
  }
  if r != 30 { ok = false }

  ## statement-match falling to the wildcard
  x := "xyz"
  mut s : u64 = 0
  match x {
    "a" => { s = 1 }
    "b" => { s = 2 }
    _ => { s = 6 }
  }
  if s != 6 { ok = false }

  if ok { return 42 }
  1
}
