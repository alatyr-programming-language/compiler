## Codec acceptance regression: `Option`/`Result` carrying `Slice(T)` preserve both view words
## through return, local construction, matching, and an aggregate parameter boundary.
E := enum { Bad }

view := fn(d : Slice(u8), n : usize) -> Option(Slice(u8)) {
  Option(Slice(u8)).Some(d[0..n])
}

local := fn(d : Slice(u8)) -> Option(Slice(u8)) {
  o := Option(Slice(u8)).Some(d[0..5])
  o
}

make := fn(d : Slice(u8), n : usize) -> Result(Slice(u8), E) {
  Result(Slice(u8), E).Ok(d[0..n])
}

take := fn(r : Result(Slice(u8), E)) -> u64 {
  match r {
    Ok(w) => { return u64(w.len) }
    Err(_) => { return 99 }
  }
}

main := fn() -> u64 {
  mut buf : [u8; 16] = [0; 16]
  d := Slice(u8)(ptr = ptr(buf[0]), len = 16)
  mut acc : u64 = 0
  match view(d, 3) {
    Some(w) => { acc = acc + u64(w.len) }
    None => { return 1 }
  }
  match local(d) {
    Some(w) => { acc = acc + u64(w.len) }
    None => { return 2 }
  }
  acc + take(make(d, 6)) + 28
}
