## Same API as objectlib; static_lib wraps the deterministic single package object in an ar archive.
TABLE := [1]

leaf := fn(x : u64) -> u64 {
  x
}

helper := fn(x : u64) -> u64 {
  leaf(x) + TABLE[0]
}

pub answer := fn(x : u64) -> u64 {
  helper(x)
}

main := fn() -> u64 {
  99
}
