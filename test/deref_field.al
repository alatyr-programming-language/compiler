## e2e (lean-lower: deref of a POINTER-TYPED STRUCT FIELD → struct binding). `x := deref(o.p)`
## where `o.p` is a `ptr(mut Inner)` field must bind `x` as the pointee struct and copy its words
## (the `deref_struct_span` path handled only a pointer-typed LOCAL, not a `.field`). This unblocks
## the allocator-borne containers' `ab := deref(v.arena)` idiom (`vec_base`/`push`/`at`). `Inner.a`=7
## + `Inner.b`=35 → 42. The fix routed the `deref(Field(Var,f))` destructure through a TYPED-PARAM
## helper (`field_var_parts`) so its `match deref(f)` lowers — matching `deref(<call-result local>)`
## silently mis-lowers (the lean lower discards a call result's element type).
Inner := struct { a : u64, b : u64 }
Outer := struct { p : ptr(mut Inner), tag : u64 }
main := fn() -> u64 {
  mut inn := Inner(a = 7, b = 35)
  o := Outer(p = ptr(inn), tag = 1)
  x := deref(o.p)
  x.a + x.b
}
