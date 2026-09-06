## Checked-mode bounds trap for a WRITE to an ARRAY FIELD of a MUTABLE MODULE-LEVEL struct
## (`gg.xs[i] = v`) -- Types 6.4 / I11 358, the store dual of
## `test/checked_global_struct_field_array_oob.al`. `emit_st_index_assign`'s `global_field_off` arm
## stored at `LABEL + (off + i)*8(%rip)` with no `cmpq`/`ud2`, and it was the ONE arm in that
## function without the guard every sibling global-array store arm already emitted. An out-of-range
## index therefore OVERWROTE the next field of the same global.
##
## FAILURE-FIRST: measured on the parent compiler this program exited 77 -- `gg.xs[3] = 77` landed on
## `guard`, so the read of `guard` that follows returned the value the program believed it had put in
## the array. Not a crash and not obvious garbage: a plausible number in the wrong storage.
##
## The in-range write+read rows run FIRST, so a compiler that trapped on every `gg.xs[i] = v` would
## fail this row rather than pass by over-trapping. 10 / 20 / 30 / 99 / 55 / 77 are pairwise distinct
## and non-zero, so a one-off address error surfaces as a distinct wrong exit.
##
## Registered `run_x86`: a64/rv64/wasm fail loud on this whole shape today, in range as well as out.
G := struct { xs : [u64; 3], guard : u64 }
mut gg := G(xs = [10, 20, 30], guard = 99)
main := fn() -> u64 {
  b : u64 = 1
  gg.xs[b] = 55
  if gg.xs[b] != 55 { return 100 }
  if gg.guard != 99 { return 101 }
  i : u64 = 3
  gg.xs[i] = 77
  return gg.guard
}
