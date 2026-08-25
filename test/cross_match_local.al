## Cross-backend statement match: selected literal and wildcard arms both write local results.
## The two scrutinees exercise both the direct literal branch and the fall-through wildcard branch.
main := fn() -> u64 {
  mut exact := 0
  match 0 {
    0 => { exact = 10 }
    _ => { exact = 1 }
  }
  mut wildcard := 0
  match 3 {
    0 => { wildcard = 1 }
    _ => { wildcard = 32 }
  }
  exact + wildcard
}
