Pk := struct { a : u64 }

bad := fn(x : u64) -> Pk {
  return u64(x)
}

main := fn() -> u64 {
  bad(42)
  return 42
}
