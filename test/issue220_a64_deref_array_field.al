## Issue #220 — AArch64 reads and writes one scalar field of a word-granular array element
## through `deref(p).arr[i]` at a runtime index. The leading pad, both element fields, the
## other element, and the tail expose a wrong element stride or field offset. x86 keeps its
## existing explicit rejection, RV64/WAT keep their fail-loud boundary, and the selected
## AArch64 surface must return 42.
Cell := struct { left : u64, value : u64, right : u64 }
Box := struct { pad : u64, arr : [Cell; 2], tail : u64 }

touch := fn(p : ptr(mut Box), i : u64) -> u64 {
  before := deref(p).arr[i].value
  deref(p).arr[i].left = 40
  deref(p).arr[i].value = 50
  after := deref(p).arr[i].left + deref(p).arr[i].value
  if before != 20 { return 1 }
  if after != 90 or deref(p).arr[i].right != 30 { return 2 }
  if deref(p).arr[0].left != 1 or deref(p).arr[0].value != 2 or deref(p).arr[0].right != 3 { return 3 }
  if deref(p).pad != 7 or deref(p).tail != 9 { return 4 }
  42
}

main := fn() -> u64 {
  mut b := Box(
    pad = 7,
    arr = [Cell(left = 1, value = 2, right = 3), Cell(left = 10, value = 20, right = 30)],
    tail = 9
  )
  touch(ptr(mut b), 1)
}
