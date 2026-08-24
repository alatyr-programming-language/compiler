main := fn() -> u64 {
  mut seen : u64 = 7
  match different_left::fail() {
    Ok(_) => { seen = 1 }
    Err(e) => {
      match e {
        First => { seen = 2 }
        Second => { seen = 3 }
        Third => { seen = 4 }
        Fourth => { seen = 42 }
      }
    }
  }
  seen
}
