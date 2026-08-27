## Issue #167: pointer field stores must use the standard byte offset and the leaf width.
## The x86 path exercises both a pointer PARAMETER and a pointer LOCAL.  It covers a later u8 field,
## a position-0 u8 field, a u16 field at a later aligned offset, and a nested aggregate field.  Every
## check includes the neighbouring fields, so a full-word store cannot pass by writing the low byte.
P8 := struct { a : u8, b : u8 }
P16 := struct { lead : u8, value : u16, tail : u8 }
Inner := struct { lead : u8, value : u16, tail : u8 }
Outer := struct { inner : Inner, after : u8 }

set_param_u8 := fn(p : ptr(mut P8)) {
  deref(p).b = 9
}

set_param_u16 := fn(p : ptr(mut P16)) {
  deref(p).value = 513
}

set_nested := fn(p : ptr(mut Outer)) {
  deref(p).inner.value = 1025
}

main := fn() -> u64 {
  ## PARAMETER + later-position u8.
  mut param_u8 := P8(a = 7, b = 2)
  set_param_u8(ptr(mut param_u8))
  if param_u8.a != 7 { return 1 }
  if param_u8.b != 9 { return 2 }

  ## LOCAL pointer + position-0 u8; the neighbour must survive the store.
  mut local_u8 := P8(a = 3, b = 11)
  local_ptr := ptr(mut local_u8)
  deref(local_ptr).a = 8
  if local_u8.a != 8 { return 3 }
  if local_u8.b != 11 { return 4 }

  ## PARAMETER + later aligned u16; both u8 neighbours must survive.
  mut param_u16 := P16(lead = 17, value = 21, tail = 29)
  set_param_u16(ptr(mut param_u16))
  if param_u16.lead != 17 { return 5 }
  if param_u16.value != 513 { return 6 }
  if param_u16.tail != 29 { return 7 }

  ## LOCAL pointer + nested aggregate path; the outer neighbour and both inner neighbours survive.
  mut nested := Outer(inner = Inner(lead = 31, value = 41, tail = 43), after = 47)
  nested_ptr := ptr(mut nested)
  set_nested(nested_ptr)
  if nested.inner.lead != 31 { return 8 }
  if nested.inner.value != 1025 { return 9 }
  if nested.inner.tail != 43 { return 10 }
  if nested.after != 47 { return 11 }
  42
}
