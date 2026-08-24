## selfhost::comptime — a constant-folding pass over the AST (ROADMAP §1/§6, item 5).
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

## rt-style AST-node allocator + reader (ROADMAP §1 fixpoint) — the lean replacement for the
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
## The allocator parameter `a` is the **ambient** within this body (D99 / Functions §5.5
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
            _ => { newnode(Expr.Bin(op, fl, fr)) }
          }
        }
        _ => { newnode(Expr.Bin(op, fl, fr)) }
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
      mut nhead := 0
      mut ntail := 0
      mut arm := head
      while arm != 0 {
        am := deref(arm_p(arm))
        fb := fold(am.body)
        anew := newarm(a, Arm(wild = am.wild, lit = am.lit, body = fb, next = 0, vs = am.vs, vl = am.vl, binds_head = am.binds_head, body_stmts = am.body_stmts, hi = am.hi))
        if nhead == 0 { nhead = anew } else {
          ap := arm_p(ntail)
          old := deref(ap)
          upd := Arm(wild = old.wild, lit = old.lit, body = old.body, next = anew, vs = old.vs, vl = old.vl, binds_head = old.binds_head, body_stmts = old.body_stmts, hi = old.hi)
          deref(ap) = upd
        }
        ntail = anew
        arm = am.next
      }
      newnode(Expr.Match(fs, nhead))
    }
    ## `name(a0, …, a5)` — a call. A call is not constant-folded further here (its result is
    ## a runtime value); the correct rewrite is a structural rebuild over the folded
    ## arguments into a fresh arena-linked `Arg` list, preserving the callee name span +
    ## `nargs`. (Distinct binding names — `gh`/`gt`/… — would collide with sibling-arm locals
    ## under the match's one name scope, so the `Arg`-list rebuild names are unique here.)
    Expr::Call(cs, cl, nargs, args_head) => {
      mut ghead := 0
      mut gtail := 0
      mut garm := args_head
      while garm != 0 {
        gold := deref(arg_p(garm))
        gfe := fold(gold.e)
        gnew := newgarg(a, Arg(e = gfe, next = 0))
        if ghead == 0 { ghead = gnew } else {
          gp := arg_p(gtail)
          gprev := deref(gp)
          gupd := Arg(e = gprev.e, next = gnew)
          deref(gp) = gupd
        }
        gtail = gnew
        garm = gold.next
      }
      newnode(Expr.Call(cs, cl, nargs, ghead))
    }
    ## `S(f0 = e0, …, fN = eN)` — a struct construction: structural rebuild over the folded
    ## field-value expressions into a fresh arena-linked `Arg` list (mirroring the `Call` arm),
    ## preserving the struct name span + field count. (Distinct binding names — `sfh`/`sft`/…
    ## — avoid colliding with locals in sibling arms; match arms share one name scope for the
    ## definite-assignment check.)
    Expr::StructLit(scs, scl, snf, sfhead) => {
      mut sfh := 0
      mut sft := 0
      mut sfa := sfhead
      while sfa != 0 {
        sfold := deref(arg_p(sfa))
        sffe := fold(sfold.e)
        sfnew := newgarg(a, Arg(e = sffe, next = 0))
        if sfh == 0 { sfh = sfnew } else {
          sfp := arg_p(sft)
          sfprev := deref(sfp)
          sfupd := Arg(e = sfprev.e, next = sfnew)
          deref(sfp) = sfupd
        }
        sft = sfnew
        sfa = sfold.next
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
      mut eph := 0
      mut ept := 0
      mut epa := ephead
      while epa != 0 {
        epold := deref(arg_p(epa))
        epfe := fold(epold.e)
        epnew := newgarg(a, Arg(e = epfe, next = 0))
        if eph == 0 { eph = epnew } else {
          epp := arg_p(ept)
          epprev := deref(epp)
          epupd := Arg(e = epprev.e, next = epnew)
          deref(epp) = epupd
        }
        ept = epnew
        epa = epold.next
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
    Expr::StrLit(ss, sn, slbl) => { newnode(Expr.StrLit(ss, sn, slbl)) }
    ## `[e0, …, eN]` — an array literal: structural rebuild over the folded element
    ## expressions into a fresh arena-linked `Arg` list, preserving the element count.
    Expr::ArrayLit(anel, aehead) => {
      mut aeh := 0
      mut aet := 0
      mut aea := aehead
      while aea != 0 {
        aeold := deref(arg_p(aea))
        aefe := fold(aeold.e)
        aenew := newgarg(a, Arg(e = aefe, next = 0))
        if aeh == 0 { aeh = aenew } else {
          aep := arg_p(aet)
          aeprev := deref(aep)
          aeupd := Arg(e = aeprev.e, next = aenew)
          deref(aep) = aeupd
        }
        aet = aenew
        aea = aeold.next
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
  }
}
