## e2e (Types §9.4 / Stdlib §2.6) — direct `==` / `!=` over `str` fields must compare UTF-8
## content through the existing string-equality lowering. The leading field covers the direct local
## shape; `o.q.name` is nested and has a nonzero word offset. On the parent revision the program
## returned 22 where 42 was due; expected result after the fix: 42.
S := struct { name : str, n : u64 }
N := struct { pad : u64, name : str, tail : u64 }
O := struct { lead : u64, q : N, tail : u64 }

main := fn() -> u64 {
  p := S(name = "abc", n = 7)
  o := O(lead = 1, q = N(pad = 2, name = "abc", tail = 3), tail = 4)
  mut acc : u64 = 0
  if p.name == "abc" { acc += 7 }
  if p.name != "abd" { acc += 11 }
  if o.q.name == "abc" { acc += 13 }
  if o.q.name != "abd" { acc += 11 }
  return acc
}
