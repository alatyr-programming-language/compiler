## Issue #170: a standard byte-layout struct array must use one element stride for
## its literal image and every indexed place.  All values are non-zero so a stale
## zeroed word cannot make the two paths agree by accident.
##
## P2 occupies two bytes (a at 0, b at 1), so three elements occupy six bytes.
## x86_64 is the positive row for this slice. AArch64 and RISC-V already share
## the byte-precise initializer and are expected to return 42; WAT's initializer
## remains fail-loud and is expected to trap until that backend gains the writer.
P2 := struct { a : u8, b : u8 }
Word := struct { a : u64, b : u64 }

main := fn() -> u64 {
  ## Control: a standalone byte-layout value and an ordinary word-layout array.
  mut direct : P2 = P2(a = 70, b = 71)
  if u64(direct.a) != 70 { return 1 }
  if u64(direct.b) != 71 { return 2 }

  mut words : [Word; 3] = [Word(a = 80, b = 81), Word(a = 82, b = 83), Word(a = 84, b = 85)]
  if words[0].b != 81 { return 3 }
  words[1].a = 86
  if words[0].b != 81 { return 4 }
  if words[2].a != 84 { return 5 }

  ## Direction 1: literal initializer -> indexed reads, with both constant and
  ## dynamic indices and every element carrying distinct non-zero field values.
  mut arr : [P2; 3] = [P2(a = 10, b = 11), P2(a = 20, b = 21), P2(a = 30, b = 31)]
  if u64(arr[0].a) != 10 { return 6 }
  if u64(arr[0].b) != 11 { return 7 }
  if u64(arr[1].a) != 20 { return 8 }
  if u64(arr[1].b) != 21 { return 9 }
  mut i := 2
  if u64(arr[i].a) != 30 { return 10 }
  if u64(arr[i].b) != 31 { return 11 }

  ## Direction 2: indexed writes -> the target and both neighbours.  The
  ## constant write exercises one place and the dynamic write exercises another.
  arr[1].a = 40
  if u64(arr[1].a) != 40 { return 12 }
  if u64(arr[1].b) != 21 { return 13 }
  if u64(arr[0].a) != 10 { return 14 }
  if u64(arr[0].b) != 11 { return 15 }
  if u64(arr[2].a) != 30 { return 16 }
  if u64(arr[2].b) != 31 { return 17 }

  i = 2
  arr[i].b = 50
  if u64(arr[i].a) != 30 { return 18 }
  if u64(arr[i].b) != 50 { return 19 }
  if u64(arr[1].a) != 40 { return 20 }
  if u64(arr[1].b) != 21 { return 21 }
  if u64(arr[0].a) != 10 { return 22 }
  if u64(arr[0].b) != 11 { return 23 }
  42
}
