## selfhost::driver — ties the passes into ONE compile function.
##
## This is the integration point of the self-hosted compiler tree: it composes the
## sibling passes — `lexer::lex_all` (source → `Vec(Token)`), `parser::parse_program`
## (tokens → `Vec(Decl)`), and `lower::emit_program` (the `Decl`s → x86_64 GAS) — into a
## single `compile(src, …) -> StrBuf` that produces assembly for a complete program. For
## legacy/default `_start` builds without a source `_start`, the driver still emits a small
## `_start -> <module>__main` process-exit wrapper; custom manifest entries are real linker
## symbols emitted by the lower (for example via `@export("name")`). Assembled + linked + run
## by the harness, the artifact's exit code proves the self-host tree compiles a
## REAL Alatyr program end to end (real source → self-host lex/parse/lower → real machine
## code → correct exit code).
##
## A value built by `parser.al` flows into `lower.al` unchanged because both reference the
## one shared `ast::Decl`/`ast::Expr` (the AST unification). The pass-specific state types
## (`parser::PC`, `lower::LCtx`/`SlotEntry`) stay local to their modules; `compile` only
## touches the public surface (`lex_all`, `parse_program`, `emit_program`).
##
## NOTE on the compatibility entry convention: the synthesized default `_start` does `call
## <module>__main` then moves `%rax` into `%rdi` and invokes `syscall` 60 (exit). A custom
## manifest `entry` is not synthesized here; it must resolve as an emitted symbol.
vec := alloc::vec
## The output/source buffers are `rt::StrBuf` (off `alloc::strbuf` for the §1 fixpoint); aliasing
## `rt` as `strbuf` keeps `strbuf::StrBuf`/`strbuf_base`/`buf_len`/`strbuf_free`/`push_byte` resolving
## to rt's. The `strbuf::strbuf(arena, cap)` CONSTRUCTOR calls now pass an rt arena (`tar`), not `a`.
strbuf := rt
io := std::io
(Decl, Token, Stmt, Expr, Arg, Param, Arm, Bind, FieldDecl, local_is_mut) := ast
(bnd_ns, bnd_nl, bnd_next) := ast
fld_p := ast::fld_p
param_p := ast::param_p
arm_p := ast::arm_p
arg_p := ast::arg_p
stmt_p := ast::stmt_p
## Local aliases for the cross-module state types — a struct constructed through a
## fully-`::` qualified path does not lower in construction position (the documented
## codegen gap), so alias them and construct via the bare name. The lexer is now `lexrt`
## (on rt); `lexer.al` (the alloc::vec lexer) is no longer used by the driver.
PC := parser::PC
ifc := iface
## A typed pointer to a Decl node at arena handle `h` (the per-module `decl_at`, duplicated here —
## the self-host lower compiles a per-module copy). Lets the `test` runner read each decl's `kind`.
decl_at := fn(T : type, h : usize) -> ptr(T) { return unchecked bitcast(ptr(T), h) }

## The per-module `decl_get`/`streq`, duplicated here for the same reason `decl_at` is. They used to be
## BARE calls that resolved to `aarch64`'s private copies (measured: `driver__d_check_linker_symbols ->
## call aarch64__streq`) — Modules §3 makes an unrelated module's non-`pub` helper unnameable from here,
## so the bare call had no legal answer and the resolver was picking the first declaration in
## declaration order. Every emitter module carries its own pair; `driver` now does too. `streq`'s
## length-first reject is a fast path, and `src + a_s` is POINTER arithmetic (a span start may be a
## REBASED handle for a comptime-synthesized name), so it routes through `rt::addr` (I11 / CG-8).
decl_get := fn(decls : ptr(rt::Vec), i : usize) -> ptr(Decl) { hh := rt::vec_get(deref(decls), i) ; return decl_at(Decl, hh) }
streq := fn(src : ptr(u8), a_s : usize, a_n : usize, b_s : usize, b_n : usize) -> bool {
  if a_n != b_n { return false }
  wa := str_at((src + a_s), a_n)
  wb := str_at((src + b_s), b_n)
  wa == wb
}

## Build the struct FIELD-ORDER table `sv` (the parser's `P_STRUCTS_TBL`) from the collected `decls`:
## one packed record per kind-2 struct decl — `name_start, name_len, nfields, then nfields × (field_ns,
## field_nl)`. Consumed by the parser's by-name struct-literal reorder (TYP-8). Mirrors the enum-name
## collection loop; run in the SAME first parse pass (getdents module order is not dependency-sorted, so
## the table must span all modules before pass 2 resolves any struct literal). Two walks per struct —
## count fields, then push the pairs — since the record's `nfields` header precedes the field pairs.
## Is the byte at `src[p]` an ASCII whitespace (space / newline / tab / CR)? The source-scan primitive
## shared by `_struct_field_default` (mirrors the whitespace test in `d_export_name`).
_ws1 := fn(src : ptr(u8), p : usize) -> bool {
  c := str_at((src + p), 1)
  c == " " or c == "\n" or c == "\t" or c == "\r"
}

## Source-scan a struct field's DEFAULT `= <expr>` (spec Types §9.4 / TYP-8) — the value the by-name
## reorder fills when the field is OMITTED at construction. The `FieldDecl` node cannot carry it (the
## seed's 8-word node limit), so it is recovered here from `src` (like `lower_layout::field_offset_attr`):
## starting just past the field's TYPE span `[ts, ts+tl)`, skip whitespace; if the next byte is `=`, the
## default is the balanced expression up to the top-level `,`/`}` (parens/brackets balanced; string
## literals skipped so a `,`/`}` inside a `"…"` default does not terminate early). Returns the default's
## `[s, n)` span (a slice of `src`); `n == 0` = the field has NO default. Neutral: no `src/`/`lib/` field
## declares a default → the scan finds no `=` → every field returns `n == 0` → the table is byte-identical.
_struct_field_default := fn(src : ptr(u8), ts : usize, tl : usize) -> DSpan {
  mut p := ts + tl
  while _ws1(src, p) { p = p + 1 }
  if str_at((src + p), 1) != "=" { return DSpan(s = 0, n = 0) }
  p = p + 1                                  ## '='
  while _ws1(src, p) { p = p + 1 }
  ds := p
  mut dep := 0
  mut scan := true
  while scan {
    c := str_at((src + p), 1)
    if dep == 0 and (c == "," or c == "}") { scan = false }
    else if c == "(" or c == "[" { dep = dep + 1; p = p + 1 }
    else if c == ")" or c == "]" { dep = dep - 1; p = p + 1 }
    else if c == "\"" {
      p = p + 1
      while str_at((src + p), 1) != "\"" { p = p + 1 }
      p = p + 1                              ## closing '"'
    }
    else { p = p + 1 }
  }
  mut e := p
  while e > ds and _ws1(src, e - 1) { e = e - 1 }
  DSpan(s = ds, n = e - ds)
}

collect_struct_table := fn(decls : rt::Vec, src : ptr(u8), in out sv : rt::Vec) {
  dcnt := rt::vec_len(decls)
  mut di := 0
  while di < dcnt {
    d := deref(decl_at(Decl, rt::vec_get(decls, di)))
    if d.kind == 2 {
      mut nf := 0
      mut f := unchecked bitcast(usize, d.fields_head)
      while f != 0 {
        fd := deref(fld_p(unchecked bitcast(ptr(mut FieldDecl), f)))
        nf += 1
        f = unchecked bitcast(usize, fd.next)
      }
      rt::vec_push(sv, d.name_start)
      rt::vec_push(sv, d.name_len)
      ## The DECLARING MODULE travels with the record (TYPE-ANCESTOR): `parser::struct_rec_of` used
      ## to take the FIRST same-named record in the table, so a struct literal's `f = v` names were
      ## checked against an unrelated module's same-named struct — a LEGAL program rejected with
      ## "unknown field name" whenever the decoy sorted first. With the module recorded, that lookup
      ## ranks its candidates by Modules §3 exactly like every other type query.
      rt::vec_push(sv, d.mod_start)
      rt::vec_push(sv, d.mod_len)
      rt::vec_push(sv, nf)
      ## Each field entry is 4 words: `ns, nl, def_start, def_len` (def_len == 0 = no default). The
      ## default span is SOURCE-SCANNED past the field's captured type span `[ts, ts+tl)` (TYP-8/§9.4).
      mut f2 := unchecked bitcast(usize, d.fields_head)
      while f2 != 0 {
        fd := deref(fld_p(unchecked bitcast(ptr(mut FieldDecl), f2)))
        rt::vec_push(sv, fd.ns)
        rt::vec_push(sv, fd.nl)
        df := _struct_field_default(src, fd.ts, fd.tl)
        rt::vec_push(sv, df.s)
        rt::vec_push(sv, df.n)
        f2 = unchecked bitcast(usize, fd.next)
      }
    }
    di += 1
  }
}

## Whether the program defines its own `_start` entry (the spec ELF entry — Modules §6.1 unprefixed,
## manifest `entry` default `_start`). When present, the lower emits it as the exact `_start` symbol
## and the driver must NOT synthesize its OWN `_start` wrapper (else a duplicate symbol / two entries).
## The declaration may be named `_start` or may provide the exact linker name through
## `@export("_start")` (Modules §6.3); both are the program's entry and must suppress the wrapper.
## `src/` compiles no `_start` (its `package.al` manifest is excluded), so this is false for the
## self-host build → the wrapper is emitted exactly as before → the TOOL-1 fixpoint is unaffected.
d_has_start := fn(decls : rt::Vec, src : ptr(u8)) -> bool {
  mut i := 0
  while i < rt::vec_len(decls) {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if d.kind == 1 and d.name_len != 0 {
      if str_at((src + d.name_start), d.name_len) == "_start" { return true }
      ex := d_export_name(src, d.name_start, d.name_len)
      if ex.n != 0 and str_at((src + ex.s), ex.n) == "_start" { return true }
    }
    i += 1
  }
  false
}

DSpan := struct { s : usize, n : usize }

## Return the aggregate head of a recorded type-alias RHS. `ret_ts/ret_tl` carries a plain or
## qualified path (`Color`, `codec::Error`); `alias_ts/alias_tl` carries a generic instance
## (`Result(u64, E)`). This helper deliberately strips only the first `(` and the path prefix —
## it does not follow alias chains.
d_alias_type_head := fn(src : ptr(u8), d : Decl) -> DSpan {
  mut s := 0
  mut n := 0
  if d.ret_tl != 0 { s = d.ret_ts; n = d.ret_tl }
  else if d.alias_tl != 0 { s = d.alias_ts; n = d.alias_tl }
  if n == 0 { return DSpan(s = 0, n = 0) }
  mut e := s
  while e < s + n and str_at((src + e), 1) != "(" { e += 1 }
  mut ts := s
  mut p := s
  while p + 1 < e {
    if str_at((src + p), 2) == "::" { ts = p + 2; p += 2 }
    else { p += 1 }
  }
  DSpan(s = ts, n = e - ts)
}

## Does the declaration set contain the DIRECT enum target head? The scan compares text, because
## aliases and target declarations may live in different module slices of the shared source buffer.
## It intentionally ignores aliases already added to the parser table: that keeps this collector to
## one hop instead of accidentally admitting an alias-of-alias constructor spelling.
d_direct_enum_decl_has := fn(decls : rt::Vec, src : ptr(u8), s : usize, n : usize) -> bool {
  mut i := 0
  while i < rt::vec_len(decls) {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if d.kind == 3 and streq(src, d.name_start, d.name_len, s, n) { return true }
    i += 1
  }
  false
}

## Add one-hop aliases of known enum types to the parser's PASS-2 constructor table. Without this,
## `R.Ok(x)` is parsed as a value UFCS call even though `R` denotes the same nominal enum as `Result`.
## The table is additive and only affects ctor-vs-UFCS AST shape; unsupported alias chains remain out.
collect_enum_aliases := fn(decls : rt::Vec, src : ptr(u8), in out ev : rt::Vec) {
  mut i := 0
  while i < rt::vec_len(decls) {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if d.kind == 0 and d.arity == 0 {
      target := d_alias_type_head(src, d)
      if target.n != 0 and d_direct_enum_decl_has(decls, src, target.s, target.n) {
        ns := d.name_start
        nl := d.name_len
        rt::vec_push(ev, ns)
        rt::vec_push(ev, nl)
      }
    }
    i += 1
  }
}

d_export_name := fn(src : ptr(u8), name_s : usize, name_l : usize) -> DSpan {
  ## VALUE position: `name := [attributes] fn(…)`.
  mut v := name_s + name_l
  while str_at((src + v), 1) == " " or str_at((src + v), 1) == "\n" or str_at((src + v), 1) == "\t" or str_at((src + v), 1) == "\r" { v = v + 1 }
  if str_at((src + v), 2) == ":=" {
    v = v + 2
    mut attrs := true
    while attrs {
      while str_at((src + v), 1) == " " or str_at((src + v), 1) == "\n" or str_at((src + v), 1) == "\t" or str_at((src + v), 1) == "\r" { v = v + 1 }
      if str_at((src + v), 1) != "@" { attrs = false }
      else {
        if str_at((src + v), 7) == "@export" {
          c := str_at((src + v + 7), 1)
          if c == "(" or c == " " or c == "\n" or c == "\t" or c == "\r" {
            mut q := v + 7
            while str_at((src + q), 1) == " " or str_at((src + q), 1) == "\n" or str_at((src + q), 1) == "\t" or str_at((src + q), 1) == "\r" { q = q + 1 }
            if str_at((src + q), 1) == "(" {
              q = q + 1
              while str_at((src + q), 1) == " " or str_at((src + q), 1) == "\n" or str_at((src + q), 1) == "\t" or str_at((src + q), 1) == "\r" { q = q + 1 }
              if str_at((src + q), 1) == "\"" {
                es := q + 1
                mut ee := es
                while str_at((src + ee), 1) != "\"" { ee = ee + 1 }
                return DSpan(s = es, n = ee - es)
              }
            }
          }
        }
        v = v + 1
        while (str_at((src + v), 1) >= "a" and str_at((src + v), 1) <= "z") or (str_at((src + v), 1) >= "A" and str_at((src + v), 1) <= "Z") or (str_at((src + v), 1) >= "0" and str_at((src + v), 1) <= "9") or str_at((src + v), 1) == "_" { v = v + 1 }
        if str_at((src + v), 1) == "(" {
          mut depth := 1
          v = v + 1
          while depth > 0 {
            c := str_at((src + v), 1)
            if c == "\"" {
              v = v + 1
              while str_at((src + v), 1) != "\"" { v = v + 1 }
              v = v + 1
            } else if c == "(" { depth = depth + 1; v = v + 1 }
            else if c == ")" { depth = depth - 1; v = v + 1 }
            else { v = v + 1 }
          }
        }
      }
    }
  }
  mut p := name_s
  mut scanning := true
  while scanning {
    while p > 0 and (str_at((src + p - 1), 1) == " " or str_at((src + p - 1), 1) == "\n" or str_at((src + p - 1), 1) == "\t" or str_at((src + p - 1), 1) == "\r") { p = p - 1 }
    if p >= 3 and str_at((src + p - 3), 3) == "mut" { p = p - 3 }
    else if p >= 3 and str_at((src + p - 3), 3) == "pub" { p = p - 3 }
    else if p >= 7 and str_at((src + p - 7), 7) == "@inline" { p = p - 7 }
    else { scanning = false }
  }
  while p > 0 and (str_at((src + p - 1), 1) == " " or str_at((src + p - 1), 1) == "\n" or str_at((src + p - 1), 1) == "\t" or str_at((src + p - 1), 1) == "\r") { p = p - 1 }
  if p < 11 { return DSpan(s = 0, n = 0) }
  if str_at((src + p - 1), 1) != ")" { return DSpan(s = 0, n = 0) }
  clq := p - 2
  if str_at((src + clq), 1) != "\"" { return DSpan(s = 0, n = 0) }
  mut oq := clq
  while oq > 0 and str_at((src + oq - 1), 1) != "\"" { oq = oq - 1 }
  if oq == 0 { return DSpan(s = 0, n = 0) }
  opq := oq - 1
  if opq < 8 { return DSpan(s = 0, n = 0) }
  if str_at((src + opq - 8), 9) != "@export(\"" { return DSpan(s = 0, n = 0) }
  DSpan(s = oq, n = clq - oq)
}

## TOOL-7 — whether this declaration emits the PACKAGE's ENTRY, i.e. a symbol the build path treats as
## an entry point. That is the SAME notion `build`/`run` use, and it has two members: the manifest
## `Target.entry` (default `_start`), the symbol the executable is linked with (`ld -e <entry>`); and a
## source-declared `_start`, the entry a program writes itself — the compiler's entry-compatibility path
## (`d_has_start`: when a declaration emits `_start`, the build does NOT synthesize its own wrapper).
## Exactly the three ways a declaration supplies such a symbol:
##   - `@export("<sym>")` on any declaration — the symbol verbatim (Modules §6.3);
##   - a ROOT-level (anonymous package-root, Modules §6.1) fn NAMED `<sym>` — root declarations are
##     UNPREFIXED, so the ordinary mangled label already IS `<sym>`;
##   - a fn named `_start` in ANY module — the lower additionally emits the unprefixed
##     `.global _start` entry alias for it.
## Used ONLY by the `test` artifact: what `alatyr test` builds is a SEPARATE artifact whose entry is the
## RUNNER's, so the package's entry is not linked into it. `main` is NOT an entry — it is an ordinary
## function, reached (or not) by a test through the normal reachability rules.
d_emits_entry := fn(src : ptr(u8), d : Decl, entry : str) -> bool {
  if d.kind != 1 { return false }
  if d.name_len == 0 { return false }
  e := d_export_name(src, d.name_start, d.name_len)
  if e.n != 0 {
    es := str_at((src + e.s), e.n)
    if es == "_start" { return true }
    if entry.len != 0 and es == entry { return true }
  }
  nm := str_at((src + d.name_start), d.name_len)
  ## the program's OWN entry: a `_start` declaration is the ELF entry whatever the manifest names.
  if nm == "_start" { return true }
  if entry.len == 0 { return false }
  if nm != entry { return false }
  lower::is_root_mod(d.mod_start, d.mod_len)
}

d_array_lit := fn(e : ptr(Expr)) -> bool {
  if unchecked bitcast(usize, e) == 0 { return false }
  mut r := false
  match deref(e) {
    Expr::ArrayLit(nel, ehead) => { r = true }
    _ => {}
  }
  r
}

d_decl_emits_mangled_symbol := fn(src : ptr(u8), d : Decl) -> bool {
  if d.name_len == 0 { return false }
  if d.kind == 1 or d.kind == 4 { return true }
  if d.is_fn == false and d.kind == 0 and d.ret_tl == 0 and d.arity == 0 {
    if local_is_mut(src, d.name_start) { return true }
    return d_array_lit(d.value)
  }
  false
}

d_export_matches_mangled_decl := fn(src : ptr(u8), es : usize, en : usize, d : Decl) -> bool {
  if d_decl_emits_mangled_symbol(src, d) == false { return false }
  ## Modules §6.1 — a ROOT-level declaration (the anonymous `package.al` module) emits its BARE name
  ## as the linker symbol, so the symbol to compare against is the name itself, not `<module>__<name>`.
  if lower::is_root_mod(d.mod_start, d.mod_len) {
    if en != d.name_len { return false }
    return streq(src, es, en, d.name_start, d.name_len)
  }
  mut ps := d.mod_start
  mut pn := d.mod_len
  mut default_mod := false
  if pn == 0 { pn = 4; default_mod = true }
  if en != pn + 2 + d.name_len { return false }
  mut prefix_ok := false
  if default_mod {
    if str_at((src + es), 4) == "main" { prefix_ok = true }
  } else {
    if streq(src, es, pn, ps, pn) { prefix_ok = true }
  }
  if prefix_ok == false { return false }
  if str_at((src + es + pn), 2) != "__" { return false }
  streq(src, es + pn + 2, d.name_len, d.name_start, d.name_len)
}

d_check_linker_symbols := fn(decls : ptr(rt::Vec), src : ptr(u8)) -> bool {
  cnt := rt::vec_len(deref(decls))
  mut bad := false
  for i in 0..cnt {
    di := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
    ei := d_export_name(src, di.name_start, di.name_len)
    if ei.n != 0 {
      for j in 0..i {
        dj := deref(decl_at(Decl, rt::vec_get(deref(decls), j)))
        ej := d_export_name(src, dj.name_start, dj.name_len)
        if ej.n != 0 and streq(src, ei.s, ei.n, ej.s, ej.n) { bad = true }
      }
      for k in 0..cnt {
        dk := deref(decl_at(Decl, rt::vec_get(deref(decls), k)))
        if d_export_matches_mangled_decl(src, ei.s, ei.n, dk) { bad = true }
      }
    }
  }
  bad
}

## Modules §6.1 CLASH RULE — a ROOT-level declaration (in the anonymous `package.al` module) emits its
## BARE name, so it shares ONE FLAT namespace with every submodule's MANGLED symbol. The two can only
## meet when a root name is literally spelled `<module>__<fn>` (`__` is a legal identifier run), but
## when they do the assembler silently keeps one definition and calls bind to the wrong function — so
## REJECT, located, rather than pick one. (Root-vs-`@export` is already covered by
## `d_check_linker_symbols`, whose `d_export_matches_mangled_decl` is root-aware.) Returns the
## offending root declaration's name offset encoded as a `d_limit_reject` span (`offset * 4`), or 0.
d_root_symbol_clash := fn(decls : ptr(rt::Vec), src : ptr(u8)) -> usize {
  cnt := rt::vec_len(deref(decls))
  mut hit := 0
  for i in 0..cnt {
    di := deref(decl_at(Decl, rt::vec_get(deref(decls), i)))
    if di.name_len != 0 and lower::is_root_mod(di.mod_start, di.mod_len) and d_decl_emits_mangled_symbol(src, di) {
      for k in 0..cnt {
        dk := deref(decl_at(Decl, rt::vec_get(deref(decls), k)))
        if lower::is_root_mod(dk.mod_start, dk.mod_len) == false {
          if d_export_matches_mangled_decl(src, di.name_start, di.name_len, dk) { hit = di.name_start }
        }
      }
    }
  }
  hit * 4
}

## ─── FN-6 lambda LIFTING — a DRIVER-level pass. Reading the decls Vec + AST nodes works correctly
## HERE (the parser module's identical read gave garbage — an isolated cross-module discrepancy; the
## driver already reads decls fine, e.g. the test runner). Rewrites each Expr::Lambda to an Expr::FnRef
## + appends a synthetic top-level fn Decl (SENTINEL name_len==0; name_start == the `fn` offset). `na` =
## AST arena (Stmt/Expr/Arg/Param arena-RELATIVE handles → node_ptr); `tar` = decl arena (Decls ABSOLUTE
## → decl_at bitcast; appended via a bump). ───

## AST-node pointer (arena-relative handle → base + h), mirroring parser's node_ptr.
d_nptr := fn(T : type, a : rt::Arena, h : usize) -> ptr(mut T) {
  base_int := unchecked bitcast(usize, a.base)
  return unchecked bitcast(ptr(mut T), base_int + h)
}

## The param count of a Param list.
d_lam_arity := fn(ph : ptr(mut Param), na : ptr(mut rt::Arena)) -> usize {
  mut c := 0
  mut p := ph
  while p != 0 { pm := deref(param_p(p)); c = c + 1; p = pm.next }
  c
}
## Allocate + store a `Param`. CRUCIAL: the store must use an INLINE `deref(bitcast(ptr(mut Param),
## addr)) = val` — exactly the shape the WORKING driver stores use (the synthetic-Decl store + the
## Lambda→FnRef rewrite). Storing through a pointer RETURNED BY A FN (`d_nptr(...)`) mis-lowered: a dump
## showed word 0 written as a STACK POINTER instead of the fields. `val` is a PARAMETER (copied in).
d_mk_param := fn(na : ptr(mut rt::Arena), val : Param) -> ptr(mut Param) {
  parser::pnode(na, val)
}

## The `next` handle of any statement (all-variant; mirrors sema's stmt_next_at).
d_next_stmt := fn(h : usize, na : ptr(mut rt::Arena)) -> usize {
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::Assign(ns, nl, v, nx) => { nx }
    Stmt::While(c, b, nx) => { nx }
    Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { nx }
    Stmt::FieldPathAssign(pl, fpv, nx) => { nx }
    Stmt::Return(rv, nx) => { nx }
    Stmt::If(c, th, el, nx) => { nx }
    Stmt::Match(sc, ah, nx) => { nx }
    Stmt::For(ns, nl, lo, hi, b, nx) => { nx }
    Stmt::DerefAssign(p, v, nx) => { nx }
    Stmt::IndexAssign(b, i, v, nx) => { nx }
    Stmt::IndexFieldAssign(b, i, fs, fl, v, nx) => { nx }
    Stmt::Loop(b, nx) => { nx }
    Stmt::Unchecked(b, nx) => { nx }
    Stmt::AllocWith(ae, b, nx) => { nx }
    Stmt::Break(_bv, _bd, nx) => { nx }
    Stmt::Continue(_cd, nx) => { nx }
    Stmt::ExprStmt(e, nx) => { nx }
    Stmt::CompIf(c, th, el, nx) => { nx }
    Stmt::CompFor(vs, vl, iv, b, nx) => { nx }
    Stmt::CompForRange(vs, vl, lo, hi, b, nx) => { nx }
    Stmt::CompMatch(sc, ah, nx) => { nx }
  }
}

d_lift_expr := fn(e : ptr(Expr), ms : usize, ml : usize, in out decls : rt::Vec, na : ptr(mut rt::Arena), tar : ptr(mut rt::Arena)) {
  match deref(e) {
    Expr::Lambda(fnpos, ph, rts, rtl, bh, val) => {
      d_lift_stmts(bh, ms, ml, decls, na, tar)
      d_lift_expr(val, ms, ml, decls, na, tar)
      sd := Decl(name_start = fnpos, name_len = 0, value = val, is_fn = true, kind = 1, arity = d_lam_arity(ph, na), is_generic = false, params_head = ph, body_stmts = bh, fields_head = 0, ret_ts = rts, ret_tl = rtl, mod_start = ms, mod_len = ml, when_cond = 0, alias_ts = 0, alias_tl = 0)
      s := rt::bump(deref(tar), size(Decl))
      sdp := unchecked bitcast(ptr(mut Decl), s)
      deref(sdp) = sd
      np := rt::vec_push(decls, s)
      nf := Expr.FnRef(fnpos, ms, ml)
      deref(unchecked bitcast(ptr(mut Expr), e)) = nf
    }
    Expr::Bin(op, l, r) => { d_lift_expr(l, ms, ml, decls, na, tar); d_lift_expr(r, ms, ml, decls, na, tar) }
    Expr::If(c, t, f) => { d_lift_expr(c, ms, ml, decls, na, tar); d_lift_expr(t, ms, ml, decls, na, tar); d_lift_expr(f, ms, ml, decls, na, tar) }
    Expr::Call(cs, cl, nn, ah) => { mut g := ah; while g != 0 { ga := deref(arg_p(g)); d_lift_expr(ga.e, ms, ml, decls, na, tar); g = ga.next } }
    Expr::Try(inner) => { d_lift_expr(inner, ms, ml, decls, na, tar) }
    Expr::Unchecked(inner) => { d_lift_expr(inner, ms, ml, decls, na, tar) }
    Expr::Bitcast(inner, bps, bpl) => { d_lift_expr(inner, ms, ml, decls, na, tar) }
    Expr::AddrOf(p) => { d_lift_expr(p, ms, ml, decls, na, tar) }
    Expr::Deref(p) => { d_lift_expr(p, ms, ml, decls, na, tar) }
    Expr::Index(b, ix) => { d_lift_expr(b, ms, ml, decls, na, tar); d_lift_expr(ix, ms, ml, decls, na, tar) }
    Expr::Field(b, fs, fl) => { d_lift_expr(b, ms, ml, decls, na, tar) }
    Expr::Slice(b, lo, hi) => { d_lift_expr(b, ms, ml, decls, na, tar); d_lift_expr(lo, ms, ml, decls, na, tar); d_lift_expr(hi, ms, ml, decls, na, tar) }
    _ => {}
  }
}

d_lift_arms := fn(ah : ptr(mut Arm), ms : usize, ml : usize, in out decls : rt::Vec, na : ptr(mut rt::Arena), tar : ptr(mut rt::Arena)) {
  mut arm := ah
  while arm != 0 {
    am := deref(arm_p(arm))
    d_lift_stmts(am.body_stmts, ms, ml, decls, na, tar)
    if unchecked bitcast(usize, am.body) != 0 { d_lift_expr(am.body, ms, ml, decls, na, tar) }
    arm = am.next
  }
}

d_lift_stmts := fn(head : ptr(mut Stmt), ms : usize, ml : usize, in out decls : rt::Vec, na : ptr(mut rt::Arena), tar : ptr(mut rt::Arena)) {
  mut s := head
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { d_lift_expr(v, ms, ml, decls, na, tar) }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { d_lift_expr(rv, ms, ml, decls, na, tar) } }
      Stmt::ExprStmt(e, nx) => { d_lift_expr(e, ms, ml, decls, na, tar) }
      Stmt::If(c, th, el, nx) => { d_lift_expr(c, ms, ml, decls, na, tar); d_lift_stmts(th, ms, ml, decls, na, tar); d_lift_stmts(el, ms, ml, decls, na, tar) }
      Stmt::While(c, b, nx) => { d_lift_expr(c, ms, ml, decls, na, tar); d_lift_stmts(b, ms, ml, decls, na, tar) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { if unchecked bitcast(usize, lo) != 0 { d_lift_expr(lo, ms, ml, decls, na, tar) }; if unchecked bitcast(usize, hi) != 0 { d_lift_expr(hi, ms, ml, decls, na, tar) }; d_lift_stmts(b, ms, ml, decls, na, tar) }
      Stmt::Loop(b, nx) => { d_lift_stmts(b, ms, ml, decls, na, tar) }
      Stmt::Unchecked(b, nx) => { d_lift_stmts(b, ms, ml, decls, na, tar) }
      Stmt::AllocWith(ae, b, nx) => { d_lift_stmts(b, ms, ml, decls, na, tar) }
      Stmt::DerefAssign(p, v, nx) => { d_lift_expr(v, ms, ml, decls, na, tar) }
      Stmt::IndexAssign(b, i, v, nx) => { d_lift_expr(v, ms, ml, decls, na, tar) }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { d_lift_expr(fv, ms, ml, decls, na, tar) }
      Stmt::FieldPathAssign(pl, fpv, nx) => { d_lift_expr(fpv, ms, ml, decls, na, tar) }
      Stmt::IndexFieldAssign(b, i, fs, fl, v, nx) => { d_lift_expr(v, ms, ml, decls, na, tar) }
      Stmt::Match(sc, ah, nx) => { d_lift_expr(sc, ms, ml, decls, na, tar); d_lift_arms(ah, ms, ml, decls, na, tar) }
      Stmt::CompIf(c, th, el, nx) => { d_lift_stmts(th, ms, ml, decls, na, tar); d_lift_stmts(el, ms, ml, decls, na, tar) }
      Stmt::CompFor(vs, vl, iv, b, nx) => { d_lift_stmts(b, ms, ml, decls, na, tar) }
      Stmt::CompForRange(vs, vl, lo, hi, b, nx) => { d_lift_stmts(b, ms, ml, decls, na, tar) }
      Stmt::CompMatch(sc, ah, nx) => { d_lift_arms(ah, ms, ml, decls, na, tar) }
      _ => {}
    }
    s = d_next_stmt(s, na)
  }
}

## ---- FN-6 CAPTURE (static closures; first slice: scalar captures, single-`return` lambda body) ----
## Lift-time AST rewrite: a capturing lambda `f := fn(n){ return n + c }` (c = an enclosing LOCAL) gets
## its free vars APPENDED as trailing params AND injected as trailing args at every direct call
## `f(x)` → `f(x, c)`; lower then sees a plain multi-arg indirect call. ESCAPE: `f` appearing as an
## `Expr::Var` (a call callee is the Call's NAME span, not a Var) is a value use → reject fail-loud.
d_nalloc := fn(a : ptr(mut rt::Arena), sz : usize) -> usize {
  rem := deref(a).off % 8
  mut aligned := deref(a).off
  if rem != 0 { aligned = deref(a).off + (8 - rem) }
  deref(a).off = aligned + sz
  aligned
}
d_cap_has := fn(caps : ptr(rt::Vec), s : usize, n : usize, src : ptr(u8)) -> bool {
  mut i := 0
  mut r := false
  while i < rt::vec_len(deref(caps)) {
    pk := rt::vec_get(deref(caps), i)
    if str_at((src + pk / 1024), pk % 1024) == str_at((src + s), n) { r = true }
    i = i + 1
  }
  r
}
d_is_param := fn(s : usize, n : usize, ph : ptr(mut Param), na : ptr(mut rt::Arena), src : ptr(u8)) -> bool {
  mut p := ph
  mut r := false
  while p != 0 {
    pm := deref(param_p(p))
    if str_at((src + pm.ns), pm.nl) == str_at((src + s), n) { r = true }
    p = pm.next
  }
  r
}
## `decls` BY VALUE (3-word Vec) — `ptr()` of the in-out param destabilizes through this recursion.
d_is_topdecl := fn(s : usize, n : usize, decls : rt::Vec, src : ptr(u8)) -> bool {
  mut i := 0
  mut r := false
  while i < rt::vec_len(decls) {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if d.name_len != 0 {
      if str_at((src + d.name_start), d.name_len) == str_at((src + s), n) { r = true }
    }
    i = i + 1
  }
  r
}
## Collect the FREE VARS of expr `e` into `caps`: every `Expr::Var` whose name is NOT a lambda param
## (`ph`), NOT a lambda-body inner LOCAL (`locals` — inner `:=`/for-var names), and NOT a top-level
## decl. Recurses the scalar-expr forms + `If`.
## The struct/enum TYPE name span of a local `[cs,cl)` bound by `cap := StructLit(T,…)` / `EnumLit(T,…)`
## somewhere in the ENCLOSING fn body `head` (recurses if/while/for/loop bodies) — used to TYPE an
## aggregate capture param. 0/0 if not found / not an aggregate-literal binding (then the capture is
## treated as scalar, and a field/index access on it is rejected fail-loud by the caller).
## The type-name span of a StructLit/EnumLit value expr (0/0 otherwise). A STANDALONE fn — NOT a nested
## `match` inside `d_local_type_span`'s Assign arm, which mis-lowers under the seed (the doubly-nested-
## match gotcha: the inner arm bindings were mis-read, so the type never resolved).
d_lit_type_span := fn(v : ptr(Expr), src : ptr(u8)) -> CSpan {
  match deref(v) {
    Expr::StructLit(ss, sl, nf, fh) => { CSpan(s = ss, n = sl) }
    Expr::EnumLit(es, el, vs, vl, np, ph) => { CSpan(s = es, n = el) }
    _ => { CSpan(s = 0, n = 0) }
  }
}
d_is_agg_type_name := fn(decls : rt::Vec, src : ptr(u8), ts : usize, tl : usize) -> bool {
  mut r := false
  mut i := 0
  while i < rt::vec_len(decls) {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if (d.kind == 2 or d.kind == 3) and streq(src, d.name_start, d.name_len, ts, tl) { r = true }
    i = i + 1
  }
  r
}

d_call_ret_type_span := fn(v : ptr(Expr), decls : rt::Vec, src : ptr(u8)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  match deref(v) {
    Expr::Call(cs, cl, nargs, ah) => {
      mut i := 0
      while i < rt::vec_len(decls) {
        d := deref(decl_at(Decl, rt::vec_get(decls, i)))
        if d.kind == 1 and d.ret_tl != 0 and streq(src, d.name_start, d.name_len, cs, cl) {
          if d_is_agg_type_name(decls, src, d.ret_ts, d.ret_tl) { r = CSpan(s = d.ret_ts, n = d.ret_tl) }
        }
        i = i + 1
      }
    }
    _ => {}
  }
  r
}

## Resolve a captured var's AGGREGATE type from the ENCLOSING fn's params `eph`. A captured enclosing
## PARAM (`outer := fn(s : Rec){ f := fn(n){ … s … } }`) is NOT a body `:=` binding, so
## `d_local_type_span` (which only scans body Assigns) misses it → the capture gets an untyped WORD slot
## → the injected by-ref arg forwards the aggregate's ADDRESS as a scalar. A whole-value forward to a
## by-ref callee then happens to work, but a copy-to-local + field read (`t := s; t.a`) silently reads 0
## (the address is treated as the struct value). Resolving the param's declared type here makes
## `d_append_cap_params` give the capture a TYPED by-ref param (as a literal-bound local already gets),
## closing that silent miscompile. Returns the param's type span IF it names a struct/enum decl, else 0/0.
d_param_type_span := fn(eph : ptr(mut Param), cs : usize, cl : usize, decls : rt::Vec, src : ptr(u8)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  mut p := eph
  while p != 0 {
    pm := deref(param_p(p))
    if pm.tl != 0 and streq(src, pm.ns, pm.nl, cs, cl) {
      if d_is_agg_type_name(decls, src, pm.ts, pm.tl) { r = CSpan(s = pm.ts, n = pm.tl) }
    }
    p = pm.next
  }
  r
}
d_local_type_span := fn(head : ptr(mut Stmt), cs : usize, cl : usize, decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) -> CSpan {
  mut r := CSpan(s = 0, n = 0)
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => {
        if str_at((src + ns), nl) == str_at((src + cs), cl) {
          lt := d_lit_type_span(v, src)
          if lt.n != 0 { r = lt }
          else {
            ct := d_call_ret_type_span(v, decls, src)
            if ct.n != 0 { r = ct }
            else {
              ## The RHS is not a directly-bound struct/enum LITERAL or aggregate-returning call — fall
              ## back to the local's EXPLICIT `: T` annotation (an array `arr : [u64;3]`, or any typed local).
              ## Lets `d_capture_pass` type + inject a by-ref capture of an annotated non-scalar local instead
              ## of the fail-loud. `local_type_span` reads the `: T` span in source after the name.
              at := local_type_span(src, ns, nl)
              if at.n != 0 { r = CSpan(s = at.s, n = at.n) }
            }
          }
        }
      }
      Stmt::If(c, th, el, nx) => { rt := d_local_type_span(th, cs, cl, decls, na, src); if rt.n != 0 { r = rt } else { re := d_local_type_span(el, cs, cl, decls, na, src); if re.n != 0 { r = re } } }
      Stmt::While(c, b, nx) => { rw := d_local_type_span(b, cs, cl, decls, na, src); if rw.n != 0 { r = rw } }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { rf := d_local_type_span(b, cs, cl, decls, na, src); if rf.n != 0 { r = rf } }
      Stmt::Loop(b, nx) => { rl := d_local_type_span(b, cs, cl, decls, na, src); if rl.n != 0 { r = rl } }
      Stmt::Unchecked(b, nx) => { rl := d_local_type_span(b, cs, cl, decls, na, src); if rl.n != 0 { r = rl } }
      Stmt::AllocWith(ae, b, nx) => { rl := d_local_type_span(b, cs, cl, decls, na, src); if rl.n != 0 { r = rl } }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
  r
}
## Is `[s,n)` a CAPTURE name (a free var: not a lambda param, not a body local, not a top-level decl,
## and not a PRELUDE namespace identifier `target`/`Arch`/`verify`/`Ordering` — those are comptime
## built-ins reached via `.` (`target.arch`, `Arch.x86_64`), NOT captured enclosing values).
d_is_cap_name := fn(s : usize, n : usize, ph : ptr(mut Param), na : ptr(mut rt::Arena), decls : rt::Vec, src : ptr(u8), locals : ptr(rt::Vec)) -> bool {
  mut r := true
  if d_is_param(s, n, ph, na, src) { r = false }
  if d_cap_has(locals, s, n, src) { r = false }
  if d_is_topdecl(s, n, decls, src) { r = false }
  nm := str_at((src + s), n)
  if nm == "target" { r = false }
  if nm == "Arch" { r = false }
  if nm == "verify" { r = false }
  if nm == "Ordering" { r = false }
  r
}
## A `.field`/`[index]` access on a captured var proves the capture is a NON-SCALAR (struct/enum). If
## its type resolves (`cap := StructLit/EnumLit` in the enclosing body) it will be given a TYPED by-ref
## capture param — fine. If it does NOT resolve, an untyped-word capture param would be field-accessed
## → a silent miscompile, so set `hardreject` (the caller then rejects fail-loud).
d_flag_nonscalar_base := fn(b : ptr(Expr), ph : ptr(mut Param), na : ptr(mut rt::Arena), decls : rt::Vec, src : ptr(u8), locals : ptr(rt::Vec), body : ptr(mut Stmt), hardreject : ptr(mut bool)) {
  match deref(b) {
    Expr::Var(vs, vn) => {
      if d_is_cap_name(vs, vn, ph, na, decls, src, locals) {
        ts := d_local_type_span(body, vs, vn, decls, na, src)
        if ts.n == 0 { deref(hardreject) = true }
      }
    }
    _ => {}
  }
}
d_cap_free := fn(e : ptr(Expr), ph : ptr(mut Param), na : ptr(mut rt::Arena), decls : rt::Vec, src : ptr(u8), locals : ptr(rt::Vec), caps : ptr(rt::Vec), body : ptr(mut Stmt), hardreject : ptr(mut bool)) {
  match deref(e) {
    Expr::Var(s, n) => {
      mut skip := false
      if d_is_cap_name(s, n, ph, na, decls, src, locals) == false { skip = true }
      if d_cap_has(caps, s, n, src) { skip = true }
      if skip == false { rt::vec_push(deref(caps), s * 1024 + n) }
    }
    Expr::Bin(op, l, r) => { d_cap_free(l, ph, na, decls, src, locals, caps, body, hardreject); d_cap_free(r, ph, na, decls, src, locals, caps, body, hardreject) }
    Expr::Unchecked(inner) => { d_cap_free(inner, ph, na, decls, src, locals, caps, body, hardreject) }
    Expr::AddrOf(inner) => { d_cap_free(inner, ph, na, decls, src, locals, caps, body, hardreject) }
    Expr::Deref(inner) => { d_cap_free(inner, ph, na, decls, src, locals, caps, body, hardreject) }
    Expr::Try(inner) => { d_cap_free(inner, ph, na, decls, src, locals, caps, body, hardreject) }
    Expr::Field(b, fs, fl) => { d_flag_nonscalar_base(b, ph, na, decls, src, locals, body, hardreject); d_cap_free(b, ph, na, decls, src, locals, caps, body, hardreject) }
    Expr::Index(b, ix) => { d_flag_nonscalar_base(b, ph, na, decls, src, locals, body, hardreject); d_cap_free(b, ph, na, decls, src, locals, caps, body, hardreject); d_cap_free(ix, ph, na, decls, src, locals, caps, body, hardreject) }
    Expr::If(c, th, el) => { d_cap_free(c, ph, na, decls, src, locals, caps, body, hardreject); d_cap_free(th, ph, na, decls, src, locals, caps, body, hardreject); d_cap_free(el, ph, na, decls, src, locals, caps, body, hardreject) }
    Expr::Call(cs, cl, nargs, ah) => {
      mut g := ah
      while g != 0 {
        ga := deref(arg_p(g))
        d_cap_free(ga.e, ph, na, decls, src, locals, caps, body, hardreject)
        g = ga.next
      }
    }
    _ => {}
  }
}
## Collect the lambda body's INNER LOCAL names (`:=` binding LHS + `for` loop vars) into `locals`, so
## `d_cap_free` does not mistake them for captures. Sets `unhandled` on a binding construct this first
## slice does not fully analyze (a `match` arm's payload binds) — the caller then declines capture
## handling for that lambda (it falls back to the normal lift → sema rejects if it truly captures).
d_cap_locals := fn(head : ptr(mut Stmt), na : ptr(mut rt::Arena), locals : ptr(rt::Vec), unhandled : ptr(mut bool)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => { rt::vec_push(deref(locals), ns * 1024 + nl) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { rt::vec_push(deref(locals), fns * 1024 + fnl); d_cap_locals(b, na, locals, unhandled) }
      Stmt::If(c, th, el, nx) => { d_cap_locals(th, na, locals, unhandled); d_cap_locals(el, na, locals, unhandled) }
      Stmt::While(c, b, nx) => { d_cap_locals(b, na, locals, unhandled) }
      Stmt::Loop(b, nx) => { d_cap_locals(b, na, locals, unhandled) }
      Stmt::Unchecked(b, nx) => { d_cap_locals(b, na, locals, unhandled) }
      Stmt::AllocWith(ae, b, nx) => { d_cap_locals(b, na, locals, unhandled) }
      Stmt::Match(sc, ah, nx) => {
        ## each arm's payload binds (`E::A(x)` → x) are arm-scoped LOCALS; collect them + recurse arm bodies.
        mut arm := ah
        while arm != 0 {
          am := deref(arm_p(arm))
          mut bd := am.binds_head
          while unchecked bitcast(usize, bd) != 0 { rt::vec_push(deref(locals), bnd_ns(bd) * 1024 + bnd_nl(bd)); bd = bnd_next(bd) }
          d_cap_locals(am.body_stmts, na, locals, unhandled)
          arm = am.next
        }
      }
      Stmt::CompIf(c, th, el, nx) => { d_cap_locals(th, na, locals, unhandled); d_cap_locals(el, na, locals, unhandled) }
      Stmt::CompMatch(sc, ah, nx) => { deref(unhandled) = true }
      Stmt::CompFor(vs, vl, iv, b, nx) => { deref(unhandled) = true }
      Stmt::CompForRange(vs, vl, lo, hi, b, nx) => { deref(unhandled) = true }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}
## Collect the free vars over a lambda body's STATEMENTS (calls `d_cap_free` on each stmt's exprs).
d_cap_free_stmts := fn(head : ptr(mut Stmt), ph : ptr(mut Param), na : ptr(mut rt::Arena), decls : rt::Vec, src : ptr(u8), locals : ptr(rt::Vec), caps : ptr(rt::Vec), body : ptr(mut Stmt), hardreject : ptr(mut bool)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => { d_cap_free(v, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { d_cap_free(rv, ph, na, decls, src, locals, caps, body, hardreject) } }
      Stmt::ExprStmt(e, nx) => { d_cap_free(e, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::If(c, th, el, nx) => { d_cap_free(c, ph, na, decls, src, locals, caps, body, hardreject); d_cap_free_stmts(th, ph, na, decls, src, locals, caps, body, hardreject); d_cap_free_stmts(el, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::While(c, b, nx) => { d_cap_free(c, ph, na, decls, src, locals, caps, body, hardreject); d_cap_free_stmts(b, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { if unchecked bitcast(usize, lo) != 0 { d_cap_free(lo, ph, na, decls, src, locals, caps, body, hardreject) }; if unchecked bitcast(usize, hi) != 0 { d_cap_free(hi, ph, na, decls, src, locals, caps, body, hardreject) }; d_cap_free_stmts(b, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::Loop(b, nx) => { d_cap_free_stmts(b, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::Unchecked(b, nx) => { d_cap_free_stmts(b, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::AllocWith(ae, b, nx) => { d_cap_free_stmts(b, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::DerefAssign(p, v, nx) => { d_cap_free(p, ph, na, decls, src, locals, caps, body, hardreject); d_cap_free(v, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::IndexAssign(b, ix, v, nx) => { d_cap_free(b, ph, na, decls, src, locals, caps, body, hardreject); d_cap_free(ix, ph, na, decls, src, locals, caps, body, hardreject); d_cap_free(v, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { d_cap_free(fv, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::Match(sc, ah, nx) => {
        d_cap_free(sc, ph, na, decls, src, locals, caps, body, hardreject)
        mut arm := ah
        while arm != 0 {
          am := deref(arm_p(arm))
          d_cap_free_stmts(am.body_stmts, ph, na, decls, src, locals, caps, body, hardreject)
          if unchecked bitcast(usize, am.body) != 0 { d_cap_free(am.body, ph, na, decls, src, locals, caps, body, hardreject) }
          arm = am.next
        }
      }
      ## comptime constructs: CompIf is FOLDED (handled like `if` — a capture in the kept branch resolves
      ## against its injected param). CompFor/CompForRange/CompMatch stay `unhandled` (set in d_cap_locals)
      ## but their free vars are still collected here, so a CAPTURING one has caps > 0 → d_try_capture
      ## rejects it fail-loud (never a silent miscompile from an un-injected capture in a comptime body).
      Stmt::CompIf(c, th, el, nx) => { d_cap_free(c, ph, na, decls, src, locals, caps, body, hardreject); d_cap_free_stmts(th, ph, na, decls, src, locals, caps, body, hardreject); d_cap_free_stmts(el, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::CompForRange(vs, vl, lo, hi, b, nx) => { if unchecked bitcast(usize, lo) != 0 { d_cap_free(lo, ph, na, decls, src, locals, caps, body, hardreject) }; if unchecked bitcast(usize, hi) != 0 { d_cap_free(hi, ph, na, decls, src, locals, caps, body, hardreject) }; d_cap_free_stmts(b, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::CompFor(vs, vl, iv, b, nx) => { d_cap_free_stmts(b, ph, na, decls, src, locals, caps, body, hardreject) }
      Stmt::CompMatch(sc, ah, nx) => { d_cap_free(sc, ph, na, decls, src, locals, caps, body, hardreject) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}
## ESCAPE: does name `[s,n)` appear as an `Expr::Var` in `e`? (Call callee is a name span, not a Var.)
d_expr_uses_var := fn(e : ptr(Expr), s : usize, n : usize, na : ptr(mut rt::Arena), src : ptr(u8), found : ptr(mut bool)) {
  match deref(e) {
    Expr::Var(vs, vn) => { if str_at((src + vs), vn) == str_at((src + s), n) { deref(found) = true } }
    Expr::Bin(op, l, r) => { d_expr_uses_var(l, s, n, na, src, found); d_expr_uses_var(r, s, n, na, src, found) }
    Expr::Unchecked(inner) => { d_expr_uses_var(inner, s, n, na, src, found) }
    Expr::AddrOf(inner) => { d_expr_uses_var(inner, s, n, na, src, found) }
    Expr::Deref(inner) => { d_expr_uses_var(inner, s, n, na, src, found) }
    Expr::Try(inner) => { d_expr_uses_var(inner, s, n, na, src, found) }
    Expr::Field(b, fs, fl) => { d_expr_uses_var(b, s, n, na, src, found) }
    Expr::Index(b, ix) => { d_expr_uses_var(b, s, n, na, src, found); d_expr_uses_var(ix, s, n, na, src, found) }
    Expr::Slice(b, lo, hi) => { d_expr_uses_var(b, s, n, na, src, found); d_expr_uses_var(lo, s, n, na, src, found); d_expr_uses_var(hi, s, n, na, src, found) }
    Expr::If(c, th, el) => { d_expr_uses_var(c, s, n, na, src, found); d_expr_uses_var(th, s, n, na, src, found); d_expr_uses_var(el, s, n, na, src, found) }
    Expr::Call(cs, cl, nargs, ah) => {
      mut g := ah
      while g != 0 {
        ga := deref(arg_p(g))
        d_expr_uses_var(ga.e, s, n, na, src, found)
        g = ga.next
      }
    }
    _ => {}
  }
}
d_stmts_use_var := fn(head : ptr(mut Stmt), s : usize, n : usize, na : ptr(mut rt::Arena), src : ptr(u8), found : ptr(mut bool)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => { d_expr_uses_var(v, s, n, na, src, found) }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { d_expr_uses_var(rv, s, n, na, src, found) } }
      Stmt::ExprStmt(e, nx) => { d_expr_uses_var(e, s, n, na, src, found) }
      Stmt::If(c, th, el, nx) => { d_expr_uses_var(c, s, n, na, src, found); d_stmts_use_var(th, s, n, na, src, found); d_stmts_use_var(el, s, n, na, src, found) }
      Stmt::While(c, b, nx) => { d_expr_uses_var(c, s, n, na, src, found); d_stmts_use_var(b, s, n, na, src, found) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { if unchecked bitcast(usize, lo) != 0 { d_expr_uses_var(lo, s, n, na, src, found) }; if unchecked bitcast(usize, hi) != 0 { d_expr_uses_var(hi, s, n, na, src, found) }; d_stmts_use_var(b, s, n, na, src, found) }
      Stmt::Loop(b, nx) => { d_stmts_use_var(b, s, n, na, src, found) }
      Stmt::Unchecked(b, nx) => { d_stmts_use_var(b, s, n, na, src, found) }
      Stmt::AllocWith(ae, b, nx) => { d_stmts_use_var(b, s, n, na, src, found) }
      Stmt::DerefAssign(p, v, nx) => { d_expr_uses_var(p, s, n, na, src, found); d_expr_uses_var(v, s, n, na, src, found) }
      Stmt::IndexAssign(b, ix, v, nx) => { d_expr_uses_var(b, s, n, na, src, found); d_expr_uses_var(ix, s, n, na, src, found); d_expr_uses_var(v, s, n, na, src, found) }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { d_expr_uses_var(fv, s, n, na, src, found) }
      Stmt::FieldPathAssign(pl, fpv, nx) => { d_expr_uses_var(fpv, s, n, na, src, found) }
      Stmt::IndexFieldAssign(b, ix, fs, fl, v, nx) => { d_expr_uses_var(v, s, n, na, src, found) }
      Stmt::Match(sc, ah, nx) => { d_expr_uses_var(sc, s, n, na, src, found) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}
## CALL REWRITE — append a trailing `Var(cap)` Arg per capture to every direct call `f(...)` in `e`.
d_expr_rw_calls := fn(e : ptr(Expr), fs : usize, fl : usize, caps : ptr(rt::Vec), na : ptr(mut rt::Arena), src : ptr(u8)) {
  match deref(e) {
    Expr::Bin(op, l, r) => { d_expr_rw_calls(l, fs, fl, caps, na, src); d_expr_rw_calls(r, fs, fl, caps, na, src) }
    Expr::Unchecked(inner) => { d_expr_rw_calls(inner, fs, fl, caps, na, src) }
    Expr::AddrOf(inner) => { d_expr_rw_calls(inner, fs, fl, caps, na, src) }
    Expr::Deref(inner) => { d_expr_rw_calls(inner, fs, fl, caps, na, src) }
    Expr::Try(inner) => { d_expr_rw_calls(inner, fs, fl, caps, na, src) }
    Expr::Field(b, ffs, ffl) => { d_expr_rw_calls(b, fs, fl, caps, na, src) }
    Expr::Index(b, ix) => { d_expr_rw_calls(b, fs, fl, caps, na, src); d_expr_rw_calls(ix, fs, fl, caps, na, src) }
    Expr::If(c, th, el) => { d_expr_rw_calls(c, fs, fl, caps, na, src); d_expr_rw_calls(th, fs, fl, caps, na, src); d_expr_rw_calls(el, fs, fl, caps, na, src) }
    Expr::Call(cs, cl, nargs, ah) => {
      mut g := ah
      while g != 0 {
        ga := deref(arg_p(g))
        d_expr_rw_calls(ga.e, fs, fl, caps, na, src)
        g = ga.next
      }
      if str_at((src + cs), cl) == str_at((src + fs), fl) {
        ncaps := rt::vec_len(deref(caps))
        ## build a chain of `Var(cap)` Args via the PARSER's node builders (`newnode`/`gnode`) + linker
        ## (`set_arg_next`) — the stores must run in the parser module (they mis-lower in the driver,
        ## writing a pointer instead of copying); the Call-node OVERWRITE below is a local-enum store via
        ## an inline bitcast, which DOES work in the driver (the Lambda→FnRef rewrite uses the same shape).
        mut chain_head := 0
        mut chain_tail := 0
        mut k := 0
        while k < ncaps {
          pk := rt::vec_get(deref(caps), k)
          vptr := parser::newnode(na, Expr.Var(pk / 1024, pk % 1024))
          argh := parser::gnode(na, Arg(e = vptr, next = 0))
          if chain_head == 0 { chain_head = argh } else { parser::set_arg_next(na, chain_tail, argh) }
          chain_tail = argh
          k = k + 1
        }
        if ah == 0 {
          nc := Expr.Call(cs, cl, nargs + ncaps, chain_head)
          deref(unchecked bitcast(ptr(mut Expr), e)) = nc
        } else {
          mut cur := ah
          while deref(arg_p(cur)).next != 0 { cur = deref(arg_p(cur)).next }
          parser::set_arg_next(na, cur, chain_head)
          nc := Expr.Call(cs, cl, nargs + ncaps, ah)
          deref(unchecked bitcast(ptr(mut Expr), e)) = nc
        }
      }
    }
    _ => {}
  }
}
d_stmts_rw_calls := fn(head : ptr(mut Stmt), fs : usize, fl : usize, caps : ptr(rt::Vec), na : ptr(mut rt::Arena), src : ptr(u8)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => { d_expr_rw_calls(v, fs, fl, caps, na, src) }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { d_expr_rw_calls(rv, fs, fl, caps, na, src) } }
      Stmt::ExprStmt(e, nx) => { d_expr_rw_calls(e, fs, fl, caps, na, src) }
      Stmt::If(c, th, el, nx) => { d_expr_rw_calls(c, fs, fl, caps, na, src); d_stmts_rw_calls(th, fs, fl, caps, na, src); d_stmts_rw_calls(el, fs, fl, caps, na, src) }
      Stmt::While(c, b, nx) => { d_expr_rw_calls(c, fs, fl, caps, na, src); d_stmts_rw_calls(b, fs, fl, caps, na, src) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { if unchecked bitcast(usize, lo) != 0 { d_expr_rw_calls(lo, fs, fl, caps, na, src) }; if unchecked bitcast(usize, hi) != 0 { d_expr_rw_calls(hi, fs, fl, caps, na, src) }; d_stmts_rw_calls(b, fs, fl, caps, na, src) }
      Stmt::Loop(b, nx) => { d_stmts_rw_calls(b, fs, fl, caps, na, src) }
      Stmt::Unchecked(b, nx) => { d_stmts_rw_calls(b, fs, fl, caps, na, src) }
      Stmt::AllocWith(ae, b, nx) => { d_stmts_rw_calls(b, fs, fl, caps, na, src) }
      Stmt::DerefAssign(p, v, nx) => { d_expr_rw_calls(p, fs, fl, caps, na, src); d_expr_rw_calls(v, fs, fl, caps, na, src) }
      Stmt::IndexAssign(b, ix, v, nx) => { d_expr_rw_calls(b, fs, fl, caps, na, src); d_expr_rw_calls(ix, fs, fl, caps, na, src); d_expr_rw_calls(v, fs, fl, caps, na, src) }
      Stmt::FieldAssign(bns, bnl, ffs, ffl, fv, nx) => { d_expr_rw_calls(fv, fs, fl, caps, na, src) }
      Stmt::FieldPathAssign(pl, fpv, nx) => { d_expr_rw_calls(fpv, fs, fl, caps, na, src) }
      Stmt::IndexFieldAssign(b, ix, ffs, ffl, v, nx) => { d_expr_rw_calls(v, fs, fl, caps, na, src) }
      Stmt::Match(sc, ah, nx) => { d_expr_rw_calls(sc, fs, fl, caps, na, src) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}
## ---- FN-6 §6.2 — capturing closure through a LOOP / NON-FORWARDING higher-order fn (HOF) ----
## When a capturing closure `f` escapes as a VALUE argument to a call `H(a, f, b)` where `H` is a
## user fn (e.g. `twice(g, x){ g(x) + g(x) }`, `map`, `filter`), the forwarding-inline can't help (H
## keeps `g` and calls it inside a loop / more than once). §6.2: generic code taking a callable
## MONOMORPHIZES over the concrete closure type — so specialize `H` to THIS closure: append f's
## captures as trailing params of `H`, thread them into every `g(cargs)` call inside `H`'s body
## (`g(cargs) -> g(cargs, <caps>)`), and append the captures at the `H(f, …)` call site (`H(f, a, b)
## -> H(f, a, b, <caps>)`). `g` stays a code-pointer PARAM; `g(cargs, caps)` is the same indirect
## call-through-slot as a non-capturing fn-value HOF, and f's lifted fn already takes `(…, caps)` from
## the ordinary capture pass — so the captures reach the call VISIBLY, no `dyn`/box (I3).
##
## FIRST INCREMENT — in-place specialization of a NON-GENERIC `H` that is called EXACTLY ONCE in the
## whole program, with f used ONLY as that one HOF argument. The single-call-site guard makes the
## in-place mutation of `H` safe (a second call would see the widened arity); anything outside this
## shape returns false → the caller keeps the fail-loud reject (never a silent miscompile). A generic
## HOF (`map(T, U, …)`) and multi-call-site specialization (a per-closure CLONE of `H`) are follow-ups.
## 1 if expr `e` is exactly `Var([fs,fl))`, else 0 — a SINGLE-match helper (kept standalone so the
## call-argument test below never binds a struct-returning-call local inside a match-arm while, a shape
## the frozen seed mis-sema's / crashes on; mirrors `d_array_lit`'s single-match style).
d_is_var_named := fn(e : ptr(Expr), fs : usize, fl : usize, src : ptr(u8)) -> usize {
  mut r := 0
  match deref(e) {
    Expr::Var(vs, vn) => { if str_at((src + vs), vn) == str_at((src + fs), fl) { r = 1 } }
    _ => {}
  }
  r
}
## Scan expr `e` for value-uses of the closure name `[fs,fl)`. SCALAR out-params (no struct ptr): `nt`
## counts TOTAL `Expr::Var(f)` uses; `nf` counts uses that are a DIRECT ARGUMENT of a `Call`, recording
## that call's callee span (`hs`/`hl`) + the f-arg position (`ap`). Mirrors `d_expr_uses_var`'s form
## coverage so `nt` stays consistent with the escape detector.
d_scan_hof_expr := fn(e : ptr(Expr), fs : usize, fl : usize, na : ptr(mut rt::Arena), src : ptr(u8), nt : ptr(mut usize), nf : ptr(mut usize), hs : ptr(mut usize), hl : ptr(mut usize), ap : ptr(mut usize)) {
  match deref(e) {
    Expr::Var(vs, vn) => { if str_at((src + vs), vn) == str_at((src + fs), fl) { n0 := deref(nt); deref(nt) = n0 + 1 } }
    Expr::Bin(op, l, r) => { d_scan_hof_expr(l, fs, fl, na, src, nt, nf, hs, hl, ap); d_scan_hof_expr(r, fs, fl, na, src, nt, nf, hs, hl, ap) }
    Expr::Unchecked(inner) => { d_scan_hof_expr(inner, fs, fl, na, src, nt, nf, hs, hl, ap) }
    Expr::AddrOf(inner) => { d_scan_hof_expr(inner, fs, fl, na, src, nt, nf, hs, hl, ap) }
    Expr::Deref(inner) => { d_scan_hof_expr(inner, fs, fl, na, src, nt, nf, hs, hl, ap) }
    Expr::Try(inner) => { d_scan_hof_expr(inner, fs, fl, na, src, nt, nf, hs, hl, ap) }
    Expr::Field(b, ffs, ffl) => { d_scan_hof_expr(b, fs, fl, na, src, nt, nf, hs, hl, ap) }
    Expr::Index(b, ix) => { d_scan_hof_expr(b, fs, fl, na, src, nt, nf, hs, hl, ap); d_scan_hof_expr(ix, fs, fl, na, src, nt, nf, hs, hl, ap) }
    Expr::Slice(b, lo, hi) => { d_scan_hof_expr(b, fs, fl, na, src, nt, nf, hs, hl, ap); d_scan_hof_expr(lo, fs, fl, na, src, nt, nf, hs, hl, ap); d_scan_hof_expr(hi, fs, fl, na, src, nt, nf, hs, hl, ap) }
    Expr::If(c, th, el) => { d_scan_hof_expr(c, fs, fl, na, src, nt, nf, hs, hl, ap); d_scan_hof_expr(th, fs, fl, na, src, nt, nf, hs, hl, ap); d_scan_hof_expr(el, fs, fl, na, src, nt, nf, hs, hl, ap) }
    Expr::Call(cs, cl, nargs, ah) => {
      mut g := ah
      mut idx := 0
      while g != 0 {
        ga := deref(arg_p(g))
        if d_is_var_named(ga.e, fs, fl, src) == 1 { deref(hs) = cs; deref(hl) = cl; deref(ap) = idx; f0 := deref(nf); deref(nf) = f0 + 1 }
        d_scan_hof_expr(ga.e, fs, fl, na, src, nt, nf, hs, hl, ap)
        g = ga.next
        idx = idx + 1
      }
    }
    _ => {}
  }
}
d_scan_hof_stmts := fn(head : ptr(mut Stmt), fs : usize, fl : usize, na : ptr(mut rt::Arena), src : ptr(u8), nt : ptr(mut usize), nf : ptr(mut usize), hs : ptr(mut usize), hl : ptr(mut usize), ap : ptr(mut usize)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => { d_scan_hof_expr(v, fs, fl, na, src, nt, nf, hs, hl, ap) }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { d_scan_hof_expr(rv, fs, fl, na, src, nt, nf, hs, hl, ap) } }
      Stmt::ExprStmt(e, nx) => { d_scan_hof_expr(e, fs, fl, na, src, nt, nf, hs, hl, ap) }
      Stmt::If(c, th, el, nx) => { d_scan_hof_expr(c, fs, fl, na, src, nt, nf, hs, hl, ap); d_scan_hof_stmts(th, fs, fl, na, src, nt, nf, hs, hl, ap); d_scan_hof_stmts(el, fs, fl, na, src, nt, nf, hs, hl, ap) }
      Stmt::While(c, b, nx) => { d_scan_hof_expr(c, fs, fl, na, src, nt, nf, hs, hl, ap); d_scan_hof_stmts(b, fs, fl, na, src, nt, nf, hs, hl, ap) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { if unchecked bitcast(usize, lo) != 0 { d_scan_hof_expr(lo, fs, fl, na, src, nt, nf, hs, hl, ap) }; if unchecked bitcast(usize, hi) != 0 { d_scan_hof_expr(hi, fs, fl, na, src, nt, nf, hs, hl, ap) }; d_scan_hof_stmts(b, fs, fl, na, src, nt, nf, hs, hl, ap) }
      Stmt::Loop(b, nx) => { d_scan_hof_stmts(b, fs, fl, na, src, nt, nf, hs, hl, ap) }
      Stmt::Unchecked(b, nx) => { d_scan_hof_stmts(b, fs, fl, na, src, nt, nf, hs, hl, ap) }
      Stmt::AllocWith(ae, b, nx) => { d_scan_hof_stmts(b, fs, fl, na, src, nt, nf, hs, hl, ap) }
      Stmt::DerefAssign(p, v, nx) => { d_scan_hof_expr(p, fs, fl, na, src, nt, nf, hs, hl, ap); d_scan_hof_expr(v, fs, fl, na, src, nt, nf, hs, hl, ap) }
      Stmt::IndexAssign(b, ix, v, nx) => { d_scan_hof_expr(b, fs, fl, na, src, nt, nf, hs, hl, ap); d_scan_hof_expr(ix, fs, fl, na, src, nt, nf, hs, hl, ap); d_scan_hof_expr(v, fs, fl, na, src, nt, nf, hs, hl, ap) }
      Stmt::FieldAssign(bns, bnl, ffs, ffl, fv, nx) => { d_scan_hof_expr(fv, fs, fl, na, src, nt, nf, hs, hl, ap) }
      Stmt::FieldPathAssign(pl, fpv, nx) => { d_scan_hof_expr(fpv, fs, fl, na, src, nt, nf, hs, hl, ap) }
      Stmt::IndexFieldAssign(b, ix, ffs, ffl, v, nx) => { d_scan_hof_expr(v, fs, fl, na, src, nt, nf, hs, hl, ap) }
      Stmt::Match(sc, ah, nx) => { d_scan_hof_expr(sc, fs, fl, na, src, nt, nf, hs, hl, ap) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}
## Count `Call` occurrences whose callee is `[cs,cl)` in expr `e` (guards the single-call-site rewrite).
d_count_calls_expr := fn(e : ptr(Expr), cs : usize, cl : usize, na : ptr(mut rt::Arena), src : ptr(u8), cnt : ptr(mut usize)) {
  match deref(e) {
    Expr::Bin(op, l, r) => { d_count_calls_expr(l, cs, cl, na, src, cnt); d_count_calls_expr(r, cs, cl, na, src, cnt) }
    Expr::Unchecked(inner) => { d_count_calls_expr(inner, cs, cl, na, src, cnt) }
    Expr::AddrOf(inner) => { d_count_calls_expr(inner, cs, cl, na, src, cnt) }
    Expr::Deref(inner) => { d_count_calls_expr(inner, cs, cl, na, src, cnt) }
    Expr::Try(inner) => { d_count_calls_expr(inner, cs, cl, na, src, cnt) }
    Expr::Field(b, ffs, ffl) => { d_count_calls_expr(b, cs, cl, na, src, cnt) }
    Expr::Index(b, ix) => { d_count_calls_expr(b, cs, cl, na, src, cnt); d_count_calls_expr(ix, cs, cl, na, src, cnt) }
    Expr::Slice(b, lo, hi) => { d_count_calls_expr(b, cs, cl, na, src, cnt); d_count_calls_expr(lo, cs, cl, na, src, cnt); d_count_calls_expr(hi, cs, cl, na, src, cnt) }
    Expr::If(c, th, el) => { d_count_calls_expr(c, cs, cl, na, src, cnt); d_count_calls_expr(th, cs, cl, na, src, cnt); d_count_calls_expr(el, cs, cl, na, src, cnt) }
    Expr::Call(ecs, ecl, nargs, ah) => {
      mut g := ah
      if str_at((src + ecs), ecl) == str_at((src + cs), cl) { c0 := deref(cnt); deref(cnt) = c0 + 1 }
      while g != 0 {
        ga := deref(arg_p(g))
        d_count_calls_expr(ga.e, cs, cl, na, src, cnt)
        g = ga.next
      }
    }
    _ => {}
  }
}
d_count_calls_stmts := fn(head : ptr(mut Stmt), cs : usize, cl : usize, na : ptr(mut rt::Arena), src : ptr(u8), cnt : ptr(mut usize)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => { d_count_calls_expr(v, cs, cl, na, src, cnt) }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { d_count_calls_expr(rv, cs, cl, na, src, cnt) } }
      Stmt::ExprStmt(e, nx) => { d_count_calls_expr(e, cs, cl, na, src, cnt) }
      Stmt::If(c, th, el, nx) => { d_count_calls_expr(c, cs, cl, na, src, cnt); d_count_calls_stmts(th, cs, cl, na, src, cnt); d_count_calls_stmts(el, cs, cl, na, src, cnt) }
      Stmt::While(c, b, nx) => { d_count_calls_expr(c, cs, cl, na, src, cnt); d_count_calls_stmts(b, cs, cl, na, src, cnt) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { if unchecked bitcast(usize, lo) != 0 { d_count_calls_expr(lo, cs, cl, na, src, cnt) }; if unchecked bitcast(usize, hi) != 0 { d_count_calls_expr(hi, cs, cl, na, src, cnt) }; d_count_calls_stmts(b, cs, cl, na, src, cnt) }
      Stmt::Loop(b, nx) => { d_count_calls_stmts(b, cs, cl, na, src, cnt) }
      Stmt::Unchecked(b, nx) => { d_count_calls_stmts(b, cs, cl, na, src, cnt) }
      Stmt::AllocWith(ae, b, nx) => { d_count_calls_stmts(b, cs, cl, na, src, cnt) }
      Stmt::DerefAssign(p, v, nx) => { d_count_calls_expr(p, cs, cl, na, src, cnt); d_count_calls_expr(v, cs, cl, na, src, cnt) }
      Stmt::IndexAssign(b, ix, v, nx) => { d_count_calls_expr(b, cs, cl, na, src, cnt); d_count_calls_expr(ix, cs, cl, na, src, cnt); d_count_calls_expr(v, cs, cl, na, src, cnt) }
      Stmt::FieldAssign(bns, bnl, ffs, ffl, fv, nx) => { d_count_calls_expr(fv, cs, cl, na, src, cnt) }
      Stmt::FieldPathAssign(pl, fpv, nx) => { d_count_calls_expr(fpv, cs, cl, na, src, cnt) }
      Stmt::IndexFieldAssign(b, ix, ffs, ffl, v, nx) => { d_count_calls_expr(v, cs, cl, na, src, cnt) }
      Stmt::Match(sc, ah, nx) => { d_count_calls_expr(sc, cs, cl, na, src, cnt) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}
d_count_prog_calls := fn(cs : usize, cl : usize, decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) -> usize {
  mut cnt := 0
  mut i := 0
  while i < rt::vec_len(decls) {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if d.is_fn {
      d_count_calls_stmts(d.body_stmts, cs, cl, na, src, ptr(cnt))
      if unchecked bitcast(usize, d.value) != 0 { d_count_calls_expr(d.value, cs, cl, na, src, ptr(cnt)) }
    }
    i = i + 1
  }
  cnt
}
## Byte offset (0-based) of the LAST `::` separator within span `[cs, cs+cl)`, else -1 (unqualified).
## Mirrors lower::colon_pos — splits `a::b::c` into module head `a::b` + tail fn `c`.
d_colon_pos := fn(src : ptr(u8), cs : usize, cl : usize) -> i64 {
  mut res := -1
  mut i := 0
  while i + 1 < cl {
    if str_at((src + cs + i), 1) == ":" and str_at((src + cs + i + 1), 1) == ":" { res = i64(i); i = i + 2 } else { i = i + 1 }
  }
  res
}
## Compare a callee's module HEAD `[bs,bl)` (source form `alloc::vec`) against a decl's MANGLED
## module span `[as_,al)` (`alloc__vec`), treating `:` and `_` as the SAME separator char. Mirrors
## lower::mod_seg_eq. Real segment names use only alnum + `_`; the `:`↔`_` loosening fires only at a
## qualified-source `::`, so a plain bare-name match is unaffected (this helper isn't used for that).
d_mod_seg_eq := fn(src : ptr(u8), as_ : usize, al : usize, bs : usize, bl : usize) -> bool {
  if al != bl { return false }
  mut ok := true
  mut i := 0
  while i < al {
    ca := str_at((src + as_ + i), 1)
    cb := str_at((src + bs + i), 1)
    if ca != cb {
      sepa := ca == ":" or ca == "_"
      sepb := cb == ":" or cb == "_"
      if not (sepa and sepb) { ok = false }
    }
    i = i + 1
  }
  ok
}

## TOOL-6 — materialize the source path for each contiguous declaration-module range in the exact
## order consumed by `lower::module_decl_ranges`. `pv` contains the full front-end list (including the
## anonymous package root and any driver-added ambient file); matching the declaration's module-name
## span against `name_start/name_len` therefore also covers synthetic manifest declarations, which are
## appended after the ordinary source declarations and would otherwise become `<unmapped-module>`.
d_emission_paths := fn(decls : rt::Vec, pv : rt::Vec, name_start : rt::Vec, name_len : rt::Vec, src : ptr(u8), in out tar : rt::Arena) -> str {
  cnt := rt::vec_len(decls)
  pcount := rt::vec_len(pv)
  mut out := rt::strbuf(tar, 16777216)
  mut i := 0
  while i < cnt {
    d := deref(decl_get(ptr(decls), i))
    ms := d.mod_start
    ml := d.mod_len
    mut j := i + 1
    mut go := true
    while go {
      mut same := false
      if j < cnt {
        dj := deref(decl_get(ptr(decls), j))
        if dj.mod_start == ms and dj.mod_len == ml { same = true }
      }
      if same { j += 1 } else { go = false }
    }
    mut path_i := pcount
    mut k := 0
    while k < pcount and path_i == pcount {
      ns := rt::vec_get(name_start, k)
      nl := rt::vec_get(name_len, k)
      if d_mod_seg_eq(src, ms, ml, ns, nl) { path_i = k }
      k += 1
    }
    if path_i < pcount {
      p := rt::svec_str_get(pv, path_i)
      kpath := rt::push_str(out, p)
    } else {
      kun := rt::push_str(out, "<unmapped-module>")
    }
    knl := rt::push_byte(out, 10)
    i = j
  }
  return str_at(out.data, out.len)
}

## Decl index+1 of a user fn matching callee span `[cs,cl)`, else 0. A BARE callee (`twice`) matches
## by whole name (byte-identical to the former form — fixpoint-safe). A QUALIFIED callee
## (`alloc::vec::map`) splits at the LAST `::` into module head `alloc::vec` + tail `map`, matching a
## decl whose NAME == tail AND whose (mangled) module == the head (segment-aware) — so the right one
## of several same-tail-name generics (`alloc::vec::map` vs `result::map`) is resolved. Mirrors the
## lowerer's qualified-callee resolution (colon_pos + callee_name_span + mod_head_matches).
d_find_fn_decl := fn(cs : usize, cl : usize, decls : rt::Vec, src : ptr(u8)) -> usize {
  mut r := 0
  mut i := 0
  cp := d_colon_pos(src, cs, cl)
  if cp >= 0 {
    hl := usize(cp)                  ## module-head length
    ts := cs + hl + 2                ## tail fn-name span (skip `::`)
    tl := cl - hl - 2
    while i < rt::vec_len(decls) {
      d := deref(decl_at(Decl, rt::vec_get(decls, i)))
      if d.is_fn { if d.name_len != 0 {
        if str_at((src + d.name_start), d.name_len) == str_at((src + ts), tl) {
          if d_mod_seg_eq(src, d.mod_start, d.mod_len, cs, hl) { r = i + 1 } } } }
      i = i + 1
    }
    return r
  }
  while i < rt::vec_len(decls) {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if d.is_fn { if d.name_len != 0 {
      if str_at((src + d.name_start), d.name_len) == str_at((src + cs), cl) { r = i + 1 } } }
    i = i + 1
  }
  r
}
## CALL-SITE RENAME+APPEND — the SURGICAL counterpart of `d_expr_rw_calls` for the MULTI-call-site
## clone form: rewrite ONLY the ONE call `H(…, f, …)` whose callee is `[hs,hl)` AND that carries the
## closure `f` (`Var([fs,fl))`) as an argument → `<clone>(…, f, …, <caps>)` — renaming the callee to
## the clone's synthesized name span `[ns,nl)` and appending the captures. Other calls to `H` (a
## non-capturing site sharing the SAME generic `H`) are left UNTOUCHED. `nf == 1` (below) guarantees
## exactly one such call, so no ambiguity.
d_expr_rw_hof_site := fn(e : ptr(Expr), hs : usize, hl : usize, fs : usize, fl : usize, ns : usize, nl : usize, caps : ptr(rt::Vec), na : ptr(mut rt::Arena), src : ptr(u8)) {
  match deref(e) {
    Expr::Bin(op, l, r) => { d_expr_rw_hof_site(l, hs, hl, fs, fl, ns, nl, caps, na, src); d_expr_rw_hof_site(r, hs, hl, fs, fl, ns, nl, caps, na, src) }
    Expr::Unchecked(inner) => { d_expr_rw_hof_site(inner, hs, hl, fs, fl, ns, nl, caps, na, src) }
    Expr::AddrOf(inner) => { d_expr_rw_hof_site(inner, hs, hl, fs, fl, ns, nl, caps, na, src) }
    Expr::Deref(inner) => { d_expr_rw_hof_site(inner, hs, hl, fs, fl, ns, nl, caps, na, src) }
    Expr::Try(inner) => { d_expr_rw_hof_site(inner, hs, hl, fs, fl, ns, nl, caps, na, src) }
    Expr::Field(b, ffs, ffl) => { d_expr_rw_hof_site(b, hs, hl, fs, fl, ns, nl, caps, na, src) }
    Expr::Index(b, ix) => { d_expr_rw_hof_site(b, hs, hl, fs, fl, ns, nl, caps, na, src); d_expr_rw_hof_site(ix, hs, hl, fs, fl, ns, nl, caps, na, src) }
    Expr::If(c, th, el) => { d_expr_rw_hof_site(c, hs, hl, fs, fl, ns, nl, caps, na, src); d_expr_rw_hof_site(th, hs, hl, fs, fl, ns, nl, caps, na, src); d_expr_rw_hof_site(el, hs, hl, fs, fl, ns, nl, caps, na, src) }
    Expr::Call(cs, cl, nargs, ah) => {
      mut g := ah
      while g != 0 {
        ga := deref(arg_p(g))
        d_expr_rw_hof_site(ga.e, hs, hl, fs, fl, ns, nl, caps, na, src)
        g = ga.next
      }
      if str_at((src + cs), cl) == str_at((src + hs), hl) {
        mut hasf := false
        mut g2 := ah
        while g2 != 0 { ga := deref(arg_p(g2)); if d_is_var_named(ga.e, fs, fl, src) == 1 { hasf = true }; g2 = deref(arg_p(g2)).next }
        if hasf {
          ncaps := rt::vec_len(deref(caps))
          mut chain_head := 0
          mut chain_tail := 0
          mut k := 0
          while k < ncaps {
            pk := rt::vec_get(deref(caps), k)
            vptr := parser::newnode(na, Expr.Var(pk / 1024, pk % 1024))
            argh := parser::gnode(na, Arg(e = vptr, next = 0))
            if chain_head == 0 { chain_head = argh } else { parser::set_arg_next(na, chain_tail, argh) }
            chain_tail = argh
            k = k + 1
          }
          if ah == 0 {
            nc := Expr.Call(ns, nl, nargs + ncaps, chain_head)
            deref(unchecked bitcast(ptr(mut Expr), e)) = nc
          } else {
            mut cur := ah
            while deref(arg_p(cur)).next != 0 { cur = deref(arg_p(cur)).next }
            parser::set_arg_next(na, cur, chain_head)
            nc := Expr.Call(ns, nl, nargs + ncaps, ah)
            deref(unchecked bitcast(ptr(mut Expr), e)) = nc
          }
        }
      }
    }
    _ => {}
  }
}
d_stmts_rw_hof_site := fn(head : ptr(mut Stmt), hs : usize, hl : usize, fs : usize, fl : usize, ns : usize, nl : usize, caps : ptr(rt::Vec), na : ptr(mut rt::Arena), src : ptr(u8)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(vns, vnl, v, nx) => { d_expr_rw_hof_site(v, hs, hl, fs, fl, ns, nl, caps, na, src) }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { d_expr_rw_hof_site(rv, hs, hl, fs, fl, ns, nl, caps, na, src) } }
      Stmt::ExprStmt(e, nx) => { d_expr_rw_hof_site(e, hs, hl, fs, fl, ns, nl, caps, na, src) }
      Stmt::If(c, th, el, nx) => { d_expr_rw_hof_site(c, hs, hl, fs, fl, ns, nl, caps, na, src); d_stmts_rw_hof_site(th, hs, hl, fs, fl, ns, nl, caps, na, src); d_stmts_rw_hof_site(el, hs, hl, fs, fl, ns, nl, caps, na, src) }
      Stmt::While(c, b, nx) => { d_expr_rw_hof_site(c, hs, hl, fs, fl, ns, nl, caps, na, src); d_stmts_rw_hof_site(b, hs, hl, fs, fl, ns, nl, caps, na, src) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { if unchecked bitcast(usize, lo) != 0 { d_expr_rw_hof_site(lo, hs, hl, fs, fl, ns, nl, caps, na, src) }; if unchecked bitcast(usize, hi) != 0 { d_expr_rw_hof_site(hi, hs, hl, fs, fl, ns, nl, caps, na, src) }; d_stmts_rw_hof_site(b, hs, hl, fs, fl, ns, nl, caps, na, src) }
      Stmt::Loop(b, nx) => { d_stmts_rw_hof_site(b, hs, hl, fs, fl, ns, nl, caps, na, src) }
      Stmt::Unchecked(b, nx) => { d_stmts_rw_hof_site(b, hs, hl, fs, fl, ns, nl, caps, na, src) }
      Stmt::AllocWith(ae, b, nx) => { d_stmts_rw_hof_site(b, hs, hl, fs, fl, ns, nl, caps, na, src) }
      Stmt::DerefAssign(p, v, nx) => { d_expr_rw_hof_site(p, hs, hl, fs, fl, ns, nl, caps, na, src); d_expr_rw_hof_site(v, hs, hl, fs, fl, ns, nl, caps, na, src) }
      Stmt::IndexAssign(b, ix, v, nx) => { d_expr_rw_hof_site(b, hs, hl, fs, fl, ns, nl, caps, na, src); d_expr_rw_hof_site(ix, hs, hl, fs, fl, ns, nl, caps, na, src); d_expr_rw_hof_site(v, hs, hl, fs, fl, ns, nl, caps, na, src) }
      Stmt::FieldAssign(bns, bnl, ffs, ffl, fv, nx) => { d_expr_rw_hof_site(fv, hs, hl, fs, fl, ns, nl, caps, na, src) }
      Stmt::FieldPathAssign(pl, fpv, nx) => { d_expr_rw_hof_site(fpv, hs, hl, fs, fl, ns, nl, caps, na, src) }
      Stmt::IndexFieldAssign(b, ix, ffs, ffl, v, nx) => { d_expr_rw_hof_site(v, hs, hl, fs, fl, ns, nl, caps, na, src) }
      Stmt::Match(sc, ah, nx) => { d_expr_rw_hof_site(sc, hs, hl, fs, fl, ns, nl, caps, na, src) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}
## Attempt §6.2 HOF specialization for a capturing closure `[fs,fl)` (fnpos = its `fn` src offset =
## lifted-fn label id; captures in `caps`) that escapes as an argument to a call recorded by the scan
## (`nf` HOF-arg uses, `nt` total value-uses, callee span `hs`/`hl`, arg position `ap`). `body` = the
## DEFINING fn's body (for capture-type resolution). Returns true on success (a fresh specialized CLONE
## is appended + the ONE capturing call site rewritten); false leaves everything untouched (caller
## rejects fail-loud).
##
## PER-CLOSURE CLONE (generalizes the earlier in-place single-call-site form): rather than mutate `H`
## in place — which would break OTHER call sites of the same `H` (a non-capturing site, or a different
## closure) — deep-clone `H`'s params + body + trailing value into fresh nodes, specialize the CLONE
## (append f's captures as trailing params, thread `g(cargs) -> g(cargs,<caps>)`), append the clone as
## a NEW decl `__hoflam<fnpos>`, and rename ONLY the capturing call site to it. The original `H` stays
## intact for its other sites, so MULTI-call-site + a generic loop HOF (map/fold shape) now work. A
## GENERIC clone keeps `is_generic` + its leading `T : type` params, so the lowerer still MONOMORPHIZES
## it over the concrete type-args (the appended captures are ordinary trailing VALUE params after the
## value params; the type-args stay positional at the widened call site, arities aligned).
d_hof_specialize := fn(nf : usize, nt : usize, hs : usize, hl : usize, ap : usize, fs : usize, fl : usize, fnpos : usize, body : ptr(mut Stmt), fn_val : ptr(Expr), caps : ptr(rt::Vec), in out decls : rt::Vec, na : ptr(mut rt::Arena), eph : ptr(mut Param), src : ptr(u8)) -> bool {
  mut ok := true
  if nf != 1 { ok = false }        ## exactly one HOF call carries f
  if nt != 1 { ok = false }        ## f is used ONLY as that one argument
  mut di1 := 0
  if ok { di1 = d_find_fn_decl(hs, hl, decls, src) }
  if di1 == 0 { ok = false }
  mut gs := 0
  mut gl := 0
  if ok {
    gsp := d_param_name_at(decls, di1 - 1, ap, na)
    gs = gsp.s
    gl = gsp.n
  }
  if gl == 0 { ok = false }
  if ok {
    hd := deref(decl_at(Decl, rt::vec_get(decls, di1 - 1)))
    ncaps := rt::vec_len(deref(caps))
    ## deep-clone H's params + body + trailing value into FRESH nodes (the shared H decl is untouched).
    mut cok := true
    cph := parser::clone_params(na, hd.params_head, ptr(cok))
    cbody := parser::clone_stmts(na, hd.body_stmts, ptr(cok))
    mut cval := unchecked bitcast(ptr(Expr), 0)
    if unchecked bitcast(usize, hd.value) != 0 { cval = parser::clone_expr(na, hd.value, ptr(cok)) }
    if cok == false { ok = false }
    if ok {
      ## 0) RENUMBER the clone body's string-literal labels by a large per-clone base (unique, far
      ## above any real label) — the deep clone copied each `StrLit`'s label VERBATIM, so without this
      ## the original H and the clone would both emit `.Lstr<ix>` → a duplicate-symbol assembler error
      ## (hit by `alloc::vec::map`'s `.expect("Vec::map: out of memory")`). base = (fnpos+1)*1000000 is
      ## unique per closure (`fnpos` = the closure's source offset) and dwarfs any real label index.
      slbase := (fnpos + 1) * 1000000
      parser::renum_str_stmts(na, cbody, slbase)
      if unchecked bitcast(usize, cval) != 0 { parser::renum_str_expr(na, cval, slbase) }
      ## 1) append f's captures as trailing params of the CLONE; `g` keeps its slot.
      newph := d_append_cap_params(cph, caps, decls, na, body, eph, src)
      ## 2) thread the caps into every `g(cargs)` call inside the CLONE body/value → `g(cargs, <caps>)`.
      d_stmts_rw_calls(cbody, gs, gl, caps, na, src)
      if unchecked bitcast(usize, cval) != 0 { d_expr_rw_calls(cval, gs, gl, caps, na, src) }
      ## 3) a unique clone name shared by the new decl AND the rewritten call site.
      mut clen := 0
      cns := parser::synth_hof_name(na, unchecked bitcast(usize, src), fnpos, ptr(clen))
      nd := Decl(name_start = cns, name_len = clen, value = cval, is_fn = true, kind = hd.kind, arity = hd.arity + ncaps, is_generic = hd.is_generic, params_head = newph, body_stmts = cbody, fields_head = hd.fields_head, ret_ts = hd.ret_ts, ret_tl = hd.ret_tl, mod_start = hd.mod_start, mod_len = hd.mod_len, when_cond = hd.when_cond, alias_ts = hd.alias_ts, alias_tl = hd.alias_tl)
      s := rt::bump(deref(na), size(Decl))
      deref(unchecked bitcast(ptr(mut Decl), s)) = nd
      rt::vec_push(decls, s)
      ## 4) rewrite ONLY the capturing call site `H(…, f, …)` → `__hoflam<fnpos>(…, f, …, <caps>)`.
      d_stmts_rw_hof_site(body, hs, hl, fs, fl, cns, clen, caps, na, src)
      if unchecked bitcast(usize, fn_val) != 0 { d_expr_rw_hof_site(fn_val, hs, hl, fs, fl, cns, clen, caps, na, src) }
    }
  }
  ok
}
## Set param `h`'s `.next` to `nx` — reconstruct with `nx` threaded as a fn PARAMETER (mirrors parser's
## `set_stmt_next`). CRUCIAL: a Param ctor whose `next` field is set from a driver LOCAL/`mut` var
## mis-lowers under the seed (gdb showed the stored `.next` word left as arena garbage, never 0);
## threading the value through a fn parameter copies it correctly, exactly as `set_stmt_next` does.
## Delegates to `parser::set_param_next` — the store is done in the PARSER module (it mis-lowers in the
## driver module: a cross-module codegen quirk that writes a pointer instead of copying the struct).
d_set_param_next := fn(na : ptr(mut rt::Arena), h : ptr(mut Param), nx : ptr(mut Param)) {
  parser::set_param_next(na, h, nx)
}
## Append the captured vars as trailing PARAMS (untyped word) to the lambda's param chain. Each cap
## Param is CREATED with `next = 0` (a LITERAL — the working form), then linked by `d_set_param_next`
## (the next handle threaded as a PARAMETER) — so no ctor ever sets `.next` from a local var.
d_append_cap_params := fn(ph : ptr(mut Param), caps : ptr(rt::Vec), decls : rt::Vec, na : ptr(mut rt::Arena), body : ptr(mut Stmt), eph : ptr(mut Param), src : ptr(u8)) -> ptr(mut Param) {
  ncaps := rt::vec_len(deref(caps))
  if ncaps == 0 { return ph }
  mut head := ph
  mut tail := param_null()
  if unchecked bitcast(usize, ph) != 0 {
    tail = ph
    while unchecked bitcast(usize, deref(param_p(tail)).next) != 0 { tail = deref(param_p(tail)).next }
  }
  ## `pmode` is a `u8`; construct it from a u8-typed zero (NOT the int literal `0`), matching the parser's
  ## `mut p_pmode : u8 = 0` — an int literal in the u8 field gave the stored Param a byte layout a
  ## WHOLE-STRUCT read (`d_lam_arity`) mis-decoded.
  mut pm8 : u8 = 0
  mut k := 0
  while k < ncaps {
    pk := rt::vec_get(deref(caps), k)
    ## TYPE the capture param: a scalar capture stays untyped (ts/tl = 0 → word slot); a struct/enum
    ## capture bound by `cap := StructLit/EnumLit` resolves to that type span, so the lifted fn binds it
    ## as a by-reference aggregate param and `cap.field` resolves (the injected by-ref arg passes the local).
    mut ct := d_local_type_span(body, pk / 1024, pk % 1024, decls, na, src)
    ## Fall back to the ENCLOSING PARAM's declared aggregate type (a captured `s : Rec` param is not a
    ## body `:=` binding, so the body scan returns 0/0 → an untyped word → silent miscompile; see
    ## d_param_type_span). A resolved aggregate type gives the capture a TYPED by-ref param.
    if ct.n == 0 { ct = d_param_type_span(eph, pk / 1024, pk % 1024, decls, src) }
    nph := d_mk_param(na, Param(ns = pk / 1024, nl = pk % 1024, next = 0, ts = ct.s, tl = ct.n, pmode = pm8, pps = 0, ppl = 0))
    if head == 0 { head = nph } else { d_set_param_next(na, tail, nph) }
    tail = nph
    k = k + 1
  }
  head
}
d_single_return := fn(bh : usize, na : ptr(mut rt::Arena)) -> ptr(Expr) {
  mut r := unchecked bitcast(ptr(Expr), 0)
  if bh != 0 {
    st := deref(stmt_p(Stmt, bh))
    match st {
      Stmt::Return(rv, nx) => { if nx == 0 { r = rv } }
      _ => {}
    }
  }
  r
}
## FN-11: is expr `e` an `AddrOf(Var([fs,fl)))` — i.e. `ptr(mut store)` for the store name? (A single
## match kept standalone — the child `Var` is read by a helper, not a nested deref-match.)
d_addr_is_var := fn(e : ptr(Expr), fs : usize, fl : usize, src : ptr(u8)) -> usize {
  mut r := 0
  match deref(e) {
    Expr::AddrOf(inner) => { r = d_is_var_named(inner, fs, fl, src) }
    _ => {}
  }
  r
}
## FN-11: does expr `e` contain a `dyn_over(ptr(mut store))` for the store name `[fs,fl)`? Sets `res`.
d_uses_dyn_over_expr := fn(e : ptr(Expr), fs : usize, fl : usize, na : ptr(mut rt::Arena), src : ptr(u8), res : ptr(mut usize)) {
  match deref(e) {
    Expr::Bin(op, l, r) => { d_uses_dyn_over_expr(l, fs, fl, na, src, res); d_uses_dyn_over_expr(r, fs, fl, na, src, res) }
    Expr::Unchecked(inner) => { d_uses_dyn_over_expr(inner, fs, fl, na, src, res) }
    Expr::AddrOf(inner) => { d_uses_dyn_over_expr(inner, fs, fl, na, src, res) }
    Expr::Deref(inner) => { d_uses_dyn_over_expr(inner, fs, fl, na, src, res) }
    Expr::Try(inner) => { d_uses_dyn_over_expr(inner, fs, fl, na, src, res) }
    Expr::Field(b, ffs, ffl) => { d_uses_dyn_over_expr(b, fs, fl, na, src, res) }
    Expr::Index(b, ix) => { d_uses_dyn_over_expr(b, fs, fl, na, src, res); d_uses_dyn_over_expr(ix, fs, fl, na, src, res) }
    Expr::If(c, th, el) => { d_uses_dyn_over_expr(c, fs, fl, na, src, res); d_uses_dyn_over_expr(th, fs, fl, na, src, res); d_uses_dyn_over_expr(el, fs, fl, na, src, res) }
    Expr::Call(cs, cl, nargs, ah) => {
      if str_at((src + cs), cl) == "dyn_over" and ah != 0 and d_addr_is_var(deref(arg_p(ah)).e, fs, fl, src) == 1 { deref(res) = 1 }
      mut g := ah
      while g != 0 { ga := deref(arg_p(g)); d_uses_dyn_over_expr(ga.e, fs, fl, na, src, res); g = ga.next }
    }
    _ => {}
  }
}
d_uses_dyn_over_stmts := fn(head : ptr(mut Stmt), fs : usize, fl : usize, na : ptr(mut rt::Arena), src : ptr(u8), res : ptr(mut usize)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => { d_uses_dyn_over_expr(v, fs, fl, na, src, res) }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { d_uses_dyn_over_expr(rv, fs, fl, na, src, res) } }
      Stmt::ExprStmt(e, nx) => { d_uses_dyn_over_expr(e, fs, fl, na, src, res) }
      Stmt::If(c, th, el, nx) => { d_uses_dyn_over_expr(c, fs, fl, na, src, res); d_uses_dyn_over_stmts(th, fs, fl, na, src, res); d_uses_dyn_over_stmts(el, fs, fl, na, src, res) }
      Stmt::While(c, b, nx) => { d_uses_dyn_over_expr(c, fs, fl, na, src, res); d_uses_dyn_over_stmts(b, fs, fl, na, src, res) }
      Stmt::Loop(b, nx) => { d_uses_dyn_over_stmts(b, fs, fl, na, src, res) }
      Stmt::Unchecked(b, nx) => { d_uses_dyn_over_stmts(b, fs, fl, na, src, res) }
      Stmt::AllocWith(ae, b, nx) => { d_uses_dyn_over_stmts(b, fs, fl, na, src, res) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}
d_try_capture := fn(fs : usize, fl : usize, v : ptr(Expr), body : ptr(mut Stmt), fn_val : ptr(Expr), in out decls : rt::Vec, na : ptr(mut rt::Arena), eph : ptr(mut Param), src : ptr(u8)) {
  match deref(v) {
    Expr::Lambda(fnpos, lph, rts, rtl, bh, lval) => {
      ## Collect the lambda body's inner LOCALS (so they aren't mistaken for captures), then its FREE
      ## VARS over ALL its statements + the trailing value. `unhandled` is set for a body construct not
      ## fully analyzed here (a `match` arm's binds); if so we DECLINE capture handling (the lambda
      ## lifts normally → sema rejects it if it truly captures — sound, just not-yet-supported).
      mut caps := rt::Vec(data = rt::bump(deref(na), 32 * 8), len = 0, cap = 32)
      mut locals := rt::Vec(data = rt::bump(deref(na), 32 * 8), len = 0, cap = 32)
      mut unhandled := false
      mut hardreject := false
      d_cap_locals(bh, na, ptr(locals), ptr(unhandled))
      d_cap_free_stmts(bh, lph, na, decls, src, ptr(locals), ptr(caps), body, ptr(hardreject))
      d_cap_free(lval, lph, na, decls, src, ptr(locals), ptr(caps), body, ptr(hardreject))
      ## `hardreject` = a NON-SCALAR capture (field/index-accessed) whose type could NOT be resolved from
      ## its enclosing binding — it would get an untyped-word param + a field access → silent miscompile.
      ## Reject fail-loud. (A non-scalar capture whose type DID resolve is given a typed by-ref param and
      ## works — see d_append_cap_params.)
      if hardreject {
        if rt::vec_len(caps) > 0 { panic("selfhost: FN-6 — capturing a non-scalar local whose type is not a directly-bound struct/enum literal is unsupported") }
      }
      ## A comptime-for / comptime-match body (`unhandled`) that CAPTURES is not injected (captures are
      ## only added at direct calls, and a comptime-for body is unrolled) → reject fail-loud rather than
      ## lift with an un-injected capture (a silent miscompile — sema does not catch the unbound var).
      if unhandled {
        if rt::vec_len(caps) > 0 { panic("selfhost: FN-6 — a capturing lambda with a comptime-for/comptime-match body is unsupported") }
      }
      if unhandled == false {
        if rt::vec_len(caps) > 0 {
          mut found := false
          d_stmts_use_var(body, fs, fl, na, src, ptr(found))
          d_expr_uses_var(fn_val, fs, fl, na, src, ptr(found))
          ## FN-11: if the closure's escaping value-use is `dyn_over(ptr(mut store))`, it is a type-erased
          ## `dyn` closure over EXPLICIT storage (not a HOF/escape to reject). Append the captures as
          ## trailing params (so the lifted body resolves them) — the lowerer builds the {code, env} fat
          ## pair + adapter — and SKIP the escape reject. `dyn_over` never appears in src/lib → dormant.
          mut dynuse := 0
          d_uses_dyn_over_stmts(body, fs, fl, na, src, ptr(dynuse))
          if unchecked bitcast(usize, fn_val) != 0 { d_uses_dyn_over_expr(fn_val, fs, fl, na, src, ptr(dynuse)) }
          if found and dynuse == 0 {
            ## The closure escapes as a VALUE. §6.2: if it flows into a specializable HOF call, MONOMORPHIZE
            ## that HOF over this concrete closure (append + thread the captures) instead of rejecting; only
            ## a shape outside the first increment falls through to the fail-loud reject.
            mut hnt := 0
            mut hnf := 0
            mut hhs := 0
            mut hhl := 0
            mut hap := 0
            d_scan_hof_stmts(body, fs, fl, na, src, ptr(hnt), ptr(hnf), ptr(hhs), ptr(hhl), ptr(hap))
            if unchecked bitcast(usize, fn_val) != 0 { d_scan_hof_expr(fn_val, fs, fl, na, src, ptr(hnt), ptr(hnf), ptr(hhs), ptr(hhl), ptr(hap)) }
            if d_hof_specialize(hnf, hnt, hhs, hhl, hap, fs, fl, fnpos, body, fn_val, ptr(caps), decls, na, eph, src) == false { panic("selfhost: FN-6 — a capturing lambda used as a VALUE (escaping its defining scope) is unsupported; call it directly") }
          }
          newph := d_append_cap_params(lph, ptr(caps), decls, na, body, eph, src)
          if newph != lph {
            nlam := Expr.Lambda(fnpos, newph, rts, rtl, bh, lval)
            deref(unchecked bitcast(ptr(mut Expr), v)) = nlam
          }
          d_stmts_rw_calls(body, fs, fl, ptr(caps), na, src)
          d_expr_rw_calls(fn_val, fs, fl, ptr(caps), na, src)
        }
      }
    }
    _ => {}
  }
}
## ---- FN-6 escaping closures via FORWARDING-HOF inlining (a slice of `dyn`, no fat-value ABI) ----
## A capturing closure passed to a pure forwarding HOF `app(f, args)` (app = `fn(g, x0, …){ return
## g(x0, …) }`) is inlined at LIFT to a DIRECT call `f(args)` — f no longer escapes, so the existing
## capture pass injects its captures. General HOFs (loops / multiple calls) still need env/dyn (rejected).
CallInfo := struct { is_call : bool, cs : usize, cl : usize, nargs : usize, ah : ptr(mut Arg) }
## Call fields of `e` (extracted via a STANDALONE match — NOT an inline match inside d_fwd_hof_arity,
## which failed to fire on a top-level-fn body's returned Call).
expr_call_info := fn(e : ptr(Expr)) -> CallInfo {
  match deref(e) {
    Expr::Call(cs, cl, nargs, ah) => { CallInfo(is_call = true, cs = cs, cl = cl, nargs = nargs, ah = ah) }
    _ => { CallInfo(is_call = false, cs = 0, cl = 0, nargs = 0, ah = 0) }
  }
}
d_var_span := fn(e : ptr(Expr)) -> CSpan {
  match deref(e) {
    Expr::Var(s, n) => { CSpan(s = s, n = n) }
    _ => { CSpan(s = 0, n = 0) }
  }
}
pm_next := fn(p : ptr(mut Param), na : ptr(mut rt::Arena)) -> ptr(mut Param) { deref(param_p(p)).next }
## Arity of a forwarding HOF `d` (body a single `return <param0>(<param1>, …)` — callee IS param0, args
## ARE the rest of the params in order), else -1.
d_fwd_hof_arity := fn(d : Decl, na : ptr(mut rt::Arena), src : ptr(u8)) -> i64 {
  mut r : i64 = 0 - 1
  if d.is_fn {
    if d.params_head != 0 {
      re := d_single_return(d.body_stmts, na)
      if unchecked bitcast(usize, re) != 0 {
        ci := expr_call_info(re)
        if ci.is_call {
          p0 := deref(param_p(d.params_head))
          mut ok := true
          if str_at((src + p0.ns), p0.nl) != str_at((src + ci.cs), ci.cl) { ok = false }
          mut pp := p0.next
          mut g := ci.ah
          while pp != 0 {
            if g == 0 { ok = false; pp = 0 } else {
              pm := deref(param_p(pp))
              ga := deref(arg_p(g))
              av := d_var_span(ga.e)
              if av.n == 0 { ok = false } else { if str_at((src + av.s), av.n) != str_at((src + pm.ns), pm.nl) { ok = false } }
              g = ga.next
              pp = pm.next
            }
          }
          if g != 0 { ok = false }
          if ok { r = i64(d.arity) }
        }
      }
    }
  }
  r
}
d_fwd_call_arity := fn(decls : rt::Vec, cs : usize, cl : usize, na : ptr(mut rt::Arena), src : ptr(u8)) -> i64 {
  mut r : i64 = 0 - 1
  mut i := 0
  while i < rt::vec_len(decls) {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if d.is_fn {
      if d.name_len != 0 {
        if str_at((src + d.name_start), d.name_len) == str_at((src + cs), cl) { r = d_fwd_hof_arity(d, na, src) }
      }
    }
    i = i + 1
  }
  r
}
## --- NAMED CALL ARGUMENTS (FN §5.1) -----------------------------------------------------------------
## A call `f(a = e0, b = e1, …)` is parsed as a `StructLit(f, …)` (the parser can't tell a named call
## from a struct literal — same `Name(field = value)` syntax — and DISCARDS the field names, keeping
## only the values by position). When `f` is a VALUE-returning function (not a struct/enum type nor a
## generic `Name := fn(T) -> type` constructor), that literal is really a named call. A driver pass
## recovers the field names by SOURCE-SCAN (the established discipline for parser-erased info), matches
## them to `f`'s parameters, REORDERS the value args into parameter order, and overwrites the node with
## a `Call` (StructLit and Call have the same 4-field shape). A name/arity mismatch is fail-loud (a
## silent 0-struct miscompile otherwise). No AST growth — names live in the source, values in the args.
d_ident_char := fn(c : str) -> bool {
  if c == "" { return false }
  if c == " " { return false }
  if c == "=" { return false }
  if c == "," { return false }
  if c == "(" { return false }
  if c == ")" { return false }
  if c == "\n" { return false }
  if c == "\t" { return false }
  true
}
## Decl index+1 of a VALUE-returning fn named `[cs,cl)` (is_fn, return type not `type`), else 0.
d_value_fn_idx := fn(decls : rt::Vec, cs : usize, cl : usize, na : ptr(mut rt::Arena), src : ptr(u8)) -> usize {
  mut r := 0
  mut i := 0
  while i < rt::vec_len(decls) {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if d.is_fn {
      if d.name_len != 0 {
        if str_at((src + d.name_start), d.name_len) == str_at((src + cs), cl) {
          if str_at((src + d.ret_ts), d.ret_tl) != "type" { r = i + 1 }
        }
      }
    }
    i = i + 1
  }
  r
}
## The j-th (0-based) field-name span in a `(n0 = v0, n1 = v1, …)` list beginning at/after `pos` (the
## source right after the callee name). {0,0} if absent. Skips balanced parens inside a value.
d_field_name_at := fn(src : ptr(u8), pos : usize, j : usize) -> CSpan {
  mut i := pos
  mut go := true
  while go { c := str_at((src + i), 1); if c == "(" { go = false } else { if c == "" { go = false } else { i = i + 1 } } }
  if str_at((src + i), 1) != "(" { return CSpan(s = 0, n = 0) }
  i = i + 1
  mut depth := 0
  mut ai := 0
  mut atname := true
  mut r := CSpan(s = 0, n = 0)
  mut scanning := true
  while scanning {
    c := str_at((src + i), 1)
    if c == "" { scanning = false }
    else if c == "(" { depth = depth + 1; i = i + 1 }
    else if c == ")" { if depth == 0 { scanning = false } else { depth = depth - 1; i = i + 1 } }
    else if c == "," { if depth == 0 { ai = ai + 1; atname = true }; i = i + 1 }
    else if c == " " { i = i + 1 }
    else {
      if atname {
        mut k := i
        mut rd := true
        while rd { if d_ident_char(str_at((src + k), 1)) { k = k + 1 } else { rd = false } }
        if ai == j { r = CSpan(s = i, n = k - i); scanning = false }
        atname = false
        i = k
      } else { i = i + 1 }
    }
  }
  r
}
## Name span of the p-th (0-based) parameter of the fn at decl index `di`, or {0,0}.
d_param_name_at := fn(decls : rt::Vec, di : usize, p : usize, na : ptr(mut rt::Arena)) -> CSpan {
  d := deref(decl_at(Decl, rt::vec_get(decls, di)))
  mut ph := d.params_head
  mut k := 0
  mut r := CSpan(s = 0, n = 0)
  while ph != 0 {
    pm := deref(param_p(ph))
    if k == p { r = CSpan(s = pm.ns, n = pm.nl) }
    k = k + 1
    ph = pm.next
  }
  r
}
## The value expr of the j-th (0-based) arg in the arena-linked Arg list `fhead`, or null.
d_arg_e_at := fn(fhead : ptr(mut Arg), j : usize, na : ptr(mut rt::Arena)) -> ptr(Expr) {
  mut g := fhead
  mut k := 0
  mut r := unchecked bitcast(ptr(Expr), 0)
  while g != 0 {
    ga := deref(arg_p(g))
    if k == j { r = ga.e }
    k = k + 1
    g = ga.next
  }
  r
}
d_arg_count := fn(fhead : ptr(mut Arg), na : ptr(mut rt::Arena)) -> usize {
  mut g := fhead
  mut k := 0
  while g != 0 { ga := deref(arg_p(g)); k = k + 1; g = ga.next }
  k
}
## Rewrite a named-call StructLit `f(b = e1, a = e0)` in place to a positional `Call(f, e0, e1)`:
## match each field name to a parameter and reorder the value args. Fail-loud on any name/arity mismatch.
d_rewrite_named_call := fn(e : ptr(Expr), ss : usize, sl : usize, nf : usize, fhead : ptr(mut Arg), di : usize, decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) {
  arity := (deref(decl_at(Decl, rt::vec_get(decls, di)))).arity
  m := d_arg_count(fhead, na)
  if m != arity { panic("selfhost: named call argument count does not match the function's arity") }
  ## build the reordered arg list: output position p = the value whose field name == param p's name.
  mut head := 0
  mut tail := 0
  mut p := 0
  while p < arity {
    pn := d_param_name_at(decls, di, p, na)
    ## find the source-order field j whose name matches param p
    mut j := 0
    mut found := 0 - 1
    while j < i64(m) {
      fn0 := d_field_name_at(src, ss + sl, usize(j))
      if fn0.n != 0 { if str_at((src + fn0.s), fn0.n) == str_at((src + pn.s), pn.n) { found = j } }
      j = j + 1
    }
    if found < 0 { panic("selfhost: named call argument does not match any parameter name") }
    ve := d_arg_e_at(fhead, usize(found), na)
    argh := parser::gnode(na, Arg(e = ve, next = 0))
    if head == 0 { head = argh } else { parser::set_arg_next(na, tail, argh) }
    tail = argh
    p = p + 1
  }
  nc := Expr.Call(ss, sl, arity, head)
  deref(unchecked bitcast(ptr(mut Expr), e)) = nc
}

d_rewrite_fwd_expr := fn(e : ptr(Expr), decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) {
  match deref(e) {
    Expr::Bin(op, l, r) => { d_rewrite_fwd_expr(l, decls, na, src); d_rewrite_fwd_expr(r, decls, na, src) }
    Expr::StructLit(ss, sl, nf, fhead) => {
      mut g := fhead
      while g != 0 { ga := deref(arg_p(g)); d_rewrite_fwd_expr(ga.e, decls, na, src); g = ga.next }
      di := d_value_fn_idx(decls, ss, sl, na, src)
      if di != 0 { d_rewrite_named_call(e, ss, sl, nf, fhead, di - 1, decls, na, src) }
    }
    Expr::Unchecked(inner) => { d_rewrite_fwd_expr(inner, decls, na, src) }
    Expr::Try(inner) => { d_rewrite_fwd_expr(inner, decls, na, src) }
    Expr::If(c, th, el) => { d_rewrite_fwd_expr(c, decls, na, src); d_rewrite_fwd_expr(th, decls, na, src); d_rewrite_fwd_expr(el, decls, na, src) }
    Expr::Call(cs, cl, nargs, ah) => {
      mut g := ah
      while g != 0 { ga := deref(arg_p(g)); d_rewrite_fwd_expr(ga.e, decls, na, src); g = ga.next }
      fa := d_fwd_call_arity(decls, cs, cl, na, src)
      if fa == i64(nargs) {
        if ah != 0 {
          a0 := deref(arg_p(ah))
          av := d_var_span(a0.e)
          if av.n != 0 {
            nc := Expr.Call(av.s, av.n, nargs - 1, a0.next)
            deref(unchecked bitcast(ptr(mut Expr), e)) = nc
          }
        }
      }
    }
    _ => {}
  }
}
d_rewrite_fwd_stmts := fn(head : ptr(mut Stmt), decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => { d_rewrite_fwd_expr(v, decls, na, src) }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { d_rewrite_fwd_expr(rv, decls, na, src) } }
      Stmt::ExprStmt(e, nx) => { d_rewrite_fwd_expr(e, decls, na, src) }
      Stmt::If(c, th, el, nx) => { d_rewrite_fwd_expr(c, decls, na, src); d_rewrite_fwd_stmts(th, decls, na, src); d_rewrite_fwd_stmts(el, decls, na, src) }
      Stmt::While(c, b, nx) => { d_rewrite_fwd_expr(c, decls, na, src); d_rewrite_fwd_stmts(b, decls, na, src) }
      Stmt::Loop(b, nx) => { d_rewrite_fwd_stmts(b, decls, na, src) }
      Stmt::Unchecked(b, nx) => { d_rewrite_fwd_stmts(b, decls, na, src) }
      Stmt::AllocWith(ae, b, nx) => { d_rewrite_fwd_stmts(b, decls, na, src) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}
## FN-11 escape check (Memory §5.3.1). A `dyn` value is a two-word `{code, env}` fat pair whose `env`
## BORROWS the on-stack `store`; the pair must NOT outlive that store. The only sound use of a `dyn`
## local in this slice is calling it (`d(args)` — the callee is a name span, never an `Expr::Var`), so
## ANY appearance of the dyn local's name as an `Expr::Var` (returned / assigned / passed / stored in an
## aggregate) is an escape-shaped use → FAIL LOUD. Dormant in src/lib (no `dyn`-typed local exists → no
## name is ever flagged), so fixpoint-neutral.
d_is_dyn_annotation := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  if n < 4 { return false }
  if str_at((src + s), 3) != "dyn" { return false }
  c := str_at((src + s + 3), 1)
  c == " " or c == "\t" or c == "\n" or c == "\r"
}
## Is name `[s,n)` bound in `head` (or a nested block) with a `dyn …` type annotation? Recurses into
## block-bearing statements so a nested-scope dyn local is still recognized.
d_name_is_dyn_local := fn(head : ptr(mut Stmt), na : ptr(mut rt::Arena), src : ptr(u8), s : usize, n : usize, res : ptr(mut bool)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => {
        if str_at((src + ns), nl) == str_at((src + s), n) {
          lt := local_type_span(src, ns, nl)
          if lt.n != 0 and d_is_dyn_annotation(src, lt.s, lt.n) { deref(res) = true }
        }
      }
      Stmt::If(c, th, el, nx) => { d_name_is_dyn_local(th, na, src, s, n, res); d_name_is_dyn_local(el, na, src, s, n, res) }
      Stmt::While(c, b, nx) => { d_name_is_dyn_local(b, na, src, s, n, res) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { d_name_is_dyn_local(b, na, src, s, n, res) }
      Stmt::Loop(b, nx) => { d_name_is_dyn_local(b, na, src, s, n, res) }
      Stmt::Unchecked(b, nx) => { d_name_is_dyn_local(b, na, src, s, n, res) }
      Stmt::AllocWith(ae, b, nx) => { d_name_is_dyn_local(b, na, src, s, n, res) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}
## Does expr `e` reference a `dyn` local (of `body`) as an `Expr::Var` value? A `Call` walks only its
## ARGS — its callee is a name span, so `d(args)` (the sole legal dyn use) does not flag `d`.
d_expr_has_dynvar := fn(e : ptr(Expr), body : ptr(mut Stmt), na : ptr(mut rt::Arena), src : ptr(u8), res : ptr(mut bool)) {
  match deref(e) {
    Expr::Var(vs, vn) => { d_name_is_dyn_local(body, na, src, vs, vn, res) }
    Expr::Bin(op, l, r) => { d_expr_has_dynvar(l, body, na, src, res); d_expr_has_dynvar(r, body, na, src, res) }
    Expr::Unchecked(inner) => { d_expr_has_dynvar(inner, body, na, src, res) }
    Expr::AddrOf(inner) => { d_expr_has_dynvar(inner, body, na, src, res) }
    Expr::Deref(inner) => { d_expr_has_dynvar(inner, body, na, src, res) }
    Expr::Try(inner) => { d_expr_has_dynvar(inner, body, na, src, res) }
    Expr::Field(b, fs, fl) => { d_expr_has_dynvar(b, body, na, src, res) }
    Expr::Index(b, ix) => { d_expr_has_dynvar(b, body, na, src, res); d_expr_has_dynvar(ix, body, na, src, res) }
    Expr::Slice(b, lo, hi) => { d_expr_has_dynvar(b, body, na, src, res); d_expr_has_dynvar(lo, body, na, src, res); d_expr_has_dynvar(hi, body, na, src, res) }
    Expr::If(c, th, el) => { d_expr_has_dynvar(c, body, na, src, res); d_expr_has_dynvar(th, body, na, src, res); d_expr_has_dynvar(el, body, na, src, res) }
    Expr::Call(cs, cl, nargs, ah) => {
      mut g := ah
      while g != 0 { ga := deref(arg_p(g)); d_expr_has_dynvar(ga.e, body, na, src, res); g = ga.next }
    }
    _ => {}
  }
}
## Scan `head`'s statements for an escaping use of a `dyn` local (a `dyn`-named `Expr::Var` in any value
## position). Recurses into nested blocks.
d_stmts_dyn_escape := fn(head : ptr(mut Stmt), body : ptr(mut Stmt), na : ptr(mut rt::Arena), src : ptr(u8), res : ptr(mut bool)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => { d_expr_has_dynvar(v, body, na, src, res) }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { d_expr_has_dynvar(rv, body, na, src, res) } }
      Stmt::ExprStmt(e, nx) => { d_expr_has_dynvar(e, body, na, src, res) }
      Stmt::If(c, th, el, nx) => { d_expr_has_dynvar(c, body, na, src, res); d_stmts_dyn_escape(th, body, na, src, res); d_stmts_dyn_escape(el, body, na, src, res) }
      Stmt::While(c, b, nx) => { d_expr_has_dynvar(c, body, na, src, res); d_stmts_dyn_escape(b, body, na, src, res) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { if unchecked bitcast(usize, lo) != 0 { d_expr_has_dynvar(lo, body, na, src, res) }; if unchecked bitcast(usize, hi) != 0 { d_expr_has_dynvar(hi, body, na, src, res) }; d_stmts_dyn_escape(b, body, na, src, res) }
      Stmt::Loop(b, nx) => { d_stmts_dyn_escape(b, body, na, src, res) }
      Stmt::Unchecked(b, nx) => { d_stmts_dyn_escape(b, body, na, src, res) }
      Stmt::AllocWith(ae, b, nx) => { d_stmts_dyn_escape(b, body, na, src, res) }
      Stmt::DerefAssign(p, v, nx) => { d_expr_has_dynvar(p, body, na, src, res); d_expr_has_dynvar(v, body, na, src, res) }
      Stmt::IndexAssign(b, ix, v, nx) => { d_expr_has_dynvar(b, body, na, src, res); d_expr_has_dynvar(ix, body, na, src, res); d_expr_has_dynvar(v, body, na, src, res) }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { d_expr_has_dynvar(fv, body, na, src, res) }
      Stmt::FieldPathAssign(pl, fpv, nx) => { d_expr_has_dynvar(fpv, body, na, src, res) }
      Stmt::IndexFieldAssign(b, ix, fs, fl, v, nx) => { d_expr_has_dynvar(v, body, na, src, res) }
      Stmt::Match(sc, ah, nx) => { d_expr_has_dynvar(sc, body, na, src, res) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}

d_capture_pass := fn(body : ptr(mut Stmt), fn_val : ptr(Expr), in out decls : rt::Vec, na : ptr(mut rt::Arena), eph : ptr(mut Param), src : ptr(u8)) {
  d_rewrite_fwd_stmts(body, decls, na, src)
  d_rewrite_fwd_expr(fn_val, decls, na, src)
  ## FN-11 (Memory §5.3.1): reject a `dyn` local that escapes its defining scope (borrows its env store).
  mut dynesc := false
  d_stmts_dyn_escape(body, body, na, src, ptr(dynesc))
  if unchecked bitcast(usize, fn_val) != 0 { d_expr_has_dynvar(fn_val, body, na, src, ptr(dynesc)) }
  if dynesc { panic("selfhost: FN-11 — a `dyn` closure borrows its env storage (Memory §5.3.1) and must not escape its defining scope; it may only be called (`d(args)`), not returned, assigned, passed, or stored") }
  mut st := body
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(fs, fl, v, nx) => { d_try_capture(fs, fl, v, body, fn_val, decls, na, eph, src) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}

## AMBIENT-ALLOCATOR elision (MEM-5). Inside an `alloc::with(A) { … }` scope, a call that omits its
## `ptr(mut Arena)` allocator parameter has `ptr(A)` (an `AddrOf`) spliced in at that parameter's
## position. The ambient `amb` is the scope's allocator `Expr*` (0 = no enclosing scope).

## Last `::`-segment of a (possibly `a::b::c`) name span → its (start,len). Byte access via the
## `str_at((src + s + i), 1) == ":"` idiom (mirrors `name_tail`) — a rebased-handle-safe 1-char view.
d_span_tail := fn(src : ptr(u8), s : usize, n : usize) -> CSpan {
  mut i := 0
  mut last := 0
  while i < n {
    if str_at(((src + s) + i), 1) == ":" { last = i + 1 }
    i = i + 1
  }
  CSpan(s = (s + last), n = n - last)
}

## Index of the `ptr(mut Arena)` parameter in decl `di`, or -1. Total param count via `d_param_count`.
d_arena_param_idx := fn(decls : rt::Vec, di : usize, na : ptr(mut rt::Arena), src : ptr(u8)) -> i64 {
  d := deref(decl_at(Decl, rt::vec_get(decls, di)))
  mut ph := d.params_head
  mut k := 0
  mut r := 0 - 1
  while ph != 0 {
    pm := deref(param_p(ph))
    if pm.tl != 0 { if str_at((src + pm.ts), pm.tl) == "ptr" {
      if pm.ppl != 0 { if str_at((src + pm.pps), pm.ppl) == "Arena" { r = i64(k) } } } }
    k = k + 1
    ph = pm.next
  }
  r
}
d_param_count := fn(decls : rt::Vec, di : usize, na : ptr(mut rt::Arena)) -> usize {
  d := deref(decl_at(Decl, rt::vec_get(decls, di)))
  mut ph := d.params_head
  mut k := 0
  while ph != 0 { pm := deref(param_p(ph)); k = k + 1; ph = pm.next }
  k
}
## di+1 of a fn decl whose name (tail-matched) has a `ptr(mut Arena)` param, else 0.
d_alloc_callee := fn(decls : rt::Vec, cs : usize, cl : usize, na : ptr(mut rt::Arena), src : ptr(u8)) -> usize {
  ct := d_span_tail(src, cs, cl)
  mut r := 0
  mut i := 0
  while i < rt::vec_len(decls) {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if d.is_fn { if d.name_len != 0 {
      if str_at((src + d.name_start), d.name_len) == str_at((src + ct.s), ct.n) {
        if d_arena_param_idx(decls, i, na, src) >= 0 { r = i + 1 } } } }
    i = i + 1
  }
  r
}
## Splice `ae` as arg index `k` into arena-linked Arg list `ah`; returns the (possibly new) head.
d_insert_arg := fn(ah : ptr(mut Arg), k : usize, ae : ptr(Expr), na : ptr(mut rt::Arena)) -> usize {
  newarg := parser::gnode(na, Arg(e = ae, next = 0))
  if k == 0 { parser::set_arg_next(na, newarg, ah); return newarg }
  mut g := ah
  mut i := 0
  while i < k - 1 and g != 0 { g = deref(arg_p(g)).next; i = i + 1 }
  gn := deref(arg_p(g)).next
  parser::set_arg_next(na, newarg, gn)
  parser::set_arg_next(na, g, newarg)
  ah
}
## If Call `e` (span cs,cl; nargs; arg head ah) omits its allocator param, splice `ptr(amb)` at it.
d_elide_call := fn(e : ptr(Expr), cs : usize, cl : usize, nargs : usize, ah : ptr(mut Arg), amb : usize, decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) {
  di1 := d_alloc_callee(decls, cs, cl, na, src)
  if di1 != 0 {
    k := d_arena_param_idx(decls, di1 - 1, na, src)
    p := d_param_count(decls, di1 - 1, na)
    if k >= 0 and nargs + 1 == p {
      aexpr := unchecked bitcast(ptr(Expr), amb)
      addr := unchecked bitcast(ptr(Expr), parser::newnode(na, Expr.AddrOf(aexpr)))
      nh := d_insert_arg(ah, usize(k), addr, na)
      nc := Expr.Call(cs, cl, nargs + 1, nh)
      deref(unchecked bitcast(ptr(mut Expr), e)) = nc
    }
  }
}
d_elide_alloc_expr := fn(e : ptr(Expr), amb : usize, decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) {
  match deref(e) {
    Expr::Bin(op, l, r) => { d_elide_alloc_expr(l, amb, decls, na, src); d_elide_alloc_expr(r, amb, decls, na, src) }
    Expr::Unchecked(inner) => { d_elide_alloc_expr(inner, amb, decls, na, src) }
    Expr::Try(inner) => { d_elide_alloc_expr(inner, amb, decls, na, src) }
    Expr::AddrOf(inner) => { d_elide_alloc_expr(inner, amb, decls, na, src) }
    Expr::If(c, th, el) => { d_elide_alloc_expr(c, amb, decls, na, src); d_elide_alloc_expr(th, amb, decls, na, src); d_elide_alloc_expr(el, amb, decls, na, src) }
    Expr::Call(cs, cl, nargs, ah) => {
      mut g := ah
      while g != 0 { ga := deref(arg_p(g)); d_elide_alloc_expr(ga.e, amb, decls, na, src); g = ga.next }
      if amb != 0 { d_elide_call(e, cs, cl, nargs, ah, amb, decls, na, src) }
    }
    _ => {}
  }
}
d_elide_alloc_stmts := fn(head : ptr(mut Stmt), amb : usize, decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => { d_elide_alloc_expr(v, amb, decls, na, src) }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { d_elide_alloc_expr(rv, amb, decls, na, src) } }
      Stmt::ExprStmt(e, nx) => { d_elide_alloc_expr(e, amb, decls, na, src) }
      Stmt::If(c, th, el, nx) => { d_elide_alloc_expr(c, amb, decls, na, src); d_elide_alloc_stmts(th, amb, decls, na, src); d_elide_alloc_stmts(el, amb, decls, na, src) }
      Stmt::While(c, b, nx) => { d_elide_alloc_expr(c, amb, decls, na, src); d_elide_alloc_stmts(b, amb, decls, na, src) }
      Stmt::Loop(b, nx) => { d_elide_alloc_stmts(b, amb, decls, na, src) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { if unchecked bitcast(usize, lo) != 0 { d_elide_alloc_expr(lo, amb, decls, na, src) }; if unchecked bitcast(usize, hi) != 0 { d_elide_alloc_expr(hi, amb, decls, na, src) }; d_elide_alloc_stmts(b, amb, decls, na, src) }
      Stmt::Unchecked(b, nx) => { d_elide_alloc_stmts(b, amb, decls, na, src) }
      Stmt::AllocWith(ae, b, nx) => { d_elide_alloc_stmts(b, unchecked bitcast(usize, ae), decls, na, src) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}

## Entry point: scan every fn decl (incl. synthetic ones appended during the walk — the loop re-reads
## the count) for lambdas. Require-typed aliases are not functions, but their inline predicate is an
## Expr::Lambda stored in `Decl.value`, so lift that value too. Reads decls the WORKING driver way
## (`decl_at` bitcast over `vec_get`).
d_lift_lambdas := fn(in out decls : rt::Vec, na : ptr(mut rt::Arena), tar : ptr(mut rt::Arena), src : ptr(u8)) {
  mut i := 0
  while i < rt::vec_len(decls) {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    ## Most non-function declarations carry a Num(0) placeholder, so this is a no-op for them. A
    ## require alias carrying an inline predicate instead has a Lambda value and must be lifted before
    ## the function-only capture pass below.
    d_lift_expr(d.value, d.mod_start, d.mod_len, decls, na, tar)
    if d.is_fn {
      d_elide_alloc_stmts(d.body_stmts, 0, decls, na, src)
      d_capture_pass(d.body_stmts, d.value, decls, na, d.params_head, src)
      d_lift_stmts(d.body_stmts, d.mod_start, d.mod_len, decls, na, tar)
    }
    i = i + 1
  }
}

## Compile `src` to a complete runnable x86_64 GAS program in a fresh `StrBuf` allocated
## from `a`. Lexes into a token `Vec`, parses into a `Decl` `Vec`, emits the `_start`
## entry wrapper (call `main`, exit with its result) followed by every function
## definition. The source byte base address + length are taken from `bytes(src)` (the
## parser/lower read literal + name spans relative to that base). The token + decl `Vec`s
## are allocated from `a` and freed before return; the returned `StrBuf` is the caller's
## to flush + free.
pub compile := fn(src : str, in out a : Arena) -> strbuf::StrBuf {
  base := unchecked bitcast(usize, src.ptr)
  ## --- lex: source -> rt token store (the MIGRATED lexer lexrt, off alloc::vec) ---
  ## lexrt reads via `bytes(src)[i]` and writes each token as a 3-word arena record
  ## {kind,start,len} with its handle in an `rt::Vec` (the parser reads it via `tok_at`). The
  ## token arena is a self-contained mmap region (freed at process exit). Starts are 0-based
  ## offsets into `src`, matching `pc.src = base`.
  ## TWO SEPARATE LOCAL rt arenas. `tar` backs tokens + decl records + the GAS buffer (threaded as
  ## the `in out da` parse param). `na` backs the AST nodes, reached ONLY via `pc.arena = ptr(na)`.
  ## Both are LOCALS (so `ptr(na)` is a stable frame address — `ptr()` of an `in out` aggregate
  ## PARAM destabilizes when threaded through the deep parser recursion, a Stage-0 codegen bug that
  ## the rt::Arena migration surfaced; the stdlib Arena dodged it). They are SEPARATE so neither is
  ## aliased by two mutation paths at once (merging them — node_alloc via the ptr AND dnode via the
  ## in-out copyback — clobbers via the aggregate copyback). `a` (the old node-arena param) is unused.
  mut tar := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(tar, 33554432)
  mut na := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(na, 33554432)
  ## `rt::vec_push` does not grow — the cap must be reserved up front. The token count is bounded
  ## by the SOURCE BYTE COUNT (every token consumes ≥1 byte; whitespace yields none), and the decl
  ## count ≤ the token count, so `bs.len + 16` (the `+16` covers the trailing EOF token + slack) is
  ## a guaranteed-sufficient cap for both — the same input-sized reservation the StrBuf output uses.
  tcap := src.len + 16
  mut toks := rt::Vec(data = rt::bump(tar, tcap * 8), len = 0, cap = tcap)
  ze := lexrt::lex_rt(src, 0, toks, tar)

  ## --- parse: rt tokens -> rt Decl-handle Vec (decls in `tar`, AST nodes in `na`) ---
  mut pc := PC(toks = ptr(toks), src = base, idx = 0, arena = ptr(na), nstr = 0, mod_s = 0, mod_l = 0, enums = unchecked bitcast(ptr(rt::Vec), 0))
  mut decls := rt::Vec(data = rt::bump(tar, tcap * 8), len = 0, cap = tcap)
  ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
  ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
  ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
  parser::set_module_base(0)
  pr := parser::parse_program(pc, decls, tar)
  match pr {
    Result::Ok(n) => {}
    Result::Err(e) => { pek := d_perr_kind(e) ; d_parse_reject(pc, pek, 0, src.len, 0, 0, tar) }
  }

  ## --- lower: Vec(Decl) -> GAS ---
  ## The runnable wrapper: a `.global _start` that calls the entry `main` and turns its `%rax`
  ## result into the Linux `exit` syscall (number 60, code in `%rdi`). The entry's MANGLED
  ## label is `main__main` (the `main` fn in the `main` module — or in the implicit default
  ## module, which lower maps to the `main` prefix), so a single-source program still works.
  d_lift_lambdas(decls, ptr(na), ptr(tar), base)
  mut sb := strbuf::strbuf(tar, 4194304)
  ## Synthesize the `_start` → `main` wrapper ONLY when the program does not define its own `_start`
  ## (else the lower emits the user's `_start` as the ELF entry — a synthesized one would duplicate it).
  if d_has_start(decls, base) == false {
    strbuf::push_str(sb, ".global _start\n_start:\n  call main__main\n  movq %rax, %rdi\n  movq $60, %rax\n  syscall\n")
  }
  mut nl := 0
  lower::emit_program(ptr(decls), sb, base, ptr(na), na, nl, 0, false)
  sb = lower::peephole_gas(ptr(sb), tar)

  ## `tar` (tokens + decls + GAS buffer) and `na` (AST nodes) are freestanding mmap regions
  ## reclaimed at process exit; nothing to free here.
  sb
}

## Compile TWO modules into one runnable program — the first step of multi-module package
## assembly (port pass #7). This is the in-memory analogue of compiling two files;
## the module names are supplied by the DRIVER (in the real package model the name comes from
## the filename — MOD-4 — NOT in-source syntax). Module A is named `m0`, module B is named
## `main` (so its `main` fn is the `main__main` entry). The two names + two sources are
## concatenated into ONE buffer so every name/literal span stays relative to a SINGLE base (the
## lower resolves all spans off one base). Each module's source region is lexed + parsed with
## that module's name as the decl module tag, accumulating into ONE `Decl` `Vec`; a cross-module
## call `m0::f(…)` in module B mangles to `m0__f`, matching module A's `f` definition label
## (`<module>__<fn>`). Then the runnable `_start` + every fn definition is emitted into a fresh
## StrBuf (the caller's to flush + free). (Two-source-only for now to keep the argument-register
## budget — a str is two words; the general N-file form arrives with the package driver.)
pub compile_pair := fn(sa : str, sb_src : str, in out a : Arena) -> strbuf::StrBuf {
  ## One rt arena `tar` backs everything the lean runtime owns here — the source-concat buffer,
  ## both modules' token records, the decl handle Vec + records, AND the GAS output buffer
  ## (freestanding mmap, lazy, reclaimed at process exit). It is created FIRST so `bld`/`out`
  ## (rt::StrBuf) can reserve from it.
  mut tar := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(tar, 33554432)
  ## A SEPARATE local rt arena for the AST nodes (kept distinct from `tar` to avoid aliasing it
  ## both via `pc.arena` and the `in out da` parse param). `pc.arena = ptr(na)`.
  mut na := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(na, 33554432)
  ## --- build the single buffer: "m0" | "main" | sa | sb_src (names first, then sources) ---
  mut bld := strbuf::strbuf(tar, 1048576)
  la := 2                  ## len("m0")
  lb := 4                  ## len("main")
  lsa := sa.len
  lsb := sb_src.len
  strbuf::push_str(bld, "m0")
  strbuf::push_str(bld, "main")
  strbuf::push_str(bld, sa)
  strbuf::push_str(bld, sb_src)
  base := unchecked bitcast(usize, strbuf::strbuf_base(bld))
  sa_off := la + lb               ## source A begins after the two names
  sb_off := la + lb + lsa         ## source B begins after source A
  ## --- module A: lex its region [sa_off, sa_off+lsa) with lexrt (base_off = sa_off → token
  ## starts are buffer-relative), parse with module-name span (0, la). ---
  ## Token/decl caps reserved from the SOURCE SIZE (rt::vec_push does not grow): per-module tokens
  ## ≤ that module's bytes; decls ≤ total tokens ≤ lsa+lsb. (+16 = EOF token + slack.)
  acap := lsa + 16
  bcap := lsb + 16
  dcap := lsa + lsb + 16
  mut rt_toksa := rt::Vec(data = rt::bump(tar, acap * 8), len = 0, cap = acap)
  za := lexrt::lex_rt(str_at(base + sa_off, lsa), sa_off, rt_toksa, tar)
  mut decls := rt::Vec(data = rt::bump(tar, dcap * 8), len = 0, cap = dcap)
  mut pca := PC(toks = ptr(rt_toksa), src = base, idx = 0, arena = ptr(na), nstr = 0, mod_s = 0, mod_l = la, enums = unchecked bitcast(ptr(rt::Vec), 0))
  ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
  ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
  ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
  parser::set_module_base(sa_off)
  ra := parser::parse_program(pca, decls, tar)
  match ra { Result::Ok(n) => {}; Result::Err(e) => { pek := d_perr_kind(e) ; d_parse_reject(pca, pek, sa_off, lsa, 0, la, tar) } }
  ## --- module B: lex its region [sb_off, sb_off+lsb), parse with module-name span (la, lb).
  ## Thread the string-literal label counter (`nstr`) so the two modules' `.Lstr` labels are
  ## globally unique (otherwise both would start at 0 and collide if each had a literal).
  mut rt_toksb := rt::Vec(data = rt::bump(tar, bcap * 8), len = 0, cap = bcap)
  zb := lexrt::lex_rt(str_at(base + sb_off, lsb), sb_off, rt_toksb, tar)
  mut pcb := PC(toks = ptr(rt_toksb), src = base, idx = 0, arena = ptr(na), nstr = pca.nstr, mod_s = la, mod_l = lb, enums = unchecked bitcast(ptr(rt::Vec), 0))
  ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
  ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
  ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
  parser::set_module_base(sb_off)
  rb := parser::parse_program(pcb, decls, tar)
  match rb { Result::Ok(n) => {}; Result::Err(e) => { pek := d_perr_kind(e) ; d_parse_reject(pcb, pek, sb_off, lsb, la, lb, tar) } }
  ## --- emit the runnable program ---
  mut gas := strbuf::strbuf(tar, 4194304)
  strbuf::push_str(gas, ".global _start\n_start:\n  call main__main\n  movq %rax, %rdi\n  movq $60, %rax\n  syscall\n")
  mut nl := 0
  lower::emit_program(ptr(decls), gas, base, ptr(na), na, nl, 0, false)
  gas = lower::peephole_gas(ptr(gas), tar)
  ## discharge the working containers (the buffer is freed AFTER emit, which read spans off it).
  ## The rt token arena `tar` is a freestanding mmap region reclaimed at process exit.
  bfree := strbuf::strbuf_free(bld)
  gas
}

## Compile N modules into one runnable program — the general form of `compile_pair`
## (port pass #7; the real package model is N files, MOD-4). `names` and `srcs`
## are parallel `Vec(str)` (module k is `names[k]` with source `srcs[k]`); the LAST module's
## `main` fn is the entry (`main__main`). Every name + every source is concatenated into ONE
## buffer so all name/literal spans stay relative to a SINGLE base (the lower resolves all
## spans off one base). Each module's source region is lexed + parsed with that module's name
## as the decl tag, accumulating into ONE `Decl` `Vec`; the string-literal label counter
## (`nstr`) is threaded across modules so `.Lstr` labels are globally unique. A cross-module
## call `mK::f(…)` mangles to `mK__f`, matching module K's `f` definition label. The returned
## StrBuf is the caller's to flush + free. This is the in-memory analogue of compiling N files
## (the file-I/O layer that reads sources off disk is a thin wrapper that fills the two Vecs).
pub compile_program := fn(names : ptr(rt::Vec), srcs : ptr(rt::Vec), in out a : Arena) -> strbuf::StrBuf {
  n := rt::vec_len(deref(names))
  ## One rt arena `tar` backs the rt::StrBuf source-concat + output buffers AND the token/decl
  ## records (created first so the buffers can reserve from it; mmap is lazy). The N-file path
  ## emits the whole program's GAS, so size generously.
  mut tar := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(tar, 134217728)
  mut na := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(na, 134217728)
  mut bld := strbuf::strbuf(tar, 8388608)
  ## per-module layout bookkeeping, recorded as the name/source bytes are appended
  mut name_start := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  mut name_len := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  mut src_off := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  mut src_len := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  ## --- append all module NAMES first (so each name span precedes the source bytes) ---
  mut k := 0
  while k < n {
    nm := rt::svec_str_get(deref(names), k)
    rt::vec_push(name_start, strbuf::buf_len(bld))
    rt::vec_push(name_len, nm.len)
    strbuf::push_str(bld, nm)
    k += 1
  }
  ## --- then append all module SOURCES ---
  k = 0
  while k < n {
    s := rt::svec_str_get(deref(srcs), k)
    rt::vec_push(src_off, strbuf::buf_len(bld))
    rt::vec_push(src_len, s.len)
    strbuf::push_str(bld, s)
    k += 1
  }
  base := unchecked bitcast(usize, strbuf::strbuf_base(bld))
  ## --- lex + parse each module's region into ONE rt Decl-handle Vec, threading nstr (all token
  ## records + the shared decls handle Vec + records live in `tar`, created above). ---
  ## Caps reserved from source size (rt::vec_push does not grow): decls ≤ total tokens ≤ total
  ## buffer bytes; per-module tokens ≤ that module's `slen`. (+16 = EOF token + slack.)
  dcap := strbuf::buf_len(bld) + 16
  mut decls := rt::Vec(data = rt::bump(tar, dcap * 8), len = 0, cap = dcap)
  mut nstr := 0
  k = 0
  while k < n {
    soff := rt::vec_get(src_off, k)
    slen := rt::vec_get(src_len, k)
    tcap := slen + 16
    mut rt_toks := rt::Vec(data = rt::bump(tar, tcap * 8), len = 0, cap = tcap)
    zt := lexrt::lex_rt(str_at(base + soff, slen), soff, rt_toks, tar)
    mut pc := PC(toks = ptr(rt_toks), src = base, idx = 0, arena = ptr(na), nstr = nstr, mod_s = rt::vec_get(name_start, k), mod_l = rt::vec_get(name_len, k), enums = unchecked bitcast(ptr(rt::Vec), 0))
    ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
    ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
    ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
    parser::set_module_base(soff)
    pr := parser::parse_program(pc, decls, tar)
    match pr { Result::Ok(c) => {}; Result::Err(e) => { pek := d_perr_kind(e) ; pmns := rt::vec_get(name_start, k) ; pmnl := rt::vec_get(name_len, k) ; d_parse_reject(pc, pek, soff, slen, pmns, pmnl, tar) } }
    nstr = pc.nstr
    k += 1
  }
  d_lift_lambdas(decls, ptr(na), ptr(tar), base)
  ## --- emit the runnable program (bld stays alive: emit reads spans off its base) ---
  mut gas := strbuf::strbuf(tar, 16777216)
  strbuf::push_str(gas, ".global _start\n_start:\n  call main__main\n  movq %rax, %rdi\n  movq $60, %rax\n  syscall\n")
  mut nl := 0
  lower::emit_program(ptr(decls), gas, base, ptr(na), na, nl, 0, false)
  gas = lower::peephole_gas(ptr(gas), tar)
  ## The file-table vectors (name/src offsets) + buffers live in the rt arena `tar`, reclaimed in
  ## bulk at process exit — nothing to free per-vector.
  gas
}

## Derive the leaf module name from a file path: the basename with a trailing `.al` stripped
## (`"…/lexer.al"` → `"lexer"`). The result is a sub-slice of `p` (no allocation). The
## package module path is assembled by `push_module_name`, which additionally strips the package's
## `source_dir` marker before joining nested path components.
module_name := fn(p : str) -> str {
  n := p.len
  ## absolute byte base of the path str ({ptr,len}); reads use the spec byte view `bytes(p)[i]`,
  ## the result is a `str_at(base+start, len)` VIEW (avoids the `p[start..end]` range-slice, which
  ## the lean self-host parser does not yet handle — and str_at lowers identically under both).
  pb := unchecked bitcast(usize, p.ptr)
  ## start = one past the last '/'
  mut start := 0
  mut i := 0
  while i < n {
    c := bytes(p)[i]
    if c == 47 { start = i + 1 }   ## '/'
    i += 1
  }
  ## end = n - 3 if the name ends in ".al", else n
  mut end := n
  if n >= start + 3 {
    if bytes(p)[n - 3] == 46 and bytes(p)[n - 2] == 97 and bytes(p)[n - 1] == 108 {
      end = n - 3   ## ".al"
    }
  }
  str_at(pb + start, end - start)
}

## Manifest §6 — is `p` the package-ROOT file? (its basename is exactly `package.al`, i.e. its module
## STEM is `package`). `package.al` is the ANONYMOUS package-root module: BOTH the manifest and, for a
## single-file package, the whole program. It reaches a compile list only when the root file IS the
## program — every package's own `package.al` is excluded from its module list (`cli::list_al_in_dir`),
## so a multi-module package (the compiler's own build included) never has one. Its declarations are
## ROOT-LEVEL and emit UNPREFIXED (Modules §6.1).
d_is_root_path := fn(p : str) -> bool {
  nm := module_name(p)
  return nm == "package"
}

## Push module `p`'s NAME into the concat buffer `bld`. A path under a `/lib/` directory (the shipped
## ambient stdlib) is named by its lib-RELATIVE path with `/` → `__` and a trailing `.al` stripped —
## so `…/lib/std/io.al` becomes module `std__io`, whose `write` definition emits the label
## `std__io__write` that a `std::io::write` call mangle to. Package source files use their path under
## `source_dir`: `…/src/geometry/vec.al` becomes `geometry__vec`, matching the source path
## `geometry::vec` and the spec's `::`→`__` symbol rule. Flat/direct files retain basename behavior.
## (Caller records the byte count via a buffer delta.)
pub push_module_name := fn(in out bld : strbuf::StrBuf, p : str) {
  ## Modules §8 — a DEPENDENCY's module is named under its ALIAS: `<alias>__<path under the dep's
  ## source dir>`, so `…/dep/src/math.al` reached as `d` becomes `d__math` and a call spelled
  ## `d::math::answer()` mangles onto it. Check this FIRST: a dependency directory may legally
  ## contain a `lib/` directory, which belongs to the dependency rather than the ambient stdlib.
  dpfx := dep_root_prefix(p)
  if dpfx != 0 {
    kal := strbuf::push_str(bld, str_at(DEP_ALIAS_S, DEP_ALIAS_N))
    kus := strbuf::push_str(bld, "__")
    mut de := p.len
    if de >= dpfx + 3 and bytes(p)[de - 3] == 46 and bytes(p)[de - 2] == 97 and bytes(p)[de - 1] == 108 { de = de - 3 }
    mut dj := dpfx
    while dj < de {
      c := bytes(p)[dj]
      if c == 47 { kd1 := strbuf::push_str(bld, "__") }
      else { kd2 := strbuf::push_byte(bld, c) }
      dj += 1
    }
    return
  }

  ## find the LAST "/lib/" in the path
  mut q := -1
  mut i := 0
  while i + 5 <= p.len {
    if bytes(p)[i] == 47 and bytes(p)[i + 1] == 108 and bytes(p)[i + 2] == 105 and bytes(p)[i + 3] == 98 and bytes(p)[i + 4] == 47 { q = i64(i) }
    i += 1
  }
  if q < 0 {
    ## Prefer the manifest-provided source root. This covers arbitrary `source_dir` values and
    ## flat packages (`source_dir = "."`) where the path has no `/src/` marker. The root is a
    ## pointer/length context set by the CLI immediately after package discovery.
    mut s := 0
    mut found_root := false
    if MODULE_ROOT_N != 0 and p.len > MODULE_ROOT_N and str_at(unchecked bitcast(usize, p.ptr), MODULE_ROOT_N) == str_at(MODULE_ROOT_P, MODULE_ROOT_N) and bytes(p)[MODULE_ROOT_N] == 47 {
      s = MODULE_ROOT_N + 1
      found_root = true
    }
    ## Direct/non-package builds have no manifest context. Locate the conventional source_dir
    ## marker in both absolute (`…/src/…`) and relative (`src/…`) paths for those callers.
    mut i := 0
    while found_root == false and i + 5 <= p.len {
      if bytes(p)[i] == 47 and bytes(p)[i + 1] == 115 and bytes(p)[i + 2] == 114 and bytes(p)[i + 3] == 99 and bytes(p)[i + 4] == 47 {
        s = i + 5
        found_root = true
      }
      i += 1
    }
    if found_root == false and p.len >= 4 and str_at(unchecked bitcast(usize, p.ptr), 4) == "src/" {
      s = 4
      found_root = true
    }
    if found_root {
      mut e := p.len
      if e >= s + 3 and bytes(p)[e - 3] == 46 and bytes(p)[e - 2] == 97 and bytes(p)[e - 1] == 108 { e = e - 3 }
      mut j := s
      while j < e {
        c := bytes(p)[j]
        if c == 47 { k1 := strbuf::push_str(bld, "__") }
        else { k2 := strbuf::push_byte(bld, c) }
        j += 1
      }
    } else {
      nm := module_name(p)
      ks := strbuf::push_str(bld, nm)
    }
  } else {
    mut s := usize(q) + 5             ## just past "/lib/"
    mut e := p.len
    if e >= s + 3 and bytes(p)[e - 3] == 46 and bytes(p)[e - 2] == 97 and bytes(p)[e - 1] == 108 { e = e - 3 }   ## strip ".al"
    mut j := s
    while j < e {
      c := bytes(p)[j]
      if c == 47 { k1 := strbuf::push_byte(bld, 95); k2 := strbuf::push_byte(bld, 95) }   ## '/' → "__"
      else { kb := strbuf::push_byte(bld, c) }
      j += 1
    }
  }
}

## Publish the manifest's module source root for the following compile/check/test call. The CLI keeps
## the owning arena alive for the whole command, so storing the pointer/length avoids inventing a
## second path metadata channel alongside the newline-joined source list.
mut MODULE_ROOT_P : usize = 0
mut MODULE_ROOT_N : usize = 0
## `MODULE_ROOT` is also populated for bare nested file lists (TOOL-14), so a
## non-empty root alone does not mean that the CLI selected a package manifest.
## `set_dep_roots` is package-only, including dependency-free packages; retain
## that distinction for TOOL-15's manifest-handle bridge.
mut MODULE_PACKAGE_CONTEXT : bool = false
pub set_module_root := fn(p : usize, n : usize) -> i64 {
  MODULE_ROOT_P = p
  MODULE_ROOT_N = n
  0
}

## TOOL-6 — the lower's span order is the order of declaration-module ranges, not the raw CLI path
## order: a package root, manifest-owned synthetic declarations, and a manifest-triggered ambient module
## can all add ranges of their own. Publish the exact newline-joined path for each range so the CLI does
## not guess attribution from a span index. The pointer stays live in the compile arena until the process
## exits, which is the lifetime of the returned GAS and the split linker call.
mut EMISSION_PATHS_P : usize = 0
mut EMISSION_PATHS_N : usize = 0
pub emission_paths_ptr := fn() -> usize { return EMISSION_PATHS_P }
pub emission_paths_len := fn() -> usize { return EMISSION_PATHS_N }

## TOOL-15 — the CLI deliberately keeps `package.al` out of the module path list, because it is
## configuration input rather than an ordinary source file in the current plumbing.  The handle is
## nevertheless an ordinary private value to the package.  Keep the bridge here, at the file-driver
## boundary: read the root manifest, recover its binding/version data, and materialize a private const
## Package-shaped value in each module owned by THIS package.  Dependencies receive no such declaration.
## The materialized aggregate is a const StructLit, so lower's existing const-field fold reads it and
## `global_needs_storage` emits neither a data label nor a linker symbol.
mut MANIFEST_HAS : bool = false
mut MANIFEST_BIND_P : usize = 0
mut MANIFEST_BIND_N : usize = 0
mut MANIFEST_BIND_S : usize = 0
mut MANIFEST_BIND_PUB : bool = false
mut MANIFEST_VERSION_S : usize = 0
mut MANIFEST_VERSION_N : usize = 0
mut MANIFEST_TYPE_S : usize = 0
mut MANIFEST_TYPE_N : usize = 0
mut MANIFEST_FIELD_S : usize = 0
mut MANIFEST_FIELD_N : usize = 0
mut MANIFEST_FIELD_STRIDE : usize = 0
mut MANIFEST_FIELD_TS : usize = 0
mut MANIFEST_FIELD_TL : usize = 0
mut MANIFEST_CHILD_P : usize = 0
mut MANIFEST_CHILD_N : usize = 0

d_manifest_ws := fn(c : str) -> bool {
  c == " " or c == "\n" or c == "\t" or c == "\r"
}

d_manifest_ident := fn(c : str) -> bool {
  b := bytes(c)[0]
  (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95
}

## Skip whitespace and the manifest's `#`/`##` comments.  This is intentionally only the small
## source scan needed to locate the one binding and its required `version` scalar; the CLI remains the
## owner of the complete configuration schema and target/dependency evaluation.
d_manifest_skip := fn(s : str, from : usize) -> usize {
  mut p := from
  mut again := true
  while again and p < s.len {
    while p < s.len and d_manifest_ws(str_at(unchecked bitcast(usize, s.ptr) + p, 1)) { p += 1 }
    if p < s.len and bytes(s)[p] == 35 {
      while p < s.len and bytes(s)[p] != 10 { p += 1 }
    } else { again = false }
  }
  p
}

## Recover the manifest binding and its `version = "…"` value.  Spans are rebased to the driver's
## shared source buffer, so the synthetic AST can use the real literal bytes without copying or
## changing the parser/AST surface.  A malformed/non-Package manifest simply contributes no handle;
## the existing CLI config path remains responsible for rejecting that manifest.
d_manifest_scan := fn(s : str, soff : usize) {
  MANIFEST_HAS = false
  MANIFEST_BIND_P = 0
  MANIFEST_BIND_N = 0
  MANIFEST_BIND_S = 0
  MANIFEST_BIND_PUB = false
  MANIFEST_VERSION_S = 0
  MANIFEST_VERSION_N = 0
  MANIFEST_CHILD_P = 0
  MANIFEST_CHILD_N = 0
  base := unchecked bitcast(usize, s.ptr)
  mut p := d_manifest_skip(s, 0)
  if p + 3 <= s.len and str_at(base + p, 3) == "pub" {
    if p + 3 == s.len or not d_manifest_ident(str_at(base + p + 3, 1)) {
      MANIFEST_BIND_PUB = true
      p = d_manifest_skip(s, p + 3)
    }
  }
  ns := p
  while p < s.len and d_manifest_ident(str_at(base + p, 1)) { p += 1 }
  if p == ns { return }
  nl := p - ns
  p = d_manifest_skip(s, p)
  if p + 2 > s.len or str_at(base + p, 2) != ":=" { return }
  p = d_manifest_skip(s, p + 2)
  if p + 7 > s.len or str_at(base + p, 7) != "Package" { return }
  if p + 7 < s.len and d_manifest_ident(str_at(base + p + 7, 1)) { return }
  MANIFEST_HAS = true
  MANIFEST_BIND_P = base + ns
  MANIFEST_BIND_N = nl
  MANIFEST_BIND_S = soff + ns
  mut i := p + 7
  while i + 7 <= s.len {
    mut ok := true
    mut j := 0
    while j < 7 { if bytes(s)[i + j] != bytes("version")[j] { ok = false } ; j += 1 }
    if ok {
      mut q := i + 7
      if i > 0 and d_manifest_ident(str_at(base + i - 1, 1)) { ok = false }
      if q < s.len and d_manifest_ident(str_at(base + q, 1)) { ok = false }
      q = d_manifest_skip(s, q)
      if ok and q < s.len and bytes(s)[q] == 61 {
        q = d_manifest_skip(s, q + 1)
        if q < s.len and bytes(s)[q] == 34 {
          mut e := q + 1
          while e < s.len and bytes(s)[e] != 34 { e += 1 }
          if e < s.len {
            MANIFEST_VERSION_S = soff + q + 1
            MANIFEST_VERSION_N = e - (q + 1)
            return
          }
        }
      }
    }
    i += 1
  }
}

## The driver-side existence probe is optional: unlike read_file_into it must not turn a normal
## non-package/file-list invocation into a missing-source panic while looking for a manifest.
d_manifest_exists := fn(in out a : rt::Arena, path : str) -> bool {
  mut pb := strbuf::strbuf(a, path.len + 16)
  k0 := strbuf::push_str(pb, path)
  k1 := strbuf::push_byte(pb, 0)
  fd := rt::sys_open(2, unchecked bitcast(usize, strbuf::strbuf_base(pb)), 0, 0)
  if fd < 0 { return false }
  cc := rt::sys_close(3, unchecked bitcast(usize, fd))
  true
}

## Find the manifest corresponding to the published package source root.  `source_dir = "."` puts
## it inside the module root; all other layouts put it in that root's parent.  The two candidates also
## cover relative and absolute paths without requiring a second path-normalisation implementation.
d_manifest_path := fn(in out a : rt::Arena) -> str {
  if MODULE_PACKAGE_CONTEXT == false or MODULE_ROOT_N == 0 { return str_at(0, 0) }
  root := str_at(MODULE_ROOT_P, MODULE_ROOT_N)
  mut b := strbuf::strbuf(a, root.len + 32)
  if root == "." {
    k0 := strbuf::push_str(b, "package.al")
  } else {
    k1 := strbuf::push_str(b, root)
    k2 := strbuf::push_str(b, "/package.al")
  }
  cand := str_at(b.data, b.len)
  if d_manifest_exists(a, cand) { return cand }
  mut last := 0
  mut seen := false
  mut i := 0
  while i < root.len { if bytes(root)[i] == 47 { last = i ; seen = true } ; i += 1 }
  mut p := strbuf::strbuf(a, root.len + 32)
  if seen {
    k3 := strbuf::push_str(p, str_at(unchecked bitcast(usize, root.ptr), last))
    k4 := strbuf::push_str(p, "/package.al")
  } else {
    k5 := strbuf::push_str(p, "package.al")
  }
  parent := str_at(p.data, p.len)
  if d_manifest_exists(a, parent) { return parent }
  str_at(0, 0)
}

## A package root is now ordinary source, but package-aware ambient discovery deliberately excludes
## bare single-file prelude triggers.  Preserve that package rule for the one root call that needs
## `lib/base/process.al`: scan the root itself, then construct only that exact module path.  Calling
## the full single-file resolver here would pull its entire prelude closure and overflow its bounded
## result buffer on a manifest containing the compiler's own declarations.
d_manifest_root_process := fn(in out a : rt::Arena, manifest : str) -> str {
  if manifest.len == 0 { return str_at(0, 0) }
  mut scan := strbuf::strbuf(a, 16777216)
  n := read_file_into(scan, a, manifest)
  src := str_at(scan.data, n)
  mut i := 0
  mut found := false
  while i < n and found == false {
    c := bytes(src)[i]
    ## Skip Alatyr line comments before looking for a bare call.
    if c == 35 and i + 1 < n and bytes(src)[i + 1] == 35 {
      i += 2
      while i < n and bytes(src)[i] != 10 { i += 1 }
    } else if c == 34 {
      ## Skip string literals, including the only escape form relevant to this scan.
      i += 1
      while i < n and bytes(src)[i] != 34 {
        if bytes(src)[i] == 92 and i + 1 < n { i += 2 } else { i += 1 }
      }
      if i < n { i += 1 }
    } else if c == 101 and i + 4 <= n and str_at(unchecked bitcast(usize, src.ptr) + i, 4) == "exit" {
      mut before_ok := true
      if i != 0 { b := bytes(src)[i - 1] ; before_ok = not ((b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95) }
      mut after := i + 4
      if after < n { b2 := bytes(src)[after] ; if (b2 >= 48 and b2 <= 57) or (b2 >= 65 and b2 <= 90) or (b2 >= 97 and b2 <= 122) or b2 == 95 { before_ok = false } }
      while before_ok and after < n and (bytes(src)[after] == 32 or bytes(src)[after] == 9 or bytes(src)[after] == 10 or bytes(src)[after] == 13) { after += 1 }
      if before_ok and after < n and bytes(src)[after] == 40 { found = true } else { i += 1 }
    } else {
      i += 1
    }
  }
  if found == false { return str_at(0, 0) }
  ldir := cli::lib_dir(a)
  if ldir.len == 0 { return str_at(0, 0) }
  mut p := strbuf::strbuf(a, ldir.len + 32)
  k0 := strbuf::push_str(p, ldir)
  k1 := strbuf::push_str(p, "/base/process.al")
  str_at(p.data, p.len)
}

## Recognize the shipped process module by MODULE PATH, not by one spelling of the filesystem prefix.
## Package ambient discovery can hand us either an absolute `/…/lib/base/process.al` or a relative
## `lib/base/process.al`; both are the same module and must occupy one slot in `pv`.
d_manifest_is_base_process_path := fn(p : str) -> bool {
  if module_name(p) != "process" { return false }
  mut i := 0
  while i + 10 <= p.len {
    if str_at(unchecked bitcast(usize, p.ptr) + i, 10) == "/lib/base/" { return true }
    i += 1
  }
  if p.len >= 10 and str_at(unchecked bitcast(usize, p.ptr), 10) == "lib/base/" { return true }
  false
}

d_manifest_has_base_process := fn(pv : rt::Vec) -> bool {
  mut k := 0
  while k < rt::vec_len(pv) {
    if d_manifest_is_base_process_path(rt::svec_str_get(pv, k)) { return true }
    k += 1
  }
  false
}

## Is `p` one of the consuming package's source modules?  Dependency rows and ambient `/lib/` files
## are explicitly excluded; a private root handle must not leak into either namespace.
d_manifest_package_path := fn(p : str) -> bool {
  if MODULE_ROOT_N == 0 { return false }
  ## A direct single-file invocation may put package.al itself in `pv`.  The manifest
  ## is already parsed as the program's anonymous root; injecting the private handle
  ## into that same AST would duplicate every root declaration (including ambient
  ## `base__assert`) and is not the manifest-handle seam.
  if d_is_root_path(p) { return false }
  if dep_root_prefix(p) != 0 { return false }
  mut lib := false
  mut i := 0
  while i + 5 <= p.len {
    if bytes(p)[i] == 47 and str_at(unchecked bitcast(usize, p.ptr) + i, 5) == "/lib/" { lib = true }
    i += 1
  }
  if lib { return false }
  root := str_at(MODULE_ROOT_P, MODULE_ROOT_N)
  if root == "." {
    ## A flat package's own discovery paths are `./…`; dependency paths retain their `../…` or
    ## absolute spelling.  The old unconditional true admitted an unaliased path dependency.
    if p.len < 2 or str_at(unchecked bitcast(usize, p.ptr), 2) != "./" { return false }
    return true
  }
  if p.len <= MODULE_ROOT_N { return false }
  if str_at(unchecked bitcast(usize, p.ptr), MODULE_ROOT_N) != root { return false }
  bytes(p)[MODULE_ROOT_N] == 47
}

## Is `p` an ordinary module owned by the consuming package, including the anonymous
## package root itself?  The root is intentionally excluded from d_manifest_package_path:
## that predicate is also the child-module detector, where `package.al` must never look like
## a `<source_dir>/<handle>.al` child.  Once package.al is parsed as the root module, however,
## the existing TOOL-15 synthetic handle and field rewrite must cover it too.
d_manifest_owned_path := fn(p : str) -> bool {
  if d_is_root_path(p) { return true }
  d_manifest_package_path(p)
}

## A root child module is a direct `<source_dir>/<handle>.al` file.  The child path itself is kept
## for the required two-sided duplicate diagnostic.
d_manifest_find_child := fn(pv : rt::Vec) -> bool {
  if MANIFEST_HAS == false or MANIFEST_BIND_N == 0 { return false }
  mut k := 0
  mut found := false
  while k < rt::vec_len(pv) and found == false {
    p := rt::svec_str_get(pv, k)
    if d_manifest_package_path(p) {
      root := str_at(MODULE_ROOT_P, MODULE_ROOT_N)
      mut rs := 0
      if root != "." { rs = MODULE_ROOT_N + 1 }
      if root == "." and p.len >= 2 and str_at(unchecked bitcast(usize, p.ptr), 2) == "./" { rs = 2 }
      if rs < p.len {
        rem := p.len - rs
        if rem == MANIFEST_BIND_N + 3 and bytes(p)[p.len - 3] == 46 and bytes(p)[p.len - 2] == 97 and bytes(p)[p.len - 1] == 108 {
          mut same := true
          mut i := 0
          while i < MANIFEST_BIND_N { if bytes(p)[rs + i] != bytes(str_at(MANIFEST_BIND_P, MANIFEST_BIND_N))[i] { same = false } ; i += 1 }
          if same {
            MANIFEST_CHILD_P = unchecked bitcast(usize, p.ptr)
            MANIFEST_CHILD_N = p.len
            found = true
          }
        }
      }
    }
    k += 1
  }
  found
}

## Render a Config-stage `pub` rejection.  The build path calls the same renderer and then aborts;
## `check` prints it and returns its normal rejection code.
d_manifest_pub_diag := fn(in out a : rt::Arena, manifest : str) {
  mut b := strbuf::strbuf(a, 512)
  k0 := strbuf::push_str(b, "alatyr: config: manifest binding '")
  k1 := strbuf::push_str(b, str_at(MANIFEST_BIND_P, MANIFEST_BIND_N))
  k2 := strbuf::push_str(b, "' must be private; `pub` is not allowed on a Package handle in ")
  k3 := strbuf::push_str(b, manifest)
  k4 := strbuf::push_byte(b, 10)
  return strbuf::sb_flush(b, 2)
}

## Render the Semantic duplicate without pretending the child file was an AST declaration.  Both
## spellings are named because the source-side module table is otherwise invisible to sema.
d_manifest_duplicate_diag := fn(in out a : rt::Arena, manifest : str) {
  mut b := strbuf::strbuf(a, 768)
  k0 := strbuf::push_str(b, "alatyr: check: semantic duplicate name: manifest declaration '")
  k1 := strbuf::push_str(b, str_at(MANIFEST_BIND_P, MANIFEST_BIND_N))
  k2 := strbuf::push_str(b, "' in ")
  k3 := strbuf::push_str(b, manifest)
  k4 := strbuf::push_str(b, " conflicts with child module ")
  k5 := strbuf::push_str(b, str_at(MANIFEST_CHILD_P, MANIFEST_CHILD_N))
  k6 := strbuf::push_byte(b, 10)
  return strbuf::sb_flush(b, 2)
}

## Add the internal `Package { version : str }` type and one private const handle for a package-owned
## module.  The type name is deliberately reserved and never appears in user source; only the handle
## name from the manifest is source-visible.  Repeating the const in each root module is what lets the
## existing lower/sema module resolver enforce dependency invisibility without changing `lower.al`.
d_manifest_ast_alloc := fn(in out a : rt::Arena, sz : usize) -> usize {
  rem := a.off % 8
  mut aligned := a.off
  if rem != 0 { aligned = a.off + (8 - rem) }
  if aligned + sz > a.cap { panic("TOOL-15: AST arena overflow") }
  a.off = aligned + sz
  aligned
}

d_manifest_field_node := fn(in out a : rt::Arena, val : FieldDecl) -> ptr(mut FieldDecl) {
  h := d_manifest_ast_alloc(a, 96)
  p := unchecked bitcast(ptr(mut FieldDecl), unchecked bitcast(usize, a.base) + h)
  deref(p) = val
  p
}

d_manifest_decl_node := fn(in out a : rt::Arena, d : Decl) -> usize {
  s := rt::bump(a, size(Decl))
  p : ptr(mut Decl) = unchecked bitcast(ptr(mut Decl), s)
  deref(p) = d
  s
}

d_manifest_module_decls := fn(pv : rt::Vec, name_start : rt::Vec, name_len : rt::Vec, in out decls : rt::Vec, in out na : rt::Arena, in out tar : rt::Arena, in out nstr : usize) {
  if MANIFEST_HAS == false or MANIFEST_VERSION_N == 0 { return }
  mut k := 0
  while k < rt::vec_len(pv) {
    p := rt::svec_str_get(pv, k)
    if d_manifest_owned_path(p) {
      ms := rt::vec_get(name_start, k)
      ml := rt::vec_get(name_len, k)
      ## Field-name rodata labels are keyed by the absolute name span.  Give every
      ## synthetic declaration its own copy of `version`, while keeping the first
      ## copy as the canonical text used by the source-AST rewrite probe.
      fns := MANIFEST_FIELD_S + k * MANIFEST_FIELD_STRIDE
      fd := d_manifest_field_node(na, FieldDecl(ns = fns, nl = MANIFEST_FIELD_N, arity = 0, next = 0, ts = MANIFEST_FIELD_TS, tl = MANIFEST_FIELD_TL, wsize = 1))
      td := Decl(name_start = MANIFEST_TYPE_S, name_len = MANIFEST_TYPE_N, value = 0, is_fn = false, kind = 2, arity = 0, is_generic = false, params_head = 0, body_stmts = 0, fields_head = fd, ret_ts = 0, ret_tl = 0, mod_start = ms, mod_len = ml, when_cond = 0, alias_ts = 0, alias_tl = 0)
      th := d_manifest_decl_node(tar, td)
      rt::vec_push(decls, th)
      lit := parser::newnode(ptr(na), Expr.StrLit(MANIFEST_VERSION_S, MANIFEST_VERSION_N, nstr))
      nstr += 1
      ah := parser::gnode(ptr(na), Arg(e = lit, next = 0))
      value := parser::newnode(ptr(na), Expr.StructLit(MANIFEST_TYPE_S, MANIFEST_TYPE_N, 1, ah))
      ad := Decl(name_start = MANIFEST_BIND_S, name_len = MANIFEST_BIND_N, value = value, is_fn = false, kind = 0, arity = 0, is_generic = false, params_head = 0, body_stmts = 0, fields_head = 0, ret_ts = 0, ret_tl = 0, mod_start = ms, mod_len = ml, when_cond = 0, alias_ts = 0, alias_tl = 0)
      ahd := d_manifest_decl_node(tar, ad)
      rt::vec_push(decls, ahd)
    }
    k += 1
  }
}

## package.al is now parsed so its ordinary root declarations participate in sema.  Its first
## declaration is still configuration, not runtime/source code: remove only that exact parsed
## binding before adding the existing synthetic TOOL-15 declaration.  The synthetic declaration
## keeps the handle source-visible to root and child modules, while an ordinary root declaration
## with the same name remains in the Vec and is correctly rejected as a same-scope duplicate.
d_manifest_drop_root_decl := fn(in out decls : rt::Vec, root_ms : usize, root_ml : usize) {
  if MANIFEST_HAS == false or MANIFEST_BIND_N == 0 { return }
  mut kept := 0
  mut i := 0
  cnt := rt::vec_len(decls)
  while i < cnt {
    h := rt::vec_get(decls, i)
    d := deref(decl_at(Decl, h))
    drop := d.mod_start == root_ms and d.mod_len == root_ml
      and d.name_start == MANIFEST_BIND_S and d.name_len == MANIFEST_BIND_N
    if drop == false {
      rt::rec_set(decls.data, kept, h)
      kept += 1
    }
    i += 1
  }
  decls.len = kept
}

## The existing lower has a deliberate fail-loud gap for a `str` field read directly from a const
## aggregate global: it can resolve the pointer word but cannot carry the view's length through every
## nested field/call shape.  Keep that lower surface untouched.  Once sema has the synthetic ordinary
## declaration, replace the one manifest scalar field with the same literal expression that the
## manifest already contains.  This is a source-AST normalization, not a new syntax or a new semantic
## path; dependencies are excluded by `allow`, so an out-of-package `app.version` remains unbound.
d_manifest_field_is_handle := fn(src : ptr(u8), fs : usize, fl : usize) -> bool {
  if streq(src, fs, fl, MANIFEST_FIELD_S, MANIFEST_FIELD_N) == false { return false }
  mut p := fs
  while p > 0 and d_manifest_ws(str_at((src + p - 1), 1)) { p -= 1 }
  if p == 0 or str_at((src + p - 1), 1) != "." { return false }
  p -= 1
  while p > 0 and d_manifest_ws(str_at((src + p - 1), 1)) { p -= 1 }
  e := p
  while p > 0 and d_manifest_ident(str_at((src + p - 1), 1)) { p -= 1 }
  if e == p { return false }
  if p > 0 {
    c := str_at((src + p - 1), 1)
    if d_manifest_ident(c) or c == "." or c == ":" { return false }
  }
  streq(src, p, e - p, MANIFEST_BIND_S, MANIFEST_BIND_N)
}

d_manifest_rewrite_expr := fn(e : ptr(Expr), allow : bool, in out nstr : usize, src : ptr(u8), na : ptr(mut rt::Arena)) {
  if unchecked bitcast(usize, e) == 0 { return }
  match deref(e) {
    Expr::Bin(op, l, r) => { d_manifest_rewrite_expr(l, allow, nstr, src, na); d_manifest_rewrite_expr(r, allow, nstr, src, na) }
    Expr::If(c, t, f) => { d_manifest_rewrite_expr(c, allow, nstr, src, na); d_manifest_rewrite_expr(t, allow, nstr, src, na); d_manifest_rewrite_expr(f, allow, nstr, src, na) }
    Expr::Match(c, ah) => {
      d_manifest_rewrite_expr(c, allow, nstr, src, na)
      mut ar := ah
      while ar != 0 {
        am := deref(arm_p(ar))
        d_manifest_rewrite_stmts(am.body_stmts, allow, nstr, src, na)
        if unchecked bitcast(usize, am.body) != 0 { d_manifest_rewrite_expr(am.body, allow, nstr, src, na) }
        ar = am.next
      }
    }
    Expr::Call(cs, cl, nn, ah) => {
      mut g := ah
      while g != 0 {
        ga := deref(arg_p(g))
        d_manifest_rewrite_expr(ga.e, allow, nstr, src, na)
        g = ga.next
      }
    }
    Expr::StructLit(ss, sl, nn, ah) => {
      mut g := ah
      while g != 0 {
        ga := deref(arg_p(g))
        d_manifest_rewrite_expr(ga.e, allow, nstr, src, na)
        g = ga.next
      }
    }
    Expr::EnumLit(es, el, vs, vl, nn, ah) => {
      mut g := ah
      while g != 0 {
        ga := deref(arg_p(g))
        d_manifest_rewrite_expr(ga.e, allow, nstr, src, na)
        g = ga.next
      }
    }
    Expr::ArrayLit(nn, ah) => {
      mut g := ah
      while g != 0 {
        ga := deref(arg_p(g))
        d_manifest_rewrite_expr(ga.e, allow, nstr, src, na)
        g = ga.next
      }
    }
    Expr::Unchecked(inner) => { d_manifest_rewrite_expr(inner, allow, nstr, src, na) }
    Expr::Bitcast(inner, ps, pl) => { d_manifest_rewrite_expr(inner, allow, nstr, src, na) }
    Expr::AddrOf(inner) => { d_manifest_rewrite_expr(inner, allow, nstr, src, na) }
    Expr::Deref(inner) => { d_manifest_rewrite_expr(inner, allow, nstr, src, na) }
    Expr::Try(inner) => { d_manifest_rewrite_expr(inner, allow, nstr, src, na) }
    Expr::Index(b, ix) => { d_manifest_rewrite_expr(b, allow, nstr, src, na); d_manifest_rewrite_expr(ix, allow, nstr, src, na) }
    Expr::Slice(b, lo, hi) => { d_manifest_rewrite_expr(b, allow, nstr, src, na); d_manifest_rewrite_expr(lo, allow, nstr, src, na); d_manifest_rewrite_expr(hi, allow, nstr, src, na) }
    Expr::Field(b, fs, fl) => {
      d_manifest_rewrite_expr(b, allow, nstr, src, na)
      mut hit := false
      if allow {
        if d_manifest_field_is_handle(src, fs, fl) { hit = true }
      }
      if hit {
        lbl := nstr
        nstr += 1
        repl := Expr.StrLit(MANIFEST_VERSION_S, MANIFEST_VERSION_N, lbl)
        deref(unchecked bitcast(ptr(mut Expr), e)) = repl
      }
    }
    Expr::Lambda(fnpos, ph, rts, rtl, bh, val) => {
      d_manifest_rewrite_stmts(bh, allow, nstr, src, na)
      d_manifest_rewrite_expr(val, allow, nstr, src, na)
    }
    _ => {}
  }
}

d_manifest_rewrite_arms := fn(ah : ptr(mut Arm), allow : bool, in out nstr : usize, src : ptr(u8), na : ptr(mut rt::Arena)) {
  mut ar := ah
  while ar != 0 {
    am := deref(arm_p(ar))
    d_manifest_rewrite_stmts(am.body_stmts, allow, nstr, src, na)
    if unchecked bitcast(usize, am.body) != 0 { d_manifest_rewrite_expr(am.body, allow, nstr, src, na) }
    ar = am.next
  }
}

d_manifest_rewrite_stmts := fn(head : ptr(mut Stmt), allow : bool, in out nstr : usize, src : ptr(u8), na : ptr(mut rt::Arena)) {
  mut s := head
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Assign(ns, nl, v, nx) => { d_manifest_rewrite_expr(v, allow, nstr, src, na) }
      Stmt::Return(rv, nx) => { d_manifest_rewrite_expr(rv, allow, nstr, src, na) }
      Stmt::ExprStmt(e, nx) => { d_manifest_rewrite_expr(e, allow, nstr, src, na) }
      Stmt::If(c, th, el, nx) => { d_manifest_rewrite_expr(c, allow, nstr, src, na); d_manifest_rewrite_stmts(th, allow, nstr, src, na); d_manifest_rewrite_stmts(el, allow, nstr, src, na) }
      Stmt::While(c, b, nx) => { d_manifest_rewrite_expr(c, allow, nstr, src, na); d_manifest_rewrite_stmts(b, allow, nstr, src, na) }
      Stmt::For(ns, nl, lo, hi, b, nx) => { d_manifest_rewrite_expr(lo, allow, nstr, src, na); d_manifest_rewrite_expr(hi, allow, nstr, src, na); d_manifest_rewrite_stmts(b, allow, nstr, src, na) }
      Stmt::Loop(b, nx) => { d_manifest_rewrite_stmts(b, allow, nstr, src, na) }
      Stmt::Unchecked(b, nx) => { d_manifest_rewrite_stmts(b, allow, nstr, src, na) }
      Stmt::AllocWith(ae, b, nx) => { d_manifest_rewrite_expr(ae, allow, nstr, src, na); d_manifest_rewrite_stmts(b, allow, nstr, src, na) }
      Stmt::Break(bv, bd, nx) => { d_manifest_rewrite_expr(bv, allow, nstr, src, na) }
      Stmt::DerefAssign(p, v, nx) => { d_manifest_rewrite_expr(p, allow, nstr, src, na); d_manifest_rewrite_expr(v, allow, nstr, src, na) }
      Stmt::IndexAssign(b, ix, v, nx) => { d_manifest_rewrite_expr(b, allow, nstr, src, na); d_manifest_rewrite_expr(ix, allow, nstr, src, na); d_manifest_rewrite_expr(v, allow, nstr, src, na) }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { d_manifest_rewrite_expr(fv, allow, nstr, src, na) }
      Stmt::FieldPathAssign(pl, fpv, nx) => { d_manifest_rewrite_expr(pl, allow, nstr, src, na); d_manifest_rewrite_expr(fpv, allow, nstr, src, na) }
      Stmt::IndexFieldAssign(b, ix, fs, fl, v, nx) => { d_manifest_rewrite_expr(b, allow, nstr, src, na); d_manifest_rewrite_expr(ix, allow, nstr, src, na); d_manifest_rewrite_expr(v, allow, nstr, src, na) }
      Stmt::Match(sc, ah, nx) => { d_manifest_rewrite_expr(sc, allow, nstr, src, na); d_manifest_rewrite_arms(ah, allow, nstr, src, na) }
      Stmt::CompIf(c, th, el, nx) => { d_manifest_rewrite_expr(c, allow, nstr, src, na); d_manifest_rewrite_stmts(th, allow, nstr, src, na); d_manifest_rewrite_stmts(el, allow, nstr, src, na) }
      Stmt::CompFor(ns, nl, iv, b, nx) => { d_manifest_rewrite_stmts(b, allow, nstr, src, na) }
      Stmt::CompForRange(ns, nl, lo, hi, b, nx) => { d_manifest_rewrite_expr(lo, allow, nstr, src, na); d_manifest_rewrite_expr(hi, allow, nstr, src, na); d_manifest_rewrite_stmts(b, allow, nstr, src, na) }
      Stmt::CompMatch(sc, ah, nx) => { d_manifest_rewrite_expr(sc, allow, nstr, src, na); d_manifest_rewrite_arms(ah, allow, nstr, src, na) }
      _ => {}
    }
    s = d_next_stmt(s, na)
  }
}

d_manifest_owned_module := fn(src : ptr(u8), ms : usize, ml : usize, pv : rt::Vec, name_start : rt::Vec, name_len : rt::Vec) -> bool {
  mut k := 0
  mut found := false
  while k < rt::vec_len(pv) and found == false {
    p := rt::svec_str_get(pv, k)
    if d_manifest_owned_path(p) and d_mod_seg_eq(src, ms, ml, rt::vec_get(name_start, k), rt::vec_get(name_len, k)) { found = true }
    k += 1
  }
  found
}

## Publish the package-owned module names to sema so the anonymous root's private declarations stop at
## the package boundary.  The same owned-path predicate feeds TOOL-15 injection/rewrite and this
## visibility table, keeping root/child access aligned while dependency modules stay separate.
d_manifest_set_sema_modules := fn(pv : rt::Vec, name_start : rt::Vec, name_len : rt::Vec, in out tar : rt::Arena) {
  if MANIFEST_HAS == false {
    sema::set_package_modules(0, 0)
    return
  }
  cap := rt::vec_len(pv) * 2 + 2
  mut owned := rt::Vec(data = rt::bump(tar, cap * 8), len = 0, cap = cap)
  mut k := 0
  while k < rt::vec_len(pv) {
    if d_manifest_owned_path(rt::svec_str_get(pv, k)) {
      rt::vec_push(owned, rt::vec_get(name_start, k))
      rt::vec_push(owned, rt::vec_get(name_len, k))
    }
    k += 1
  }
  sema::set_package_modules(unchecked bitcast(usize, ptr(owned)), rt::vec_len(owned))
}

d_manifest_rewrite_decls := fn(decls : rt::Vec, pv : rt::Vec, name_start : rt::Vec, name_len : rt::Vec, src : ptr(u8), in out nstr : usize, na : ptr(mut rt::Arena)) {
  mut i := 0
  while i < rt::vec_len(decls) {
    d := deref(decl_get(ptr(decls), i))
    if d_manifest_owned_module(src, d.mod_start, d.mod_len, pv, name_start, name_len) {
      if unchecked bitcast(usize, d.value) != 0 { d_manifest_rewrite_expr(d.value, true, nstr, src, na) }
      d_manifest_rewrite_stmts(d.body_stmts, true, nstr, src, na)
    }
    i += 1
  }
}

## Append the hidden type spelling to the shared source buffer and publish its spans.  This is AST
## backing storage only; it is never added to the path/file table and cannot become a module/symbol.
d_manifest_type_source := fn(in out bld : strbuf::StrBuf, n : usize) {
  MANIFEST_TYPE_S = strbuf::buf_len(bld)
  k0 := strbuf::push_str(bld, "__manifest_Package")
  MANIFEST_TYPE_N = strbuf::buf_len(bld) - MANIFEST_TYPE_S
  k1 := strbuf::push_str(bld, " := struct { ")
  MANIFEST_FIELD_S = strbuf::buf_len(bld)
  k2 := strbuf::push_str(bld, "version")
  MANIFEST_FIELD_N = strbuf::buf_len(bld) - MANIFEST_FIELD_S
  MANIFEST_FIELD_STRIDE = MANIFEST_FIELD_N + 1
  mut i := 1
  while i < n {
    ks := strbuf::push_byte(bld, 32)
    kv := strbuf::push_str(bld, "version")
    i += 1
  }
  k3 := strbuf::push_str(bld, " : ")
  MANIFEST_FIELD_TS = strbuf::buf_len(bld)
  k4 := strbuf::push_str(bld, "str")
  MANIFEST_FIELD_TL = strbuf::buf_len(bld) - MANIFEST_FIELD_TS
  k5 := strbuf::push_str(bld, " }\n")
}

## Modules §8 / MOD-7 — publish the resolved PATH-DEPENDENCY table: newline-terminated
## `<dep source dir>\t<alias>` rows, in the same pointer/length shape (and lifetime) as the module
## root above. `push_module_name` names a file under such a directory `<alias>__<module>`, so the
## dependency's items live under its ALIAS namespace (`<alias>::<module>::…`) instead of being merged
## FLATLY into the consuming package. EMPTY for a dependency-free package (every build in `src/` +
## every existing fixture) → not one emitted module name moves → fixpoint-neutral.
mut DEP_ROOTS_P : usize = 0
mut DEP_ROOTS_N : usize = 0
pub set_dep_roots := fn(p : usize, n : usize) -> i64 {
  DEP_ROOTS_P = p
  DEP_ROOTS_N = n
  MODULE_PACKAGE_CONTEXT = true
  0
}

## The byte offset just past the `<dep source dir>/` prefix of `p` in the published dependency table,
## with the matching row's ALIAS span returned in `DEP_ALIAS_S`/`DEP_ALIAS_N` — or 0 when `p` belongs to
## no dependency. (Scalar out-params through globals: the lean lower's multi-value return shapes are
## deliberately avoided on this path.)
mut DEP_ALIAS_S : usize = 0
mut DEP_ALIAS_N : usize = 0
dep_root_prefix := fn(p : str) -> usize {
  if DEP_ROOTS_N == 0 { return 0 }
  rows := str_at(DEP_ROOTS_P, DEP_ROOTS_N)
  mut i := 0
  mut hit := 0
  while i < rows.len and hit == 0 {
    mut e := i
    while e < rows.len and bytes(rows)[e] != 10 { e += 1 }
    mut t := i
    while t < e and bytes(rows)[t] != 9 { t += 1 }
    dl := t - i
    if dl != 0 and p.len > dl + 1 {
      if str_at(unchecked bitcast(usize, p.ptr), dl) == str_at(DEP_ROOTS_P + i, dl) and bytes(p)[dl] == 47 {
        DEP_ALIAS_S = DEP_ROOTS_P + t + 1
        DEP_ALIAS_N = e - (t + 1)
        hit = dl + 1
      }
    }
    i = e + 1
  }
  return hit
}

## Read the whole file at `path`, appending its bytes to `sb`; returns the number of bytes
## appended. Reads in 8 KiB chunks until EOF (`file_read` → `Ok(0)`). This is the source-input
## primitive a self-hosted compiler needs (the read counterpart of `std::io::write_file` that
## puts emitted GAS on disk) — it lets the driver pull a real `.al` file off disk into the
## single shared lex buffer.
read_file_into := fn(in out sb : strbuf::StrBuf, in out scratch : rt::Arena, path : str) -> usize {
  ## Build a NUL-terminated path in a small scratch `StrBuf` (open needs a C string, but the `path`
  ## str {ptr,len} is a span into a larger buffer, not NUL-terminated). `push_byte` appends the path
  ## bytes; the final `push_byte(0)` is the terminator. (No fixed `[u8; N]` array — the lean
  ## self-host parser does not handle array types; a bump-backed StrBuf serves as the byte buffer.)
  ## Raw `rt::sys_*` syscalls + raw isize return checks — no `std::io`/`Result`/`io::File`, which the
  ## lean self-host lower cannot compile; this lowers identically under both compilers.
  mut pbuf := strbuf::strbuf(scratch, path.len + 16)
  mut k := 0
  while k < path.len {
    kk := strbuf::push_byte(pbuf, bytes(path)[k])
    k += 1
  }
  kn := strbuf::push_byte(pbuf, 0)   ## NUL terminator
  pa := unchecked bitcast(usize, strbuf::strbuf_base(pbuf))
  fd := rt::sys_open(2, pa, 0, 0)   ## open(path, O_RDONLY, 0)
  if fd < 0 { panic("selfhost: cannot open source file") }
  ufd := unchecked bitcast(usize, fd)
  mut total := 0
  mut done := false
  ## Read each chunk DIRECTLY into the output buffer at `sb.data + sb.len` (the next free byte) —
  ## no intermediate chunk array. The kernel writes exactly `c` bytes; advance `sb.len` past them.
  ## `sb` is fixed-capacity: bound every syscall by its remaining reservation. If the file has
  ## more bytes than the caller reserved, stop before the next syscall and report it rather than
  ## letting the kernel overwrite the next arena allocation.
  while done == false {
    if sb.len >= sb.cap { panic("rt: StrBuf overflow") }
    available := sb.cap - sb.len
    mut chunk := 8192
    if available < chunk { chunk = available }
    nr := rt::sys_read(0, ufd, sb.data + sb.len, chunk)   ## read(fd, sb.data+sb.len, min(8192, available))
    if nr <= 0 {
      done = true
    } else {
      c := unchecked bitcast(usize, nr)
      sb.len = sb.len + c
      total += c
    }
  }
  cc := rt::sys_close(3, ufd)
  total
}

## Compile N source FILES into one runnable program — the file-I/O form of `compile_program`
## and the mechanism the TOOL-1 fixpoint harness uses to feed the self-host tree its OWN `.al`
## sources (port pass #7). `paths` is a `Vec(str)` of file paths; module k's name is
## `module_name(paths[k])` (the filename stem, MOD-4) and its source is the file's bytes. Every
## name + every source is concatenated into one buffer (all spans relative to a single base),
## each region lexed + parsed with its module name as the decl tag into one shared `Decl` `Vec`,
## the `.Lstr` counter threaded across modules, then emitted. The returned StrBuf is the
## caller's to flush + free. The LAST module's `main` fn is the entry (`main__main`).
## The normal `build`/emit path — entry `_start` calls the program's `main` (the wrapper keeps
## the public `compile_files(paths, a)` signature stable for its existing callers + the fixpoint).
## FND-11 — is `[cs, cs+cl)` a manifest-limit-list delimiter byte? (`,` space `(` `)` tab newline `[` `]`)
## The list dual of `sema::limits_all_known`'s split — a limit NAME is a maximal run of non-delimiters.
d_lim_delim := fn(c : str) -> bool {
  if c == "," { return true }
  if c == " " { return true }
  if c == "(" { return true }
  if c == ")" { return true }
  if c == "\t" { return true }
  if c == "\n" { return true }
  if c == "[" { return true }
  if c == "]" { return true }
  return false
}

## FND-11 — byte-equality of two ABSOLUTE spans (cross-buffer: the manifest ceiling and a module's
## `@limits` list live in DIFFERENT source buffers, so a same-base `streq` can't be used).
d_span_eq := fn(a1 : usize, n1 : usize, a2 : usize, n2 : usize) -> bool {
  if n1 != n2 { return false }
  mut i := 0
  mut ok := true
  while i < n1 { if str_at(a1 + i, 1) != str_at(a2 + i, 1) { ok = false } ; i += 1 }
  ok
}

## FND-11 — does the limit word [wbase+ws, +wl) appear as a WHOLE name in the list [lbase+ls, +ll)?
## Both are delimiter-split into names; a name equals the needle by cross-buffer byte compare.
d_word_in_list := fn(wbase : usize, ws : usize, wl : usize, lbase : usize, ls : usize, ll : usize) -> bool {
  mut i := 0
  mut found := false
  while i < ll {
    if d_lim_delim(str_at(lbase + ls + i, 1)) {
      i += 1
    } else {
      mut j := i
      while j < ll and not d_lim_delim(str_at(lbase + ls + j, 1)) { j += 1 }
      if d_span_eq(lbase + ls + i, j - i, wbase + ws, wl) { found = true }
      i = j
    }
  }
  found
}

## A compact handle to the per-file source table (each file's module-NAME span + its offset span in
## the concatenated source buffer), so a build-time diagnostic can map a global buffer offset back to
## its OWNING file — a FILE-RELATIVE line + the module name — without threading four parallel `Vec`s
## through the helper's parameter list.
DFileTab := struct { ns : ptr(rt::Vec), nl : ptr(rt::Vec), so : ptr(rt::Vec), sl : ptr(rt::Vec), n : usize }
## High-bit diagnostic marker shared with sema::ambiguous_err. It preserves the bootstrap-sensitive
## low-two-bit CheckErr encoding while giving the public check/build renderers one distinct message.
DIAG_AMBIG_MARKER := 4611686018427387904
DIAG_LIMIT_MARKER := 2305843009213693952
## CT-12 / Comptime §2.6 — the COMPTIME guard-failure class (shared with sema::comptime_err). Above
## the ambiguous marker so every pre-existing `CheckErr` value decodes byte-for-byte as before; the
## payload uses eight-byte slots (low three bits = the guard kind, the rest = the source offset).
DIAG_CT_MARKER := 6917529027641081856
## Declarations §3.1 / Memory §1.6 — a write to an existing binding without `mut`. This sits above
## the comptime marker and below 2^63, preserving every older CheckErr range while giving both public
## semantic entry points one stable, located message.
DIAG_IMMUTABLE_MARKER := 8070450532247928832
comptime_guard_name := fn(kind : usize) -> str {
  if kind == 1 { return "comptime overflow" }
  if kind == 2 { return "comptime division by zero" }
  if kind == 3 { return "comptime shift out of range" }
  "comptime guard failure"
}
limit_name := fn(kind : usize) -> str {
  if kind == 1 { return "no_comptime" }
  if kind == 2 { return "no_alloc" }
  if kind == 3 { return "freestanding" }
  if kind == 4 { return "no_unchecked" }
  if kind == 5 { return "no_abstractions" }
  "unknown"
}
d_limit_kind := fn(base : usize, s : usize, n : usize) -> usize {
  w := str_at(base + s, n)
  if w == "no_comptime" { return 1 }
  if w == "no_alloc" { return 2 }
  if w == "freestanding" { return 3 }
  if w == "no_unchecked" { return 4 }
  if w == "no_abstractions" { return 5 }
  0
}

## FND-10/11 build-time limits REJECT (§1 item 6 / §5) — the BUILD-path twin of the `check` decode.
## `code` is a `CheckErr`-encoded reject (kind in the low 2 bits, source START offset in the rest)
## returned by `enforce_declared_limits` / `d_check_limits_ceiling` / `enforce_ceiling`. Print a
## SOURCE-LOCATED message (`<what> at line N in <module>`) to stderr, mapping the offset to its owning
## file exactly as the check path does, then abort fail-loud via `panic` (the build path carries no
## error-return channel — a config error is an I3 abort, not a silent relaxation). DORMANT for the
## self-host build (no `@limits`, empty ceiling) → never called → the TOOL-1 fixpoint is unaffected.
d_limit_reject := fn(code : usize, what : str, base : usize, ft : ptr(DFileTab), in out a : rt::Arena) {
  limit := code >= DIAG_LIMIT_MARKER and code < DIAG_AMBIG_MARKER
  mut span := code / 4
  mut lkind := 0
  if limit {
    raw_limit := code - DIAG_LIMIT_MARKER
    span = raw_limit / 8
    lkind = raw_limit % 8
  }
  mut db := rt::strbuf(a, 256)
  w0 := rt::push_str(db, "alatyr: build: ")
  if limit {
    w1 := rt::push_str(db, "@limits(")
    w2 := rt::push_str(db, limit_name(lkind))
    w3 := rt::push_str(db, ") violation")
  } else {
    w1 := rt::push_str(db, what)
  }
  if span > 0 {
    ## Map the GLOBAL concatenated-buffer offset back to the owning file (`so[k] <= span < so[k]+sl[k]`)
    ## so the line is FILE-relative and the module is named — never a line counted across earlier files.
    mut fk := 0
    mut fbase := 0
    mut fi := 0
    while fi < ft.n {
      fo := rt::vec_get(deref(ft.so), fi)
      fln := rt::vec_get(deref(ft.sl), fi)
      if span >= fo and span < fo + fln { fk = fi; fbase = fo }
      fi += 1
    }
    w4 := rt::push_str(db, " at line ")
    mut line := 1
    srcv := str_at(base, span)
    mut ci := fbase
    while ci < span { if bytes(srcv)[ci] == 10 { line = line + 1 } ; ci = ci + 1 }
    w5 := rt::push_int(db, i64(line))
    win := rt::push_str(db, " in ")
    wm := rt::push_str(db, str_at(base + rt::vec_get(deref(ft.ns), fk), rt::vec_get(deref(ft.nl), fk)))
  }
  w4 := rt::push_byte(db, 10)
  wf := rt::sb_flush(db, 2)
  panic("")
}

## sema-on-build REJECT (§1 item 6 / §5) — the BUILD-path twin of the `check_files` decode. `code` is
## the `CheckErr` verdict returned by `sema::check_program` (kind in the low 2 bits — 1 unbound name,
## 2 type mismatch, 3 duplicate name — the source START offset in the rest, `code / 4`). Print the SAME
## source-LOCATED `alatyr: check: <kind> at line N in <module>` message the `check` subcommand renders,
## mapping the offset to its owning file, then abort fail-loud via `panic` (the build path carries no
## error-return channel — an ill-typed program is an I3 abort before any GAS is emitted). Never fires for
## the self-host build: sema accepts the whole src/ tree → `code == 0` → not called → GAS byte-identical
## → the TOOL-1 fixpoint is unaffected. Modeled on `d_limit_reject` (own StrBuf + `ptr(DFileTab)`), the
## proven-compiling shape — NOT a shared helper over the four raw file Vecs (that form miscompiled here).
d_sema_reject := fn(code : usize, base : usize, ft : ptr(DFileTab), in out a : rt::Arena) {
  limit := code >= DIAG_LIMIT_MARKER and code < DIAG_AMBIG_MARKER
  immutable := code >= DIAG_IMMUTABLE_MARKER
  ctg := code >= DIAG_CT_MARKER and code < DIAG_IMMUTABLE_MARKER
  ambig := code >= DIAG_AMBIG_MARKER and code < DIAG_CT_MARKER
  mut raw := code
  mut kind := 0
  mut span := 0
  if limit {
    raw = code - DIAG_LIMIT_MARKER
    kind = raw % 8
    span = raw / 8
  } else if immutable {
    raw = code - DIAG_IMMUTABLE_MARKER
    span = raw / 4
  } else if ctg {
    raw = code - DIAG_CT_MARKER
    kind = raw % 8
    span = raw / 8
  } else {
    if ambig { raw = code - DIAG_AMBIG_MARKER }
    kind = raw % 4
    span = raw / 4
  }
  mut db := rt::strbuf(a, 256)
  w0 := rt::push_str(db, "alatyr: check: ")
  ## The KIND + SOURCE SPAN are only reliable when the failure propagated through the `CheckErr`
  ## channel (`span > 0`); many checks poison via `mark_failed`, which carries no span, so `code` is
  ## then the default `unbound_err(0,0)` == 1. Print the LOCATED kind + 1-based line only when
  ## `span > 0`; otherwise an honest unlocated message. `span == 0 && kind == 3` is the duplicate case.
  if span > 0 {
    if limit {
      wk0 := rt::push_str(db, "@limits(")
      wk1 := rt::push_str(db, limit_name(kind))
      wk2 := rt::push_str(db, ") violation")
    } else if immutable { wki := rt::push_str(db, "immutable binding") }
    else if ctg { wkc := rt::push_str(db, comptime_guard_name(kind)) }
    else if ambig { wk := rt::push_str(db, "ambiguous call") }
    else if kind == 1 { wk := rt::push_str(db, "unbound name") }
    else if kind == 2 { wk := rt::push_str(db, "type mismatch") }
    else if kind == 3 { wk := rt::push_str(db, "duplicate name") }
    else { wk := rt::push_str(db, "invalid") }
    mut fk := 0
    mut fbase := 0
    mut fi := 0
    while fi < ft.n {
      fo := rt::vec_get(deref(ft.so), fi)
      fln := rt::vec_get(deref(ft.sl), fi)
      if span >= fo and span < fo + fln { fk = fi; fbase = fo }
      fi += 1
    }
    w1 := rt::push_str(db, " at line ")
    mut line := 1
    srcv := str_at(base, span)
    mut ci := fbase
    while ci < span { if bytes(srcv)[ci] == 10 { line = line + 1 } ; ci = ci + 1 }
    w2 := rt::push_int(db, i64(line))
    win := rt::push_str(db, " in ")
    wm := rt::push_str(db, str_at(base + rt::vec_get(deref(ft.ns), fk), rt::vec_get(deref(ft.nl), fk)))
  } else if kind == 3 {
    wd := rt::push_str(db, "duplicate name")
  } else {
    wu := rt::push_str(db, "type error (location not tracked)")
  }
  w4 := rt::push_byte(db, 10)
  wf := rt::sb_flush(db, 2)
  panic("")
}

## FND-11 (Tooling §2.3) — a file's `@limits(…)` may only be STRICTER than the manifest `limits`
## CEILING: every ceiling limit MUST appear in that file's `@limits` list. A module with NO `@limits`
## marker inherits the ceiling (nothing to check). A marker that OMITS a ceiling limit is a laxer-than-
## ceiling contract → reject (the caller aborts fail-loud with a located diagnostic; an I3 config error,
## not a silent relaxation). Returns a `CheckErr`-encoded reject located at the offending marker's limit
## list (`1 + ret_ts * 4`), or 0 when every file conforms. The ceiling lists BARE limit names (as
## `@limits` does). DORMANT when the ceiling is empty — the self-host build's package.al declares no
## `limits`, so no ceiling → this returns 0 at once → GAS byte-identical → the TOOL-1 fixpoint is
## unaffected. The `@limits` marker is a kind-0/arity-99 decl whose `ret` span is its FULL limit list
## (parser); scanned against every such marker in the combined tree.
d_check_limits_ceiling := fn(ceiling : str, decls : ptr(rt::Vec), src : ptr(u8)) -> usize {
  if ceiling.len == 0 { return 0 }
  cbase := unchecked bitcast(usize, ceiling.ptr)
  cnt := rt::vec_len(deref(decls))
  mut ci := 0
  while ci < ceiling.len {
    if d_lim_delim(str_at(cbase + ci, 1)) {
      ci += 1
    } else {
      mut cj := ci
      while cj < ceiling.len and not d_lim_delim(str_at(cbase + cj, 1)) { cj += 1 }
      ## the ceiling name [ci, cj) must be present in EVERY module's @limits marker
      mut k := 0
      while k < cnt {
        d := deref(decl_get(decls, k))
        if d.kind == 0 and d.arity == 99 and d.ret_tl != 0 {
          if not d_word_in_list(cbase, ci, cj - ci, src, d.ret_ts, d.ret_tl) {
            return DIAG_LIMIT_MARKER + d.ret_ts * 8 + d_limit_kind(cbase, ci, cj - ci)
          }
        }
        k += 1
      }
      ci = cj
    }
  }
  0
}

pub compile_files := fn(paths : str, in out a : Arena, entry : str, ceiling : str, spanbase : usize) -> strbuf::StrBuf {
  return compile_files_mode(paths, a, false, entry, ceiling, "", false, spanbase, false)
}

## Library artifact variant of `compile_files`: retain only `pub`/`@export` API roots, omit executable
## wrappers and test declarations, and leave the resulting GAS ready for object/archive assembly.
pub compile_files_library := fn(paths : str, in out a : Arena, ceiling : str) -> strbuf::StrBuf {
  return compile_files_mode(paths, a, false, "", ceiling, "", false, 0, true)
}

## Select the package artifact's front-end roots while keeping the returned GAS shape identical for
## executable callers. Library targets deliberately receive no executable entry symbol or span table;
## object/archive assembly consumes the combined stream directly.
pub compile_files_target := fn(paths : str, in out a : Arena, entry : str, ceiling : str, spanbase : usize, library_mode : bool) -> strbuf::StrBuf {
  if library_mode { return compile_files_library(paths, a, ceiling) }
  return compile_files(paths, a, entry, ceiling, spanbase)
}

## TOOL-6/P3: scalar accessors keep the cli → driver boundary independent of StrBuf copying.
pub interface_summary_ptr := fn() -> usize { ifc::summary_ptr() }
pub interface_summary_len := fn() -> usize { ifc::summary_len() }

## Tooling §2.7 — forward the manifest's selected `build.<name>` facts to the lower's fold globals. A thin
## `cli → driver → lower` hop (the proven adjacency; a direct `cli → lower` call is not resolved by the
## lean module linker). `p`/`n` are the (ptr, len) of the `name=value\n` profile-flag blob.
pub set_build_flags := fn(p : usize, n : usize) -> i64 {
  return lower::set_build_flags(p, n)
}

## Tooling §2.7 / TOOL-17 — forward the selected artifact kind across the qualified child-module
## boundary. `lower.al` is intentionally not part of this seam: ctfold owns the target-kind fact and
## folds it wherever the lower's comptime condition evaluator is reached.
pub set_target_kind := fn(kind : usize) -> i64 {
  return lower::ctfold::set_target_kind(kind)
}

## Tooling §2.7 / TOOL-17 — forward the selected x86 code-size enum as a scalar. Keep this beside
## target.kind; lower::ctfold owns the comptime fact and src/lower.al stays outside this slice.
pub set_target_code_size := fn(code_size : usize) -> i64 {
  return lower::ctfold::set_target_code_size(code_size)
}

## Cross-target `test` is routed through the existing non-x86 multi-file front end. These scalars keep
## the path-list and test selection out of aggregate parameters, which the lean self-host lower does
## not reliably copy across a module boundary.
mut D_RAW_PATHS : usize = 0
mut D_TEST_MODE : usize = 0
mut D_TEST_FILTER_P : usize = 0
mut D_TEST_FILTER_N : usize = 0
mut D_TEST_KEEP : usize = 0
mut D_TEST_ENTRY_P : usize = 0
mut D_TEST_ENTRY_N : usize = 0

pub set_cross_test_filter := fn(p : usize, n : usize) -> i64 {
  D_TEST_FILTER_P = p
  D_TEST_FILTER_N = n
  return 0
}

pub compile_files_cross_test := fn(paths : str, in out a : Arena, backend : usize, keep_going : bool, ceiling : str) -> strbuf::StrBuf {
  ## `test` already ran the canonical x86-shaped check before entering this path. The backend front end
  ## below must receive the package's complete newline-joined module list, not reinterpret that list as
  ## one filesystem path and silently fall back to only the final source file.
  D_RAW_PATHS = 1
  D_TEST_MODE = 1
  D_TEST_KEEP = 0
  if keep_going { D_TEST_KEEP = 1 }
  D_TEST_ENTRY_P = TEST_ENTRY_P
  D_TEST_ENTRY_N = TEST_ENTRY_N
  mut out := d_compile_file_multi(paths, backend)
  D_RAW_PATHS = 0
  D_TEST_MODE = 0
  D_TEST_FILTER_P = 0
  D_TEST_FILTER_N = 0
  D_TEST_KEEP = 0
  D_TEST_ENTRY_P = 0
  D_TEST_ENTRY_N = 0
  out
}

## TOOL-5 — the CLI forwards the optional test description filter as raw pointer/length facts. Keeping
## the boundary scalar avoids the lean lower's fragile aggregate-string copyback across cli → driver.
mut TEST_FILTER_P : usize = 0
mut TEST_FILTER_N : usize = 0
mut TEST_JOBS : usize = 1
mut TEST_KEEP_GOING : usize = 0
## TOOL-7 — the PACKAGE's entry symbol (`Target.entry`, default `_start`) for the current `test`
## invocation, forwarded as scalar (ptr, len) facts for the same reason as the filter. The test
## artifact EXCLUDES the declaration that emits it; empty means the default `_start`.
mut TEST_ENTRY_P : usize = 0
mut TEST_ENTRY_N : usize = 0
pub set_test_entry := fn(p : usize, n : usize) -> i64 {
  TEST_ENTRY_P = p
  TEST_ENTRY_N = n
  return 0
}
pub set_test_filter := fn(p : usize, n : usize) -> i64 {
  TEST_FILTER_P = p
  TEST_FILTER_N = n
  return 0
}
pub set_test_options := fn(jobs : usize, keep_going : bool) -> i64 {
  TEST_JOBS = jobs
  TEST_KEEP_GOING = 0
  if keep_going { TEST_KEEP_GOING = 1 }
  return 0
}

## The `test` path — emit a runner `_start` that calls every `@test` fn (kind 5) in turn and exits
## with the FAILURE COUNT: a test returning `Result(usize, str)` is a pass on the `Ok` tag (0 in
## %rax — the enum tag is word 0 of the register-returned Result), a fail otherwise; `%rbx`
## (callee-saved, preserved across the calls) accumulates failures. (A `@test` should return
## `Result(usize, str)`; a void test's %rax is undefined — TOOL-5 soft-fail form is the supported one.)
## TOOL-7 — in TEST mode the `entry` argument names the PACKAGE's entry symbol, which this artifact
## EXCLUDES (the runner supplies its own `_start`); in build mode the same argument names the entry the
## artifact links WITH. One notion, one parameter.
d_test_entry := fn() -> str {
  mut e := "_start"
  if TEST_ENTRY_N != 0 { e = str_at(unchecked bitcast(ptr(u8), TEST_ENTRY_P), TEST_ENTRY_N) }
  e
}

pub compile_files_test := fn(paths : str, in out a : Arena) -> strbuf::StrBuf {
  filter := str_at(unchecked bitcast(ptr(u8), TEST_FILTER_P), TEST_FILTER_N)
  pkg_entry := d_test_entry()
  return compile_files_mode(paths, a, true, pkg_entry, "", filter, TEST_KEEP_GOING != 0, 0, false)
}

## The `ceiling` is the manifest `limits` list (FND-11), forwarded so a TEST build honours the same ceiling
## `check`/`build`/`run` do. It was hard-coded empty here, so `alatyr test` compiled a package whose module
## declared a laxer `@limits` than the package allows — the one command whose job is to tell you the package
## is sound. Empty for a bare file list, exactly as before.
pub compile_files_test_with_options := fn(paths : str, in out a : Arena, keep_going : bool, ceiling : str) -> strbuf::StrBuf {
  filter := str_at(unchecked bitcast(ptr(u8), TEST_FILTER_P), TEST_FILTER_N)
  pkg_entry := d_test_entry()
  return compile_files_mode(paths, a, true, pkg_entry, ceiling, filter, keep_going, 0, false)
}

test_desc_matches := fn(base : usize, start : usize, len : usize, filter : str) -> bool {
  if filter.len == 0 { return true }
  if filter.len > len { return false }
  mut i := 0
  while i + filter.len <= len {
    if str_eq(str_at(base + start + i, filter.len), filter) { return true }
    i += 1
  }
  return false
}

test_ret_is_result := fn(base : usize, start : usize, len : usize) -> bool {
  if len < 6 { return false }
  return str_at(base + start, 6) == "Result"
}

## Emit a test description as `.byte` data instead of `.ascii`, so quotes, backslashes, and arbitrary
## UTF-8 bytes cannot corrupt the generated GAS string. The returned label is a raw byte span; the
## runner writes exactly `len` bytes to stdout.
emit_test_desc_data := fn(in out gas : strbuf::StrBuf, base : usize, start : usize, len : usize, ti : usize) {
  strbuf::push_str(gas, ".Ltestdesc")
  strbuf::push_int(gas, i64(ti))
  strbuf::push_str(gas, ":\n  .byte ")
  if len == 0 {
    strbuf::push_str(gas, "0\n")
  } else {
    mut i := 0
    while i < len {
      if i != 0 { strbuf::push_str(gas, ", ") }
      strbuf::push_int(gas, i64(bytes(str_at(base + start, len))[i]))
      i += 1
    }
    strbuf::push_byte(gas, 10)
  }
}

## Emit one report line: `test <description>: ok`, `FAIL (soft)`, or `FAIL (trap)`. Raw sys_write calls
## keep the runner independent of the stdlib and preserve the one-process-per-test execution model.
## `kind`: 0 = pass, 1 = Result::Err soft failure, 2 = child trap / abnormal wait status.
emit_test_report := fn(in out gas : strbuf::StrBuf, ti : usize, dlen : usize, kind : u8) {
  strbuf::push_str(gas, "\n  movq $1, %rdi\n  leaq .Ltestprefix(%rip), %rsi\n  movq $5, %rdx\n  movq $1, %rax\n  syscall\n  movq $1, %rdi\n  leaq .Ltestdesc")
  strbuf::push_int(gas, i64(ti))
  strbuf::push_str(gas, "(%rip), %rsi\n  movq $")
  strbuf::push_int(gas, i64(dlen))
  strbuf::push_str(gas, ", %rdx\n  movq $1, %rax\n  syscall\n  movq $1, %rdi\n  leaq .Ltest")
  if kind == 0 { strbuf::push_str(gas, "ok") }
  else if kind == 1 { strbuf::push_str(gas, "soft") }
  else { strbuf::push_str(gas, "trap") }
  strbuf::push_str(gas, "(%rip), %rsi\n  movq $")
  if kind == 0 { strbuf::push_str(gas, "5") } else { strbuf::push_str(gas, "14") }
  strbuf::push_str(gas, ", %rdx\n  movq $1, %rax\n  syscall\n")
}

compile_files_mode := fn(paths : str, in out a : Arena, test_mode : bool, entry : str, ceiling : str, filter : str, keep_going : bool, spanbase : usize, library_mode : bool) -> strbuf::StrBuf {
  ## One rt arena backs the rt::StrBuf source-concat + output buffers AND the token/decl records
  ## (created first; mmap is lazy). This is the TOOL-1 self-compile path — the concatenated `.al`
  ## sources + the whole tree's emitted GAS are large, so size generously.
  mut tar := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(tar, 536870912)
  EMISSION_PATHS_P = 0
  EMISSION_PATHS_N = 0
  mut na := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(na, 536870912)
  ## A SEPARATE arena for the per-module TOKEN records (handles + `{kind,start,len}` records).
  ## Tokens MUST NOT share `tar` with the decls: the self-host lower's in-out `Arena` mutation
  ## through `lexrt::lex_rt` does not propagate `tar.off` past the token records, so when the
  ## parser then `dnode`s a Decl into `tar` it bumps from the stale offset and OVERWRITES the
  ## module's tail token records (the EOF among them → the parser over-runs → "parse error";
  ## found by a gdb hardware-watchpoint: `dnode` clobbered `rt.al`'s `sb_flush` `len` token).
  ## A module's tokens are dead once it is parsed (the AST/Decl records hold SOURCE offsets, not
  ## token indices), so `tokar` is reset to empty per module — bounded, and decls in `tar` can
  ## never collide with tokens in `tokar`.
  mut tokar := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(tokar, 536870912)
  ## `paths` is a NEWLINE-joined list of file paths ("p0\np1\n…") — the lean I/O-boundary form (a
  ## file path has no embedded newline; no `alloc::vec(str)`, which the self-host lower cannot
  ## compile). Scan it into an rt `str`-vector `pv` (2-word {ptr,len} records) for random access by
  ## module index, exactly as the old `Vec(str)` param provided. Empty segments are skipped.
  pbase := unchecked bitcast(usize, paths.ptr)
  mut pv := rt::Vec(data = rt::bump(tar, 256 * 8), len = 0, cap = 256)
  ## Put the anonymous package root FIRST.  The final module in `pv` remains the package entry
  ## module, as required by the existing build/link convention.
  manifest := d_manifest_path(tar)
  ## Reset manifest state before this front-end invocation; run/check can share the same driver process
  ## and a previous package must not leave TOOL-15 ownership or sema package-boundary facts live.
  MANIFEST_HAS = false
  if manifest.len != 0 { mh := rt::svec_str_push(pv, tar, manifest) }
  mut si := 0
  mut seg := 0
  while si <= paths.len {
    mut isnl := true
    if si < paths.len { isnl = bytes(paths)[si] == 10 }
    if isnl {
      if si > seg {
        pp := str_at(pbase + seg, si - seg)
        if manifest.len == 0 or not d_is_root_path(pp) { ph := rt::svec_str_push(pv, tar, pp) }
      }
      seg = si + 1
    }
    si += 1
  }
  if d_manifest_has_base_process(pv) == false {
    root_process := d_manifest_root_process(tar, manifest)
    if root_process.len != 0 and d_manifest_has_base_process(pv) == false { rp := rt::svec_str_push(pv, tar, root_process) }
  }
  n := rt::vec_len(pv)
  mut bld := strbuf::strbuf(tar, 16777216)
  mut name_start := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  mut name_len := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  mut src_off := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  mut src_len := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  ## --- append all module NAMES (filename stems) first ---
  ## `root_k` = the index of the package-ROOT module (`package.al`) if one is being compiled, else
  ## `n` (the "none" sentinel). Manifest §6 / Modules §6.1: that module is ANONYMOUS and its
  ## declarations emit UNPREFIXED; `lower::set_root_module` below publishes its name span so every
  ## mangling site can recognise it. A multi-module package never compiles its `package.al`, so
  ## `root_k == n` for the compiler's own build → nothing published → emission byte-identical.
  mut root_k := n
  mut k := 0
  while k < n {
    p := rt::svec_str_get(pv, k)
    if d_is_root_path(p) { root_k = k }
    rt::vec_push(name_start, strbuf::buf_len(bld))
    before := strbuf::buf_len(bld)
    push_module_name(bld, p)                 ## stem, OR a `/lib/` path's mangled name (std__io)
    rt::vec_push(name_len, strbuf::buf_len(bld) - before)
    k += 1
  }
  ## --- then append all module SOURCES, read off disk into the shared buffer ---
  k = 0
  while k < n {
    p := rt::svec_str_get(pv, k)
    rt::vec_push(src_off, strbuf::buf_len(bld))
    nread := read_file_into(bld, tar, p)
    rt::vec_push(src_len, nread)
    k += 1
  }
  ## TOOL-15: package.al is parsed as the anonymous root, but its configuration binding is replaced
  ## by the private synthetic declarations below.  Recover the manifest's source region from the
  ## root entry in `pv`; its real spans keep diagnostics and the field rewrite source-located.
  mut manifest_off := 0
  mut manifest_len := 0
  if manifest.len != 0 and root_k < n {
    manifest_off = rt::vec_get(src_off, root_k)
    manifest_len = rt::vec_get(src_len, root_k)
  }
  base := unchecked bitcast(usize, strbuf::strbuf_base(bld))
  if manifest_len != 0 {
    d_manifest_scan(str_at(base + manifest_off, manifest_len), manifest_off)
    if MANIFEST_HAS {
      if MANIFEST_BIND_PUB {
        d_manifest_pub_diag(tar, manifest)
        panic("")
      }
      if d_manifest_find_child(pv) {
        d_manifest_duplicate_diag(tar, manifest)
        panic("")
      }
      d_manifest_type_source(bld, n)
    }
  }
  ## Publish the ANONYMOUS package-ROOT module to the lower (Modules §6.1 / Manifest §6) — its
  ## declarations emit UNPREFIXED linker symbols. Always published, `0/0` when there is no root file
  ## in the compile list, so the setting can never leak in from an earlier compile in this process.
  if root_k < n {
    krs := lower::set_root_module(rt::vec_get(name_start, root_k), rt::vec_get(name_len, root_k))
  } else {
    krn := lower::set_root_module(0, 0)
  }
  ## --- lex + parse each module's region into ONE rt Decl-handle Vec, threading nstr (all token
  ## records + the shared decls handle Vec + records live in `tar`, created above). ---
  ## Caps reserved from source size (rt::vec_push does not grow): decls ≤ total tokens ≤ total
  ## buffer bytes; per-file tokens ≤ that file's `slen`. (+16 = EOF token + slack.)
  dcap := strbuf::buf_len(bld) + n * 8 + 64
  mut decls := rt::Vec(data = rt::bump(tar, dcap * 8), len = 0, cap = dcap)
  ## The enum-type-NAME table (packed (name_start, name_len) pairs, spans into `base`) — filled in
  ## PASS 1 and consulted in PASS 2 so the generic-enum-ctor rewrite fires only for real enum types
  ## (module order is getdents, so all modules must be parsed before the enum-ctor-vs-UFCS decisions
  ## are sound). PASS 1 runs with a NULL table (→ the parser's old always-fire behavior; enum DECLS
  ## parse fine regardless, and only enum-ctor USES are affected, which don't change collection).
  mut ev := rt::Vec(data = rt::bump(tar, dcap * 16), len = 0, cap = dcap * 2)
  mut sv := rt::Vec(data = rt::bump(tar, dcap * 32), len = 0, cap = dcap * 4)
  parser::set_structs_tbl(0)
  mut nstr := 0
  ## --- PASS 1: parse to discover enum-type names (results otherwise discarded) ---
  k = 0
  while k < n {
    soff := rt::vec_get(src_off, k)
    slen := rt::vec_get(src_len, k)
    tcap := slen + 16
    tokar.off = 0
    mut rt_toks := rt::Vec(data = rt::bump(tokar, tcap * 8), len = 0, cap = tcap)
    zt := lexrt::lex_rt(str_at(base + soff, slen), soff, rt_toks, tokar)
    mut pc := PC(toks = ptr(rt_toks), src = base, idx = 0, arena = ptr(na), nstr = nstr, mod_s = rt::vec_get(name_start, k), mod_l = rt::vec_get(name_len, k), enums = unchecked bitcast(ptr(rt::Vec), 0))
    ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
    ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
    ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
    parser::set_module_base(soff)
    pr := parser::parse_program(pc, decls, tar)
    match pr { Result::Ok(c) => {}; Result::Err(e) => { pek := d_perr_kind(e) ; pmns := rt::vec_get(name_start, k) ; pmnl := rt::vec_get(name_len, k) ; d_parse_reject(pc, pek, soff, slen, pmns, pmnl, tar) } }
    nstr = pc.nstr
    k += 1
  }
  ## collect kind-3 (enum-type) decl names into `ev`; then reset the AST arena + decls + nstr for pass 2
  dcnt1 := rt::vec_len(decls)
  mut di := 0
  while di < dcnt1 {
    d := deref(decl_at(Decl, rt::vec_get(decls, di)))
    if d.kind == 3 { rt::vec_push(ev, d.name_start); rt::vec_push(ev, d.name_len) }
    di += 1
  }
  collect_enum_aliases(decls, base, ev)
  collect_struct_table(decls, base, sv)         ## by-name struct-literal reorder table (TYP-8)
  parser::set_structs_tbl(unchecked bitcast(usize, ptr(sv)))
  na.off = 0
  decls.len = 0
  nstr = 0
  ## --- PASS 2: re-parse with the enum-name table (the AST/decls used for emit) ---
  k = 0
  while k < n {
    soff := rt::vec_get(src_off, k)
    slen := rt::vec_get(src_len, k)
    tcap := slen + 16
    tokar.off = 0                              ## reuse `tokar` for THIS module's tokens (prev module's are dead)
    mut rt_toks := rt::Vec(data = rt::bump(tokar, tcap * 8), len = 0, cap = tcap)
    zt := lexrt::lex_rt(str_at(base + soff, slen), soff, rt_toks, tokar)
    mut pc := PC(toks = ptr(rt_toks), src = base, idx = 0, arena = ptr(na), nstr = nstr, mod_s = rt::vec_get(name_start, k), mod_l = rt::vec_get(name_len, k), enums = ptr(ev))
    ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
    ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
    ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
    parser::set_module_base(soff)
    pr := parser::parse_program(pc, decls, tar)
    match pr { Result::Ok(c) => {}; Result::Err(e) => { pek := d_perr_kind(e) ; pmns := rt::vec_get(name_start, k) ; pmnl := rt::vec_get(name_len, k) ; d_parse_reject(pc, pek, soff, slen, pmns, pmnl, tar) } }
    nstr = pc.nstr
    k += 1
  }
  if root_k < n { d_manifest_drop_root_decl(decls, rt::vec_get(name_start, root_k), rt::vec_get(name_len, root_k)) }
  d_lift_lambdas(decls, ptr(na), ptr(tar), base)
  d_manifest_module_decls(pv, name_start, name_len, decls, na, tar, nstr)
  d_manifest_rewrite_decls(decls, pv, name_start, name_len, base, nstr, ptr(na))
  ## TOOL-6 — lower groups the final declaration vector, including manifest/synthetic declarations, by
  ## module-name run. Publish that exact run-to-file mapping before any emission so the split linker and
  ## its manifest can name every span independently of the original CLI path order.
  emission_paths := d_emission_paths(decls, pv, name_start, name_len, base, tar)
  EMISSION_PATHS_P = unchecked bitcast(usize, emission_paths.ptr)
  EMISSION_PATHS_N = emission_paths.len
  d_manifest_set_sema_modules(pv, name_start, name_len, tar)
  ## FND-10/11 build-time limits: first enforce each file's declared `@limits`, then validate/enforce any
  ## manifest ceiling. This is limits-only parity with `check`, not the full type-checker, so build rejects
  ## contract violations without depending on unrelated check-only gaps in the self-host tree.
  mut ftab := DFileTab(ns = ptr(name_start), nl = ptr(name_len), so = ptr(src_off), sl = ptr(src_len), n = n)
  ## sema-on-build (PHASE B): run the canonical type-checker over the already-parsed tree BEFORE any GAS
  ## is emitted, so an ill-typed program is rejected at BUILD (not silently compiled) with the same
  ## source-LOCATED diagnostic the `check` subcommand prints. Reuses these decls (parsed once above) — no
  ## re-parse. sema accepts the whole self-host src/ tree, so this returns 0 for the TOOL-1 self-build →
  ## identical emission → GAS byte-identical → fixpoint unaffected; the emit-site aggregate→scalar
  ## fail-loud nets are RETAINED (sema does not yet reject those sinks). `d_sema_reject` aborts fail-loud.
  scode := sema::check_program(ptr(decls), base, ptr(na))
  if scode != 0 { d_sema_reject(scode, base, ptr(ftab), tar) }
  dlc := sema::enforce_declared_limits(ptr(decls), base, ptr(na))
  if dlc != 0 { d_limit_reject(dlc, "a module violates its declared @limits / @export contract", base, ptr(ftab), tar) }
  cc := d_check_limits_ceiling(ceiling, ptr(decls), base)
  if cc != 0 { d_limit_reject(cc, "a file's @limits is laxer than the manifest limits ceiling", base, ptr(ftab), tar) }
  ec := sema::enforce_ceiling(ptr(decls), base, ptr(na), ceiling)
  if ec != 0 { d_limit_reject(ec, "a module violates a manifest limits ceiling restriction", base, ptr(ftab), tar) }
  if d_check_linker_symbols(ptr(decls), base) {
    panic("selfhost: duplicate linker symbol")
  }
  ## Modules §6.1 — a root-level (unprefixed) declaration must not collide with a submodule's mangled
  ## symbol. Never fires without a package-root module in the compile list → dormant for the self-build.
  rsc := d_root_symbol_clash(ptr(decls), base)
  if rsc != 0 { d_limit_reject(rsc, "a root-level declaration collides with a module's mangled symbol", base, ptr(ftab), tar) }
  ## §8 `@repr(T)` representability: reject a non-integer / too-narrow enum tag type (spec Types §8)
  ## fail-loud before emission. No `@repr` in the corpus → never fires for the self-host build.
  lower::validate_repr(ptr(decls), base)
  ## TOOL-7 — the artifact `alatyr test` builds is a SEPARATE artifact whose entry point is the RUNNER's,
  ## so the package's own entry is NOT linked into it: drop every declaration that emits the entry symbol
  ## (`entry` here = the manifest `Target.entry`, default `_start` — the same notion the build path links
  ## the executable with) from THIS artifact's declaration set. Dropping the DECLARATION, not renaming the
  ## symbol (a hidden rewrite would break a freestanding program's own linker script — I3), keeps the DCE
  ## roots, the `__test<i>` ordinals and the emission in agreement: the entry simply is not part of this
  ## artifact. Everything else stays unprivileged — `main` is an ordinary fn, reached or not by a test.
  ## Mirrors `build`/`run` dropping the `@test` items (TOOL-5): neither artifact is the other with
  ## additions. The checks above ran on the FULL declaration set, so an ill-typed entry is still rejected
  ## under `test`; and `test_mode` is never the self-host build path → the TOOL-1 fixpoint is unaffected.
  if test_mode {
    dcnt_e := rt::vec_len(decls)
    mut kept := 0
    mut ei := 0
    while ei < dcnt_e {
      dh := rt::vec_get(decls, ei)
      de := deref(decl_at(Decl, dh))
      if d_emits_entry(base, de, entry) == false {
        rt::rec_set(decls.data, kept, dh)
        kept += 1
      }
      ei += 1
    }
    decls.len = kept
  }
  ## --- emit the runnable program (bld stays alive: emit reads spans off its base) ---
  ## The ELF entry `_start` calls the program's entry fn `<entry-module>__main`. The entry module
  ## is the LAST module in the list (the documented convention — `main.al` is passed last), so the
  ## fixpoint set (…, cli, main) keeps `main__main`. Spelling it from the last module's name (rather
  ## than a hardcoded `main__main`) makes a SINGLE-FILE build work: `<prog> foo.al` → `foo__main`.
  mut gas := strbuf::strbuf(tar, 67108864)
  if test_mode {
    ## TEST runner: `_start` schedules each selected `@test` fn (kind 5, emitted under `__test<i>` by
    ## the lower) in a separate child process. The parent keeps at most TEST_JOBS children alive, waits
    ## for any child with wait4(-1), records each result by deterministic test ordinal, then prints the
    ## reports in source order after the runnable set drains. Fail-fast (`-k` absent) stops LAUNCHING new
    ## tests after the first observed failure but still waits for children already in flight, so no child
    ## is abandoned and failure counting remains exact for all launched tests.
    strbuf::push_str(gas, ".section .rodata\n.Ltestprefix: .byte 116, 101, 115, 116, 32\n.Ltestok: .byte 58, 32, 111, 107, 10\n.Ltestsoft: .byte 58, 32, 70, 65, 73, 76, 32, 40, 115, 111, 102, 116, 41, 10\n.Ltesttrap: .byte 58, 32, 70, 65, 73, 76, 32, 40, 116, 114, 97, 112, 41, 10\n")
    ddata := rt::vec_len(decls)
    mut selected_count := 0
    mut dii := 0
    while dii < ddata {
      dhh := rt::vec_get(decls, dii)
      ddd := deref(decl_at(Decl, dhh))
      if ddd.kind == 5 and test_desc_matches(base, ddd.name_start, ddd.name_len, filter) {
        emit_test_desc_data(gas, base, ddd.name_start, ddd.name_len, dii)
        selected_count += 1
      }
      dii += 1
    }
    frame_size := selected_count * 16 + 16
    status_off := selected_count * 16
    pid_off := selected_count * 8
    mut jobs := TEST_JOBS
    if jobs == 0 { jobs = 1 }
    strbuf::push_str(gas, ".text\n.global _start\n_start:\n  xorq %rbx, %rbx\n  xorq %r13, %r13\n  xorq %r14, %r14\n  xorq %r15, %r15\n  subq $")
    strbuf::push_int(gas, i64(frame_size))
    strbuf::push_str(gas, ", %rsp\n  movq %rsp, %r12\n.Ltestfill:\n  cmpq $")
    strbuf::push_int(gas, i64(selected_count))
    strbuf::push_str(gas, ", %r13\n  jge .Ltestdrain\n  cmpq $0, %r15\n  jne .Ltestdrain\n  cmpq $")
    strbuf::push_int(gas, i64(jobs))
    strbuf::push_str(gas, ", %r14\n  jge .Ltestwait\n  jmp .Ltestdispatch\n.Ltestafterspawn:\n  incq %r13\n  incq %r14\n  jmp .Ltestfill\n.Ltestdrain:\n  cmpq $0, %r14\n  je .Ltestreports\n.Ltestwait:\n  movq $-1, %rdi\n  leaq ")
    strbuf::push_int(gas, i64(status_off))
    strbuf::push_str(gas, "(%r12), %rsi\n  xorq %rdx, %rdx\n  xorq %r10, %r10\n  movq $61, %rax\n  syscall\n  cmpq $0, %rax\n  jl .Ltestwaiterr\n  movq %rax, %r11\n  decq %r14\n  xorq %rcx, %rcx\n.Ltestfindpid:\n  cmpq %r13, %rcx\n  jge .Ltestfill\n  movq ")
    strbuf::push_int(gas, i64(pid_off))
    strbuf::push_str(gas, "(%r12,%rcx,8), %rax\n  cmpq %r11, %rax\n  je .Ltestfoundpid\n  incq %rcx\n  jmp .Ltestfindpid\n.Ltestfoundpid:\n  movq ")
    strbuf::push_int(gas, i64(status_off))
    strbuf::push_str(gas, "(%r12), %rax\n  testq $127, %rax\n  jne .Ltestwaittrap\n  shrq $8, %rax\n  andq $255, %rax\n  cmpq $0, %rax\n  je .Ltestwaitpass\n  jmp .Ltestclassnz\n.Ltestwaitpass:\n  movq $0, (%r12,%rcx,8)\n  jmp .Ltestfill\n.Ltestwaittrap:\n  movq $2, %rdx\n  jmp .Ltestwaitfail\n.Ltestwaitfail:\n  movq %rdx, (%r12,%rcx,8)\n  incq %rbx\n")
    if keep_going { } else { strbuf::push_str(gas, "  movq $1, %r15\n") }
    strbuf::push_str(gas, "  jmp .Ltestfill\n.Ltestwaiterr:\n  incq %rbx\n  xorq %r14, %r14\n  movq $1, %r15\n  jmp .Ltestreports\n.Ltestclassnz:\n")
    dcnt := rt::vec_len(decls)
    mut ti := 0
    mut ord := 0
    while ti < dcnt {
      hh := rt::vec_get(decls, ti)
      dd := deref(decl_at(Decl, hh))
      if dd.kind == 5 and test_desc_matches(base, dd.name_start, dd.name_len, filter) {
        strbuf::push_str(gas, "  cmpq $")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, ", %rcx\n  je .Ltestnz")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_byte(gas, 10)
        ord += 1
      }
      ti += 1
    }
    strbuf::push_str(gas, "  movq $2, %rdx\n  jmp .Ltestwaitfail\n")
    ti = 0
    ord = 0
    while ti < dcnt {
      hh2 := rt::vec_get(decls, ti)
      dd2 := deref(decl_at(Decl, hh2))
      if dd2.kind == 5 and test_desc_matches(base, dd2.name_start, dd2.name_len, filter) {
        strbuf::push_str(gas, ".Ltestnz")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, ":\n")
        if dd2.ret_tl != 0 and test_ret_is_result(base, dd2.ret_ts, dd2.ret_tl) { strbuf::push_str(gas, "  movq $1, %rdx\n") }
        else { strbuf::push_str(gas, "  movq $2, %rdx\n") }
        strbuf::push_str(gas, "  jmp .Ltestwaitfail\n")
        ord += 1
      }
      ti += 1
    }
    strbuf::push_str(gas, ".Ltestdispatch:\n")
    ti = 0
    ord = 0
    while ti < dcnt {
      hh3 := rt::vec_get(decls, ti)
      dd3 := deref(decl_at(Decl, hh3))
      if dd3.kind == 5 and test_desc_matches(base, dd3.name_start, dd3.name_len, filter) {
        strbuf::push_str(gas, "  cmpq $")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, ", %r13\n  je .Ltestspawn")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_byte(gas, 10)
        ord += 1
      }
      ti += 1
    }
    strbuf::push_str(gas, "  jmp .Ltestdrain\n")
    ti = 0
    ord = 0
    while ti < dcnt {
      hh4 := rt::vec_get(decls, ti)
      dd4 := deref(decl_at(Decl, hh4))
      if dd4.kind == 5 and test_desc_matches(base, dd4.name_start, dd4.name_len, filter) {
        strbuf::push_str(gas, ".Ltestspawn")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, ":\n  movq $57, %rax\n  syscall\n  cmpq $0, %rax\n  je .Ltestchild")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, "\n  js .Ltestforkfail")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, "\n  movq %rax, ")
        strbuf::push_int(gas, i64(pid_off + ord * 8))
        strbuf::push_str(gas, "(%r12)\n  jmp .Ltestafterspawn\n.Ltestforkfail")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, ":\n  movq $2, ")
        strbuf::push_int(gas, i64(ord * 8))
        strbuf::push_str(gas, "(%r12)\n  incq %rbx\n")
        if keep_going { } else { strbuf::push_str(gas, "  movq $1, %r15\n") }
        strbuf::push_str(gas, "  incq %r13\n  jmp .Ltestfill\n.Ltestchild")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, ":\n  call __test")
        strbuf::push_int(gas, i64(ti))
        if dd4.ret_tl != 0 and test_ret_is_result(base, dd4.ret_ts, dd4.ret_tl) {
          strbuf::push_str(gas, "\n  cmpq $0, %rax\n  je .Ltx")
          strbuf::push_int(gas, i64(ord))
          strbuf::push_str(gas, "\n  movq $1, %rdi\n  jmp .Lte")
          strbuf::push_int(gas, i64(ord))
          strbuf::push_str(gas, "\n.Ltx")
          strbuf::push_int(gas, i64(ord))
          strbuf::push_str(gas, ":\n  xorq %rdi, %rdi\n.Lte")
          strbuf::push_int(gas, i64(ord))
          strbuf::push_str(gas, ":\n  movq $60, %rax\n  syscall\n")
        } else {
          ## Void tests pass if the call returns normally. Any trap never reaches this exit.
          strbuf::push_str(gas, "\n  xorq %rdi, %rdi\n  movq $60, %rax\n  syscall\n")
        }
        ord += 1
      }
      ti += 1
    }
    strbuf::push_str(gas, ".Ltestreports:\n")
    ti = 0
    ord = 0
    while ti < dcnt {
      hh5 := rt::vec_get(decls, ti)
      dd5 := deref(decl_at(Decl, hh5))
      if dd5.kind == 5 and test_desc_matches(base, dd5.name_start, dd5.name_len, filter) {
        strbuf::push_str(gas, "  cmpq $")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, ", %r13\n  jle .Ltestreportnext")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, "\n  movq ")
        strbuf::push_int(gas, i64(ord * 8))
        strbuf::push_str(gas, "(%r12), %rax\n  cmpq $0, %rax\n  je .Ltestreportok")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, "\n  cmpq $1, %rax\n  je .Ltestreportsoft")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, "\n  jmp .Ltestreporttrap")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, "\n.Ltestreportok")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, ":\n")
        emit_test_report(gas, ti, dd5.name_len, 0)
        strbuf::push_str(gas, "  jmp .Ltestreportnext")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, "\n.Ltestreportsoft")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, ":\n")
        emit_test_report(gas, ti, dd5.name_len, 1)
        strbuf::push_str(gas, "  jmp .Ltestreportnext")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, "\n.Ltestreporttrap")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, ":\n")
        emit_test_report(gas, ti, dd5.name_len, 2)
        strbuf::push_str(gas, ".Ltestreportnext")
        strbuf::push_int(gas, i64(ord))
        strbuf::push_str(gas, ":\n")
        ord += 1
      }
      ti += 1
    }
    strbuf::push_str(gas, "  movq %rbx, %rdi\n  movq $60, %rax\n  syscall\n")
  } else {
    ## Compatibility wrapper for the DEFAULT ELF entry only. A manifest custom `Target.entry` is a
    ## linker symbol chosen by the package author; the compiler must not invent a body for it. Such a
    ## symbol can be supplied by source with `@export("<entry>")` (or by future artifact forms) and
    ## `cli::link_exe` selects it with `ld -e <entry>`. For `_start`, preserve the existing
    ## `<module>__main` wrapper when the program has not defined its own `_start`; the self-host build
    ## depends on that compatibility path because `package.al` is a manifest, not a compiled module.
    if entry == "_start" and library_mode == false and d_has_start(decls, base) == false {
      strbuf::push_str(gas, ".global ")
      strbuf::push_str(gas, entry)
      strbuf::push_str(gas, "\n")
      strbuf::push_str(gas, entry)
      strbuf::push_str(gas, ":\n  call ")
      if n > 0 {
        mut es := rt::vec_get(name_start, n - 1)
        mut el := rt::vec_get(name_len, n - 1)
        mut mi := 0
        while mi < n {
          ms := rt::vec_get(name_start, mi)
          ml := rt::vec_get(name_len, mi)
          if str_at(base + ms, ml) == "main" { es = ms; el = ml }
          mi += 1
        }
        ## Modules §6.1 / Manifest §6 — when the entry module is the ANONYMOUS package root (a
        ## single-file package, `main` declared in `package.al`), its `main` is a ROOT-LEVEL
        ## declaration and emits UNPREFIXED. The wrapper must then call `main`, not the
        ## `package__main` nothing defines. Non-root modules keep the `<module>__main` form.
        if lower::is_root_mod(es, el) == false {
          em := str_at(base + es, el)
          strbuf::push_str(gas, em)
          strbuf::push_str(gas, "__")
        }
      } else {
        strbuf::push_str(gas, "main__")
      }
      strbuf::push_str(gas, "main\n  movq %rax, %rdi\n  movq $60, %rax\n  syscall\n")
    }
  }
  ## TOOL-6/P3: build the deterministic exported interface/layout sidecar only for split builds.
  ## Ordinary compiler output remains byte-for-byte unchanged; the sidecar is output-neutral
  ## substrate for the future interface-aware emit cache.
  if spanbase != 0 {
    mut ib := strbuf::strbuf(tar, 16777216)
    ir := ifc::emit_interface_summary(ptr(decls), base, ptr(ib), tar)
    if ir != 0 { panic("selfhost: interface summary failed") }
  }
  ## the GLOBAL label counter for one program emission — a scalar `in out` threaded through the
  ## whole emit recursion (lower::emit_program → emit_fn → emit_gas/…), so labels never collide
  ## across functions. (Idiomatic form, exercising the scalar out-param ABI; was a `StrBuf.lbl`
  ## field workaround while scalar `in out` write-back was unimplemented.)
  mut nl := 0
  lower::emit_program(ptr(decls), gas, base, ptr(na), na, nl, spanbase, library_mode)
  ## TOOL-6 1c-γ: when a span buffer was supplied (the build path), peephole PER SPAN and rewrite the
  ## table to post-peephole offsets so `cli::link_exe` can split the final `.s` into per-module `.o`.
  ## The dump/test paths pass `spanbase == 0` → the plain whole-buffer peephole (byte-identical result).
  if spanbase != 0 {
    gas = lower::peephole_and_respan(ptr(gas), spanbase, tar)
  } else {
    gas = lower::peephole_gas(ptr(gas), tar)
  }
  ## The file-table vectors + buffers live in the rt arena `tar`, reclaimed in bulk at exit.
  gas
}

## ---------------------------------------------------------------------------------------------
## QUALIFIED-CALLEE NORMALIZATION (for the module-unaware backends).
## ---------------------------------------------------------------------------------------------
## `lower.al` resolves a `::`-qualified callee at emit time (`colon_pos` + `mod_head_matches`) and
## mangles the label to `<module>__<fn>`. The aarch64 / riscv64 / wat backends are MODULE-UNAWARE —
## they compare a call's callee span byte-for-byte against `d.name_start/d.name_len` and emit the bare
## name as the branch target — so a call written `std::math::sqrt(x)` or `mm::sqrt(x)` matches NO decl
## even when `lib/std/math.al` is right there in `decls`, and the backend emits its "undefined/builtin
## callee" trap. Merely feeding those backends the multi-module `decls` is therefore INERT on its own.
##
## This pass closes that gap in the FRONT END rather than in three backends: for every call with a
## `::` in its callee span, resolve the target decl the way the lowerer does, then REWRITE the call's
## callee span in place to that decl's own NAME span. After it, a module-unaware `streq` against
## `d.name_start/d.name_len` succeeds and the bare `bl <name>` / `call $<name>` label is exactly the
## label the backend emits for the definition.
##
## Only calls that TODAY reach the backend's undefined-callee trap are touched: a bare callee has no
## `::` and is skipped, and an unresolvable qualified callee (an unknown head — `mem::…`, or an alias
## the calling module does not declare, or a leaf no decl defines) is LEFT ALONE, so it keeps trapping.
## The pass runs ONLY from `d_compile_file_multi`; the x86 path is untouched.
##
## KNOWN LIMIT (reported, not worked around): the backends' label space is the BARE decl name, so two
## modules that each define `f` collide at the assembler. Resolution here is exact (module-head aware),
## but the emitted label is still bare — the backends need real `<module>__<fn>` mangling before a
## program can pull two same-named lib functions.

## Whether the declaration at `name_s` carries the source-level `pub` prefix. The parser consumes
## visibility without growing Decl, so this narrow resolver recovers it from the declaration spelling.
d_alias_decl_is_pub := fn(src : ptr(u8), name_s : usize) -> bool {
  mut p := name_s
  while p > 0 {
    c := str_at((src + p - 1), 1)
    if c == " " or c == "\n" or c == "\t" or c == "\r" { p = p - 1 } else { break }
  }
  if p < 3 or str_at((src + p - 3), 3) != "pub" { return false }
  if p >= 4 {
    c := str_at((src + p - 4), 1)
    if c != " " and c != "\n" and c != "\t" and c != "\r" { return false }
  }
  true
}

## Resolve exactly ONE module-valued re-export in a qualified head. For
## `facade::math::floor`, the head is `facade::math`; this finds `math := std::math` in the
## `facade` module, requires that binding to be `pub`, and returns its RHS module path. A nested
## owner and a second alias hop are deliberately not followed: this helper is bounded and
## non-recursive, so cycles cannot turn name resolution into an unbounded walk.
d_one_reexport_module := fn(src : ptr(u8), hs : usize, hl : usize, decls : rt::Vec) -> CSpan {
  cp := d_colon_pos(src, hs, hl)
  if cp < 0 { return CSpan(s = 0, n = 0) }
  owner_len := usize(cp)
  if d_colon_pos(src, hs, owner_len) >= 0 { return CSpan(s = 0, n = 0) }
  owner_s := hs
  alias_s := hs + owner_len + 2
  alias_l := hl - owner_len - 2
  if alias_l == 0 { return CSpan(s = 0, n = 0) }
  mut i := 0
  while i < rt::vec_len(decls) {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.ret_tl != 0
       and d.name_len == alias_l and streq(src, d.name_start, d.name_len, alias_s, alias_l)
       and d_mod_seg_eq(src, d.mod_start, d.mod_len, owner_s, owner_len)
       and d_alias_decl_is_pub(src, d.name_start) {
      return CSpan(s = d.ret_ts, n = d.ret_tl)
    }
    i += 1
  }
  CSpan(s = 0, n = 0)
}

## The decl index + 1 of the fn a QUALIFIED callee span `[cs,cl)` names, as seen from the module
## `[ms,ml)` that contains the call — else 0. Three bounded forms resolve:
##   • FULL path (`alloc::vec::push`) — `d_find_fn_decl` already matches tail-name + mangled module head.
##   • module ALIAS (`mm := std::math` then `mm::sqrt`) — the single-segment head is looked up among the
##     CALLING module's own alias decls (parser: a module alias is a kind-0/arity-0 decl whose `ret`
##     span holds the RHS PATH, `std::math`, and whose value is the `Num(0)` placeholder); that path is
##     the effective head, matched against the target decl's mangled module (`std__math`) by
##     `d_mod_seg_eq`.
##   • one PUB re-export (`facade::math::floor`) — the multi-segment head resolves its final `math`
##     binding in `facade` through the one-hop helper above, then uses the same declaration scan.
## An unknown head resolves to 0 (so `mem::…` and friends are never diverted).
d_qual_target := fn(cs : usize, cl : usize, ms : usize, ml : usize, decls : rt::Vec, src : ptr(u8)) -> usize {
  cp := d_colon_pos(src, cs, cl)
  if cp < 0 { return 0 }
  direct := d_find_fn_decl(cs, cl, decls, src)
  if direct != 0 { return direct }
  hl := usize(cp)                    ## module-head length (source form)
  ts := cs + hl + 2                  ## tail fn-name span (past the `::`)
  tl := cl - hl - 2
  if tl == 0 { return 0 }
  cnt := rt::vec_len(decls)
  mut ehs := 0
  mut ehn := 0
  mut i := 0
  if d_colon_pos(src, cs, hl) >= 0 {
    ## Exactly one facade re-export: `facade::math::floor` → RHS `std::math`.
    one := d_one_reexport_module(src, cs, hl, decls)
    if one.n == 0 { return 0 }
    ehs = one.s
    ehn = one.n
  } else {
    ## A single-segment head is a local alias (`mm := std::math`), looked up only in the
    ## calling module. Unlike the re-export branch, this is not a public-surface lookup.
    while i < cnt {
      d := deref(decl_at(Decl, rt::vec_get(decls, i)))
      if d.is_fn == false and d.kind == 0 and d.arity == 0 and d.ret_tl != 0 and d.name_len == hl {
        if str_at((src + d.name_start), d.name_len) == str_at((src + cs), hl) {
          if d_mod_seg_eq(src, d.mod_start, d.mod_len, ms, ml) { ehs = d.ret_ts ; ehn = d.ret_tl }
        }
      }
      i += 1
    }
  }
  if ehn == 0 { return 0 }
  mut r := 0
  i = 0
  while i < cnt {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if d.is_fn and d.name_len != 0 {
      if str_at((src + d.name_start), d.name_len) == str_at((src + ts), tl) {
        if d_mod_seg_eq(src, d.mod_start, d.mod_len, ehs, ehn) { r = i + 1 }
      }
    }
    i += 1
  }
  r
}

## GENERIC GATE (bounded, target-specific). A resolved injected generic is still reported as
## UNRESOLVED unless it is the one AArch64 slice whose end-to-end evidence is green. This keeps all
## other generic library entry points fail-loud while the backend mono path is completed incrementally.
## The accepted slice is `base::slice::sort`: its scalar `Slice(T)` argument and same-module helper
## closure are handled by aarch64. `sort_by`, other injected generic entry points, and RV64 remain
## gated until they have their own reproducer and evidence.
mut D_BACKEND := 0
## The entry module's mangled-name span. RV64/WAT keep generic bare callees inside this module only;
## AArch64 switches to the caller-module span for the one permitted injected mono closure.
mut D_EMS : usize = 0
mut D_EML : usize = 0
d_qual_target_ok := fn(cs : usize, cl : usize, ms : usize, ml : usize, decls : rt::Vec, src : ptr(u8)) -> usize {
  di := d_qual_target(cs, cl, ms, ml, decls, src)
  if di == 0 { return 0 }
  d := deref(decl_at(Decl, rt::vec_get(decls, di - 1)))
  if d.is_generic {
    if D_BACKEND != 1 { return 0 }
    if d.mod_len != 11 or str_at((src + d.mod_start), d.mod_len) != "base__slice" { return 0 }
    if d.name_len != 4 or str_at((src + d.name_start), d.name_len) != "sort" { return 0 }
  }
  di
}

## ---- pass state (module globals, so the recursive walkers keep their 6-parameter shape) ----
## `D_KEEP` — 0, or the arena address of a per-decl REACHABILITY byte-block (one word per decl).
## When set, the walker MARKS every decl a call can resolve to (qualified target and/or every
## bare-name candidate) instead of rewriting, and raises `D_KEEP_CHANGED` on each new mark, so the
## caller can iterate the call graph to a fixpoint.
mut D_KEEP : usize = 0
mut D_KEEP_CHANGED : usize = 0
## `D_QUAL_RW` — 1 while the walker is REWRITING resolvable qualified callees to their target's bare
## name span. The two phases are deliberately separate: nothing is rewritten until the kept decl set
## has been proven free of duplicate emitted names, because a rewrite into an ambiguous bare name
## would let the backend bind the call to the WRONG same-named function (a silent miscompile).
mut D_QUAL_RW : usize = 0
## Mark every decl a call to `[cs,cl)` could bind to. A qualified callee marks its EXACT resolved
## target; a bare callee marks EVERY fn decl of that name (the module-unaware backends resolve a bare
## name by scanning all decls, so all candidates are live and the duplicate guard must see them).
## A generic bare callee is marked only when it belongs to the caller's module. This retains a
## same-module helper reached by a permitted injected generic instance without making an unrelated
## same-named library generic reachable from the entry module. Qualified injected entry points still
## pass through `d_qual_target_ok` above.
## On RV64/WAT retain the original entry-module boundary; only AArch64's bounded mono slice needs
## the caller-module rule while walking a generic function body.
mut D_GENERIC_WALK := 0
d_mark_callee := fn(cs : usize, cl : usize, ms : usize, ml : usize, decls : rt::Vec, src : ptr(u8)) {
  if D_KEEP == 0 { return }
  kb := unchecked bitcast(ptr(mut u8), D_KEEP)
  if d_colon_pos(src, cs, cl) >= 0 {
    di := d_qual_target_ok(cs, cl, ms, ml, decls, src)
    if di != 0 {
      if rt::rec_get(kb, di - 1) == 0 { rt::rec_set(kb, di - 1, 1) ; D_KEEP_CHANGED = 1 }
    }
    return
  }
  cnt := rt::vec_len(decls)
  mut i := 0
  while i < cnt {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if d.kind == 1 and d.name_len == cl and cl != 0 {
      if str_at((src + d.name_start), d.name_len) == str_at((src + cs), cl) {
        mut allow := true
        if d.is_generic {
          mut same_mod := d_mod_seg_eq(src, d.mod_start, d.mod_len, D_EMS, D_EML)
          if D_BACKEND == 1 and D_GENERIC_WALK != 0 { same_mod = d_mod_seg_eq(src, d.mod_start, d.mod_len, ms, ml) }
          if same_mod == false { allow = false }
        }
        if allow {
          if rt::rec_get(kb, i) == 0 { rt::rec_set(kb, i, 1) ; D_KEEP_CHANGED = 1 }
        }
      }
    }
    i += 1
  }
}

## Walk `e`: mark reachable callees (`D_KEEP`) and/or rewrite a resolvable `::`-qualified callee to
## the target decl's bare NAME span (`D_QUAL_RW`).
d_qual_expr := fn(e : ptr(Expr), ms : usize, ml : usize, decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) {
  match deref(e) {
    Expr::Bin(op, l, r) => { d_qual_expr(l, ms, ml, decls, na, src); d_qual_expr(r, ms, ml, decls, na, src) }
    Expr::Unchecked(inner) => { d_qual_expr(inner, ms, ml, decls, na, src) }
    Expr::AddrOf(inner) => { d_qual_expr(inner, ms, ml, decls, na, src) }
    Expr::Deref(inner) => { d_qual_expr(inner, ms, ml, decls, na, src) }
    Expr::Try(inner) => { d_qual_expr(inner, ms, ml, decls, na, src) }
    Expr::Field(b, ffs, ffl) => { d_qual_expr(b, ms, ml, decls, na, src) }
    Expr::Index(b, ix) => { d_qual_expr(b, ms, ml, decls, na, src); d_qual_expr(ix, ms, ml, decls, na, src) }
    Expr::If(c, th, el) => { d_qual_expr(c, ms, ml, decls, na, src); d_qual_expr(th, ms, ml, decls, na, src); d_qual_expr(el, ms, ml, decls, na, src) }
    Expr::Call(cs, cl, nargs, ah) => {
      mut g := ah
      while g != 0 {
        ga := deref(arg_p(g))
        d_qual_expr(ga.e, ms, ml, decls, na, src)
        g = ga.next
      }
      d_mark_callee(cs, cl, ms, ml, decls, src)
      if D_QUAL_RW != 0 {
        di := d_qual_target_ok(cs, cl, ms, ml, decls, src)
        if di != 0 {
          td := deref(decl_at(Decl, rt::vec_get(decls, di - 1)))
          nc := Expr.Call(td.name_start, td.name_len, nargs, ah)
          deref(unchecked bitcast(ptr(mut Expr), e)) = nc
        }
      }
    }
    _ => {}
  }
}
d_qual_stmts := fn(head : ptr(mut Stmt), ms : usize, ml : usize, decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => { d_qual_expr(v, ms, ml, decls, na, src) }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { d_qual_expr(rv, ms, ml, decls, na, src) } }
      Stmt::ExprStmt(e, nx) => { d_qual_expr(e, ms, ml, decls, na, src) }
      Stmt::If(c, th, el, nx) => { d_qual_expr(c, ms, ml, decls, na, src); d_qual_stmts(th, ms, ml, decls, na, src); d_qual_stmts(el, ms, ml, decls, na, src) }
      Stmt::While(c, b, nx) => { d_qual_expr(c, ms, ml, decls, na, src); d_qual_stmts(b, ms, ml, decls, na, src) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { if unchecked bitcast(usize, lo) != 0 { d_qual_expr(lo, ms, ml, decls, na, src) }; if unchecked bitcast(usize, hi) != 0 { d_qual_expr(hi, ms, ml, decls, na, src) }; d_qual_stmts(b, ms, ml, decls, na, src) }
      Stmt::Loop(b, nx) => { d_qual_stmts(b, ms, ml, decls, na, src) }
      Stmt::Unchecked(b, nx) => { d_qual_stmts(b, ms, ml, decls, na, src) }
      Stmt::AllocWith(ae, b, nx) => { d_qual_stmts(b, ms, ml, decls, na, src) }
      Stmt::DerefAssign(p, v, nx) => { d_qual_expr(p, ms, ml, decls, na, src); d_qual_expr(v, ms, ml, decls, na, src) }
      Stmt::IndexAssign(b, ix, v, nx) => { d_qual_expr(b, ms, ml, decls, na, src); d_qual_expr(ix, ms, ml, decls, na, src); d_qual_expr(v, ms, ml, decls, na, src) }
      Stmt::FieldAssign(bns, bnl, ffs, ffl, fv, nx) => { d_qual_expr(fv, ms, ml, decls, na, src) }
      Stmt::FieldPathAssign(pl, fpv, nx) => { d_qual_expr(fpv, ms, ml, decls, na, src) }
      Stmt::IndexFieldAssign(b, ix, ffs, ffl, v, nx) => { d_qual_expr(v, ms, ml, decls, na, src) }
      Stmt::Match(sc, ah, nx) => { d_qual_expr(sc, ms, ml, decls, na, src) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}
## Walk every fn body (+ trailing return expr) of the decls currently flagged in `keep` — or of ALL
## fn decls when `keep` is 0. One sweep of the marking / rewriting pass.
d_qual_sweep := fn(decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8), keep : usize) {
  cnt := rt::vec_len(decls)
  mut i := 0
  while i < cnt {
    mut live := true
    if keep != 0 { live = rt::rec_get(unchecked bitcast(ptr(mut u8), keep), i) != 0 }
    if live {
      d := deref(decl_at(Decl, rt::vec_get(decls, i)))
      if d.kind == 1 or d.kind == 5 {
        prev_generic_walk := D_GENERIC_WALK
        D_GENERIC_WALK = 0
        if d.is_generic { D_GENERIC_WALK = 1 }
        d_qual_stmts(d.body_stmts, d.mod_start, d.mod_len, decls, na, src)
        if unchecked bitcast(usize, d.value) != 0 { d_qual_expr(d.value, d.mod_start, d.mod_len, decls, na, src) }
        D_GENERIC_WALK = prev_generic_walk
      }
    }
    i += 1
  }
}

## Does decl `d` emit a bare LINKER LABEL of its own name? (A kind-1 fn, or a module-level VALUE
## global — the two decl shapes the module-unaware backends name by the source identifier.)
d_emits_bare_label := fn(d : Decl) -> bool {
  if d.kind == 1 { return true }
  return d.is_fn == false and d.kind == 0 and d.arity == 0 and unchecked bitcast(usize, d.value) != 0
}

## Do two KEPT decls emit the SAME bare label? The module-unaware backends have exactly one label per
## source identifier, so a collision is both an assembler reject AND — worse — an ambiguous bare-name
## call resolution. The caller drops the whole injected `lib/` set when this is true.
d_kept_name_clash := fn(decls : rt::Vec, src : ptr(u8), keep : usize) -> bool {
  kb := unchecked bitcast(ptr(mut u8), keep)
  cnt := rt::vec_len(decls)
  mut i := 0
  while i < cnt {
    if rt::rec_get(kb, i) != 0 {
      di := deref(decl_at(Decl, rt::vec_get(decls, i)))
      if di.name_len != 0 and d_emits_bare_label(di) {
        mut j := i + 1
        while j < cnt {
          if rt::rec_get(kb, j) != 0 {
            dj := deref(decl_at(Decl, rt::vec_get(decls, j)))
            if dj.name_len == di.name_len and d_emits_bare_label(dj) {
              if str_at((src + dj.name_start), dj.name_len) == str_at((src + di.name_start), di.name_len) { return true }
            }
          }
          j += 1
        }
      }
    }
    i += 1
  }
  return false
}

## Resolve module-qualified callees for the module-unaware backends and PRUNE the injected `lib/`
## closure down to what the program actually reaches. Returns the decl vector to emit.
##
## The backends emit EVERY kind-1 decl under its bare source name, so handing them the whole ambient
## closure would (a) define `unwrap`/`map`/`eq`/… several times over — the assembler rejects the file —
## and (b) make a bare call ambiguous. So:
##   1. seed `keep` with every decl of the ENTRY module (index `n-1`'s module name) plus every decl
##      that emits no label of its own (structs, enums, aliases, type decls — kept wholesale, they
##      only inform layout);
##   2. iterate the call graph to a fixpoint, marking each callee a kept fn can bind to (a qualified
##      call marks its exact target; a bare call marks EVERY same-named candidate, so ambiguity is
##      visible to the guard);
##   3. if any two kept decls would emit the SAME bare label, DROP the whole injected set and fall
##      back to the entry module alone — precisely the pre-injection decl set, so a program that
##      compiled before still compiles the same way, and nothing is ever bound to the wrong function;
##   4. otherwise rewrite the qualified callees to their target's bare name and emit the kept set.
d_resolve_and_prune := fn(decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8), ems : usize, eml : usize, tar : ptr(mut rt::Arena)) -> rt::Vec {
  cnt := rt::vec_len(decls)
  kb := rt::bump(deref(tar), cnt * 8 + 8)
  mut i := 0
  while i < cnt {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    mut seed := 0
    if d_mod_seg_eq(src, d.mod_start, d.mod_len, ems, eml) { seed = 1 }
    ## a decl that emits no label of its own (struct / enum / alias / type decl) only informs layout,
    ## so the whole injected set is kept. (Dropping the GENERIC ones was tried and is WRONG: PASS 1
    ## already recorded their names in the parser's enum table, so `Option.Some(20)` still parses as an
    ## EnumLit and, with the decl gone, lowers with discriminant -1.)
    if d_emits_bare_label(d) == false { seed = 1 }
    rt::rec_set(kb, i, seed)
    i += 1
  }
  D_QUAL_RW = 0
  D_KEEP = kb
  D_KEEP_CHANGED = 1
  while D_KEEP_CHANGED != 0 {
    D_KEEP_CHANGED = 0
    d_qual_sweep(decls, na, src, kb)
  }
  D_KEEP = 0
  clash := d_kept_name_clash(decls, src, kb)
  if clash {
    ## fall back to the entry module alone (no rewriting ran, so every qualified callee still hits
    ## the backend's undefined-callee trap exactly as it did before the ambient closure existed).
    mut ud := rt::Vec(data = rt::bump(deref(tar), cnt * 8 + 8), len = 0, cap = cnt + 1)
    i = 0
    while i < cnt {
      h := rt::vec_get(decls, i)
      d := deref(decl_at(Decl, h))
      if d_mod_seg_eq(src, d.mod_start, d.mod_len, ems, eml) { rt::vec_push(ud, h) }
      i += 1
    }
    return ud
  }
  D_QUAL_RW = 1
  d_qual_sweep(decls, na, src, kb)
  D_QUAL_RW = 0
  mut pd := rt::Vec(data = rt::bump(deref(tar), cnt * 8 + 8), len = 0, cap = cnt + 1)
  i = 0
  while i < cnt {
    if rt::rec_get(kb, i) != 0 { rt::vec_push(pd, rt::vec_get(decls, i)) }
    i += 1
  }
  pd
}

## ---------------------------------------------------------------------------------------------
## WAT AGGREGATE-COMPARE GUARD.
## ---------------------------------------------------------------------------------------------
## The wat backend lowers a bare `==` / `!=` between two AGGREGATE values (struct / enum locals) to
## `i64.eq` on their stack ADDRESSES — it compares identity, not contents, and answers "not equal" for
## two structurally equal values. That is a PRE-EXISTING silent miscompile, not something this lane
## introduces: on the compiler as it stood BEFORE this change, a single-file program declaring its own
## payload enum and comparing two equal values already exits 22 instead of 42. It only becomes visible
## to the corpus once the ambient closure supplies `Option`/`Result`, which makes such a comparison
## reachable in `test/enum_eq_payload.al` where it previously trapped on the missing decl.
##
## A TRAP must never become a wrong answer, so a wat compile whose entry module compares aggregates
## falls back to the single-file front end — byte-for-byte the pipeline that produced the old trap.
## Detection runs on the FULLY parsed tree (the aggregate types are only known once the closure is in),
## and the fallback then re-runs the front end with the closure suppressed. Remove this guard when
## `wat.al` either compares aggregate contents or fails loud on the attempt.
mut D_AGGCMP : usize = 0
## Is `[cs,cl)` a local whose binding RHS gives it a struct/enum type, in the body `body`?
d_var_is_agg := fn(cs : usize, cl : usize, body : ptr(mut Stmt), decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) -> bool {
  if cl == 0 { return false }
  lt := d_local_type_span(body, cs, cl, decls, na, src)
  if lt.n == 0 { return false }
  return d_is_agg_type_name(decls, src, lt.s, lt.n)
}
## Does expression `e` denote an aggregate VALUE (a struct/enum literal, or a local bound to one)?
d_expr_is_agg := fn(e : ptr(Expr), body : ptr(mut Stmt), decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) -> bool {
  lt := d_lit_type_span(e, src)
  if lt.n != 0 { return true }
  vs := d_var_span(e)
  if vs.n != 0 { return d_var_is_agg(vs.s, vs.n, body, decls, na, src) }
  return false
}
## Raise `D_AGGCMP` when `e` contains an `==` (op 20) / `!=` (op 28) over an aggregate operand.
d_aggcmp_expr := fn(e : ptr(Expr), body : ptr(mut Stmt), decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) {
  match deref(e) {
    Expr::Bin(op, l, r) => {
      if op == 20 or op == 28 {
        if d_expr_is_agg(l, body, decls, na, src) { D_AGGCMP = 1 }
        if d_expr_is_agg(r, body, decls, na, src) { D_AGGCMP = 1 }
      }
      d_aggcmp_expr(l, body, decls, na, src)
      d_aggcmp_expr(r, body, decls, na, src)
    }
    Expr::Unchecked(inner) => { d_aggcmp_expr(inner, body, decls, na, src) }
    Expr::Try(inner) => { d_aggcmp_expr(inner, body, decls, na, src) }
    Expr::AddrOf(inner) => { d_aggcmp_expr(inner, body, decls, na, src) }
    Expr::Deref(inner) => { d_aggcmp_expr(inner, body, decls, na, src) }
    Expr::If(c, th, el) => { d_aggcmp_expr(c, body, decls, na, src); d_aggcmp_expr(th, body, decls, na, src); d_aggcmp_expr(el, body, decls, na, src) }
    Expr::Index(b, ix) => { d_aggcmp_expr(b, body, decls, na, src); d_aggcmp_expr(ix, body, decls, na, src) }
    Expr::Call(cs, cl, n, ah) => {
      mut g := ah
      while g != 0 { ga := deref(arg_p(g)); d_aggcmp_expr(ga.e, body, decls, na, src); g = ga.next }
    }
    _ => {}
  }
}
d_aggcmp_stmts := fn(head : ptr(mut Stmt), body : ptr(mut Stmt), decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8)) {
  mut st := head
  while st != 0 {
    x := deref(stmt_p(Stmt, st))
    match x {
      Stmt::Assign(ns, nl, v, nx) => { d_aggcmp_expr(v, body, decls, na, src) }
      Stmt::Return(rv, nx) => { if unchecked bitcast(usize, rv) != 0 { d_aggcmp_expr(rv, body, decls, na, src) } }
      Stmt::ExprStmt(e, nx) => { d_aggcmp_expr(e, body, decls, na, src) }
      Stmt::If(c, th, el, nx) => { d_aggcmp_expr(c, body, decls, na, src); d_aggcmp_stmts(th, body, decls, na, src); d_aggcmp_stmts(el, body, decls, na, src) }
      Stmt::While(c, b, nx) => { d_aggcmp_expr(c, body, decls, na, src); d_aggcmp_stmts(b, body, decls, na, src) }
      Stmt::For(fns, fnl, lo, hi, b, nx) => { d_aggcmp_stmts(b, body, decls, na, src) }
      Stmt::Loop(b, nx) => { d_aggcmp_stmts(b, body, decls, na, src) }
      Stmt::Unchecked(b, nx) => { d_aggcmp_stmts(b, body, decls, na, src) }
      Stmt::AllocWith(ae, b, nx) => { d_aggcmp_stmts(b, body, decls, na, src) }
      Stmt::Match(sc, ah, nx) => { d_aggcmp_expr(sc, body, decls, na, src) }
      _ => {}
    }
    st = d_next_stmt(st, na)
  }
}
## 1 iff any fn of the ENTRY module `[ems,eml)` compares aggregates with `==` / `!=`.
d_entry_aggcmp := fn(decls : rt::Vec, na : ptr(mut rt::Arena), src : ptr(u8), ems : usize, eml : usize) -> bool {
  D_AGGCMP = 0
  cnt := rt::vec_len(decls)
  mut i := 0
  while i < cnt {
    d := deref(decl_at(Decl, rt::vec_get(decls, i)))
    if d.kind == 1 and d_mod_seg_eq(src, d.mod_start, d.mod_len, ems, eml) {
      d_aggcmp_stmts(d.body_stmts, d.body_stmts, decls, na, src)
      if unchecked bitcast(usize, d.value) != 0 { d_aggcmp_expr(d.value, d.body_stmts, decls, na, src) }
    }
    i += 1
  }
  mut hit := false
  if D_AGGCMP != 0 { hit = true }
  hit
}

## ---------------------------------------------------------------------------------------------
## The NON-x86 (aarch64 / riscv64 / wat) MULTI-FILE front end.
## ---------------------------------------------------------------------------------------------
## Historically each of `compile_file_aarch64` / `compile_file_riscv64` / `compile_file_wat` did ONE
## read + lex + parse of ONE file with NO import resolution, so every module-qualified stdlib callee
## (`std::math::sqrt`, `alloc::vec::push`, `std::fmt::print`, …) was simply ABSENT from `decls` and the
## backend emitted its "undefined/builtin callee" trap — by measurement the single largest trap bucket
## on all three backends. `d_compile_file_multi` gives them the SAME front end the x86 single-file path
## runs: resolve the ambient `lib/` closure, then read + lex + 2-pass-parse EVERY module in it into ONE
## shared `decls` vector before the backend emits.
##
## The ambient closure is resolved by the ONE import resolver — `cli::ambient_paths` driven off
## `cli::lib_dir`, literally the two calls `cli::run_cli` makes before `driver::compile_files` for a
## single-file x86 build (`is_pkg == false`, so a 2-segment alias like `mm := std::math` injects too).
## No second resolver is written here.
##
## LAYERING NOTE: this is a driver → cli call, the inverse of the usual direction. The resolver is a
## CLI-tier concern (it reads `/proc/self/exe` to locate the shipped `lib/`); duplicating it in the
## driver would be a second resolver free to drift from the x86 path's. The self-host symbol space is
## FLAT — `parser.al` consumes `pub` but does not yet gate on visibility — so `cli::lib_dir` /
## `cli::ambient_paths` resolve from here today. When visibility IS gated, those two must be marked
## `pub` (or the pair lifted into a module both tiers may import).
##
## Returns the newline-joined compile list: the ambient `lib/` modules FIRST, the program LAST (so the
## program's module stays the entry, matching `compile_files_mode`'s last-module convention).
## 1 while the WAT aggregate-compare guard has forced a SINGLE-FILE retry (no ambient closure).
mut D_NOLIB : usize = 0
d_ambient_paths := fn(in out sc : rt::Arena, path : str) -> str {
  if D_RAW_PATHS != 0 { return path }
  mut ub := rt::strbuf(sc, path.len + 16)
  ku := rt::push_str(ub, path)
  kn := rt::push_byte(ub, 10)
  upaths := str_at(ub.data, ub.len)
  ## the WAT aggregate-compare guard's retry wants the bare entry file, with no ambient closure at all
  if D_NOLIB != 0 { return upaths }
  ldir := cli::lib_dir(sc)
  ap := cli::ambient_paths(sc, upaths, ldir, false)
  if ap.len == 0 { return upaths }
  mut cb := rt::strbuf(sc, ap.len + upaths.len + 16)
  k1 := rt::push_str(cb, ap)
  k2 := rt::push_str(cb, upaths)
  return str_at(cb.data, cb.len)
}

## Compile ONE `.al` program (plus its resolved ambient `lib/` closure) with a non-x86 backend:
## `backend` 0 = WAT, 1 = AArch64 GAS, 2 = RISC-V64 GAS. The front end is the two-pass multi-module
## shape of `compile_files_mode` (PASS 1 discovers enum-type names + the struct field-order table,
## PASS 2 re-parses with both), minus the x86-only tail (test runner, `_start` wrapper, sema, limits,
## lambda lifting, peephole) — those either belong to the x86 lowering or are not yet meaningful for
## these backends. Arenas are sized like `compile_files_mode`'s (the whole shipped `lib/` closure can
## reach ~300 KB of source); `mmap` is lazy so the resident cost stays proportional to what is used.
d_compile_file_multi := fn(path : str, backend : usize) -> strbuf::StrBuf {
  D_BACKEND = backend
  ## a dedicated scratch arena for import resolution — `paths` and every source `ambient_paths`
  ## read live in it, so it must outlive the call (it does: arenas are reclaimed at process exit).
  mut sc := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(sc, 134217728)
  paths := d_ambient_paths(sc, path)
  mut tar := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(tar, 536870912)
  mut na := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(na, 536870912)
  ## tokens get their OWN arena, reset per module — see the long note in `compile_files_mode`: a
  ## module's tokens are dead once parsed, and sharing `tar` lets `dnode` clobber the tail tokens.
  mut tokar := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(tokar, 536870912)
  ## scan the newline-joined path list into an rt `str`-vector for random access by module index
  pbase := unchecked bitcast(usize, paths.ptr)
  mut pv := rt::Vec(data = rt::bump(tar, 256 * 8), len = 0, cap = 256)
  mut si := 0
  mut seg := 0
  while si <= paths.len {
    mut isnl := true
    if si < paths.len { isnl = bytes(paths)[si] == 10 }
    if isnl {
      if si > seg {
        ph := rt::svec_str_push(pv, tar, str_at(pbase + seg, si - seg))
      }
      seg = si + 1
    }
    si += 1
  }
  n := rt::vec_len(pv)
  mut bld := strbuf::strbuf(tar, 16777216)
  mut name_start := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  mut name_len := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  mut src_off := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  mut src_len := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  ## --- module NAMES (filename stems, or a `/lib/` path's mangled name `std__math`) ---
  mut k := 0
  while k < n {
    p := rt::svec_str_get(pv, k)
    rt::vec_push(name_start, strbuf::buf_len(bld))
    before := strbuf::buf_len(bld)
    push_module_name(bld, p)
    rt::vec_push(name_len, strbuf::buf_len(bld) - before)
    k += 1
  }
  ## --- then all module SOURCES, read off disk into the shared buffer ---
  k = 0
  while k < n {
    p := rt::svec_str_get(pv, k)
    rt::vec_push(src_off, strbuf::buf_len(bld))
    nread := read_file_into(bld, tar, p)
    rt::vec_push(src_len, nread)
    k += 1
  }
  base := unchecked bitcast(usize, strbuf::strbuf_base(bld))
  dcap := strbuf::buf_len(bld) + 16
  mut decls := rt::Vec(data = rt::bump(tar, dcap * 8), len = 0, cap = dcap)
  mut ev := rt::Vec(data = rt::bump(tar, dcap * 16), len = 0, cap = dcap * 2)
  mut sv := rt::Vec(data = rt::bump(tar, dcap * 32), len = 0, cap = dcap * 4)
  parser::set_structs_tbl(0)
  mut nstr := 0
  ## --- PASS 1: parse with a NULL enum table to discover enum-type names (results discarded) ---
  k = 0
  while k < n {
    soff := rt::vec_get(src_off, k)
    slen := rt::vec_get(src_len, k)
    tcap := slen + 16
    tokar.off = 0
    mut rt_toks := rt::Vec(data = rt::bump(tokar, tcap * 8), len = 0, cap = tcap)
    zt := lexrt::lex_rt(str_at(base + soff, slen), soff, rt_toks, tokar)
    mut pc := PC(toks = ptr(rt_toks), src = base, idx = 0, arena = ptr(na), nstr = nstr, mod_s = rt::vec_get(name_start, k), mod_l = rt::vec_get(name_len, k), enums = unchecked bitcast(ptr(rt::Vec), 0))
    ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
    ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
    ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
    parser::set_module_base(soff)
    pr := parser::parse_program(pc, decls, tar)
    match pr { Result::Ok(c) => {}; Result::Err(e) => { pek := d_perr_kind(e) ; pmns := rt::vec_get(name_start, k) ; pmnl := rt::vec_get(name_len, k) ; d_parse_reject(pc, pek, soff, slen, pmns, pmnl, tar) } }
    nstr = pc.nstr
    k += 1
  }
  dcnt1 := rt::vec_len(decls)
  mut di := 0
  while di < dcnt1 {
    d := deref(decl_at(Decl, rt::vec_get(decls, di)))
    if d.kind == 3 { rt::vec_push(ev, d.name_start); rt::vec_push(ev, d.name_len) }
    di += 1
  }
  collect_enum_aliases(decls, base, ev)
  collect_struct_table(decls, base, sv)         ## by-name struct-literal reorder table (TYP-8)
  parser::set_structs_tbl(unchecked bitcast(usize, ptr(sv)))
  na.off = 0
  decls.len = 0
  nstr = 0
  ## --- PASS 2: re-parse with the enum-name table (the AST/decls the backend emits) ---
  k = 0
  while k < n {
    soff := rt::vec_get(src_off, k)
    slen := rt::vec_get(src_len, k)
    tcap := slen + 16
    tokar.off = 0
    mut rt_toks2 := rt::Vec(data = rt::bump(tokar, tcap * 8), len = 0, cap = tcap)
    zt2 := lexrt::lex_rt(str_at(base + soff, slen), soff, rt_toks2, tokar)
    mut pc2 := PC(toks = ptr(rt_toks2), src = base, idx = 0, arena = ptr(na), nstr = nstr, mod_s = rt::vec_get(name_start, k), mod_l = rt::vec_get(name_len, k), enums = ptr(ev))
    ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
    ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
    ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
    parser::set_module_base(soff)
    pr2 := parser::parse_program(pc2, decls, tar)
    match pr2 { Result::Ok(c) => {}; Result::Err(e) => { pek := d_perr_kind(e) ; pmns := rt::vec_get(name_start, k) ; pmnl := rt::vec_get(name_len, k) ; d_parse_reject(pc2, pek, soff, slen, pmns, pmnl, tar) } }
    nstr = pc2.nstr
    k += 1
  }
  ## Match the ordinary compile paths: lift parsed local lambdas before any lowering-side
  ## normalization or backend emission. This multi-file path previously passed Expr::Lambda
  ## through unchanged, while compile/compile_program/compile_files_mode all lift exactly once.
  d_lift_lambdas(decls, ptr(na), ptr(tar), base)
  ## §5.1 fill omitted trailing parameter-defaults (same filler the x86_64 emit runs) so defaults are
  ## uniform across backends. No-op for a program with no defaults.
  lower::fill_program(ptr(decls), base, ptr(na))
  ## Resolve `mod::fn` / `alias::fn` callees to the target decl's BARE name and prune the injected
  ## `lib/` closure to what the program reaches — without this the module-unaware backends cannot use
  ## any of the decls this front end just supplied. A single-module compile (nothing injected) skips
  ## it: there is no qualified callee to resolve and nothing to prune.
  mut ed := decls
  if n > 1 {
    ems := rt::vec_get(name_start, n - 1)
    eml := rt::vec_get(name_len, n - 1)
    D_EMS = ems
    D_EML = eml
    ## WAT AGGREGATE-COMPARE GUARD (see its note): retry WITHOUT the ambient closure, reproducing the
    ## exact single-file pipeline whose trap this program had before the closure made the comparison
    ## reachable. Only the wat backend needs it — aarch64/riscv64 compare aggregate contents correctly.
    mut watagg := false
    if backend == 0 { watagg = d_entry_aggcmp(decls, ptr(na), base, ems, eml) }
    if watagg {
      D_NOLIB = 1
      rsb := d_compile_file_multi(path, backend)
      D_NOLIB = 0
      return rsb
    }
    ed = d_resolve_and_prune(decls, ptr(na), base, ems, eml, ptr(tar))
  }
  ## TOOL-7 — the cross-target test artifact has the same entry exclusion as the canonical x86 test
  ## artifact. The cross runner supplies its own `_start`; retaining the package entry would either
  ## create a duplicate linker symbol or, for a named entry, link code that the test artifact must not
  ## contain. Apply this after pruning so the backend sees one coherent declaration vector.
  if D_TEST_MODE != 0 {
    mut cross_entry := "_start"
    if D_TEST_ENTRY_N != 0 {
      cross_entry = str_at(unchecked bitcast(ptr(u8), D_TEST_ENTRY_P), D_TEST_ENTRY_N)
    }
    ecnt := rt::vec_len(ed)
    mut ekept := 0
    mut ei := 0
    while ei < ecnt {
      eh := rt::vec_get(ed, ei)
      ee := deref(decl_at(Decl, eh))
      if d_emits_entry(base, ee, cross_entry) == false {
        rt::rec_set(ed.data, ekept, eh)
        ekept += 1
      }
      ei += 1
    }
    ed.len = ekept
  }
  mut out := strbuf::strbuf(tar, 67108864)
  if backend == 0 { wat::emit_wat_program(ptr(ed), out, base, na) }
  if backend == 1 {
    mut cross_test_mode := D_TEST_MODE
    aarch64::set_cross_test_mode(cross_test_mode)
    mut cross_filter_p := D_TEST_FILTER_P
    mut cross_filter_n := D_TEST_FILTER_N
    aarch64::set_cross_test_filter(cross_filter_p, cross_filter_n)
    mut cross_keep := D_TEST_KEEP
    aarch64::set_cross_test_options(cross_keep)
    aarch64::emit_a64_program(ptr(ed), out, base, na)
  }
  if backend == 2 {
    mut rv_test_mode := D_TEST_MODE
    riscv64::set_cross_test_mode(rv_test_mode)
    mut rv_filter_p := D_TEST_FILTER_P
    mut rv_filter_n := D_TEST_FILTER_N
    riscv64::set_cross_test_filter(rv_filter_p, rv_filter_n)
    mut rv_keep := D_TEST_KEEP
    riscv64::set_cross_test_options(rv_keep)
    riscv64::emit_rv_program(ptr(ed), out, base, na)
  }
  out
}

## TYPE-CHECK the program an EMIT-to-stdout surface (`alatyr wat|aarch64|riscv64 <file>`) is about to
## emit, returning the `check_files` status: 0 well-typed, 1 rejected by sema, 9 a module fails to parse.
## The located `alatyr: check: …` diagnostic is printed by `check_files` itself, to stderr.
##
## WHY THIS EXISTS. Those three surfaces used to emit whatever the PARSER accepted and then `return 0`
## unconditionally. The parser's own reject did fire, but NO type-checker ran anywhere on the path, so a
## program the `-o` build path refuses (exit 1, `alatyr: check: type mismatch at line 2 in …`) got 34 / 44
## / 54 lines of WAT / AArch64 / RISC-V GAS on stdout and exit 0 instead — machine code for a program the
## compiler knows is wrong. That inverts I11 correct-or-trap, and is worse than a missing feature because
## the emitted output looks legitimate. It also silently distorted every gate that reads these surfaces:
## three of the four columns of EVERY `reject_*` fixture recorded "accepted".
##
## WHY A SEPARATE FRONT-END RUN rather than `sema::check_program` over the tree `d_compile_file_multi`
## has already parsed — measured, because the shared-tree form CRASHES the backends. `lower_layout`
## memoizes name→decl INDEX lookups in its `_sdc_*` / `_edc_*` 512-bucket caches, keyed on (name span,
## `src` base, naming module) and NOT on the identity of the `decls` vector. On this path
## `d_resolve_and_prune` replaces `decls` with a pruned `ed`: same `src` base, DIFFERENT indices — so every
## entry sema left in those caches became a stale HIT for the backend. Measured on the 630 `run` fixtures:
## 74 died with a null deref in `lower_layout::enum_max_arity` (via `aarch64::a64_val_words`), every one an
## enum program, and 2 more became false rejects. Giving the check its OWN arenas gives it its own `src`
## base, so its cache entries can never alias the emit run's. The x86 build path never saw this because
## nothing prunes `decls` after its sema call.
##
## Composed from the two pieces that already exist, so neither a third import resolver nor a second
## checker is written here: `d_ambient_paths` — literally the resolver the emit path itself uses, so the
## check sees EXACTLY the module closure that is about to be emitted — and `check_files`, the `check`
## subcommand's own entry. The emit surfaces therefore accept precisely what `alatyr check` accepts, which
## is the property the corpus already gates through `check_accept` / `check_reject`. Never on the
## self-build path → the TOOL-1 fixpoint is unaffected.
pub check_file_emit := fn(path : str, in out a : Arena) -> usize {
  mut cs := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(cs, 134217728)
  paths := d_ambient_paths(cs, path)
  return check_files(paths, cs, "")
}

## backend breadth (WASM→WAT): compile a `.al` program to a WAT module. Runs the shared
## non-x86 multi-file front end (`d_compile_file_multi`) so the module-qualified stdlib the program
## imports is present in `decls`, then `wat::emit_wat_program`.
pub compile_file_wat := fn(path : str, in out a : Arena) -> strbuf::StrBuf {
  return d_compile_file_multi(path, 0)
}

## (`alatyr fmt`) — the byte length of the file at `path`, probed BEFORE anything is
## reserved. Every arena and every buffer on the fmt path is a function of the input (see
## `compile_file_fmt`), and `read_file_into` only reports its length AFTER it has already written the
## bytes into a buffer that had to be sized first — so the size has to come from the file itself.
## `lseek(fd, 0, SEEK_END)` is the whole probe: open, seek to the end, close.
##
## Returns 0 when the path cannot be opened or is not seekable. That is deliberate and NOT a silent
## failure: the caller reaches `read_file_into`'s own `open` a moment later, which owns the
## "selfhost: cannot open source file" diagnostic — duplicating it here would print it twice, and
## reporting it here instead would move a user-facing message into a size probe. A 0 falls back to
## the caps below, which are the pre-existing constants, so an unseekable-but-readable input is no
## worse off than before this change.
fmt_lseek := @abi(syscall) fn(num : usize, fd : usize, off : usize, whence : usize) -> isize
fmt_file_size := fn(in out scratch : rt::Arena, path : str) -> usize {
  ## a NUL-terminated copy of `path` for `open` (the `path` str is a span into a larger buffer) —
  ## the same idiom `read_file_into` uses, for the same reason.
  mut pbuf := strbuf::strbuf(scratch, path.len + 16)
  mut k := 0
  while k < path.len {
    kk := strbuf::push_byte(pbuf, bytes(path)[k])
    k += 1
  }
  kn := strbuf::push_byte(pbuf, 0)
  pa := unchecked bitcast(usize, strbuf::strbuf_base(pbuf))
  fd := rt::sys_open(2, pa, 0, 0)   ## open(path, O_RDONLY, 0)
  if fd < 0 { return 0 }
  ufd := unchecked bitcast(usize, fd)
  e := fmt_lseek(8, ufd, 0, 2)      ## lseek(fd, 0, SEEK_END)
  cc := rt::sys_close(3, ufd)
  if e < 0 { return 0 }
  return unchecked bitcast(usize, e)
}

## The larger of two sizes — the fmt path's caps are `max(<the old constant>, <the input-derived
## bound>)`, so an input small enough that the derived bound falls below what already worked keeps
## the historical headroom instead of being tightened by this change.
fmt_cap_max := fn(x : usize, y : usize) -> usize {
  if x > y { return x }
  return y
}

## `alatyr fmt`: parse a single `.al` file and re-emit CANONICAL source (fmt::emit_fmt_
## program). A single parse pass suffices (fmt fail-louds on the enum/aggregate forms the two-pass
## enum table exists for). Additive: never invoked by the self-build, so fixpoint-neutral.
pub compile_file_fmt := fn(path : str, in out a : Arena) -> strbuf::StrBuf {
  ## EVERY cap below is a function of the INPUT SIZE, measured — not a constant that happens to fit
  ## the tree today. `alatyr fmt src/lower.al` (1 665 400 bytes) used to die with `rt: arena overflow
  ## (bump past cap)` because `tar` was a fixed 64 MiB while its consumers scale LINEARLY with the
  ## source: `decls` reserves 8 bytes per input byte, `ev` 16, `comments` 8 — 32x the input before
  ## the source buffer and the output buffer are counted at all. So the module most in need of
  ## formatting was the one module `fmt` could not format, and every future module would cross the
  ## same constant.
  ##
  ## `tar`'s three vectors are kept at their OWN provable bounds, not at an estimate:
  ##   `decls`    1 slot per input byte  (`dcap = nsz + 16`; a declaration costs >= 1 source byte)
  ##   `ev`       2 slots per `dcap`     (one (start,len) pair per enum decl, + the prelude seeds)
  ##   `comments` 1 slot per input byte  (a `##` comment costs >= 2 bytes and pushes 2 slots)
  ##   `rt_toks`  1 slot per input byte  (`tcap = nsz + 16`; a token costs >= 1 source byte)
  ## They are kept AT those bounds on purpose. `rt::vec_push` does not check `cap` (rt.al: "no
  ## growth - reserve cap"), so a cap below the provable bound is not a fail-loud - measured, an
  ## 8-slot `comments` vector on a 20 KB input overran into the output buffer and died on a `ud2`
  ## bounds trap (SIGILL, exit 132) with NO diagnostic. Tightening them needs a bounds check in
  ## `vec_push` first.
  ##
  ## MEASURED, three ways, because the per-byte cost is a function of the input's SHAPE and the
  ## compiler's own sources are not the worst of them:
  ##  (1) an instrumented build dumped `tar.off`/`na.off`/`tokar.off`/`out.len` for all 1 483 `.al`
  ##      files under `src/` + `lib/` + `test/`. Worst per-byte ratios there: tar 33x, na 6.4x,
  ##      tokar 11.2x on the largest file (27x on a tiny one), out 1.2275x.
  ##  (2) `na` is NOT bounded by source length - comptime expansion is not
  ##      (`test/sort_conformance.al`: 1 839 bytes in, 1 331 KB of AST arena). Bisecting a
  ##      statement-dense generated input to the exact `AST: out of memory` boundary put the real
  ##      worst case at 23.1 AST bytes per source byte; 48x is reserved.
  ##  (3) the compiler's own files are DECLARATION-SPARSE, and `parse_program` bumps a `Decl` record
  ##      out of `tar` per declaration. Pass 1's contiguous Decl tail is reclaimed after its enum
  ##      facts have been copied into the earlier `ev` reservation, before pass 2 allocates its own
  ##      records. Bisecting two declaration-dense shapes to the
  ##      `rt: arena overflow` boundary: `f<N> := fn() {}` (17.7 B/decl) needs 87 bytes of `tar` per
  ##      input byte and `a<N>:=1` (9.8 B/decl) needs 101 - i.e. ~9x for the `Decl` records on top of
  ##      the 32x of vectors, where the compiler's own sources need 1x. A 33x coefficient formatted
  ##      `src/lower.al` fine and still died on a 1.3 MB file of 72 841 declarations; 64x is
  ##      reserved, which is ~3x the densest shape measured.
  ## Reserving is not spending: `mmap` is lazy and nothing here is MAP_POPULATE. `fmt src/lower.al`
  ## (1 665 400 B) reserves 425 MB of address space and touches 22 MB of it (VmPeak vs VmHWM,
  ## cross-checked against getrusage's maxRSS).
  ## Every cap is `max(<the old constant>, <the derived bound>)`, so no input that worked before
  ## this change gets a smaller reservation than it had - measured, `fmt src/sema.al` costs the
  ## same 7 868 kB and 0.12 s before and after.
  mut szar := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(szar, 65536)
  nsz := fmt_file_size(szar, path)
  ## the OUTPUT buffer and the SOURCE buffer, sized first because `tar` has to hold both.
  ## `bld` = the source + the module name appended after it + `sb_byte`'s 8-byte word-store slack.
  ocap := fmt_cap_max(16777216, nsz * 2 + 65536)
  bcap := fmt_cap_max(16777216, nsz + path.len + 64)
  mut tar := rt::Arena(base = 0, off = 0, cap = 0)
  ## decls(8x) + ev(16x) + comments(8x) + the parser's `Decl` records(32x reserved, ~9x measured on
  ## the densest shape) + `bld` + `out`, + 4 MiB slack. `bcap`/`ocap` are the caps ACTUALLY passed to
  ## the two constructors below, not the derived bounds: they carry the old 16 MiB floor, and `tar`
  ## has to hold what is RESERVED, not what is needed.
  rt::arena_init(tar, fmt_cap_max(67108864, nsz * 64 + ocap + bcap + 4259840))
  mut na := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(na, fmt_cap_max(67108864, nsz * 48 + 67108864))
  mut tokar := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(tokar, fmt_cap_max(67108864, nsz * 32 + 1048576))
  mut bld := strbuf::strbuf(tar, bcap)
  nread := read_file_into(bld, tar, path)
  ## The module NAME for a parse diagnostic (`d_parse_diag` renders `in <module>` from a span into
  ## this same buffer, so the name has to live in it). Appended AFTER the source, deliberately: the
  ## source keeps offset 0, so `parser::set_module_base(0)`, `str_at(base, nread)`,
  ## `fmt::scan_comments(base, nread, ..)` and `fmt::fmt_find_ident(base, nread, ..)` all still
  ## address it from 0. The StrBuf never grows (rt.al: `cap` is reserved once), so `base` — captured
  ## on the next line — stays this address; the name costs a few bytes of a 16 MiB reservation. The
  ## PC's own `mod_s`/`mod_l` stay 0/0 on purpose: they are stamped onto every `Decl`, and fmt's
  ## OUTPUT must not change.
  fmns := strbuf::buf_len(bld)
  push_module_name(bld, path)
  fmnl := strbuf::buf_len(bld) - fmns
  base := unchecked bitcast(usize, strbuf::strbuf_base(bld))
  tcap := nread + 16
  mut rt_toks := rt::Vec(data = rt::bump(tokar, tcap * 8), len = 0, cap = tcap)
  zt := lexrt::lex_rt(str_at(base, nread), 0, rt_toks, tokar)
  dcap := nread + 16
  mut decls := rt::Vec(data = rt::bump(tar, dcap * 8), len = 0, cap = dcap)
  ## PASS 1 (null enum table) — discover enum-type names so PASS 2 can tell a real generic-enum ctor
  ## `E(T).V(..)` from a plain call-then-member `f(args).member`. Without the table `is_generic_enum_
  ## ctor` always assumes the ctor shape and DROPS the call args (fmt then re-emits `E(T).V` losing
  ## `f(args)`). A non-null table makes the parser defer to `is_enum_name` (parser.al is_generic_enum_
  ## ctor / enums_known). Same two-pass shape as compile_file_wat, but WITHOUT the struct-literal
  ## reorder table — fmt must preserve field order as written, so structs_tbl stays null.
  mut ev := rt::Vec(data = rt::bump(tar, dcap * 16), len = 0, cap = dcap * 2)
  pass1_decl_mark := tar.off
  mut pc1 := PC(toks = ptr(rt_toks), src = base, idx = 0, arena = ptr(na), nstr = 0, mod_s = 0, mod_l = 0, enums = unchecked bitcast(ptr(rt::Vec), 0))
  ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
  ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
  ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
  parser::set_module_base(0)
  pr1 := parser::parse_program(pc1, decls, tar)
  match pr1 { Result::Ok(c) => {}; Result::Err(e) => { pek := d_perr_kind(e) ; d_parse_reject(pc1, pek, 0, nread, fmns, fmnl, tar) } }
  mut di := 0
  while di < rt::vec_len(decls) {
    d := deref(decl_at(Decl, rt::vec_get(decls, di)))
    if d.kind == 3 { rt::vec_push(ev, d.name_start); rt::vec_push(ev, d.name_len) }
    di += 1
  }
  ## The PRELUDE tryable enums `Result` / `Option` are enum names too, and NO source file declares
  ## them — so a table built from this file's own decls left `is_enum_name("Result")` false and the
  ## generic-enum-ctor rewrite never fired. `Result(usize, ser::SerError).Ok(0)` then parsed as an
  ## ordinary call, and an ordinary call ARGUMENT does not consume a qualified VALUE path's `::seg`
  ## tail — so the argument loop ran past the closing `)` and swallowed EVERY FOLLOWING DECLARATION
  ## into the argument list (`serialize_roundtrip` came back as one giant `Result(usize, ser,
  ## SerError.Ok(0), main, fn() -> u64 { … })`, which no longer built). Seed the table with the two
  ## names, taken from the first whole-identifier occurrence in this file's own text — the table
  ## matches by TEXT through a span into `src`, so an entry has to point at real source bytes.
  mut prs : usize = 0
  if fmt::fmt_find_ident(base, nread, "Result", 6, ptr(prs)) != 0 { rt::vec_push(ev, prs); rt::vec_push(ev, 6) }
  mut pos : usize = 0
  if fmt::fmt_find_ident(base, nread, "Option", 6, ptr(pos)) != 0 { rt::vec_push(ev, pos); rt::vec_push(ev, 6) }
  collect_enum_aliases(decls, base, ev)
  ## `decls.data`, `ev`, the source buffer, and their contents all precede this mark. PASS 1 appends
  ## only Decl records to `tar`; after enum names and aliases have been copied into `ev`, those records
  ## are dead. Rewind exactly that contiguous tail before PASS 2, preserving every earlier allocation.
  tar.off = pass1_decl_mark
  ## reset for PASS 2 (the AST arena, decls, and the token buffer)
  na.off = 0
  decls.len = 0
  tokar.off = 0
  mut rt_toks2 := rt::Vec(data = rt::bump(tokar, tcap * 8), len = 0, cap = tcap)
  zt2 := lexrt::lex_rt(str_at(base, nread), 0, rt_toks2, tokar)
  mut pc := PC(toks = ptr(rt_toks2), src = base, idx = 0, arena = ptr(na), nstr = 0, mod_s = 0, mod_l = 0, enums = ptr(ev))
  ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
  ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
  ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
  parser::set_module_base(0)
  pr := parser::parse_program(pc, decls, tar)
  match pr { Result::Ok(c) => {}; Result::Err(e) => { pek := d_perr_kind(e) ; d_parse_reject(pc, pek, 0, nread, fmns, fmnl, tar) } }
  ## scan the source for `##` line comments (start,end pairs) so fmt can retain top-level leading
  ## (doc) comments. Sized to the source length (a comment costs ≥ 2 bytes, so ≤ nread pairs).
  mut comments := rt::Vec(data = rt::bump(tar, (nread + 16) * 8), len = 0, cap = nread + 16)
  fmt::scan_comments(base, nread, ptr(comments))
  mut out := strbuf::strbuf(tar, ocap)
  fmt::emit_fmt_program(ptr(decls), base, out, na, ptr(comments))
  out
}

## (backend breadth), item 2: compile a `.al` program to an AArch64 GAS program. Runs the
## shared non-x86 multi-file front end (`d_compile_file_multi`) — so a module-qualified stdlib callee
## (`std::math::sqrt`, `alloc::vec::push`, …) reaches the backend in `decls` instead of hitting its
## "undefined/builtin callee" trap — then `aarch64::emit_a64_program`. The emitted `.s` is assembled +
## linked by the cross binutils (`aarch64-unknown-linux-gnu-{as,ld}`) and run under `qemu-aarch64`; the
## exit code is what `main` computes — cross-validated against the x86_64 and WASM backends.
pub compile_file_aarch64 := fn(path : str, in out a : Arena) -> strbuf::StrBuf {
  return d_compile_file_multi(path, 1)
}

## (backend breadth), item 3: compile a `.al` program to a RISC-V64 GAS program. Same
## shared multi-file front end as `compile_file_aarch64`, then `riscv64::emit_rv_program`. Assembled +
## linked by `riscv64-unknown-linux-gnu-{as,ld}` and run under `qemu-riscv64`.
pub compile_file_riscv64 := fn(path : str, in out a : Arena) -> strbuf::StrBuf {
  return d_compile_file_multi(path, 2)
}

## Human description of a `ParseErr.Expected(k)` token kind for the parse diagnostic — the numeric
## lexer kind (lexrt's table) → a readable cue rendered as "(expected <desc>)". Only the kinds the
## parser actually emits (`Expected(1)` a name, `Expected(5)` `:=`) plus the common punctuation are
## mapped; an unlisted kind returns "" so the caller renders only the quoted offending token. `k <= 0`
## (EOF / no expectation) also returns "".
parse_expected_desc := fn(k : i64) -> str {
  if k == 1 { return "a name" }
  if k == 5 { return "`:=`" }
  if k == 6 { return "`->`" }
  if k == 8 { return "`:`" }
  if k == 10 { return "`(`" }
  if k == 11 { return "`)`" }
  if k == 12 { return "`{`" }
  if k == 13 { return "`}`" }
  if k == 21 { return "`=`" }
  return ""
}

## THE ONE located parse diagnostic (§1 item 6 / §5) — the renderer every `parse_program` `Err` in
## this module goes through.
##
## `parser::parse_program` returns `Result(usize, ParseErr)` and `ParseErr` is `enum { Expected(u8),
## Eof }`: it carries the EXPECTED token kind and NOTHING ELSE — no span, no line, no module. The
## position is not in the error VALUE at all. It is in the `PC` the failed parse left behind
## (`parser::cur(pc)` still points at the offending token) plus the module base the caller handed to
## `parser::set_module_base`. That is the whole reason only `check_files` was ever located: it is the
## one caller that read `cur(pc)` back afterwards. Every OTHER call site collapsed the `Err` into
## `panic("selfhost: parse error")` — 21 bytes, no position — which measured as unlocated on the `-o`
## build, `run`, `test`, `fmt` and bare-GAS-emit paths. (`wat`/`aarch64`/`riscv64` looked located only
## because `check_file_emit` runs `check_files` as a pre-pass in front of them.) Two lanes routed
## around this channel and used `parser::reject_at` instead; with one renderer behind every site the
## `Result` channel is worth trusting again, and the tenth site cannot drift from the other nine.
##
## `span`/`tlen` are the offending token's GLOBAL offset+length in the shared source buffer at `base`;
## `modbase` is the failing module's START in that buffer, so the line is counted from THERE and is
## FILE-relative rather than counted across every ambient stdlib module ahead of it; `mns`/`mnl` are
## the module NAME's span in the same buffer (`mnl == 0` — a single-source bridge entry with no name —
## renders the line without the ` in <module>` tail). Own StrBuf + scalar params, the shape
## `d_sema_reject` proved here: a helper taking the StrBuf `in out` PLUS the four file-table Vec
## pointers miscompiled at runtime on this tree, which is why `check_files` carried an inline copy.
## Writes to fd 2 and RETURNS — the caller decides whether to abort (`d_parse_reject`) or to carry a
## status code back (`check_files` / `check` return 9). Never fires on the self-build path (the tree
## parses), so the TOOL-1 fixpoint is unaffected.
d_parse_diag := fn(base : usize, span : usize, tlen : usize, ekind : i64, modbase : usize, mns : usize, mnl : usize, in out a : rt::Arena) -> usize {
  ## 1 KiB, not the 256 the inline copy used: the message quotes an arbitrarily long identifier AND a
  ## mangled module name, and `rt::sb_byte` panics on overflow — which would replace the diagnostic
  ## with "rt: StrBuf overflow". A KiB of a multi-megabyte arena buys the margin.
  mut pdb := strbuf::strbuf(a, 1024)
  pw0 := rt::push_str(pdb, "alatyr: parse: unexpected token")
  ## quote the OFFENDING lexeme (its source text) so the diagnostic names WHAT was unexpected, not
  ## just where. EOF (no lexeme) skips the quote.
  if tlen > 0 {
    pwq0 := rt::push_str(pdb, " `")
    pwqt := rt::push_str(pdb, str_at(base + span, tlen))
    pwq1 := rt::push_str(pdb, "`")
  }
  ## render the EXPECTED kind from the `ParseErr` payload ("(expected a name)" / "(expected `:=`)")
  ## when the parser named one. An unmapped/absent kind renders nothing.
  ped := parse_expected_desc(ekind)
  if ped.len > 0 {
    pwe0 := rt::push_str(pdb, " (expected ")
    pwe1 := rt::push_str(pdb, ped)
    pwe2 := rt::push_str(pdb, ")")
  }
  ## LOCATE when there is anything to locate from: a nonzero offset, or a named module (a named
  ## module at offset 0 is line 1 of that module, which is a fact worth printing).
  mut loc := span > 0
  if mnl > 0 { loc = true }
  if loc {
    pw1 := rt::push_str(pdb, " at line ")
    mut pline := 1
    psrcv := str_at(base, span)
    mut pci := modbase
    while pci < span { if bytes(psrcv)[pci] == 10 { pline = pline + 1 } ; pci = pci + 1 }
    pw2 := rt::push_int(pdb, i64(pline))
    if mnl > 0 {
      pwin := rt::push_str(pdb, " in ")
      pwm := rt::push_str(pdb, str_at(base + mns, mnl))
    }
  }
  pw3 := rt::push_byte(pdb, 10)
  pwf := rt::sb_flush(pdb, 2)
  return 0
}

## Decode a `ParseErr` into the numeric EXPECTED token kind `d_parse_diag` renders (`Eof` names no
## expectation → 0). Exists so the thirteen `Result::Err(e)` arms do not each carry their own `match`:
## the payload is what makes the message say "(expected `:=`)" instead of only naming the token.
d_perr_kind := fn(e : parser::ParseErr) -> i64 {
  mut k : i64 = 0
  match e {
    parser::ParseErr::Expected(x) => { k = i64(x) }
    parser::ParseErr::Eof => { k = 0 }
  }
  return k
}

## Read the offending token out of the `PC` a FAILED parse left behind and render the diagnostic.
## `pc.idx` is still ON the token `parse_decl` refused, so `parser::cur(pc)` is its span. A trailing
## EOF sentinel (kind 0) carries no usable offset, so fall back to the LAST byte of the failing
## module — which maps into that module at its final line — exactly as `check_files` does.
d_parse_diag_pc := fn(pc : PC, ekind : i64, modbase : usize, modlen : usize, mns : usize, mnl : usize, in out a : rt::Arena) -> usize {
  ft := parser::cur(pc)
  mut span := 0
  mut tlen := 0
  if ft.kind != 0 {
    span = ft.start
    tlen = ft.len
  } else if modlen > 0 {
    span = modbase + modlen - 1
  }
  return d_parse_diag(pc.src, span, tlen, ekind, modbase, mns, mnl, a)
}

## The ABORTING form, for the ten `parse_program` call sites that have NO error-return channel —
## `compile`, `compile_pair` (x2), `compile_program`, `compile_files_mode` (x2), `d_compile_file_multi`
## (x2) and `compile_file_fmt` (x2), i.e. every build / `-o` / `run` / `test` / `fmt` / emit path.
## Prints the located diagnostic, then aborts fail-loud: an unparsable program is an I11 trap BEFORE
## any GAS reaches stdout, never a silent partial build. `panic("")` after the flush is the shape
## `d_limit_reject` / `d_sema_reject` already use on the build path (measured rc 1, nothing on stdout).
d_parse_reject := fn(pc : PC, ekind : i64, modbase : usize, modlen : usize, mns : usize, mnl : usize, in out a : rt::Arena) {
  zpd := d_parse_diag_pc(pc, ekind, modbase, modlen, mns, mnl, a)
  panic("")
}

## Run the FRONT END over a newline-joined FILE LIST (the `check` subcommand): lex + parse every
## module into ONE combined `Decl` Vec (exactly as `compile_files`, so the proven multi-module
## parse path is reused), then run `sema::check_program` over the whole tree. Returns a status
## code: 0 the program is well-typed, 1 sema rejects it (an unbound name OR a type mismatch),
## 9 a module fails to parse. NO GAS is emitted — this is the type-check-only acceptance entry.
pub check_files := fn(paths : str, in out a : Arena, ceiling : str) -> usize {
  mut tar := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(tar, 536870912)
  mut na := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(na, 536870912)
  mut tokar := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(tokar, 536870912)
  pbase := unchecked bitcast(usize, paths.ptr)
  mut pv := rt::Vec(data = rt::bump(tar, 256 * 8), len = 0, cap = 256)
  ## Keep the anonymous root first so the existing final-module entry convention is unchanged.
  manifest := d_manifest_path(tar)
  ## Keep check's front-end state isolated from an earlier build/check pass in this process.
  MANIFEST_HAS = false
  if manifest.len != 0 { mh := rt::svec_str_push(pv, tar, manifest) }
  mut si := 0
  mut seg := 0
  while si <= paths.len {
    mut isnl := true
    if si < paths.len { isnl = bytes(paths)[si] == 10 }
    if isnl {
      if si > seg {
        pp := str_at(pbase + seg, si - seg)
        if manifest.len == 0 or not d_is_root_path(pp) { ph := rt::svec_str_push(pv, tar, pp) }
      }
      seg = si + 1
    }
    si += 1
  }
  if d_manifest_has_base_process(pv) == false {
    root_process := d_manifest_root_process(tar, manifest)
    if root_process.len != 0 and d_manifest_has_base_process(pv) == false { rp := rt::svec_str_push(pv, tar, root_process) }
  }
  n := rt::vec_len(pv)
  mut bld := strbuf::strbuf(tar, 16777216)
  mut name_start := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  mut name_len := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  mut src_off := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  mut src_len := rt::Vec(data = rt::bump(tar, n * 8), len = 0, cap = n)
  mut root_k := n
  mut k := 0
  while k < n {
    p := rt::svec_str_get(pv, k)
    if d_is_root_path(p) { root_k = k }
    rt::vec_push(name_start, strbuf::buf_len(bld))
    before := strbuf::buf_len(bld)
    push_module_name(bld, p)                 ## stem, OR a `/lib/` path's mangled name (std__io)
    rt::vec_push(name_len, strbuf::buf_len(bld) - before)
    k += 1
  }
  k = 0
  while k < n {
    p := rt::svec_str_get(pv, k)
    rt::vec_push(src_off, strbuf::buf_len(bld))
    nread := read_file_into(bld, tar, p)
    rt::vec_push(src_len, nread)
    k += 1
  }
  ## TOOL-15: recover the package handle from the anonymous root entry now present in `pv`.
  mut manifest_off := 0
  mut manifest_len := 0
  if manifest.len != 0 and root_k < n {
    manifest_off = rt::vec_get(src_off, root_k)
    manifest_len = rt::vec_get(src_len, root_k)
  }
  base := unchecked bitcast(usize, strbuf::strbuf_base(bld))
  if manifest_len != 0 {
    d_manifest_scan(str_at(base + manifest_off, manifest_len), manifest_off)
    if MANIFEST_HAS {
      if MANIFEST_BIND_PUB {
        d_manifest_pub_diag(tar, manifest)
        return 1
      }
      if d_manifest_find_child(pv) {
        d_manifest_duplicate_diag(tar, manifest)
        return 1
      }
      d_manifest_type_source(bld)
    }
  }
  dcap := strbuf::buf_len(bld) + n * 8 + 64
  mut decls := rt::Vec(data = rt::bump(tar, dcap * 8), len = 0, cap = dcap)
  ## The parser's by-name struct-construction table is a PASS-1 product, just like the enum-name table.
  ## `check_files` must publish it before PASS 2; otherwise `check` accepts unknown named fields and
  ## disagrees with build, which already rejects them in its equivalent two-pass path.
  mut sv := rt::Vec(data = rt::bump(tar, dcap * 32), len = 0, cap = dcap * 4)
  parser::set_structs_tbl(0)
  mut nstr := 0
  mut perr := false
  mut perr_span := 0
  mut perr_tlen := 0   ## byte length of the offending token (0 = EOF / no lexeme to quote)
  mut perr_kind : i64 = 0   ## the EXPECTED token kind from `ParseErr.Expected(k)` (0 = EOF / none)
  mut perr_mb := 0     ## the failing module's START offset — the line is counted from HERE
  mut perr_mns := 0    ## and its NAME's span, so the diagnostic can say `in <module>`
  mut perr_mnl := 0
  ## The enum-type-NAME table (packed (name_start, name_len) pairs into `base`) — filled by PASS 1,
  ## consulted by PASS 2. WITHOUT it `enums_known(pc) == false` makes the parser assume the CTOR shape
  ## for EVERY `recv.method(args)` (parser.al `is_ctor`), so a UFCS method call over a simple-`Var`
  ## receiver parsed as an `EnumLit` instead of a `Call` — and `sema`'s whole call-level battery
  ## (arity, undefined callee, per-argument conformance, the receiver's own name resolution, and every
  ## nested call inside the argument list) is keyed on `Expr::Call`, so NONE of it reached the node.
  ## `check` therefore returned 0 on programs `build` rejects. `compile_files` / `d_compile_file_multi` /
  ## `compile_file_fmt` already run this two-pass shape; this makes `check` agree with them.
  mut ev := rt::Vec(data = rt::bump(tar, dcap * 16), len = 0, cap = dcap * 2)
  ## --- PASS 1: parse with a NULL enum table to discover the enum-type names ---
  k = 0
  while k < n {
    soff := rt::vec_get(src_off, k)
    slen := rt::vec_get(src_len, k)
    tcap := slen + 16
    tokar.off = 0
    mut rt_toks := rt::Vec(data = rt::bump(tokar, tcap * 8), len = 0, cap = tcap)
    zt := lexrt::lex_rt(str_at(base + soff, slen), soff, rt_toks, tokar)
    mut pc := PC(toks = ptr(rt_toks), src = base, idx = 0, arena = ptr(na), nstr = nstr, mod_s = rt::vec_get(name_start, k), mod_l = rt::vec_get(name_len, k), enums = unchecked bitcast(ptr(rt::Vec), 0))
    ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
    ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
    ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
    parser::set_module_base(soff)
    pr := parser::parse_program(pc, decls, tar)
    ## On a parse failure, `pc.idx` is left at the offending token — capture its GLOBAL source offset
    ## for the diagnostic. Keep the FIRST error's location (`perr == false` guard) since the loop parses
    ## every module and a later one must not clobber it. A trailing EOF sentinel (kind 0) carries no
    ## offset, so fall back to the LAST byte of the current file (maps into it at its final line).
    match pr { Result::Ok(c) => {}; Result::Err(e) => {
      if perr == false {
        ft := parser::cur(pc)
        if ft.kind != 0 { perr_span = ft.start; perr_tlen = ft.len } else if slen > 0 { perr_span = soff + slen - 1 }
        ## capture the EXPECTED token kind from the `ParseErr` payload (now that a returned
        ## `Result(_, ParseErr).Err(e)` delivers its multi-word enum payload whole) so the diagnostic
        ## can name WHAT was expected, not just the offending token. `Eof` carries no expectation.
        perr_kind = d_perr_kind(e)
        ## …and the module the failure is IN, so the render below needs no second scan over the file
        ## table to recover what this iteration already knows.
        perr_mb = soff
        perr_mns = rt::vec_get(name_start, k)
        perr_mnl = rt::vec_get(name_len, k)
      }
      perr = true
    } }
    nstr = pc.nstr
    k += 1
  }
  ## A parse failure carries a source location (§1 item 6 / §5), not a bare rc 9 — and it now renders
  ## through `d_parse_diag`, the SAME renderer every aborting `parse_program` call site uses, so the
  ## `check` message and the build/emit/fmt messages cannot drift apart. This used to be an inline
  ## copy because a shared helper taking the `StrBuf` in-out PLUS the four file-table Vec pointers
  ## miscompiled here; `d_parse_diag` takes its own StrBuf and plain scalars (the `d_sema_reject`
  ## shape) and needs no file-table scan at all — the loop above already knew which module failed.
  if perr {
    zpd := d_parse_diag(base, perr_span, perr_tlen, perr_kind, perr_mb, perr_mns, perr_mnl, tar)
    return 9
  }
  ## collect the kind-3 (enum-type) decl names, then reset the AST arena + decls + nstr for PASS 2.
  ## The enum table only steers ctor-vs-UFCS node CHOICE on an already-accepted token sequence (both
  ## `is_ctor` branches build a node; neither can fail), so PASS 2 cannot introduce a parse error PASS 1
  ## did not already report — the reject above stays the single parse-diagnostic site.
  dcnt1 := rt::vec_len(decls)
  mut cdi := 0
  while cdi < dcnt1 {
    cd := deref(decl_at(Decl, rt::vec_get(decls, cdi)))
    ## bind the two spans to LOCALS before pushing: passing `cd.name_start` — a field read off a
    ## `deref(<call>)`-bound aggregate local — DIRECTLY as the `in out`-Vec `vec_push`'s value argument
    ## mis-lowers here and kills the process (the same field-through-call-result hazard the AGENTS.md
    ## "bind a `deref(<call>)` field to a local where flagged" rule names). Constants push fine, so it is
    ## the argument, not the loop or the Vec.
    cns := cd.name_start
    cnl := cd.name_len
    if cd.kind == 3 { zp1 := rt::vec_push(ev, cns); zp2 := rt::vec_push(ev, cnl) }
    cdi += 1
  }
  collect_enum_aliases(decls, base, ev)
  collect_struct_table(decls, base, sv)
  parser::set_structs_tbl(unchecked bitcast(usize, ptr(sv)))
  na.off = 0
  decls.len = 0
  nstr = 0
  ## --- PASS 2: re-parse with the enum-name table — the AST `sema` actually checks ---
  k = 0
  while k < n {
    soff := rt::vec_get(src_off, k)
    slen := rt::vec_get(src_len, k)
    tcap := slen + 16
    tokar.off = 0
    mut rt_toks2 := rt::Vec(data = rt::bump(tokar, tcap * 8), len = 0, cap = tcap)
    zt2 := lexrt::lex_rt(str_at(base + soff, slen), soff, rt_toks2, tokar)
    mut pc2 := PC(toks = ptr(rt_toks2), src = base, idx = 0, arena = ptr(na), nstr = nstr, mod_s = rt::vec_get(name_start, k), mod_l = rt::vec_get(name_len, k), enums = ptr(ev))
    ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
    ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
    ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
    parser::set_module_base(soff)
    pr2 := parser::parse_program(pc2, decls, tar)
    ## PASS 2 cannot fail where PASS 1 succeeded (the enum table only picks between two node SHAPES on an
    ## already-accepted token sequence), so this arm is unreachable — accumulate into a flag rather than
    ## returning from inside the arm (an early `return` in a match arm nested in a `while` mis-lowers).
    match pr2 { Result::Ok(c) => {}; Result::Err(e) => { perr = true } }
    nstr = pc2.nstr
    k += 1
  }
  if perr { return 9 }
  if root_k < n { d_manifest_drop_root_decl(decls, rt::vec_get(name_start, root_k), rt::vec_get(name_len, root_k)) }
  d_lift_lambdas(decls, ptr(na), ptr(tar), base)
  d_manifest_module_decls(pv, name_start, name_len, decls, na, tar, nstr)
  d_manifest_rewrite_decls(decls, pv, name_start, name_len, base, nstr, ptr(na))
  d_manifest_set_sema_modules(pv, name_start, name_len, tar)
  mut r := sema::check_program(ptr(decls), base, ptr(na))
  ## FND-11 — the LAXER-THAN-CEILING rule, which `check` was missing while `build` enforced it: a file whose
  ## `@limits` list OMITS a ceiling limit declares a weaker contract than the package allows. `check` ran
  ## only `enforce_ceiling` (does the code VIOLATE a restriction), so a module declaring `@limits(no_comptime)`
  ## under a `[no_alloc]` ceiling passed `check` and was rejected by `build` — the split Tooling §2.2/§5
  ## forbids. Same predicate, same `DIAG_LIMIT_MARKER` code shape, and in the SAME order as
  ## `compile_files_mode`, so both commands report the same failure first.
  if r == 0 { r = d_check_limits_ceiling(ceiling, ptr(decls), base) }
  if r == 0 { r = sema::enforce_ceiling(ptr(decls), base, ptr(na), ceiling) }
  if r == 0 { return 0 }
  ## DIAGNOSTIC (§1 item 6 / §5): decode the `CheckErr` code — kind in the low 2 bits (1 unbound name,
  ## 2 type mismatch, 3 duplicate name), the source START offset in the rest (`r / 4`) — and print a
  ## source-LOCATED message to stderr. The 1-based line is the count of newlines before the offset.
  ## The verdict is normalized back to `1` (reject) so the `check` exit code is unchanged.
  limit := r >= DIAG_LIMIT_MARKER and r < DIAG_AMBIG_MARKER
  immutable := r >= DIAG_IMMUTABLE_MARKER
  ctg := r >= DIAG_CT_MARKER and r < DIAG_IMMUTABLE_MARKER
  ambig := r >= DIAG_AMBIG_MARKER and r < DIAG_CT_MARKER
  mut raw := r
  mut kind := 0
  mut span := 0
  if limit {
    raw = r - DIAG_LIMIT_MARKER
    kind = raw % 8
    span = raw / 8
  } else if immutable {
    raw = r - DIAG_IMMUTABLE_MARKER
    span = raw / 4
  } else if ctg {
    raw = r - DIAG_CT_MARKER
    kind = raw % 8
    span = raw / 8
  } else {
    if ambig { raw = r - DIAG_AMBIG_MARKER }
    kind = raw % 4
    span = raw / 4
  }
  mut db := strbuf::strbuf(tar, 256)
  dw0 := rt::push_str(db, "alatyr: check: ")
  ## The KIND + SOURCE SPAN are only reliable when the failure propagated through the `CheckErr`
  ## channel (`span > 0`); many checks poison via `mark_failed` (to avoid a lean-lower early-return
  ## gotcha), which carries no span, so `r` is then the default `unbound_err(0,0)` == 1. Print the
  ## LOCATED kind + 1-based line only when `span > 0`; otherwise an honest unlocated message (no
  ## misleading kind/line). `span == 0 && kind == 3` is the duplicate-name case (a known kind).
  if span > 0 {
    if limit {
      dwk0 := rt::push_str(db, "@limits(")
      dwk1 := rt::push_str(db, limit_name(kind))
      dwk2 := rt::push_str(db, ") violation")
    } else if immutable { dwki := rt::push_str(db, "immutable binding") }
    else if ctg { dwkc := rt::push_str(db, comptime_guard_name(kind)) }
    else if ambig { dwk := rt::push_str(db, "ambiguous call") }
    else if kind == 1 { dwk := rt::push_str(db, "unbound name") }
    else if kind == 2 { dwk := rt::push_str(db, "type mismatch") }
    else if kind == 3 { dwk := rt::push_str(db, "duplicate name") }
    else { dwk := rt::push_str(db, "invalid") }
    ## Map the GLOBAL concatenated-buffer offset back to the OWNING file (`src_off[k] <= span <
    ## src_off[k]+src_len[k]`), so a multi-file check reports a FILE-RELATIVE line + names the module
    ## — not a line counted across every earlier file's source (§1 item 6: stable locations per file).
    mut fk := 0
    mut fbase := 0
    mut fi := 0
    while fi < n {
      fo := rt::vec_get(src_off, fi)
      fln := rt::vec_get(src_len, fi)
      if span >= fo and span < fo + fln { fk = fi; fbase = fo }
      fi += 1
    }
    dw1 := rt::push_str(db, " at line ")
    mut line := 1
    srcv := str_at(base, span)
    mut ci := fbase
    while ci < span { if bytes(srcv)[ci] == 10 { line = line + 1 } ; ci = ci + 1 }
    dw2 := rt::push_int(db, i64(line))
    dwin := rt::push_str(db, " in ")
    dwm := rt::push_str(db, str_at(base + rt::vec_get(name_start, fk), rt::vec_get(name_len, fk)))
  } else if kind == 3 {
    dwd := rt::push_str(db, "duplicate name")
  } else {
    dwu := rt::push_str(db, "type error (location not tracked)")
  }
  dw3 := rt::push_byte(db, 10)
  dwf := rt::sb_flush(db, 2)
  return 1
}

## Run the FRONT END through the type-checker: lex → parse → `sema::check_program`. Returns a
## status code — 0 the program is well-typed (all names bound, no type mismatch), 1 it is
## rejected (an unbound name OR a type mismatch), 9 it fails to parse. Composes the same lex +
## parse the `compile` path uses, then the canonical `sema` pass (real type-checking, not just
## use-before-decl) over the resulting `Decl` `Vec`. The working containers are freed before
## return. This is the acceptance entry the `selfhost_typecheck_tree_e2e` harness drives to
## prove the tree ACCEPTS a well-typed program and REJECTS an ill-typed one.
pub check := fn(src : str, in out a : Arena) -> usize {
  base := unchecked bitcast(usize, src.ptr)
  mut tar := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(tar, 16777216)
  mut na := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(na, 16777216)
  tcap := src.len + 16
  mut toks := rt::Vec(data = rt::bump(tar, tcap * 8), len = 0, cap = tcap)
  ze := lexrt::lex_rt(src, 0, toks, tar)
  mut pc := PC(toks = ptr(toks), src = base, idx = 0, arena = ptr(na), nstr = 0, mod_s = 0, mod_l = 0, enums = unchecked bitcast(ptr(rt::Vec), 0))
  mut decls := rt::Vec(data = rt::bump(tar, tcap * 8), len = 0, cap = tcap)
  ## Keep the single-file check entry in sync with check_files: struct construction is parsed by name
  ## only when PASS 2 has the declaration-order table from PASS 1.
  mut sv := rt::Vec(data = rt::bump(tar, tcap * 32), len = 0, cap = tcap * 4)
  parser::set_structs_tbl(0)
  ## PASS 1 (null enum table) — discover the enum-type names. The same two-pass shape `check_files`
  ## and `compile_files` run, and for the same reason: with a NULL table every `recv.method(args)`
  ## parses as an `EnumLit` (parser.al `is_ctor`), and sema's call-level checks are keyed on
  ## `Expr::Call`, so a UFCS call reached NO call-level check at all.
  ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
  ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
  ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
  parser::set_module_base(0)
  pr := parser::parse_program(pc, decls, tar)
  mut rc := 0
  match pr {
    Result::Ok(n) => {
      mut ev := rt::Vec(data = rt::bump(tar, tcap * 16), len = 0, cap = tcap * 2)
      dcnt1 := rt::vec_len(decls)
      mut cdi := 0
      while cdi < dcnt1 {
        cd := deref(decl_at(Decl, rt::vec_get(decls, cdi)))
        ## bind the spans to LOCALS first — see `check_files`' twin loop.
        cns := cd.name_start
        cnl := cd.name_len
        if cd.kind == 3 { zp1 := rt::vec_push(ev, cns); zp2 := rt::vec_push(ev, cnl) }
        cdi += 1
      }
      collect_enum_aliases(decls, base, ev)
      collect_struct_table(decls, base, sv)
      parser::set_structs_tbl(unchecked bitcast(usize, ptr(sv)))
      na.off = 0
      decls.len = 0
      mut toks2 := rt::Vec(data = rt::bump(tar, tcap * 8), len = 0, cap = tcap)
      ze2 := lexrt::lex_rt(src, 0, toks2, tar)
      mut pc2 := PC(toks = ptr(toks2), src = base, idx = 0, arena = ptr(na), nstr = 0, mod_s = 0, mod_l = 0, enums = ptr(ev))
      ## tell the parser where THIS module starts in the shared buffer, so a parser-level located reject
      ## counts its line from the MODULE base, not from the base of a buffer that holds every ambient
      ## stdlib module ahead of it (parser.al `src_line_at` / `P_MOD_BASE`).
      parser::set_module_base(0)
      pr2 := parser::parse_program(pc2, decls, tar)
      match pr2 {
        Result::Ok(n2) => { rc = sema::check_program(ptr(decls), base, ptr(na)) }
        Result::Err(e2) => { pek2 := d_perr_kind(e2) ; zp2 := d_parse_diag_pc(pc2, pek2, 0, src.len, 0, 0, tar) ; rc = 9 }
      }
    }
    Result::Err(e) => { pek := d_perr_kind(e) ; zp1 := d_parse_diag_pc(pc, pek, 0, src.len, 0, 0, tar) ; rc = 9 }
  }
  rc
}
