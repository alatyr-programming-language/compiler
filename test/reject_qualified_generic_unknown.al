## A qualified generic type argument must resolve in its named module. Unknown paths are a located
## semantic rejection, never a scalar-layout fallback.
bad := fn() -> Result(usize, missing::Error) {
  return Result(usize, missing::Error).Ok(42)
}

main := fn() -> u64 {
  match bad() { Ok(n) => { return u64(n) } Err(_) => { return 1 } }
}
