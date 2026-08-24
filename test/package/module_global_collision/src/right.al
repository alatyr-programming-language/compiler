LIMIT : u8 = 2
VALUES : [u8; 4] = [10, 20, 30, 40]

pub sample := fn() -> u64 {
  return u64(LIMIT) + u64(VALUES[1])
}
