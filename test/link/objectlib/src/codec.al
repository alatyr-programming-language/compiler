## A library target retains the public API and its private transitive helper, but does not invent an
## executable entry point for this package.
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
