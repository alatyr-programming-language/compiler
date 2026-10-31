## e2e / four backends (#696) — a `comptime for` RANGE BOUND that wraps a comptime value in
## `unchecked` names that value. Grammar §3.7: `unchecked e` yields the inner expression's value; the
## block only switches the overflow checks off. Comptime §8.3 then emits the body once per element of
## the half-open range, so `0 .. unchecked (N)` and `0 .. N` are the same loop.
##
## Measured on the parent (`2cf60b45`, x86_64; one program per loop, the count as the exit code):
## the six shapes below iterated 0, 0, 4, 6, 0 and 0 times, against 6, 4, 3, 7, 5 and 2 here. Each
## `unchecked e` read as 0, and `typeinfo(...).len` under arithmetic read as 0 too. This whole file
## exits 3 on the parent on all four backends. Every shape compiled clean, with no diagnostic: the
## program ran a different loop.
##
## The first two loops are the CONTROL: a literal bound and a bare module-const bound agreed before
## this fix and still do, so a failure in code 1 or 2 says the repair broke a shape it was not aimed at.
N := 6
K := unchecked (5)
P := struct { a : u64, b : u64, c : u64 }

main := fn() -> u64 {
  ## control: literal bound
  mut lit : u64 = 0
  comptime for i in 0 .. 4 { lit = lit + 1 }
  if lit != 4 { return 1 }

  ## control: bare module-const bound
  mut bare : u64 = 0
  comptime for i in 0 .. N { bare = bare + 1 }
  if bare != 6 { return 2 }

  ## `unchecked` around a module const, in the HI bound
  mut u1 : u64 = 0
  comptime for i in 0 .. unchecked (N) { u1 = u1 + 1 }
  if u1 != 6 { return 3 }

  ## `unchecked` around a literal, in the HI bound
  mut u2 : u64 = 0
  comptime for i in 0 .. unchecked (4) { u2 = u2 + 1 }
  if u2 != 4 { return 4 }

  ## `unchecked` in the LO bound (1 .. 4)
  mut u3 : u64 = 0
  comptime for i in unchecked (1) .. 4 { u3 = u3 + 1 }
  if u3 != 3 { return 5 }

  ## `unchecked` as one operand of const arithmetic (0 .. 7)
  mut u4 : u64 = 0
  comptime for i in 0 .. N + unchecked (1) { u4 = u4 + 1 }
  if u4 != 7 { return 6 }

  ## a module const whose own value is `unchecked (5)`
  mut u5 : u64 = 0
  comptime for i in 0 .. K { u5 = u5 + 1 }
  if u5 != 5 { return 7 }

  ## a typeinfo count as one operand of const arithmetic (3 - 1)
  mut u6 : u64 = 0
  comptime for i in 0 .. typeinfo(P).fields.len - 1 { u6 = u6 + 1 }
  if u6 != 2 { return 8 }

  return 42
}
