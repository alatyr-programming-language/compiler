## P1 codec acceptance: indexing a concrete Slice(T) payload binding.
## The payload view is stored as a full `Slice(T)` type span in the match alias slot;
## both statement-match and expression-match indexing must recover the element kind from
## that span. Byte elements use byte loads/stores, while word elements keep word stride.
E := enum { Bad }

view_u8 := fn(d : Slice(u8), n : usize) -> Result(Slice(u8), E) {
  Result(Slice(u8), E).Ok(d[0..n])
}

byte_write_dynamic := fn() -> bool {
  mut b : [u8; 8] = [7; 8]
  d := Slice(u8)(ptr = ptr(b[0]), len = 8)
  mut k : usize = 2
  match view_u8(d, 4) {
    Ok(w) => { w[k] = 21 }
    Err(_) => { return false }
  }
  b[2] == 21 and b[1] == 7 and b[3] == 7
}

byte_write_constant := fn() -> bool {
  mut b : [u8; 8] = [7; 8]
  d := Slice(u8)(ptr = ptr(b[0]), len = 8)
  match view_u8(d, 4) {
    Ok(w) => { w[0] = 21 }
    Err(_) => { return false }
  }
  b[0] == 21 and b[1] == 7
}

byte_read_dynamic := fn() -> bool {
  mut b : [u8; 8] = [7; 8]
  b[2] = 21
  d := Slice(u8)(ptr = ptr(b[0]), len = 8)
  mut k : usize = 2
  match view_u8(d, 4) {
    Ok(w) => { return w[k] == 21 }
    Err(_) => { return false }
  }
}

byte_read_constant_expr := fn() -> bool {
  mut b : [u8; 8] = [7; 8]
  b[0] = 21
  d := Slice(u8)(ptr = ptr(b[0]), len = 8)
  return match view_u8(d, 4) {
    Ok(w) => { w[0] == 21 }
    Err(_) => { false }
  }
}

word_roundtrip := fn() -> bool {
  mut b : [u64; 4] = [7; 4]
  d := Slice(u64)(ptr = ptr(b[0]), len = 4)
  mut k : usize = 2
  r := Result(Slice(u64), E).Ok(d)
  match r {
    Ok(w) => {
      w[k] = 21
      if w[k] != 21 { return false }
    }
    Err(_) => { return false }
  }
  b[2] == 21 and b[1] == 7 and b[3] == 7
}

main := fn() -> u64 {
  mut score : u64 = 0
  if byte_write_dynamic() { score += 10 }
  if byte_write_constant() { score += 10 }
  if byte_read_dynamic() { score += 10 }
  if byte_read_constant_expr() { score += 10 }
  if word_roundtrip() { score += 2 }
  score
}
