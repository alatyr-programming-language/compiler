## e2e / issue #926 — the CONTROL: a legal comptime initializer CHAIN still builds and folds.
##
## The cycle refusal must cost nothing to a program §7.1 allows: "an initializer may reference another
## binding's comptime value", evaluated in dependency order. `B := A + 1` reads `A`'s comptime value
## and is not a cycle — there IS an order (`A` then `B`). Without this row the refusal could be made
## vacuously true by rejecting every module-level const that names another const, and nothing else in
## the corpus would notice: `A : u64 = 1` / `B := A + 1` is the shortest program that distinguishes a chain
## from a cycle.
##
## x86_64 only: the twins' fold of a const-to-const reference is #923's remaining half and is not what
## this row is about, so the row pins the backend whose crash #926 reports rather than claiming a
## four-backend result.
A : u64 = 1
B := A + 1

main := fn() -> u64 {
  return B
}
## expect: run 2
