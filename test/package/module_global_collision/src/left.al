LIMIT : u8 = 1
VALUES : [u8; 4] = [1, 2, 3, 4]

pub sample := fn() -> u64 {
  return u64(LIMIT) + u64(VALUES[1])
}
