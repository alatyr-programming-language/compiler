## e2e — issue #447, the FENCE this slice deliberately did not move. Issue #447 fixed a nested enum
## place (`o.inner.t`) as a `match` scrutinee for an INLINE struct LOCAL root. A struct PARAMETER is
## passed BY REFERENCE, so its slot holds a pointer rather than the struct, and reading a multi-word
## leaf through that pointer is a separate, still-unbuilt lowering that `resolve_nested_ptr_field`
## refuses out loud in `src/lower.al`.
##
## This row exists so that a future widening of `word_field_path` cannot silently turn that located
## reject into an unmeasured emission: it must stay a REJECT, with the diagnostic that names the
## pointer, until someone measures the shape and lifts the fence on purpose.
##
## Same status on the parent (7ed9ffd) and on this tree: the build fails and says so.
##
## IR-39 (#1786) lifted the fence on the default x86_64 route, measured: the shared IR passes `Outer` by
## reference at the layout `lower_layout::field_byte_place` gives (`ib_struct_image_why`), reads
## `o.inner.t` there, and the program answers 22 (`Tag.Green`), its value. The legacy emitter
## (`alatyr x86-legacy`) still refuses at `resolve_nested_ptr_field`, and the twins still trap.
Tag := enum { Red, Green, Blue }
Inner := struct { t : Tag }
Outer := struct { lead : u64, inner : Inner }

pick := fn(o : Outer) -> u64 {
  match o.inner.t { Red => 11, Green => 22, Blue => 33, _ => 91 }
}

main := fn() -> u64 {
  o := Outer(lead = 7, inner = Inner(t = Tag.Green))
  pick(o)
}
