pub wrap := fn(x : usize) -> Result(usize, codec::Error) {
  return Result(usize, codec::Error).Ok(x)
}
