main := fn() -> u64 {
  mut buf : [u8; 1] = [0; 1]
  big := shl(usize(1), 63)
  s := Slice(u8)(ptr = ptr(buf[0]), len = big)

  mut from_for : u64 = 0
  for i in 0..s.len {
    from_for = 1
    break
  }

  mut from_while : u64 = 0
  mut k : usize = 0
  while k < s.len {
    from_while = 1
    k = big
  }

  from_for * 40 + from_while * 2
}
