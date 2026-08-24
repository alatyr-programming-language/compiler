## Grammar §2/§3: newlines are valid array item separators, just like commas.
T : [u8; 8] = [
  10, 11, 12, 13
  20, 21, 22, 23
]

main := fn() -> u64 {
  mut i : usize = 5
  u64(T[i]) + 21
}
