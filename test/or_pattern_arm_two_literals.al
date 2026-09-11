## Control Flow §5.4 — the shared-body defect is not "the same text twice" (#673). FOUR alternatives
## share ONE body holding TWO DIFFERENT string literals, a float literal and nested control flow, so
## a fix that merely collapsed identical text would still emit four copies of the second cell.
##
## It is also the per-family census. Emitted from this one shared body are: `.Lstr` (two cells, the
## family that collided), `.Lflt` (already deduplicated by its own pool — a float literal's label IS
## its source offset, which a HOF clone copies verbatim), and the jump/return families `.L<N>` /
## `.Lra<N>_<k>`, which are handed out by a counter at emission time and are therefore DISTINCT in
## each of the four text copies. Only the data families can collide; only they are deduplicated.
##
## `k = 3` takes the group arm: prints `two` then `three`, and returns 12 + 30 = 42.
step := fn(x : u64) -> u64 { x + 10 }

main := fn() -> u64 {
  mut k : u64 = 3
  mut acc : u64 = 0
  mut f : f64 = 1.5
  match k {
    1 => { acc = 1 }
    2 | 3 | 4 | 5 => {
      print("two\n")
      print("three\n")
      f = f + 0.25
      acc = step(acc)
      if f > 1.0 { acc = acc + 2 } else { acc = acc + 1 }
      mut i : u64 = 0
      while i < 3 { acc = acc + 10 ; i = i + 1 }
    }
    _ => { acc = 0 }
  }
  acc
}
