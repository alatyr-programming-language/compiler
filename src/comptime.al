## selfhost::comptime — a constant-folding pass over the AST.
##
## The fifth promoted pass: it walks the parser AST and **evaluates the sub-expressions
## that are known at compile time**, rewriting a binary node whose folded operands are
## both literals into a single literal node — the core of the comptime engine ("compute
## what is known before runtime", Comptime §1). A node that is not fully constant (it
## mentions a `Var`) is rebuilt unchanged over its folded children. Output is a fresh
## AST in the arena, so the input is left intact.
##
## This is the AST→AST shape the real comptime/monomorphization pass scales from — the
## unroll fixpoint and `typeinfo`/derive expansion are the same "evaluate-and-rewrite the
## AST" machinery over richer nodes. The AST types are shared from `selfhost::ast` (sibling
## submodule) via local comptime aliases (Modules §4.1) — `fold` rewrites the SAME `Expr`
## the parser produced, no redeclaration. It recurses into every sub-expression and rebuilds
## the node over its folded children. Operator bytes match the tree (16 `+`, 17 `-`, 18 `*`,
## 19 `/`).
(Arg, Arm, Expr) := ast
arm_p := ast::arm_p
arg_p := ast::arg_p

## rt-style AST-node allocator + reader (fixpoint) — the lean replacement for the
## generic `allocate`/`get` allocator (which the self-host lower cannot compile: `Result(Handle(T),
## AllocError)` / `scoped` / generic `Handle(T)` param). Same OFFSET handle semantics as `allocate`,
## so interchangeable with any remaining `get` readers. Mirrors `parser::node_alloc`/`node_ptr`.
node_alloc := fn(in out a : rt::Arena, sz : usize) -> usize {
  rem := a.off % 8
  mut aligned := a.off
  if rem != 0 { aligned = a.off + (8 - rem) }
  if aligned + sz > a.cap { panic("comptime: out of memory") }
  a.off = aligned + sz
  return aligned
}
node_ptr := fn(T : type, a : rt::Arena, h : usize) -> ptr(mut T) {
  base_int := unchecked bitcast(usize, a.base)
  return unchecked bitcast(ptr(mut T), base_int + h)
}

## Allocate one `Expr` node in the arena and return a pointer to it.
newnode := fn(a : ptr(mut rt::Arena), val : Expr) -> ptr(mut Expr) {
  idx := node_alloc(deref(a), 64)
  np := node_ptr(Expr, deref(a), idx)
  deref(np) = val
  np
}

## Allocate one `Arm` node in the arena and return its arena index (the link form `Arm`s
## use). Mirrors `parser::anode`.
newarm := fn(a : ptr(mut rt::Arena), val : Arm) -> ptr(mut Arm) {
  idx := node_alloc(deref(a), 96)
  p := node_ptr(Arm, deref(a), idx)
  deref(p) = val
  p
}

## Allocate one `Arg` (call argument) node in the arena and return its handle (the link form
## call arg lists use). Mirrors `parser::gnode`.
newgarg := fn(a : ptr(mut rt::Arena), val : Arg) -> ptr(mut Arg) {
  idx := node_alloc(deref(a), 64)
  p := node_ptr(Arg, deref(a), idx)
  deref(p) = val
  p
}

## Apply a binary operator to two compile-time-known operands (wrapping; `unchecked`).
apply := fn(op : u8, l : i64, r : i64) -> i64 {
  match op {
    16 => { unchecked (l + r) }
    17 => { unchecked (l - r) }
    18 => { unchecked (l * r) }
    19 => { unchecked (l / r) }
    29 => { unchecked (l % r) }
    40 => { if l != 0 and r != 0 { 1 } else { 0 } }
    41 => { if l != 0 or r != 0 { 1 } else { 0 } }
    42 => { if l == 0 { 1 } else { 0 } }
    _ => { 0 }
  }
}

## Fold an expression: rebuild it in the arena with every fully-constant sub-expression
## reduced to a single literal. A `Bin` whose folded children are both `Num` becomes one
## `Num`; otherwise it is rebuilt over the folded children (a partial fold).
## The allocator parameter `a` is the **ambient** within this body (Functions §5.5
## step 2), so `newnode` / `fold` calls elide it — `newnode(Expr.Num(v))` rather than
## `newnode(a, Expr.Num(v))`. The default allocation is the enclosing `a`.
pub fold := fn(e : ptr(Expr), a : ptr(mut rt::Arena)) -> ptr(mut Expr) {
  node := deref(e)
  match node {
    Expr::Num(v, s, n) => { newnode(Expr.Num(v, s, n)) }
    Expr::BoolLit(v) => { newnode(Expr.BoolLit(v)) }
    Expr::Var(s, n) => { newnode(Expr.Var(s, n)) }
    Expr::Bin(op, l, r) => {
      fl := fold(l)
      fr := fold(r)
      lnode := deref(fl)
      match lnode {
        Expr::Num(lv, ls, ln) => {
          rnode := deref(fr)
          match rnode {
            Expr::Num(rv, rs, rn) => { newnode(Expr.Num(apply(op, lv, rv), 0, 0)) }
            Expr::BoolLit | Expr::Var | Expr::Bin | Expr::If | Expr::Match | Expr::Call
              | Expr::StructLit | Expr::Field | Expr::EnumLit | Expr::AddrOf | Expr::Deref
              | Expr::StrLit | Expr::ArrayLit | Expr::Index | Expr::Try | Expr::FloatLit | Expr::Slice
              | Expr::CompField | Expr::Unchecked | Expr::Lambda | Expr::FnRef | Expr::Bitcast
              | Expr::Loop => { newnode(Expr.Bin(op, fl, fr)) }
          }
        }
        Expr::BoolLit | Expr::Var | Expr::Bin | Expr::If | Expr::Match | Expr::Call
          | Expr::StructLit | Expr::Field | Expr::EnumLit | Expr::AddrOf | Expr::Deref | Expr::StrLit
          | Expr::ArrayLit | Expr::Index | Expr::Try | Expr::FloatLit | Expr::Slice | Expr::CompField
          | Expr::Unchecked | Expr::Lambda | Expr::FnRef | Expr::Bitcast | Expr::Loop => { newnode(Expr.Bin(op, fl, fr)) }
      }
    }
    ## An `if`/`else`: fold each part and rebuild over the folded children (a constant
    ## condition could select a branch, but a structural rebuild is sufficient and correct).
    Expr::If(c, t, f) => {
      fc := fold(c)
      ft := fold(t)
      ff := fold(f)
      newnode(Expr.If(fc, ft, ff))
    }
    ## A `match`: fold the scrutinee, then rebuild every arm over its folded body into a
    ## fresh arena-linked `Arm` list, and rebuild the `Match` node pointing at it.
    Expr::Match(scrut, head) => {
      fs := fold(scrut)
      mut nhead : Option(ptr(mut Arm)) = Option.None
      mut ntail : Option(ptr(mut Arm)) = Option.None
      mut arm : Option(ptr(mut Arm)) = head
      loop {
        match arm {
          Some(armq) => {
            am := deref(arm_p(armq))
            fb := fold(am.body)
            anew := newarm(a, Arm(wild = am.wild, lit = am.lit, body = fb, next = Option.None, vs = am.vs, vl = am.vl, binds_head = am.binds_head, body_stmts = am.body_stmts, hi = am.hi))
            match ntail {
              Some(ntailq) => {
                ap := arm_p(ntailq)
                old := deref(ap)
                upd := Arm(wild = old.wild, lit = old.lit, body = old.body, next = Option.Some(anew), vs = old.vs, vl = old.vl, binds_head = old.binds_head, body_stmts = old.body_stmts, hi = old.hi)
                deref(ap) = upd
              }
              None => { nhead = Option.Some(anew) }
            }
            ntail = Option.Some(anew)
            arm = am.next
          }
          None => { break }
        }
      }
      newnode(Expr.Match(fs, nhead))
    }
    ## `name(a0, …, a5)` — a call. A call is not constant-folded further here (its result is
    ## a runtime value); the correct rewrite is a structural rebuild over the folded
    ## arguments into a fresh arena-linked `Arg` list, preserving the callee name span +
    ## `nargs`. (Distinct binding names — `gh`/`gt`/… — would collide with sibling-arm locals
    ## under the match's one name scope, so the `Arg`-list rebuild names are unique here.)
    Expr::Call(cs, cl, nargs, args_head) => {
      mut ghead : Option(ptr(mut Arg)) = Option.None
      mut gtail : Option(ptr(mut Arg)) = Option.None
      mut garm : Option(ptr(mut Arg)) = args_head
      loop {
        match garm {
          Some(garmq) => {
            gold := deref(arg_p(garmq))
            gfe := fold(gold.e)
            gnew := newgarg(a, Arg(e = gfe, next = Option.None))
            match gtail {
              Some(gtail0) => {
                gp := arg_p(gtail0)
                gprev := deref(gp)
                gupd := Arg(e = gprev.e, next = Option.Some(gnew))
                deref(gp) = gupd
              }
              None => { ghead = Option.Some(gnew) }
            }
            gtail = Option.Some(gnew)
            garm = gold.next
          }
          None => { break }
        }
      }
      newnode(Expr.Call(cs, cl, nargs, ghead))
    }
    ## `S(f0 = e0, …, fN = eN)` — a struct construction: structural rebuild over the folded
    ## field-value expressions into a fresh arena-linked `Arg` list (mirroring the `Call` arm),
    ## preserving the struct name span + field count. (Distinct binding names — `sfh`/`sft`/…
    ## — avoid colliding with locals in sibling arms; match arms share one name scope for the
    ## definite-assignment check.)
    Expr::StructLit(scs, scl, snf, sfhead) => {
      mut sfh : Option(ptr(mut Arg)) = Option.None
      mut sft : Option(ptr(mut Arg)) = Option.None
      mut sfa : Option(ptr(mut Arg)) = sfhead
      loop {
        match sfa {
          Some(sfaq) => {
            sfold := deref(arg_p(sfaq))
            sffe := fold(sfold.e)
            sfnew := newgarg(a, Arg(e = sffe, next = Option.None))
            match sft {
              Some(sft0) => {
                sfp := arg_p(sft0)
                sfprev := deref(sfp)
                sfupd := Arg(e = sfprev.e, next = Option.Some(sfnew))
                deref(sfp) = sfupd
              }
              None => { sfh = Option.Some(sfnew) }
            }
            sft = Option.Some(sfnew)
            sfa = sfold.next
          }
          None => { break }
        }
      }
      newnode(Expr.StructLit(scs, scl, snf, sfh))
    }
    ## `base.f` — a field read: structural rebuild over the folded base expression.
    Expr::Field(fbase, flds, fldl) => {
      gb := fold(fbase)
      newnode(Expr.Field(gb, flds, fldl))
    }
    ## `E.V(p0, …, pN)` — an enum-variant construction: structural rebuild over the folded
    ## payload-arg expressions into a fresh arena-linked `Arg` list, preserving the
    ## enum/variant name spans + arg count. (Distinct binding names avoid sibling-arm collision.)
    Expr::EnumLit(ees, eel, evs, evl, enp, ephead) => {
      mut eph : Option(ptr(mut Arg)) = Option.None
      mut ept : Option(ptr(mut Arg)) = Option.None
      mut epa : Option(ptr(mut Arg)) = ephead
      loop {
        match epa {
          Some(epaq) => {
            epold := deref(arg_p(epaq))
            epfe := fold(epold.e)
            epnew := newgarg(a, Arg(e = epfe, next = Option.None))
            match ept {
              Some(ept0) => {
                epp := arg_p(ept0)
                epprev := deref(epp)
                epupd := Arg(e = epprev.e, next = Option.Some(epnew))
                deref(epp) = epupd
              }
              None => { eph = Option.Some(epnew) }
            }
            ept = Option.Some(epnew)
            epa = epold.next
          }
          None => { break }
        }
      }
      newnode(Expr.EnumLit(ees, eel, evs, evl, enp, eph))
    }
    ## `ptr(<place>)` / `deref(<ptr>)` — pointer intrinsics: not constant-folded
    ## (their value is a runtime address / load); structural rebuild over the folded inner
    ## expression, preserving the variant.
    Expr::AddrOf(pe) => {
      gp := fold(pe)
      newnode(Expr.AddrOf(gp))
    }
    Expr::Deref(pe) => {
      gp := fold(pe)
      newnode(Expr.Deref(gp))
    }
    ## A string literal is not constant-folded (its value is a runtime {ptr, len}); rebuild it
    ## structurally, preserving the inner-bytes span + label index.
    Expr::StrLit(ss, sn, slbl, sps, spn) => { newnode(Expr.StrLit(ss, sn, slbl, sps, spn)) }
    ## `[e0, …, eN]` — an array literal: structural rebuild over the folded element
    ## expressions into a fresh arena-linked `Arg` list, preserving the element count.
    Expr::ArrayLit(anel, aehead) => {
      mut aeh : Option(ptr(mut Arg)) = Option.None
      mut aet : Option(ptr(mut Arg)) = Option.None
      mut aea : Option(ptr(mut Arg)) = aehead
      loop {
        match aea {
          Some(aeaq) => {
            aeold := deref(arg_p(aeaq))
            aefe := fold(aeold.e)
            aenew := newgarg(a, Arg(e = aefe, next = Option.None))
            match aet {
              Some(aet0) => {
                aep := arg_p(aet0)
                aeprev := deref(aep)
                aeupd := Arg(e = aeprev.e, next = Option.Some(aenew))
                deref(aep) = aeupd
              }
              None => { aeh = Option.Some(aenew) }
            }
            aet = Option.Some(aenew)
            aea = aeold.next
          }
          None => { break }
        }
      }
      newnode(Expr.ArrayLit(anel, aeh))
    }
    ## `a[i]` — an element read: not constant-folded (a runtime projection); structural
    ## rebuild over the folded base + index expressions, preserving the variant.
    Expr::Index(ibase, iidx) => {
      gib := fold(ibase)
      gii := fold(iidx)
      newnode(Expr.Index(gib, gii))
    }
    ## `inner?` — the tryable `?` operator: not constant-folded (a runtime control-flow
    ## construct); structural rebuild over the folded inner expression, preserving the variant.
    Expr::Try(inner) => {
      gtr := fold(inner)
      newnode(Expr.Try(gtr))
    }
    ## `unchecked <inner>` — PRESERVE the verification-mode wrapper over the folded inner (so the
    ## `unchecked` scope survives to lower, where `emit_gas` sets `verify.checked` false for it).
    Expr::Unchecked(inner) => {
      gux := fold(inner)
      newnode(Expr.Unchecked(gux))
    }
    ## Issue #680 — the seven variants this `match` never named. With no arm and no `_` a `match` that
    ## takes no arm yields −1, so any of them reaching `fold` came back as a wild pointer; the
    ## exhaustiveness check now sees `node := deref(e)` and refuses the gap instead. None of them is a
    ## constant to reduce: leaves are copied, and expression children are folded and rebuilt in place.
    ## `Lambda` and `Loop` keep their statement-list payloads, which `fold` does not walk.
    Expr::FloatLit(fls, fln) => { newnode(Expr.FloatLit(fls, fln)) }
    Expr::Slice(sb, slo, shi) => {
      gsb := fold(sb)
      gslo := fold(slo)
      gshi := fold(shi)
      newnode(Expr.Slice(gsb, gslo, gshi))
    }
    Expr::CompField(cfb, cfi) => {
      gcfb := fold(cfb)
      gcfi := fold(cfi)
      newnode(Expr.CompField(gcfb, gcfi))
    }
    Expr::Lambda(lpos, lparams, lrts, lrtl, lbody, lval) => { newnode(Expr.Lambda(lpos, lparams, lrts, lrtl, lbody, lval)) }
    Expr::FnRef(frs, frn, frp) => { newnode(Expr.FnRef(frs, frn, frp)) }
    Expr::Bitcast(bci, bcs, bcn) => {
      gbci := fold(bci)
      newnode(Expr.Bitcast(gbci, bcs, bcn))
    }
    Expr::Loop(lpb) => { newnode(Expr.Loop(lpb)) }
  }
}
