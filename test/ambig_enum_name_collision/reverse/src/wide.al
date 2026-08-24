pub Error := enum { First, Second, Third, Fourth }

pub fail := fn() -> Result(u64, Error) {
  Result(u64, Error).Err(Error.Fourth)
}
