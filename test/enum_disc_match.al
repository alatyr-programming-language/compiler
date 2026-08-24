## spec Types §6.2 — `match` dispatch on a PINNED enum must reach the right arm: construction stores the
## pinned discriminant (word 0) and `match` compares against the SAME pinned value (both flow through
## `variant_index`), so one fix keeps them consistent. `Code.B` (pinned 10) must select the B arm → 42.
Code := enum { A = 5, B = 10, C = 100 }

main := fn() -> u64 {
  x := Code.B
  mut r := 0
  match x {
    Code.A => { r = 1 }
    Code.B => { r = 42 }
    Code.C => { r = 2 }
  }
  r
}
