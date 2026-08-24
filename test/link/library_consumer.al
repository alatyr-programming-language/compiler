answer := @extern("codec__answer") fn(x : u64) -> u64

main := fn() -> u64 {
  answer(41)
}
