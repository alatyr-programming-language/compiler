main := fn() -> u64 {
  if size(Result(usize, codec::Error)) != 24 { return 3 }
  match user::wrap(42) {
    Ok(n) => { return u64(n) }
    Err(_) => { return 1 }
  }
}
