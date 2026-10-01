## Issue #792 — a field of a struct read THROUGH A POINTER (`deref(p).f`) whose type is an enum or an
## `Option(u64)`. Every check below built cleanly on the parent and ran to a wrong value or crashed:
## an enum field returned by value from `deref(p).op` was the null enum (the `match` took the wrong
## arm, and the first check answered 2 here); passed straight as an argument its first word was handed
## over as the callee's block pointer (SIGSEGV); a payload enum field read through the pointer gave
## 0; and an `Option(u64)` FIELD was laid out as one word while its constructor stored two, so its
## payload read back as the next field. Each check has its own exit code.
Kty := enum { KI8, KI64, KNone }
Rec := struct { op : Kty, v : i64, off : usize }
VRegId := brand(u64)
Opnd := enum { ONone, OVReg(VRegId), OImm(i64) }
ORec := struct { v : i64, a : Opnd, off : usize }
SRec := struct { op : Kty, span : Option(u64), off : usize }
r_op := fn(p : ptr(mut Rec)) -> Kty { deref(p).op }
code := fn(k : Kty) -> u64 { match k { KI8 => { 1 }; KI64 => { 2 }; KNone => { 3 } } }
r_a := fn(p : ptr(mut ORec)) -> Opnd { deref(p).a }
opnd_val := fn(o : Opnd) -> u64 {
  match o { ONone => { 0 }; OVReg(v) => { u64(v) * 10 }; OImm(i) => { u64(i) } }
}
r_span := fn(p : ptr(mut SRec)) -> Option(u64) { deref(p).span }
r_span_bound := fn(p : ptr(mut SRec)) -> Option(u64) { rv : SRec = deref(p); rv.span }
put := fn(p : ptr(mut SRec), it : SRec) { deref(p) = it }
mk := fn(k : Kty, s : Option(u64)) -> SRec { SRec(op = k, span = s, off = 7) }
main := fn() -> u64 {
  mut r := Rec(op = Kty.KI64, v = 5, off = 9)
  p : ptr(mut Rec) = ptr(mut r)
  mut s : u64 = 0
  match r_op(p) { KI8 => { s = 100 }; KI64 => { s = 2 }; KNone => { s = 1000 } }
  if s != 2 { return 2 }
  if code(r_op(p)) != 2 { return 3 }
  if code(deref(p).op) != 2 { return 4 }
  q : ptr(Rec) = ptr(r)
  if code(deref(q).op) != 2 { return 5 }
  mut o := ORec(v = 5, a = Opnd.OVReg(VRegId(3)), off = 9)
  op : ptr(mut ORec) = ptr(mut o)
  if opnd_val(r_a(op)) != 30 { return 6 }
  deref(op).a = Opnd.OImm(12)
  if opnd_val(r_a(op)) != 12 { return 7 }
  mut sr := SRec(op = Kty.KI8, span = Option(u64).None, off = 9)
  sp : ptr(mut SRec) = ptr(mut sr)
  match r_span(sp) { Some(v) => { return 8 }; None => {} }
  put(sp, mk(Kty.KI64, Option(u64).Some(30)))
  match r_span(sp) { Some(v) => { if v != 30 { return 9 } }; None => { return 10 } }
  match r_span_bound(sp) { Some(v) => { if v != 30 { return 11 } }; None => { return 12 } }
  rv : SRec = deref(sp)
  if u64(rv.off) != 7 { return 13 }
  if size(SRec) != 32 { return 14 }
  42
}
