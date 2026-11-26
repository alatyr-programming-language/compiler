## e2e/fmt — Tooling §4.3.3, TOOL-28 (spec 1.12.0; #1918): a binary-operator chain that overflows 100
## columns breaks AFTER each operator, the operator ending the line. fmt used to break BEFORE it, so a
## `-` chain came out as lines beginning with `- name`; under Grammar §2.6 (SYN-12) `-` is not a
## continuing token, so each such line is a NEW statement and the formatted program meant something else.
## One chain per operator family — `-`, `+`, `and` and a comparison under `or` — each wide enough to
## wrap. The exit status checks that the formatted program keeps its value: a `-` chain read as separate
## statements leaves `xxxx` at 50 instead of 42, and the first wrong probe returns its own code.
main := fn() -> u64 {
  aaaaaaaaaaaaaaaaaaaa : u64 = 50
  bbbbbbbbbbbbbbbbbbbbbbbbb : u64 = 4
  ccccccccccccccccccccccc : u64 = 4
  dddddddddddddddddddd : u64 = 0
  xxxxxxxxxxxxxxxxxxxx := aaaaaaaaaaaaaaaaaaaa - bbbbbbbbbbbbbbbbbbbbbbbbb - ccccccccccccccccccccccc - dddddddddddddddddddd
  yyyyyyyyyyyyyyyyyyyy := aaaaaaaaaaaaaaaaaaaa + bbbbbbbbbbbbbbbbbbbbbbbbb + ccccccccccccccccccccccc + dddddddddddddddddddd
  zzzzzzzzzzzzzzzzzzzz := aaaaaaaaaaaaaaaaaaaa == 50 and bbbbbbbbbbbbbbbbbbbbbbbbb == 4 and ccccccccccccccccccccccc == 4
  wwwwwwwwwwwwwwwwwwww := aaaaaaaaaaaaaaaaaaaa < bbbbbbbbbbbbbbbbbbbbbbbbb or ccccccccccccccccccccccc != 4 or dddddddddddddddddddd > 0
  if xxxxxxxxxxxxxxxxxxxx != 42 { return 1 }
  if yyyyyyyyyyyyyyyyyyyy != 58 { return 2 }
  if not zzzzzzzzzzzzzzzzzzzz { return 3 }
  if wwwwwwwwwwwwwwwwwwww { return 4 }
  xxxxxxxxxxxxxxxxxxxx
}
## expect: run 42
