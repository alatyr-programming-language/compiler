pub Error := enum { Bad }

pub go := fn(x : usize) -> Result(usize, Error) {
  if x == 0 { return Result(usize, Error).Err(Error.Bad) }
  Result(usize, Error).Ok(x)
}
