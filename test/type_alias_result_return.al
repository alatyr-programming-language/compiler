## One-hop generic enum alias keeps both its return identity and its payload layout.
E := enum { Bad }
R := Result(u64, E)

f := fn(x : u64) -> R { R.Ok(x + 1) }

main := fn() -> u64 {
  match f(41) {
    Ok(v) => { return 100 + v }
    Err(_) => { return 7 }
  }
}
