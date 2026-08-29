## selfhost::lower::rodata — the .rodata AST walker.
##
## MOD-12: this child owns the complete AST traversal that discovers and emits string/embed/float
## literal cells. It deliberately keeps the ROD_* scan state and label helpers in the ancestor module;
## the const-global safety check stays with this declaration walker and calls the parent-owned helper.
## This split changes only module ownership, not emission policy or output.
##
## The walker has no sibling-child dependencies. Its direct dependencies are the AST node projections
## and the runtime buffer/vector types below; parent helpers resolve through the lower ancestor chain.
strbuf := rt
arm_p := ast::arm_p
arg_p := ast::arg_p
stmt_p := ast::stmt_p
(Decl, Expr, Stmt, local_is_mut) := ast
(push_str, push_int) := rt
## DATA-SECTION (`.rodata`) emission for string literals. Each `StrLit` carries a unique
## label index (assigned at parse time), so the AST is walked once before the `.text` section
## and every literal occurrence is emitted as `.Lstr<idx>: .ascii "<bytes>"` (the inner bytes
## read verbatim from the source via `str_at` — escapes deferred, the toy strings are plain
## ASCII). `.ascii` emits exactly the bytes with NO null terminator, matching the {ptr, len}
## representation (len = the byte count). The walk recurses over every expression child + the
## fn body statement lists, so a literal anywhere in the program gets its data entry.
##
## The deref-`match` on the expr pointer `e` stays a function-body match over a direct PARAM
## (the lowerable shape) — `emit_rodata_expr` is itself the recursion point.
##
## A StrLit's stored `sl` is the RUNTIME byte length. The `.ascii` directive needs the RAW source
## span (the escape sequence is emitted verbatim and `as` decodes it), so recover it by scanning
## `sl` logical bytes: a simple escape consumes two raw bytes while `\xHH` consumes four. Emitting
## `sl` raw bytes instead would truncate a literal by the extra source bytes in an x-escape.
rodata_raw_span := fn(src : ptr(u8), ss : usize, sl : usize) -> usize {
  mut bi := 0
  mut si := 0
  while bi < sl {
    if bytes(str_at((src + ss + si), 1))[0] == 92 {
      if bytes(str_at((src + ss + si + 1), 1))[0] == 120 { si = si + 4 }
      else { si = si + 2 }
    } else { si = si + 1 }
    bi += 1
  }
  si
}
rodata_hex_digit := fn(c : u8) -> usize {
  if c >= 48 and c <= 57 { return usize(c - 48) }
  if c >= 65 and c <= 70 { return usize(c - 65) + 10 }
  if c >= 97 and c <= 102 { return usize(c - 97) + 10 }
  0
}
rodata_has_x_escape := fn(src : ptr(u8), ss : usize, sl : usize) -> bool {
  mut bi := 0
  mut si := 0
  while bi < sl {
    if bytes(str_at((src + ss + si), 1))[0] == 92 {
      if bytes(str_at((src + ss + si + 1), 1))[0] == 120 { return true }
      si = si + 2
    } else { si = si + 1 }
    bi += 1
  }
  false
}
## Emit a literal containing `\xHH` as explicit bytes. GAS's `.ascii` escape parser is not
## portable for a following source byte (`"\x00A"` was assembled as 0x0A), so x-escape literals
## bypass it and are decoded by the compiler before assembly.
emit_rodata_decoded := fn(in out sb : strbuf::StrBuf, src : ptr(u8), ss : usize, sl : usize) {
  mut bi := 0
  mut si := 0
  mut any := false
  while bi < sl {
    mut b := 0
    if bytes(str_at((src + ss + si), 1))[0] == 92 {
      esc := bytes(str_at((src + ss + si + 1), 1))[0]
      if esc == 120 {
        b = rodata_hex_digit(bytes(str_at((src + ss + si + 2), 1))[0]) * 16
        b = b + rodata_hex_digit(bytes(str_at((src + ss + si + 3), 1))[0])
        si = si + 4
      } else {
        if esc == 110 { b = 10 }
        else if esc == 116 { b = 9 }
        else if esc == 114 { b = 13 }
        else if esc == 48 { b = 0 }
        else if esc == 92 or esc == 34 or esc == 39 { b = usize(esc) }
        else { b = usize(esc) }
        si = si + 2
      }
    } else {
      b = usize(bytes(str_at((src + ss + si), 1))[0])
      si = si + 1
    }
    if not any { push_str(sb, " .byte ") } else { push_str(sb, ", ") }
    push_int(sb, i64(b))
    any = true
    bi += 1
  }
  if not any { push_str(sb, " 0") }
  push_str(sb, "\n")
}
## The `.rodata` entry for a `StrLit`. A NORMAL literal: `.Lstr<lbl>: .ascii "<inner source bytes>"`.
## An EMBED literal: its baked file bytes as `.Lstr<lbl>: .byte b0, b1, …`, read from the ABSOLUTE
## address `ss` (baked into the compile arena by `parser::embed_strlit`, NOT a source offset), so ANY
## binary byte (NUL / high / newline) is exact with no `.ascii` escaping.
##
## EMBED DETECTION — `lbl % 1000000 >= 500000` (`parser::embed_label_base` = 500000): an embed's
## label carries the marker in its LOW residue. This is invariant under the closure-hoist label
## RENUMBER (`driver` adds `(fnpos+1)*1000000` to a cloned literal's label — a multiple of 1000000,
## so the residue is preserved), and the renumber leaves `ss` untouched, so a renumbered embed is
## still recognized and still reads its absolute address. Normal labels have residue < 500000 (the
## whole compiler uses ~6.5k strings; the renumber design already assumes < 1000000 per module), so
## they never collide. `src/`+`lib/` contain NO embeds → the `.byte` branch is never taken in a
## self-build → the emitted GAS is byte-identical → the TOOL-1 fixpoint is neutral.
emit_strlit_rodata := fn(in out sb : strbuf::StrBuf, src : ptr(u8), ss : usize, sl : usize, lbl : usize) {
  ## slice 1d SCAN pass: record the module's smallest label index and emit NOTHING (see `ROD_SCAN`).
  if ROD_SCAN != 0 {
    if ROD_HAS == 0 { ROD_MIN = lbl }
    if lbl < ROD_MIN { ROD_MIN = lbl }
    ROD_HAS = 1
    return
  }
  globl_lstr(sb, lbl)
  push_lstr(sb, lbl)
  if lbl % 1000000 >= 500000 {
    push_str(sb, ":")
    mut ei := 0
    while ei < sl {
      eb := bytes(str_at(unchecked bitcast(ptr(u8), ss + ei), 1))[0]
      if ei == 0 { push_str(sb, " .byte ") } else { push_str(sb, ", ") }
      push_int(sb, i64(usize(eb)))
      ei = ei + 1
    }
    push_str(sb, "\n")
  } else {
    if rodata_has_x_escape(src, ss, sl) {
      push_str(sb, ":")
      emit_rodata_decoded(sb, src, ss, sl)
    } else {
      push_str(sb, ": .ascii \"")
      rs := rodata_raw_span(src, ss, sl)
      push_str(sb, str_at((src + ss), rs))
      push_str(sb, "\"\n")
    }
  }
}
emit_rodata_expr := fn(e : ptr(Expr), in out sb : strbuf::StrBuf, src : ptr(u8), a : rt::Arena, seen : ptr(mut rt::Vec)) {
  match deref(e) {
    Expr::Num(v, s, n) => {}
    Expr::Var(s, n) => {}
    Expr::Bin(op, l, r) => {
      emit_rodata_expr(l, sb, src, a, seen)
      emit_rodata_expr(r, sb, src, a, seen)
    }
    Expr::If(c, t, f) => {
      emit_rodata_expr(c, sb, src, a, seen)
      emit_rodata_expr(t, sb, src, a, seen)
      emit_rodata_expr(f, sb, src, a, seen)
    }
    Expr::Match(scrut, head) => {
      emit_rodata_expr(scrut, sb, src, a, seen)
      mut arm := head
      while arm != 0 {
        am := deref(arm_p(arm))
        ## a STR-LITERAL pattern arm (`wild == 4`) carries its pattern StrLit's node handle in `lit`
        ## — emit that literal's `.ascii` rodata (the dispatch byte-compares against it).
        if am.wild == 4 { emit_rodata_expr(unchecked bitcast(ptr(Expr), usize(am.lit)), sb, src, a, seen) }
        emit_rodata_expr(am.body, sb, src, a, seen)
        emit_rodata_stmts(am.body_stmts, sb, src, a, seen)
        arm = am.next
      }
    }
    Expr::Call(cs, cl, nargs, args_head) => {
      mut g := args_head
      while g != 0 {
        ga := deref(arg_p(g))
        emit_rodata_expr(ga.e, sb, src, a, seen)
        g = ga.next
      }
    }
    Expr::StructLit(cs, cl, nf, fhead) => {
      mut g := fhead
      while g != 0 {
        ga := deref(arg_p(g))
        emit_rodata_expr(ga.e, sb, src, a, seen)
        g = ga.next
      }
    }
    Expr::Field(base, fs, fl) => { emit_rodata_expr(base, sb, src, a, seen) }
    Expr::EnumLit(es, el, vs, vl, np, phead) => {
      mut g := phead
      while g != 0 {
        ga := deref(arg_p(g))
        emit_rodata_expr(ga.e, sb, src, a, seen)
        g = ga.next
      }
    }
    Expr::AddrOf(p) => { emit_rodata_expr(p, sb, src, a, seen) }
    Expr::Deref(p) => { emit_rodata_expr(p, sb, src, a, seen) }
    Expr::ArrayLit(nel, ehead) => {
      mut g := ehead
      while g != 0 {
        ga := deref(arg_p(g))
        emit_rodata_expr(ga.e, sb, src, a, seen)
        g = ga.next
      }
    }
    Expr::Index(base, idx) => {
      emit_rodata_expr(base, sb, src, a, seen)
      emit_rodata_expr(idx, sb, src, a, seen)
    }
    Expr::Try(inner) => { emit_rodata_expr(inner, sb, src, a, seen) }
    Expr::Unchecked(inner) => { emit_rodata_expr(inner, sb, src, a, seen) }
    Expr::Bitcast(inner, _bcs, _bcl) => { emit_rodata_expr(inner, sb, src, a, seen) }
    ## the data entry for this literal (delegated to `emit_strlit_rodata`, which handles both the
    ## `.ascii` source-literal case and the embed `.byte` case; see its EMBED DETECTION note).
    Expr::StrLit(ss, sl, lbl, _ps, _pn) => { emit_strlit_rodata(sb, src, ss, sl, lbl) }
    ## the data entry for a FLOAT literal: `.Lflt<start>: .double <verbatim source text>` — the
    ## ASSEMBLER computes the IEEE-754 bits from the decimal text (e.g. "1.5"), so the compiler needs
    ## no float arithmetic of its own. The label is keyed on the literal's source-span start,
    ## matching the `movsd .Lflt<start>(%rip)` load in `emit_gas`.
    ##
    ## DEDUP by source-offset: unlike a `StrLit` (whose label index `lbl` is renumbered per HOF clone
    ## so every emission is unique), a `FloatLit` has NO separate label field — its label IS the source
    ## offset `fss`. When the driver's D-cap path DEEP-CLONES a HOF body carrying a float literal, the
    ## clone copies `fss` VERBATIM (it cannot be bumped — `fss` also indexes the literal's decimal text),
    ## so the original and the clone would both emit `.Lflt<fss>:` → an assembler "symbol already defined".
    ## Both loads (`movsd .Lflt<fss>`) name the SAME offset and read the SAME text, so ONE shared `.rodata`
    ## entry is correct: emit each distinct `fss` at most once, tracking emitted offsets in `seen`. In an
    ## un-cloned program every FloatLit has a unique `fss`, so nothing is skipped → the GAS is byte-
    ## identical → the TOOL-1 fixpoint is unaffected (`src/`+`lib/` float offsets are all unique).
    Expr::FloatLit(fss, fsl) => {
      ## slice 1d: the SCAN pass emits nothing AND must not touch `seen` (marking a float as emitted
      ## here would make the real pass skip its `.rodata` cell → an undefined `.Lflt` reference).
      if ROD_SCAN == 0 {
      mut fdup := false
      mut fk := 0
      while fk < rt::vec_len(deref(seen)) {
        if rt::vec_get(deref(seen), fk) == fss { fdup = true }
        fk += 1
      }
      if fdup == false {
        rt::vec_push(deref(seen), fss)
        globl_lflt(sb, fss)
        push_lflt(sb, fss)
        push_str(sb, ": .double ")
        push_str(sb, str_at((src + fss), fsl))
        push_str(sb, "\n")
      }
      }
    }
  }
}

## Walk a body statement list, emitting the `.rodata` entry for any string literal in any
## sub-expression (and recursing into nested branch/arm/loop statement lists).
emit_rodata_stmts := fn(head : ptr(mut Stmt), in out sb : strbuf::StrBuf, src : ptr(u8), a : rt::Arena, seen : ptr(mut rt::Vec)) {
  mut s := head
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { emit_rodata_expr(v, sb, src, a, seen); s = nx }
      Stmt::While(c, b, nx) => {
        emit_rodata_expr(c, sb, src, a, seen)
        emit_rodata_stmts(b, sb, src, a, seen)
        s = nx
      }
      Stmt::Loop(b, nx) => {
        emit_rodata_stmts(b, sb, src, a, seen)
        s = nx
      }
      Stmt::Unchecked(b, nx) => {
        emit_rodata_stmts(b, sb, src, a, seen)
        s = nx
      }
      Stmt::AllocWith(ae, b, nx) => {
        emit_rodata_expr(ae, sb, src, a, seen)
        emit_rodata_stmts(b, sb, src, a, seen)
        s = nx
      }
      Stmt::Break(_bv, _bd, nx) => { s = nx }
      Stmt::Continue(_cd, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { emit_rodata_expr(e, sb, src, a, seen); s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { emit_rodata_expr(fv, sb, src, a, seen); s = nx }
      Stmt::FieldPathAssign(pl, fpv, nx) => { emit_rodata_expr(fpv, sb, src, a, seen); s = nx }
      Stmt::Return(rv, nx) => { emit_rodata_expr(rv, sb, src, a, seen); s = nx }
      Stmt::If(c, th, el, nx) => {
        emit_rodata_expr(c, sb, src, a, seen)
        emit_rodata_stmts(th, sb, src, a, seen)
        emit_rodata_stmts(el, sb, src, a, seen)
        s = nx
      }
      Stmt::Match(sc, ah, nx) => {
        emit_rodata_expr(sc, sb, src, a, seen)
        mut arm := ah
        while arm != 0 {
          am := deref(arm_p(arm))
          ## a STR-LITERAL pattern arm (`wild == 4`): emit the pattern StrLit's `.ascii` rodata.
          if am.wild == 4 { emit_rodata_expr(unchecked bitcast(ptr(Expr), usize(am.lit)), sb, src, a, seen) }
          emit_rodata_stmts(am.body_stmts, sb, src, a, seen)
          arm = am.next
        }
        s = nx
      }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => {
        emit_rodata_expr(flo, sb, src, a, seen)
        if unchecked bitcast(usize, fhi) != 0 { emit_rodata_expr(fhi, sb, src, a, seen) }   ## fhi==0 = for-over-iterable
        emit_rodata_stmts(fb, sb, src, a, seen)
        s = nx
      }
      Stmt::CompIf(ccond, cthen, celse, nx) => {
        emit_rodata_stmts(cthen, sb, src, a, seen)
        emit_rodata_stmts(celse, sb, src, a, seen)
        s = nx
      }
      Stmt::CompFor(cvs, cvl, civ, cb, nx) => {
        emit_rodata_stmts(cb, sb, src, a, seen)
        s = nx
      }
      Stmt::CompForRange(crvs, crvl, crlo, crhi, crb, nx) => {
        emit_rodata_stmts(crb, sb, src, a, seen)
        s = nx
      }
      Stmt::CompMatch(cmsc, cmah, nx) => {
        mut car := cmah
        while car != 0 { cam := deref(arm_p(car)); emit_rodata_stmts(cam.body_stmts, sb, src, a, seen); car = cam.next }
        s = nx
      }
      Stmt::DerefAssign(ptr, val, nx) => {
        emit_rodata_expr(ptr, sb, src, a, seen)
        emit_rodata_expr(val, sb, src, a, seen)
        s = nx
      }
      Stmt::IndexAssign(ib, ii, iv, nx) => {
        emit_rodata_expr(ib, sb, src, a, seen)
        emit_rodata_expr(ii, sb, src, a, seen)
        emit_rodata_expr(iv, sb, src, a, seen)
        s = nx
      }
      Stmt::IndexFieldAssign(fia, fii, ifs, ifl, fiv, nx) => {
        emit_rodata_expr(fia, sb, src, a, seen)
        emit_rodata_expr(fii, sb, src, a, seen)
        emit_rodata_expr(fiv, sb, src, a, seen)
        s = nx
      }
    }
  }
}

## One declaration's rodata contribution. The scan pass and the real per-module pass must walk the
## same AST shapes; keeping that policy here prevents `emit_program` from growing another copy when
## the module-local data lane gains a new declaration kind. `check_const` is enabled only for the real
## pass because the scan exists solely to derive label bases.
pub emit_rodata_decl := fn(d : Decl, decls : ptr(rt::Vec), src : ptr(u8), in out sb : strbuf::StrBuf, a : rt::Arena, seen : ptr(mut rt::Vec), check_const : bool) {
  if d.kind == 1 or d.kind == 5 {
    emit_rodata_stmts(d.body_stmts, sb, src, a, seen)
    emit_rodata_expr(d.value, sb, src, a, seen)
  } else if d.kind == 0 {
    ## CORRECT-OR-TRAP: a CONST module-level GLOBAL (`G := mk()`, no `mut`) whose initializer is
    ## a runtime CALL returning an AGGREGATE. A const global has NO storage — its value is folded at each
    ## use — and a call folds to nothing, so `G.a` silently read 0 while the initializer never ran.
    ## A `mut` global is deliberately excluded: it gets real zero-initialized storage.
    if check_const and d.is_fn == false and d.ret_tl == 0 and d.arity == 0 and local_is_mut(src, d.name_start) == false and global_init_agg_call(d.value, decls, src, a) {
      panic("selfhost: a CONST module-level global initialized by a runtime CALL returning an aggregate (struct / enum / tuple / str / slice) is not lowered — a const global's initializer must be a compile-time constant (a literal), and the call never runs (its fields would silently read 0); build the value inside a function instead")
    }
    emit_rodata_expr(d.value, sb, src, a, seen)
  }
}
