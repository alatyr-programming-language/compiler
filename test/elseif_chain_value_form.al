## e2e — the VALUE spelling of the same chain: `if … { v }`, repeated `else if` arms, and `else { z }`
## used as a bound
## expression and as a function's tail. The statement spelling already chained (the statement parser
## recurses on the `else`), but the value parser demanded a brace after `else` and blindly skipped one
## token when an `if` was there instead — reading the nested CONDITION as the else-value and swallowing
## the real brace, which drifted the cursor and killed the parse. Every arm of both chains is
## exercised, one distinct value each, so a chain that binds the wrong condition to the wrong value
## cannot pass. Returns 42; the first input that disagrees returns its own code 100..106 (each under
## 126, which is wasm's `proc_exit` ceiling).
bound := fn(n : u64) -> u64 {
  v := if n == 0 { 3 } else if n == 1 { 4 } else if n == 2 { 5 } else { 6 }
  return v
}
tail := fn(n : u64) -> u64 {
  if n == 0 { 7 } else if n == 1 { 8 } else { 9 }
}
main := fn() -> u64 {
  if bound(0) != 3 { return 100 }
  if bound(1) != 4 { return 101 }
  if bound(2) != 5 { return 102 }
  if bound(3) != 6 { return 103 }
  if tail(0) != 7 { return 104 }
  if tail(1) != 8 { return 105 }
  if tail(2) != 9 { return 106 }
  return 42
}
