## TOOL-5 regression: this helper is reachable only from an @test body. The conditional Err
## must keep its non-Ok tag, while the final Ok remains a distinct return path.
private_condition := fn() -> bool {
  false
}

Result := fn(T : type, E : type) -> type {
  return enum { Ok(T), Err(E) }
}

@test("conditional Err tag without helper") fn() -> Result(usize, u64) {
  condition := false
  if condition == false {
    return Result(usize, u64).Err(2)
  }
  Result(usize, u64).Ok(0)
}

@test("private helper and conditional Err") fn() -> Result(usize, u64) {
  condition := private_condition()
  if condition == false {
    return Result(usize, u64).Err(1)
  }
  Result(usize, u64).Ok(0)
}

main := fn() -> u64 {
  42
}
