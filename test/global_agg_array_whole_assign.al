## e2e — WHOLE-VALUE reassignment of a mutable scalar-ARRAY global (`T = [ … ]`, an array LITERAL RHS).
## The single-word global-write path dropped every element past element 0 (word 0 got an address, not a
## value). Now each element is stored to `LABEL + k*8`. Init [10,15,100]; after `T = [1,2,39]` all three
## survive: 1 + 2 + 39 = 42. Neutral: src/ whole-assigns no array globals (only indexed writes).
mut T := [10, 15, 100]
main := fn() -> u64 {
  T = [1, 2, 39]
  T[0] + T[1] + T[2]
}
