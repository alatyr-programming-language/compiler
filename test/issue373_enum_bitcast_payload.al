## e2e (enum→enum bitcast is the identity on the block). Two equal-width nominal enums reinterpreted
## into one another must carry the discriminant AND every payload word (Types §3.4/§4.4). Before the
## fix only word 0 moved: the correct arm was selected over a zeroed payload, a clean-compiling wrong
## value. Every payload word is checked on its own — never through a sum — so a permuted or partially
## copied image is visible, and each failure carries its own code from 100 so the answer names the
## word that moved wrong. Success is 42; every failure code is distinct and below 126.
E1 := enum { Pair(u64, u64), None }
E2 := enum { Pair(u64, u64), None }
F1 := enum { Trio(u64, u64, u64), None }
F2 := enum { Trio(u64, u64, u64), None }

main := fn() -> u64 {
  if size(E1) != size(E2) { return 100 }
  if size(F1) != size(F2) { return 101 }

  ## Control: the ordinary construction/match path is correct without any bitcast.
  c := E1.Pair(7, 9)
  match c {
    E1.Pair(a, b) => {
      if a != 7 { return 102 }
      if b != 9 { return 103 }
    }
    E1.None => { return 104 }
  }

  e := E1.Pair(10, 32)
  f := unchecked bitcast(E2, e)
  match f {
    E2.Pair(x, y) => {
      if x != 10 { return 105 }
      if y != 32 { return 106 }
    }
    E2.None => { return 107 }
  }

  ## The checked spelling must agree with the unchecked one — verification mode is not a
  ## representation change.
  g := bitcast(E2, e)
  match g {
    E2.Pair(x, y) => {
      if x != 10 { return 108 }
      if y != 32 { return 109 }
    }
    E2.None => { return 110 }
  }

  ## Three payload words, three distinct values, each verified separately.
  t := F1.Trio(1, 2, 3)
  u := unchecked bitcast(F2, t)
  match u {
    F2.Trio(p, q, r) => {
      if p != 1 { return 111 }
      if q != 2 { return 112 }
      if r != 3 { return 113 }
    }
    F2.None => { return 114 }
  }

  ## Nullary-variant control: the discriminant alone still selects the right arm.
  n := E1.None
  m := unchecked bitcast(E2, n)
  match m {
    E2.Pair(x, y) => { return 115 }
    E2.None => {}
  }

  return 42
}
