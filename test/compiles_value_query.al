## Value-position capability queries fold before ordinary call lowering.
takes_str := fn(s : str) -> u64 { 42 }
takes_u := fn(s : u64) -> u64 { 42 }
good := compiles(1)
bad := compiles(takes_str(1))
known := resolves(takes_u(1))
missing := resolves(no_such_function(1))
main := fn() -> u64 {
  if good {
    if bad { 99 } else {
      if known {
        if missing { 98 } else { 42 }
      } else { 97 }
    }
  } else { 88 }
}
