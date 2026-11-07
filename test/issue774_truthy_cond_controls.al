## e2e — issue #774 CONTROL: the conditions the refusal must leave ALONE. A `bool` local IS truthy
## (Control Flow §4 names it as the condition), an explicit comparison yields `bool`, and `and`/`or`
## over two bools stays bool (§8.1). It answers 7 = 1 + 2 + 4 on the parent and after; a fix that
## refuses any row here is over-broad.
main := fn() -> u64 {
  mut b : bool = true
  mut n : u64 = 3
  mut k : u64 = 0
  if b { k += 1 }
  if n != 0 { k += 2 }
  if b and n > 0 { k += 4 }
  return k
}
## expect: run 7
