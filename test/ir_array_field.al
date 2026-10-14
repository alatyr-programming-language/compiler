## IR slice 3c (`docs/ir-slice-3.md` §7): an ARRAY FIELD `[u64; N]` of a struct local is a run inside
## the struct's frame object on the register twins, at the field's `lower_layout::field_byte_place` and
## a stride of one word: the literal stores each element, `r.u[i] = v` writes one (a literal and a
## dynamic index), and the sibling scalar fields before and after the array keep their places. The
## unsigned element compare of #707 is `signedness_struct_field_array`; a signed sibling field is
## `ir_struct_field_signed` (#765, still wrong on legacy wasm, so not mixed in here). The legacy
## emitters answer 42 too: this is the guard that the IR's field place equals theirs, not a fix.
Rec := struct { a : u64, u : [u64; 3], b : u64 }
main := fn() -> u64 {
  mut r : Rec = Rec(a = 1, u = [10, 20, 30], b = 8)
  r.u[1] = 5
  mut k : usize = 2
  r.u[k] = r.u[k] + 2
  if r.b != 8 { return 2 }
  r.u[0] + r.u[1] + r.u[2] + r.a - 6
}
