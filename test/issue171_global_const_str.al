## A typed immutable module-level str is a compile-time value whose runtime view must
## materialize both words at every direct use. The non-"ok" payload makes a zero
## length or an accidental pointer visibly wrong.
G : str = "gamma"
N : u64 = 7

return_global := fn() -> str {
  return G
}

param_len := fn(s : str) -> u64 {
  return s.len
}

main := fn() -> u64 {
  ## Direct UFCS/call form: G.len().
  if G.len() != 5 { return 1 }
  ## Direct field form: G.len.
  if G.len != 5 { return 2 }
  if not str_eq(G, "gamma") { return 3 }
  ## The pointer half of the direct global view.
  if bytes(G)[0] != 103 { return 4 }
  if bytes(G)[4] != 97 { return 5 }

  ## Returning the global as a str must deliver both return words.
  r := return_global()
  if r.len != 5 { return 6 }
  if bytes(r)[0] != 103 { return 7 }
  if bytes(r)[4] != 97 { return 8 }

  ## Existing working controls: copy into a local, pass as a str parameter,
  ## and use a local literal. Keep a scalar global beside them.
  s := G
  if s.len != 5 { return 9 }
  if param_len(G) != 5 { return 10 }
  local := "gamma"
  if local.len != 5 { return 11 }
  if N != 7 { return 12 }
  return 42
}
