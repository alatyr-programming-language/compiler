## #646 — a SIGNED local whose name is ALSO bound, untyped, in an inner scope of the same function
## took the UNSIGNED overflow guard on its `+`, while its `<` kept the SIGNED comparison. At k = -1
## the two disagreed: the compare read -1 and continued, the increment's CARRY fired, and the
## program died on the guard's trap. That is a crash on a program the language defines — Types §3.2
## puts signedness in the operations, so the operand's own interpretation picks the add and the
## compare alike, and Concurrency §6.1 traps only an operation that OVERFLOWS: -1 + 1 does not
## overflow i64.
##
## The cause is the slot map, not the arithmetic. `:=` locals are function-scoped in this backend,
## `collect_slots` descends into every nested block, and `bind_slot_typed` no-ops on a name it has
## already bound — so of two declarations of one name only the FIRST reaches the slot map, together
## with the FIRST binding's recorded type. When that first one is untyped (`mut k := 0`, whose
## literal initializer the scalar inference declines), the later `mut k : i64 = ...` loses its
## annotation and `is_signed_expr` cannot prove the counter signed.
##
## MEASURED ON THE PARENT (b61bfa4, x86_64): this program compiles and links clean, then dies with
## SIGILL, exit 132. It is a CRASH, not a wrong value, so an ordinary "did it return the right
## number" assertion passes on the parent and proves nothing. On aarch64/riscv64/wasm the parent
## already answers 42 for THIS shape: those backends recover the annotation by a source scan of the
## function's TOP-LEVEL statements rather than from the slot map. That is also why the annotated
## declarations below sit at top level and only the colliding untyped ones are nested — the three
## non-x86 scans do not descend, so an annotated local declared inside a block is a separate,
## pre-existing gap (#651) that this fixture must not freeze into the oracle.
##
## Every earlier untyped binding here is LOAD-BEARING. Delete one and the annotation reaches the
## slot, the guard is already signed, and that function passes on the unfixed compiler. A reduction
## that drops them proves nothing.
neg := fn() -> i64 { 0 - 1 }

## The plain collision: `k` is bound untyped inside an `if`, then annotated `i64` at top level and
## taken to -1. The `+` guard must be the signed one that `while k < 3` already compares with.
rebound_add := fn() -> i64 {
  mut r : i64 = 0
  if r == 1 {
    mut k := 0
    while k < 3 { k = k + 1 }
    r = r + i64(k)
  }
  mut k : i64 = neg()
  k = k + 1
  r + k
}

## The colliding untyped binding three blocks deep, so a repair that only reads the top level of a
## function body does not pass.
rebound_add_deep := fn(sel : u64) -> i64 {
  mut out : i64 = 7
  if sel == 1 {
    if out == 7 {
      while out == 7 {
        mut n := 0
        n = n + 1
        out = i64(n)
      }
    }
  }
  mut n : i64 = neg()
  n = n + 1
  out + n
}

## `-` and `*` read their guard from the same operand type as `+`, so the repair must move all
## three. `m * 3` at m = -1 is where the unsigned `mulq` guard fires.
rebound_sub_mul := fn() -> i64 {
  mut acc : i64 = 0
  if acc == 1 {
    mut m := 0
    acc = acc + i64(m)
  }
  mut m : i64 = neg()
  ## `d`/`p` carry their own annotation only so the FINAL sum stays inside this fixture's subject:
  ## an operand inferred from a `Bin` records no type on the three non-x86 backends, and an
  ## unannotated `acc + d + p` would trap there on that unrelated, pre-existing gap.
  d : i64 = m - 1
  p : i64 = m * 3
  acc + d + p
}

main := fn() -> u64 {
  if rebound_add() != 0 { return 1 }
  if rebound_add_deep(0) != 7 { return 2 }
  if rebound_add_deep(1) != 1 { return 3 }
  want : i64 = 0 - 5
  if rebound_sub_mul() != want { return 4 }
  return 42
}
