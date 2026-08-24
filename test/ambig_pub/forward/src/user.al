E := codec::Error
pub wrap := fn(x : usize) -> Result(usize, codec::Error) {
  return Result(usize, E).Ok(x)
}
