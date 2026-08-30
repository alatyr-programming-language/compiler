## selfhost::lower::ctfold — COMPILE-TIME FOLDING: the `comptime if` condition evaluator and its
## located reject, the `build.<flag>` profile facts (Tooling §2.7), the `target.<facet>` facet
## comparison, the capability queries (`resolves`/`compiles`), the `comptime for` header recovery and
## its range bounds, and the `typeinfo(T)` counts. 29 functions, one type (`QRef`).
##
## MOD-12: `src/lower.al` supplies module `lower`'s own items and `src/lower/` supplies its children;
## the two halves are ONE module scope (Modules §1), so `driver`'s `lower::` call sites are untouched
## and this file is a DESCENDANT of `lower`. Every UNQUALIFIED name it does not import — `streq`,
## `decl_at`, `module_const_value`, `guard_resolve_tp`, `size_of_type_span`, and the `BUILD_FLAGS_P`/
## `BUILD_FLAGS_N` globals — binds `lower.al`'s OWN declaration through the ancestor chain (Modules §3
## for values, TYPE-ANCESTOR for types).
##
## Audit-listed as "entangled by `VERIFY_CHK`"; that entanglement went away when `d18876c` moved the
## verification mode into `LCtx`, and `comptime_cond_eval` now folds `verify.checked` off `cx.vchk`.
##
## The module is named `ctfold`, not `comptime`, for a hard reason: `comptime` is a KEYWORD, so the
## parse of `(lower_show_src_line, …) := comptime` fails outright with
## `parse: unexpected token 'comptime' (expected a name)`. A submodule named after a keyword can never
## be imported by bare name, which is the one spelling that keeps the boundary `@inline`-transparent.
##
## Two members deliberately did NOT come along:
##   - `set_build_flags` (and therefore `BUILD_FLAGS_P`/`BUILD_FLAGS_N`) stays in `src/lower.al`: it is
##     `pub` and `cli` calls it as `lower::set_build_flags`. The band READS the two globals from here
##     through the ancestor chain.
##   - `compfor_iter_arg` stays too, for two independent reasons: it is `pub` (other back ends call it
##     as `lower::compfor_iter_arg`), and it calls `fnty_skip_ws`, which band 3 already moved into the
##     `lower::fnval` CHILD — a bare call from one child to another is a SIBLING reach that Modules §3
##     gives no legal spelling. Left in the parent it is parent -> child, which §3 does sanction, and
##     its call to this band's `comptime_arg_end` is parent -> child as well.
##
## NOTE the import ORDER: a BARE module alias (`strbuf := rt`) followed by a listed projection is a
## parse error in the self-host parser unless a QUALIFIED alias (`x := m::y`) separates them.
strbuf := rt
arg_p := ast::arg_p
arm_p := ast::arm_p
fld_p := ast::fld_p
param_p := ast::param_p
stmt_p := ast::stmt_p
(Arg, Decl, Expr, Param, Stmt) := ast
(push_str, push_int) := strbuf
(CSpan, LCtx, arg_expr_at, var_name_span) := lower_ctx
(base_type_name, ct_bind_depth, ct_bound_value, enum_decl_of, struct_decl_of, typearg_at) := lower_layout
## SIBLING child, reached by an EXPLICIT qualified path (Modules §4). It was a bare name until the
## place band moved to `src/lower/place.al`; a bare child-to-child call would bind through the
## unique-declaration leniency, which `scripts/callee_module_check.sh` cannot see.
(field_place_parts) := lower::place

## Recursion budget for a `comptime if <CONST>` chain (a module const whose value is itself a const).
## A cycle terminates at -1 (the located reject) instead of recursing forever.
mut COMPTIME_CONST_DEPTH : i64 = 0

## Is `s` a non-empty run of ASCII decimal digits (an integer flag default)?
bf_is_int := fn(s : str) -> bool {
  if s.len == 0 { return false }
  mut i := 0
  while i < s.len { c := bytes(s)[i] ; if c < 48 or c > 57 { return false } ; i += 1 }
  return true
}
bf_parse_int := fn(s : str) -> i64 {
  mut v := 0
  mut i := 0
  while i < s.len { v = v * 10 + i64(bytes(s)[i] - 48) ; i += 1 }
  return v
}

## Scan the profile-flag blob for `build.<name>` and classify its value in ONE code (no str-carrying
## struct return — reading a `str` field out of a returned aggregate is a lean-lower landmine, so the
## value `str` never leaves this frame): `1` = bool true · `0` = bool false · `>= 8` = an integer flag
## whose value is `code - 8` · `0 - 2` = found but not a bool/integer · `0 - 3` = not declared. Blob lines
## are `name=value\n`; each name span is compared to `name`, the value span to `true`/`false` or digits.
build_flag_scan := fn(name : str) -> i64 {
  if BUILD_FLAGS_N == 0 { return 0 - 3 }
  blob := str_at(unchecked bitcast(ptr(u8), BUILD_FLAGS_P), BUILD_FLAGS_N)
  bb := unchecked bitcast(usize, blob.ptr)
  mut i := 0
  while i < blob.len {
    mut e := i
    while e < blob.len and bytes(blob)[e] != 61 { e = e + 1 }        ## '=' (61)
    mut le := e
    while le < blob.len and bytes(blob)[le] != 10 { le = le + 1 }    ## end of line (10)
    if e < blob.len {
      nm := str_at(bb + i, e - i)
      if nm == name {
        ## The manifest scanner is intentionally shallow. A profile override may leave a closing
        ## aggregate delimiter adjacent to the token when it is reassembled from a list slice, so
        ## trim harmless whitespace/delimiters before classifying the value. This keeps the query
        ## surface fail-loud without mistaking `true)` for a non-bool flag.
        mut ve := le
        while ve > e + 1 and (bytes(blob)[ve - 1] == 32 or bytes(blob)[ve - 1] == 9 or bytes(blob)[ve - 1] == 10 or bytes(blob)[ve - 1] == 13 or bytes(blob)[ve - 1] == 41 or bytes(blob)[ve - 1] == 93 or bytes(blob)[ve - 1] == 125) { ve = ve - 1 }
        val := str_at(bb + e + 1, ve - (e + 1))
        if val == "true" { return 1 }
        if val == "false" { return 0 }
        if bf_is_int(val) { return bf_parse_int(val) + 8 }
        return 0 - 2
      }
    }
    i = le + 1
  }
  return 0 - 3
}

## Fold `comptime if build.<name>` to 1 (true) / 0 (false). A comptime-if condition is a bool (Comptime
## §8.2), so only bool flags are foldable here. `build.debug` defaults TRUE (the `debug` default profile)
## when the blob does not carry it (a bare compile with no manifest). An undeclared flag, or a value that
## is not a bool, FAILS LOUD (never a silent false).
build_flag_bool := fn(name : str) -> i64 {
  c := build_flag_scan(name)
  if c == 1 { return 1 }
  if c == 0 { return 0 }
  if c == 0 - 3 {
    if name == "debug" { return 1 }
    panic("selfhost: comptime if build.<name> — flag not declared in the manifest profile_flags")
    return 0
  }
  panic("selfhost: comptime if build.<name> — the flag is not a bool")
  return 0
}

build_flag_str_eq := fn(name : str, rhs : str) -> i64 {
  if BUILD_FLAGS_N == 0 {
    if name == "profile" { if rhs == "debug" { return 1 } return 0 }
    panic("selfhost: build.<name> comparison — flag not declared in the manifest profile_flags")
  }
  c := build_flag_scan(name)
  if c >= 8 or c == 0 or c == 1 {
    panic("selfhost: build.<name> comparison — the flag is not a str or enum")
    return 0
  }
  blob := str_at(unchecked bitcast(ptr(u8), BUILD_FLAGS_P), BUILD_FLAGS_N)
  bb := unchecked bitcast(usize, blob.ptr)
  mut i := 0
  while i < blob.len {
    mut e := i
    while e < blob.len and bytes(blob)[e] != 61 { e = e + 1 }
    mut le := e
    while le < blob.len and bytes(blob)[le] != 10 { le = le + 1 }
    if e < blob.len {
      nm := str_at(bb + i, e - i)
      if nm == name {
        mut ve := le
        while ve > e + 1 and (bytes(blob)[ve - 1] == 32 or bytes(blob)[ve - 1] == 9 or bytes(blob)[ve - 1] == 10 or bytes(blob)[ve - 1] == 13 or bytes(blob)[ve - 1] == 41 or bytes(blob)[ve - 1] == 93 or bytes(blob)[ve - 1] == 125) { ve = ve - 1 }
        val := str_at(bb + e + 1, ve - (e + 1))
        if val == rhs { return 1 }
        return 0
      }
    }
    i = le + 1
  }
  if name == "profile" { if rhs == "debug" { return 1 } return 0 }
  panic("selfhost: build.<name> comparison — flag not declared in the manifest profile_flags")
  return 0
}

## Compare an integer-typed profile flag with a bare integer comptime value. The profile blob deliberately
## carries values rather than a second type table, so `build_flag_scan`'s classification is the lower's
## boundary: `>= 8` is an integer, `0`/`1` is bool, `-2` is str/enum, and `-3` is undeclared. A type
## mismatch is rejected here instead of falling through to the generic comptime-condition diagnostic.
build_flag_int_eq := fn(name : str, rhs : i64) -> i64 {
  c := build_flag_scan(name)
  if c >= 8 {
    if c - 8 == rhs { return 1 }
    return 0
  }
  if c == 0 - 3 {
    panic("selfhost: build.<name> comparison — flag not declared in the manifest profile_flags")
    return 0
  }
  panic("selfhost: build.<name> comparison — the flag is not an integer")
  return 0
}

build_cmp_rhs_text := fn(e : ptr(Expr), src : ptr(u8), a : rt::Arena) -> str {
  match deref(e) {
    Expr::StrLit(rs, rn, rl, _ps, _pn) => { return str_at((src + rs), rn) }
    Expr::Field(rb, rfs, rfl) => {
      rvn := var_name_span(rb)
      if rvn.n != 0 {
        mut sb := rt::strbuf(a, rvn.n + rfl + 16)
        k1 := rt::push_str(sb, str_at((src + rvn.s), rvn.n))
        k2 := rt::push_byte(sb, 46)
        k3 := rt::push_str(sb, str_at((src + rfs), rfl))
        return str_at(sb.data, sb.len)
      }
      return ""
    }
    ## `E.V` — a nullary enum-variant reference. When `E` names a KNOWN enum the parser emits an `EnumLit`
    ## (not a `Field`, see parser.al §1840); rebuild the canonical `E.V` text (matching the manifest blob's
    ## `mode=Mode.slow` token, cli.al `mf_token`) so an enum-typed profile flag compares by variant.
    Expr::EnumLit(ees, eel, evs, evl, enp, eah) => {
      if eel != 0 {
        mut eb := rt::strbuf(a, eel + evl + 16)
        j1 := rt::push_str(eb, str_at((src + ees), eel))
        j2 := rt::push_byte(eb, 46)
        j3 := rt::push_str(eb, str_at((src + evs), evl))
        return str_at(eb.data, eb.len)
      }
      return ""
    }
    _ => { return "" }
  }
}

## The `build.<name>` LHS of a comptime `build.<name> == …` comparison (Tooling §2.6/§2.7): the flag-NAME
## span when `l` is a `Field` whose base `Var` is `build`, else `n == 0`. A SEPARATE fn so the caller
## (`comptime_cond_eval`'s `Bin` arm) needs no nested `match deref(l)` inside a `match` arm — a self-host
## lower idiom limit (mirrors `build_cmp_rhs_text` / `arch_rhs_name`, and the `decl_guard_fold` note).
build_lhs_flag_name := fn(l : ptr(Expr), src : ptr(u8)) -> CSpan {
  match deref(l) {
    Expr::Field(lb, lfs, lfl) => {
      lvn := var_name_span(lb)
      if lvn.n != 0 and str_at((src + lvn.s), lvn.n) == "build" { return CSpan(s = lfs, n = lfl) }
      return CSpan(s = 0, n = 0)
    }
    _ => { return CSpan(s = 0, n = 0) }
  }
}

## Emit a bare `build.<name>` VALUE expression as an immediate push (Tooling §2.7): a bool flag → 0/1, an
## integer flag → its default; `build.debug` → 1 (the debug default profile). A str/enum-typed flag value
## in value position is NOT supported by the lean lower → FAILS LOUD (scoped out; the v1 value surface is
## bool + integer). An undeclared flag FAILS LOUD.
pub emit_build_flag_value := fn(name : str, in out sb : strbuf::StrBuf) {
  c := build_flag_scan(name)
  mut v := 0
  if c == 1 { v = 1 }
  else if c == 0 { v = 0 }
  else if c >= 8 { v = c - 8 }
  else if c == 0 - 3 {
    if name == "debug" { v = 1 }
    else { panic("selfhost: build.<name> value — flag not declared in the manifest profile_flags") }
  } else { panic("selfhost: build.<name> value — only bool/integer flags are supported as a value") }
  push_str(sb, "  movq $")
  push_int(sb, v)
  push_str(sb, ", %rax\n  pushq %rax\n")
}
## Conservative capability-query predicate for build-path folding. It answers whether the operand's
## names resolve in the current declaration/module environment and, for `compiles`, applies the
## bounded literal/inferred-type compatibility checks below. Runtime evaluation is never performed.
comptime_query_is_str_lit := fn(e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::StrLit(_s, _n, _l, _ps, _pn) => { true }
    _ => { false }
  }
}
## The supported scalar `v.(f)` projection inside a `comptime for f in typeinfo(S).fields` body.
## The ordinary emitter already resolves this AST shape through the active `cf_*` context. The query
## mirror must use the same concrete field type, otherwise a valid projection is treated as unknown and
## every `compiles(v.(f))` answer becomes false. This helper is query-only: aggregate/str projections
## remain fail-loud in ordinary value position, while the capability query may compare their exact type
## without evaluating or emitting the operand.
comptime_query_comp_field_type := fn(e : ptr(Expr), cx : ptr(LCtx), a : rt::Arena) -> CSpan {
  match deref(e) {
    Expr::CompField(base, idx) => {
      if cx.cf_var_l == 0 { return CSpan(s = 0, n = 0) }
      vn := var_name_span(idx)
      if vn.n == 0 or not streq(cx.src, vn.s, vn.n, cx.cf_var_s, cx.cf_var_l) { return CSpan(s = 0, n = 0) }
      bt := expr_type_span(base, cx)
      if bt.n == 0 { return CSpan(s = 0, n = 0) }
      ft := field_type_span(cx.decls, cx.src, bt.s, bt.n, cx.cf_fld_s, cx.cf_fld_l, deref(cx.mar))
      if ft.n == 0 { return CSpan(s = 0, n = 0) }
      ft
    }
    _ => { CSpan(s = 0, n = 0) }
  }
}
comptime_query_arg_ok := fn(e : ptr(Expr), pm : ptr(mut Param), cx : ptr(LCtx), a : rt::Arena) -> bool {
  pb := base_type_name(cx.src, deref(pm).ts, deref(pm).tl)
  mut et := comptime_query_comp_field_type(e, cx, a)
  if et.n == 0 { et = expr_type_span(e, cx) }
  if et.n != 0 and pb.n != 0 { return norm_type_eq(cx.src, et.s, et.n, pb.s, pb.n) }
  if arg_is_num_literal(e) { return is_int_scalar_type(cx.src, pb.s, pb.n) }
  if arg_is_float_literal(e) { return is_float_scalar_type(cx.src, pb.s, pb.n) }
  if comptime_query_is_str_lit(e) { return str_at((cx.src + pb.s), pb.n) == "str" }
  true
}
comptime_query_call_ok := fn(cs : usize, cl : usize, na : usize, ah : ptr(mut Arg), cx : ptr(LCtx), a : rt::Arena, types : bool) -> bool {
  cnt := rt::vec_len(deref(cx.decls))
  cp := colon_pos(cx.src, cs, cl)
  mut qns := cs
  mut qnl := cl
  mut qms := cx.mod_s
  mut qml := cx.mod_l
  if cp >= 0 {
    qns = cs + usize(cp) + 2
    qnl = cl - usize(cp) - 2
    qms = cs
    qml = usize(cp)
    ## Modules §4.1 / MOD-4: a renamed module alias (`m := std::math`) is
    ## the same namespace as its RHS path. The ordinary lower already follows
    ## this binding for `m::floor`; keep the query mirror on the same path.
    ## Only a single-segment head is an alias (multi-segment heads are already
    ## literal module paths), and the alias must belong to the caller module.
    if colon_pos(cx.src, qms, qml) < 0 {
      mut i := 0
      mut as_ := 0
      mut al := 0
      while i < cnt {
        d := deref(decl_get(cx.decls, i))
        if d.kind == 0 and d.arity == 0 and d.ret_tl != 0 and d.name_len == qml
          and streq(cx.src, d.name_start, d.name_len, qms, qml)
          and streq(cx.src, d.mod_start, d.mod_len, cx.mod_s, cx.mod_l) {
          as_ = d.ret_ts
          al = d.ret_tl
        }
        i += 1
      }
      if al != 0 { qms = as_ ; qml = al }
    }
  }
  mut found := false
  mut i := 0
  while i < cnt {
    d := deref(decl_get(cx.decls, i))
    mut name_ok := streq(cx.src, d.name_start, d.name_len, qns, qnl)
    mut module_ok := true
    if cp >= 0 { module_ok = mod_head_matches(cx.src, d.mod_start, d.mod_len, qms, qml) }
    if (d.kind == 1 or d.kind == 4) and d.arity == na and name_ok and module_ok {
      if not types {
        found = true
      } else if d.is_generic {
        found = true
      } else {
        mut p := d.params_head
        mut g := ah
        mut ok := true
        while p != 0 and g != 0 {
          pm := param_p(p)
          if not comptime_query_arg_ok(deref(arg_p(g)).e, pm, cx, a) { ok = false }
          p = deref(pm).next
          g = deref(arg_p(g)).next
        }
        if p != 0 or g != 0 { ok = false }
        if ok { found = true }
      }
    }
    i += 1
  }
  found
}
## The build-path query mirror for the narrow QUERY constructor/binary conformance boundary. The
## canonical sema attempt rejects a known aggregate beside a scalar literal; build lowering has a
## deliberately conservative fallback because it may receive an AST copy after the sema rewrite. Keep
## this mirror limited to that exact shape so aggregate+aggregate operator overloads remain resolvable.
comptime_query_bin_aggregate_bad := fn(op : u8, l : ptr(Expr), r : ptr(Expr), cx : ptr(LCtx), a : rt::Arena, types : bool) -> bool {
  if not types { return false }
  if op == 20 or op == 24 or op == 25 or op == 26 or op == 27 or op == 28 { return false }
  if op == 40 or op == 41 or op == 42 { return false }
  lt := expr_type_span(l, cx)
  rt := expr_type_span(r, cx)
  mut la := false
  mut ra := false
  if lt.n != 0 { la = struct_decl_of(cx.decls, cx.src, lt.s, lt.n) >= 0 or enum_decl_of(cx.decls, cx.src, lt.s, lt.n) >= 0 }
  if rt.n != 0 { ra = struct_decl_of(cx.decls, cx.src, rt.s, rt.n) >= 0 or enum_decl_of(cx.decls, cx.src, rt.s, rt.n) >= 0 }
  if la and expr_is_numlit(r) and operator_decl_idx(cx.decls, cx.src, i64(op), lt.s, lt.n, a) >= 0 { la = false }
  if ra and expr_is_numlit(l) and operator_decl_idx(cx.decls, cx.src, i64(op), rt.s, rt.n, a) >= 0 { ra = false }
  (la and expr_is_numlit(r)) or (ra and expr_is_numlit(l))
}
pub comptime_query_expr_ok := fn(e : ptr(Expr), cx : ptr(LCtx), a : rt::Arena, types : bool) -> bool {
  match deref(e) {
    Expr::Num(v, s, n) => { true }
    Expr::BoolLit(v) => { true }
    Expr::FloatLit(s, n) => { true }
    Expr::StrLit(s, n, l, _ps, _pn) => { true }
    Expr::Var(s, n) => {
      ei := entry_of(cx.slots, cx.src, s, n)
      ent := deref(svec_at(SlotEntry, cx.slots, ei))
      if streq(cx.src, ent.ns, ent.nl, s, n) { return true }
      if unchecked bitcast(usize, module_const_value(cx.decls, cx.src, s, n)) != 0 { return true }
      is_module_mut_global(cx.decls, cx.src, s, n)
    }
    Expr::Bin(op, l, r) => {
      if comptime_query_bin_aggregate_bad(op, l, r, cx, a, types) { return false }
      comptime_query_expr_ok(l, cx, a, types) and comptime_query_expr_ok(r, cx, a, types)
    }
    Expr::Call(cs, cl, na, ah) => {
      if not comptime_query_call_ok(cs, cl, na, ah, cx, a, types) { return false }
      mut g := ah
      mut ok := true
      while g != 0 {
        if not comptime_query_expr_ok(deref(arg_p(g)).e, cx, a, types) { ok = false }
        g = deref(arg_p(g)).next
      }
      ok
    }
    Expr::StructLit(_ss, _sl, _nf, fh) => {
      mut g := fh
      mut ok := true
      while g != 0 {
        if not comptime_query_expr_ok(deref(arg_p(g)).e, cx, a, types) { ok = false }
        g = deref(arg_p(g)).next
      }
      ok
    }
    Expr::EnumLit(_es, _el, _vs, _vl, _np, ph) => {
      mut g := ph
      mut ok := true
      while g != 0 {
        if not comptime_query_expr_ok(deref(arg_p(g)).e, cx, a, types) { ok = false }
        g = deref(arg_p(g)).next
      }
      ok
    }
    Expr::ArrayLit(_nel, eh) => {
      mut g := eh
      mut ok := true
      while g != 0 {
        if not comptime_query_expr_ok(deref(arg_p(g)).e, cx, a, types) { ok = false }
        g = deref(arg_p(g)).next
      }
      ok
    }
    Expr::If(c, t, f) => { comptime_query_expr_ok(c, cx, a, types) and comptime_query_expr_ok(t, cx, a, types) and comptime_query_expr_ok(f, cx, a, types) }
    Expr::CompField(base, idx) => {
      if not comptime_query_expr_ok(base, cx, a, types) { false }
      else { comptime_query_comp_field_type(e, cx, a).n != 0 }
    }
    _ => { false }
  }
}
## The `<Base>.<name>` pair of a qualified reference (`Arch.x86_64`, `Os.linux`, `Env.gnu`,
## `Container.elf`, and equally the LHS `target.arch`): `bs/bl` = the BASE name span, `s/n` = the
## trailing name span; `n == 0` when `e` is not a `Field` over a bare `Var`. The generalisation of
## `arch_rhs_name` to all four TARGET facets (Tooling §2.7: `target.arch` / `target.os` /
## `target.env` / `target.container`).
QRef := struct { bs : usize, bl : usize, s : usize, n : usize }
qual_ref_name := fn(e : ptr(Expr), src : ptr(u8)) -> QRef {
  match deref(e) {
    Expr::Field(b, fs, fl) => {
      vn := var_name_span(b)
      if vn.n != 0 { return QRef(bs = vn.s, bl = vn.n, s = fs, n = fl) }
      QRef(bs = 0, bl = 0, s = 0, n = 0)
    }
    _ => { QRef(bs = 0, bl = 0, s = 0, n = 0) }
  }
}

## The selected package artifact kind, forwarded by the CLI through driver. 0 = executable (the
## manifest/default kind), 1 = object, 2 = static_lib, 3 = source, 4 = shared_lib. The latter two
## are only observable on the check path today; build rejects unsupported artifact kinds before
## lowering. Keep this as a scalar fact at the child boundary so `src/lower.al` remains untouched.
mut TARGET_KIND : usize = 0
pub set_target_kind := fn(kind : usize) -> i64 {
  TARGET_KIND = kind
  return 0
}

## Selected Target.code_size: 0 = b16, 1 = b32, 2 = b64 (x86_64 default).
mut TARGET_CODE_SIZE : usize = 2
pub set_target_code_size := fn(code_size : usize) -> i64 {
  TARGET_CODE_SIZE = code_size
  return 0
}

## Selected Machine projections (Tooling §2.7). Defaults describe the compiler's existing host-shaped
## target; the CLI replaces them with the fully resolved variant before any source reaches lowering.
## Codes match the manifest scanner: Arch x86_64/i386/aarch64/aarch32/riscv32/riscv64 = 0..5,
## Os linux/android/windows/macos/freebsd/none = 0..5, Env gnu/musl/eabi/eabihf/bionic/none = 0..5,
## Container elf/pe/macho/com = 0..3, Startup raw/libc = 0..1, Subsystem console/windows/native = 0..2.
mut TARGET_ARCH : usize = 0
mut TARGET_OS : usize = 0
mut TARGET_ENV : usize = 0
mut TARGET_CONTAINER : usize = 0
mut TARGET_STARTUP : usize = 0
mut TARGET_SUBSYSTEM : usize = 0
pub set_target_model := fn(arch : usize, os : usize, env : usize, container : usize, startup : usize, subsystem : usize) -> i64 {
  TARGET_ARCH = arch
  TARGET_OS = os
  TARGET_ENV = env
  TARGET_CONTAINER = container
  TARGET_STARTUP = startup
  TARGET_SUBSYSTEM = subsystem
  return 0
}

target_model_rhs_code := fn(base : str, value : str) -> usize {
  if base == "Arch" {
    if value == "x86_64" { return 0 }
    if value == "i386" { return 1 }
    if value == "aarch64" { return 2 }
    if value == "aarch32" { return 3 }
    if value == "riscv32" { return 4 }
    if value == "riscv64" { return 5 }
  }
  if base == "Os" {
    if value == "linux" { return 0 }
    if value == "android" { return 1 }
    if value == "windows" { return 2 }
    if value == "macos" { return 3 }
    if value == "freebsd" { return 4 }
    if value == "none" { return 5 }
  }
  if base == "Env" {
    if value == "gnu" { return 0 }
    if value == "musl" { return 1 }
    if value == "eabi" { return 2 }
    if value == "eabihf" { return 3 }
    if value == "bionic" { return 4 }
    if value == "none" { return 5 }
  }
  if base == "Container" {
    if value == "elf" { return 0 }
    if value == "pe" { return 1 }
    if value == "macho" { return 2 }
    if value == "com" { return 3 }
  }
  if base == "Startup" {
    if value == "raw" { return 0 }
    if value == "libc" { return 1 }
  }
  if base == "Subsystem" {
    if value == "console" { return 0 }
    if value == "windows" { return 1 }
    if value == "native" { return 2 }
  }
  99
}

target_model_current_code := fn(facet : str) -> usize {
  if facet == "arch" { return TARGET_ARCH }
  if facet == "os" { return TARGET_OS }
  if facet == "env" { return TARGET_ENV }
  if facet == "container" { return TARGET_CONTAINER }
  if facet == "startup" { return TARGET_STARTUP }
  if facet == "subsystem" { return TARGET_SUBSYSTEM }
  99
}

## Fold the EQUALITY of a TARGET-facet comparison `target.<facet> <op> <Enum>.<variant>` against THIS
## build's machine model (Comptime §9.2, Tooling §2.7). The lean target is the one `package.al`
## declares — x86_64 / linux / gnu / elf — so: 1 = the RHS variant IS this build's value for that
## facet, 0 = it names a different one, -1 = the operand pair is not a target-facet comparison at all
## (the caller defers). The RESULT IS THE `==` ANSWER; the caller applies the operator, which is what
## the previous RHS-only arch fold failed to do. The `arch` facet reproduces `arch_rhs_name`'s fold
## exactly for `==` (every `src/`+`lib/` site spells `target.arch == Arch.<name>`), so the self-build's
## emission is unchanged.
pub target_facet_eq := fn(l : ptr(Expr), r : ptr(Expr), src : ptr(u8)) -> i64 {
  lq := qual_ref_name(l, src)
  if lq.n == 0 { return -1 }
  if str_at((src + lq.bs), lq.bl) != "target" { return -1 }
  rq := qual_ref_name(r, src)
  if rq.n == 0 { return -1 }
  facet := str_at((src + lq.s), lq.n)
  base := str_at((src + rq.bs), rq.bl)
  vnm := str_at((src + rq.s), rq.n)
  rhs := target_model_rhs_code(base, vnm)
  current := target_model_current_code(facet)
  if rhs < 99 and current < 99 {
    if rhs == current { return 1 }
    return 0
  }
  if facet == "kind" and base == "Kind" {
    if vnm == "executable" { if TARGET_KIND == 0 { return 1 } return 0 }
    if vnm == "object" { if TARGET_KIND == 1 { return 1 } return 0 }
    if vnm == "static_lib" { if TARGET_KIND == 2 { return 1 } return 0 }
    if vnm == "source" { if TARGET_KIND == 3 { return 1 } return 0 }
    if vnm == "shared_lib" { if TARGET_KIND == 4 { return 1 } return 0 }
    return -1
  }
  if facet == "code_size" and base == "CodeSize" {
    if vnm == "b16" { if TARGET_CODE_SIZE == 0 { return 1 } return 0 }
    if vnm == "b32" { if TARGET_CODE_SIZE == 1 { return 1 } return 0 }
    if vnm == "b64" { if TARGET_CODE_SIZE == 2 { return 1 } return 0 }
    return -1
  }
  return -1
}

## The end offset of the balanced TYPE text starting at `p0` — the `)` that closes the enclosing
## `typeinfo(`, or a top-level `,`; trailing whitespace trimmed. `p0` itself when no terminator is
## found inside `lim`. Keeps a nested spelling (`ptr(T)`, `Vec(u64)`, `[T; 4]`) whole, exactly as
## `cx.it` holds one.
pub comptime_arg_end := fn(src : ptr(u8), p0 : usize, lim : usize) -> usize {
  mut p := p0
  mut d := 0
  mut r := p0
  mut done := false
  while p < lim and done == false {
    c := str_at((src + p), 1)
    if c == "(" or c == "[" { d = d + 1 ; p = p + 1 }
    else if c == "]" { if d > 0 { d = d - 1 } ; p = p + 1 }
    else if c == ")" { if d == 0 { r = p ; done = true } else { d = d - 1 ; p = p + 1 } }
    else if c == "," { if d == 0 { r = p ; done = true } else { p = p + 1 } }
    else { p = p + 1 }
  }
  if done == false { return p0 }
  mut e := r
  mut trim := true
  while e > p0 and trim {
    c2 := str_at((src + (e - 1)), 1)
    if c2 == " " or c2 == "\n" or c2 == "\t" or c2 == "\r" { e = e - 1 } else { trim = false }
  }
  e
}


## The CONCRETE type a `comptime for … in typeinfo(X).…` header ITERATES: the header's `typeinfo(X)`
## argument (recovered by source-scan) resolved through the enclosing instance's type-PARAMETER
## bindings with the SAME `guard_resolve_tp` the `when` path uses — `X` names one of the 1st/2nd/3rd
## type-params → that param's concrete instance type; a concrete type name → itself. Falls back to the
## instance type `cx.it` when the header cannot be scanned, so every header `src/`+`lib/` spells
## (`typeinfo(T)`, T = the 1st type-param) resolves to exactly the `cx.it` the previous `cx.it`-only
## emit used → byte-identical, fixpoint-neutral.
pub compfor_target_type := fn(cx : ptr(LCtx), vs : usize, vl : usize) -> CSpan {
  cftp := GuardTP(gp_s = cx.gp_s, gp_l = cx.gp_l, its = cx.it_s, itl = cx.it_l,
                  gp2_s = cx.gp2_s, gp2_l = cx.gp2_l, its2 = cx.it2_s, itl2 = cx.it2_l,
                  gp3_s = cx.gp3_s, gp3_l = cx.gp3_l, its3 = cx.it3_s, itl3 = cx.it3_l)
  ia := compfor_iter_arg(cx.src, vs, vl)
  if ia.n == 0 { return CSpan(s = cx.it_s, n = cx.it_l) }
  guard_resolve_tp(ptr(cftp), cx.src, ia.s, ia.n)
}

## Write the SOURCE LINE containing byte offset `off` (with its newline) to stderr — the lean lower's
## stand-in for a LOCATED diagnostic. The lower has no diagnostic channel of its own (every other
## fail-loud here is a bare static `panic`), so the location is one `write(2, …)` straight out of the
## source text; the caller then panics with the reason.
pub lower_show_src_line := fn(src : ptr(u8), off : usize) {
  mut lo : usize = 0
  if off > 4096 { lo = off - 4096 }
  mut s := off
  while s > lo and str_at((src + (s - 1)), 1) != "\n" { s = s - 1 }
  hi := off + 4096
  mut e := off
  while e < hi and str_at((src + e), 1) != "\n" { e = e + 1 }
  mut n := e - s
  if e < hi { n = n + 1 }
  w := rt::sys_write(1, 2, unchecked bitcast(usize, rt::addr(src, s)), n)
}

## A representative SOURCE OFFSET for a condition expression — the leftmost leaf that carries a span
## of its own (a `Var` / `Field` / `Call` / `StrLit` name). 0 when none does. Recurses on itself
## (never a nested `match`) to stay within the self-host lower's idiom limits.
pub comptime_cond_src_off := fn(e : ptr(Expr)) -> usize {
  match deref(e) {
    Expr::Var(vs, vn) => { vs }
    Expr::Field(fb, ffs, ffl) => { ffs }
    Expr::Call(ccs, ccl, cna, cah) => { ccs }
    Expr::StrLit(sls, sln, sll, _ps, _pn) => { sls }
    Expr::Bin(bop, bl, br) => {
      mut o := comptime_cond_src_off(bl)
      if o == 0 { o = comptime_cond_src_off(br) }
      o
    }
    Expr::Match(msc, mah) => { comptime_cond_src_off(msc) }
    _ => { 0 }
  }
}

## Fail LOUD on a `comptime if` condition the lower cannot fold. Comptime §9.1/§9.2: the controlling
## expression MUST be comptime-known and emission applies to the SELECTED branch — so "cannot fold"
## has no selected branch and MUST be a REJECT. Emitting NEITHER arm (the previous behaviour) silently
## DELETES both arms' effects, which is a silent miscompile: `comptime if target.os == Os.linux
## { x = 30 } else { x = 70 }` left `x` at its prior value with no diagnostic at all. The offending
## source line is written to stderr first (`lower_show_src_line`), so the reject is located.
pub comptime_reject_cond := fn(cond : ptr(Expr), src : ptr(u8)) {
  off := comptime_cond_src_off(cond)
  if off != 0 { lower_show_src_line(src, off) }
  panic("selfhost: `comptime if` — cannot fold this comptime condition (the source line above). The lower folds target machine projections, verify.checked, build.<flag>, a module const, an integer comparison, size(T), typeinfo(T).fields/variants.len, a type equality, a `match typeinfo(T)` kind test, resolves(…)/compiles(…), and and/or/not over those. Rejected rather than silently emitting NEITHER branch.")
}
## Fold a `comptime if` condition at compile time: 1 = true (emit the then-branch), 0 = false (emit
## the else-branch), -1 = cannot fold — which the CALLER turns into a LOCATED REJECT
## (`comptime_reject_cond`), never a silent "emit neither branch".
##
## The lean target is x86_64 / linux / gnu / elf, and the selected package artifact kind is forwarded
## as `TARGET_KIND`, so `target.<facet> == <Enum>.<variant>` folds against
## that model (and `!=` is its NEGATION — see `target_facet_eq`), and `verify.checked` folds to the
## current mode (`cx.vchk`: 1 checked / 0 inside `unchecked`). Everything structural — `size(X)`,
## `typeinfo(X).fields.len`, `match typeinfo(X) { <Kind>(_) => … }` — DELEGATES to the `when`-guard fold
## helpers (`guard_size_operand` / `guard_field_count` / `guard_typeinfo_kind` over a `GuardTP` built
## from this context's type-param bindings) rather than carrying a second, weaker evaluator: `comptime
## if` and `when` now fold the same predicates the same way, and both honour the `typeinfo(X)` ARGUMENT
## instead of assuming the instance type.
pub comptime_cond_eval := fn(cond : ptr(Expr), cx : ptr(LCtx), a : rt::Arena) -> i64 {
  src := cx.src
  ## This context's type-parameter bindings as the `when`-guard fold's own `GuardTP` bundle, built as
  ## THIS function's OWN top-level local — a `GuardTP` address-taken deep inside a match arm has no
  ## reliable frame home in the lean lower (see `guard_pred_call_fold`).
  cetp := GuardTP(gp_s = cx.gp_s, gp_l = cx.gp_l, its = cx.it_s, itl = cx.it_l,
                  gp2_s = cx.gp2_s, gp2_l = cx.gp2_l, its2 = cx.it2_s, itl2 = cx.it2_l,
                  gp3_s = cx.gp3_s, gp3_l = cx.gp3_l, its3 = cx.it3_s, itl3 = cx.it3_l)
  tp := ptr(cetp)
  match deref(cond) {
    Expr::BoolLit(v) => { if v != 0 { return 1 } return 0 }
    Expr::Unchecked(inner) => { return comptime_cond_eval(inner, cx, a) }
    Expr::Call(cs, cl, na, ah) => {
      nm := str_at((src + cs), cl)
      if (nm == "resolves" or nm == "compiles") and na == 1 {
        qa := arg_expr_at(ah, 0, a)
        if unchecked bitcast(usize, qa) == 0 { return 0 }
        if comptime_query_expr_ok(qa, cx, a, nm == "compiles") { return 1 }
        return 0
      }
      ## `resolves(f, arg, …)` — the SPEC's own arity-≥2 capability query (Comptime §6.1/§10:
      ## `resolves-query ::= "resolves" "(" fn-expr "," arg-list ")"`): does a call to `f` with THESE
      ## arguments resolve? Split the leading fn-expr off as the CALLEE and ask the same resolution
      ## the `compiles(expr)` query performs on a call. Previously ONLY the arity-1 spelling folded, so
      ## the spec form fell to -1 → NEITHER branch emitted (a deterministic-garbage return value).
      if nm == "resolves" and na >= 2 {
        f0 := arg_expr_at(ah, 0, a)
        fsp := var_name_span(f0)
        if fsp.n == 0 { return -1 }
        rtail := deref(arg_p(ah)).next
        if comptime_query_call_ok(fsp.s, fsp.n, na - 1, rtail, cx, a, true) { return 1 }
        return 0
      }
      return -1
    }
    Expr::Var(cvs, cvl) => {
      ## A local `comptime` binding has no frame slot; fold its recorded scalar expression exactly like
      ## a module constant, with the same recursion bound.
      cvlocal := comptime_slot_expr(cx.ctslots, cx.src, cvs, cvl)
      if unchecked bitcast(usize, cvlocal) != 0 {
        if COMPTIME_CONST_DEPTH >= 8 { return -1 }
        COMPTIME_CONST_DEPTH = COMPTIME_CONST_DEPTH + 1
        lcr := comptime_cond_eval(cvlocal, cx, a)
        COMPTIME_CONST_DEPTH = COMPTIME_CONST_DEPTH - 1
        return lcr
      }
      ## `comptime if <CONST>` — a module-level comptime constant used AS the whole condition
      ## (Comptime §9.1: any comptime-KNOWN controlling expression). Re-enter the evaluator on the
      ## constant's own value (`K := true`, `K := 1 < 2`, `K := target.os == Os.linux`), bounded by a
      ## depth counter so a const-refers-to-const cycle terminates at -1 (the located reject) instead
      ## of recursing forever. A bare RUNTIME local is not a module const → -1 → rejected, which is
      ## right: it is not comptime-known.
      cvv := module_const_value(cx.decls, src, cvs, cvl)
      if unchecked bitcast(usize, cvv) == 0 { return -1 }
      if COMPTIME_CONST_DEPTH >= 8 { return -1 }
      COMPTIME_CONST_DEPTH = COMPTIME_CONST_DEPTH + 1
      cr := comptime_cond_eval(cvv, cx, a)
      COMPTIME_CONST_DEPTH = COMPTIME_CONST_DEPTH - 1
      return cr
    }
    Expr::Bin(op, l, r) => {
      ## `comptime if build.<name> == "str"` / `== E.V` (Tooling §2.6/§2.7) — fold a str/enum-typed
      ## profile flag from the SELECTED profile blob. LHS is `build.<name>` (a `Field` whose base `Var`
      ## is `build`); RHS is a string literal or an `E.V` enum reference (`build_cmp_rhs_text`). Only
      ## `==`(20)/`!=`(28); an undeclared flag FAILS LOUD inside `build_flag_str_eq` (never a silent 0).
      ## Placed FIRST so it wins over the arch/type-name arms (whose RHS helpers do not match `build.*`).
      if i64(op) == 20 or i64(op) == 28 {
        bfn := build_lhs_flag_name(l, src)
        if bfn.n != 0 {
          rtext := build_cmp_rhs_text(r, src, a)
          if rtext.len != 0 {
            eqv := build_flag_str_eq(str_at((src + bfn.s), bfn.n), rtext)
            if i64(op) == 20 { return eqv }
            if eqv == 1 { return 0 }
            return 1
          }
        }
      }
      ## `comptime if build.<name> == N` / `!= N` (Tooling §2.7) — fold a declared integer profile
      ## flag against the bare numeric RHS. Keep this next to the str/enum arm: both are closed profile
      ## facts, and the helper gives a type-mismatch/undeclared flag a fail-loud boundary.
      if i64(op) == 20 or i64(op) == 28 {
        bfn := build_lhs_flag_name(l, src)
        if bfn.n != 0 and guard_expr_is_num(r) {
          eqv := build_flag_int_eq(str_at((src + bfn.s), bfn.n), guard_expr_num(r))
          if i64(op) == 20 { return eqv }
          if eqv == 1 { return 0 }
          return 1
        }
      }
      ## TARGET gating `target.<facet> == / != <Enum>.<variant>` (Comptime §9.2, Tooling §2.7) — the
      ## four machine facets plus selected artifact `kind` are folded against the current build, with the
      ## OPERATOR honoured. The previous fold read only the RHS `Arch.<name>` and returned the `==`
      ## answer for BOTH operators, so `comptime if target.arch != Arch.x86_64` emitted the WRONG
      ## branch — and disagreed with `sema::guard_fold`, `a64_comp_cond_fold`, `rv_comp_cond_fold` and
      ## `wat_comp_cond_fold`, every one of which already branches on `op == 20` / `op == 28`.
      if i64(op) == 20 or i64(op) == 28 {
        tfv := target_facet_eq(l, r, src)
        if tfv >= 0 {
          if i64(op) == 20 { return tfv }
          if tfv == 1 { return 0 }
          return 1
        }
      }
      ## `not <cond>` — the parser stores it as `Bin(42, operand, operand)`; negate the fold
      ## (1↔0, an unfoldable -1 stays -1).
      if i64(op) == 42 {
        lv := comptime_cond_eval(l, cx, a)
        if lv == 1 { return 0 }
        if lv == 0 { return 1 }
        return -1
      }
      ## boolean `and`(40)/`or`(41) composition (Comptime §4.2): recurse into both operands and
      ## combine. A decided operand short-circuits (`false and _` = 0, `true or _` = 1) even when the
      ## other is unfoldable; otherwise -1 (defer). Every operand is itself a comptime predicate
      ## (arch / verify / type-equality / nested and/or/not), folded by this same evaluator.
      if i64(op) == 40 {
        lv := comptime_cond_eval(l, cx, a)
        if lv == 0 { return 0 }
        rv := comptime_cond_eval(r, cx, a)
        if rv == 0 { return 0 }
        if lv == 1 and rv == 1 { return 1 }
        return -1
      }
      if i64(op) == 41 {
        lv := comptime_cond_eval(l, cx, a)
        if lv == 1 { return 1 }
        rv := comptime_cond_eval(r, cx, a)
        if rv == 1 { return 1 }
        if lv == 0 and rv == 0 { return 0 }
        return -1
      }
      ## scalar/nominal TYPE-name equality `T == <type>` / `T != <type>` (Comptime §4.1), folded inside
      ## a monomorphized instance where `T` = the concrete instance type (`cx.it`). The LHS must be a
      ## bare type-PARAMETER Var (not itself a concrete type name — so `u32 == u64` does NOT mis-fold as
      ## `cx.it == u64`), and the RHS a recognized type name. Covers the single-type-param generic; a
      ## multi-param `when U == …` would compare against `cx.it` (the tracked instance type) — future work.
      if (i64(op) == 20 or i64(op) == 28) and cx.it_l != 0 {
        lvn := var_name_span(l)
        if lvn.n != 0 and (not is_type_name(l, cx.decls, src, a)) and is_type_name(r, cx.decls, src, a) {
          rvn := var_name_span(r)
          itbn := base_type_name(src, cx.it_s, cx.it_l)
          eq := streq(src, itbn.s, itbn.n, rvn.s, rvn.n)
          if i64(op) == 20 { if eq { return 1 } return 0 }
          if eq { return 0 }
          return 1
        }
      }
      ## STRUCTURAL comparisons, DELEGATED to the `when`-guard fold helpers over this context's
      ## `GuardTP` (so `comptime if` and `when` agree to the byte): `size(X) <op> N` (§8 word model)
      ## and `typeinfo(X).fields.len` / `.variants.len` / `.n` `<op> N` (appendix §4.1), each with `X`
      ## resolved through the 1st/2nd/3rd type-param bindings — or a plain LITERAL comparison
      ## `N <op> M` (Comptime §4: a closed comptime fact). All three used to fall to -1.
      if guard_expr_is_num(r) {
        lsz := guard_size_operand(l, tp, cx.decls, src, a)
        if lsz >= 0 { return guard_cmp(i64(op), lsz, guard_expr_num(r)) }
        lcnt := guard_field_count(l, tp, cx.decls, src, a)
        if lcnt >= 0 { return guard_cmp(i64(op), lcnt, guard_expr_num(r)) }
        if guard_expr_is_num(l) { return guard_cmp(i64(op), guard_expr_num(l), guard_expr_num(r)) }
      }
      ## TYPE-NAME equality where BOTH sides are concrete type names (`u64 == u64`, `S != T` outside a
      ## generic) — Comptime §4.1's type equality as a closed comptime fact. Disjoint from the
      ## type-PARAMETER arm above, which requires the LHS to be a NON-type-name Var.
      if i64(op) == 20 or i64(op) == 28 {
        tl2 := var_name_span(l)
        tr2 := var_name_span(r)
        if tl2.n != 0 and tr2.n != 0 and is_type_name(l, cx.decls, src, a) and is_type_name(r, cx.decls, src, a) {
          teq := streq(src, tl2.s, tl2.n, tr2.s, tr2.n)
          if i64(op) == 20 { if teq { return 1 } return 0 }
          if teq { return 0 }
          return 1
        }
      }
      return -1
    }
    Expr::Field(b, fs, fl) => {
      vn := var_name_span(b)
      if vn.n != 0 and str_at((src + vn.s), vn.n) == "verify" {
        if cx.vchk { return 1 }
        return 0
      }
      ## `comptime if build.<flag>` (Tooling §2.7) — fold a bool profile flag from the selected profile;
      ## undeclared / non-bool fails LOUD inside `build_flag_bool` (never a silent 0).
      if vn.n != 0 and str_at((src + vn.s), vn.n) == "build" {
        return build_flag_bool(str_at((src + fs), fl))
      }
      return -1
    }
    Expr::Match(scrut, arms_head) => {
      ## `match typeinfo(X) { <Kind>(_) => true; _ => false }` — a structural is-KIND test, folded by
      ## the SCRUTINEE'S OWN argument `X` (resolved through the type-param bindings by
      ## `guard_typeinfo_kind`), exactly as `guard_fold_inst`'s twin arm folds a `when` guard. The
      ## first arm's variant name is the tested kind (`comptime_kind_of_name`); a match → the first
      ## arm's value (`true`, so 1), else the wildcard (`false`, so 0). Powers `derive`'s type dispatch.
      ##
      ## Previously this arm ignored `typeinfo`'s ARGUMENT and keyed off `cx.it` alone, so at top level
      ## (no instance) it deferred to -1 → NEITHER branch emitted, and inside an `A` instance
      ## `typeinfo(B)` tested A. It also fired on ANY `match` whose first arm happened to be named
      ## `Struct`/`Enum`/`Array`/`Scalar`; a non-`typeinfo(<type>)` scrutinee now folds to -1.
      k := guard_typeinfo_kind(scrut, tp, cx.decls, src, a)
      if k < 0 { return -1 }
      am := deref(arm_p(arms_head))
      if am.vl != 0 {
        want := comptime_kind_of_name(src, am.vs, am.vl)
        if want >= 0 {
          if k == want { return 1 }
          return 0
        }
      }
      return -1
    }
    _ => { return -1 }
  }
}

## Does a statement list contain a `comptime for … in typeinfo(T).fields` (`is_variants == 0`),
## possibly nested inside `comptime if` branches? Used by the mono worklist to instantiate a
## self-recursive derive for each field type. EXHAUSTIVE over `Stmt` (every arm sets `s = nx`) so
## the walk always terminates.
pub stmts_have_compfor := fn(head : ptr(mut Stmt), a : rt::Arena) -> bool {
  mut s := head
  mut found := false
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::CompFor(vs, vl, iv, b, nx) => { if iv == 0 { found = true } ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { if stmts_have_compfor(rb, a) { found = true } ; s = nx }
      Stmt::CompMatch(cmsc, cmah, nx) => { mut car : usize = cmah; while car != 0 { cam := deref(arm_p(car)); if stmts_have_compfor(cam.body_stmts, a) { found = true }; car = cam.next } ; s = nx }
      Stmt::CompIf(c, th, el, nx) => {
        if stmts_have_compfor(th, a) { found = true }
        if stmts_have_compfor(el, a) { found = true }
        s = nx
      }
      Stmt::If(c, th, el, nx) => { s = nx }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::Loop(b, nx) => { s = nx }
      Stmt::Unchecked(b, nx) => { s = nx }
      Stmt::AllocWith(ae, b, nx) => { s = nx }
      Stmt::For(f1, f2, f3, f4, fb, nx) => { s = nx }
      Stmt::Match(sc, ah, nx) => { s = nx }
      Stmt::Assign(a1, a2, a3, nx) => { s = nx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::FieldAssign(b1, b2, b3, b4, b5, nx) => { s = nx }
      Stmt::FieldPathAssign(pb1, pb2, nx) => { s = nx }
      Stmt::DerefAssign(p1, p2, nx) => { s = nx }
      Stmt::IndexAssign(i1, i2, i3, nx) => { s = nx }
      Stmt::IndexFieldAssign(j1, j2, j3, j4, j5, nx) => { s = nx }
      Stmt::Break(_bv, _bd, nx) => { s = nx }
      Stmt::Continue(_cd, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
    }
  }
  found
}

## Does a statement list contain a `match` with a COMPTIME-VARIANT-TEMPLATE arm (`wild == 2`), possibly
## nested? Used by the mono worklist to instantiate a self-recursive enum derive per variant PAYLOAD
## type. EXHAUSTIVE over `Stmt` so the walk terminates.
pub stmts_have_variant_template := fn(head : ptr(mut Stmt), a : rt::Arena) -> bool {
  mut s := head
  mut found := false
  while s != 0 {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Match(sc, ah, nx) => {
        mut arm := ah
        while arm != 0 {
          am := deref(arm_p(arm))
          if am.wild == 2 { found = true }
          if stmts_have_variant_template(am.body_stmts, a) { found = true }
          arm = am.next
        }
        s = nx
      }
      Stmt::CompIf(c, th, el, nx) => {
        if stmts_have_variant_template(th, a) { found = true }
        if stmts_have_variant_template(el, a) { found = true }
        s = nx
      }
      Stmt::CompFor(cvs, cvl, civ, cb, nx) => { if stmts_have_variant_template(cb, a) { found = true } ; s = nx }
      Stmt::CompForRange(rvs, rvl, rlo, rhi, rb, nx) => { if stmts_have_variant_template(rb, a) { found = true } ; s = nx }
      Stmt::CompMatch(cmsc, cmah, nx) => { mut car : usize = cmah; while car != 0 { cam := deref(arm_p(car)); if stmts_have_variant_template(cam.body_stmts, a) { found = true }; car = cam.next } ; s = nx }
      Stmt::If(c, th, el, nx) => {
        if stmts_have_variant_template(th, a) { found = true }
        if stmts_have_variant_template(el, a) { found = true }
        s = nx
      }
      Stmt::While(c, b, nx) => { s = nx }
      Stmt::Loop(b, nx) => { s = nx }
      Stmt::Unchecked(b, nx) => { s = nx }
      Stmt::AllocWith(ae, b, nx) => { s = nx }
      Stmt::For(f1, f2, f3, f4, fb, nx) => { s = nx }
      Stmt::Assign(a1, a2, a3, nx) => { s = nx }
      Stmt::Return(rv, nx) => { s = nx }
      Stmt::FieldAssign(b1, b2, b3, b4, b5, nx) => { s = nx }
      Stmt::FieldPathAssign(pb1, pb2, nx) => { s = nx }
      Stmt::DerefAssign(p1, p2, nx) => { s = nx }
      Stmt::IndexAssign(i1, i2, i3, nx) => { s = nx }
      Stmt::IndexFieldAssign(j1, j2, j3, j4, j5, nx) => { s = nx }
      Stmt::Break(_bv, _bd, nx) => { s = nx }
      Stmt::Continue(_cd, nx) => { s = nx }
      Stmt::ExprStmt(e, nx) => { s = nx }
    }
  }
  found
}

## Fold a `comptime for` range bound against the ACTIVE generic-operator comptime-VALUE binding
## (TYP-10 slice B): a bound expression over the operator's comptime parameter (`N/64` in
## `comptime for i in 0 .. N/64`) evaluates with `N` at its bound value (`192` → `3`). Returns
## -1 when the expression is not a literal/bound fold (the caller falls through to the ordinary
## path — a module-const / typeinfo bound is unaffected). Consulted ONLY while a binding is
## active (`ct_bind_depth() > 0`), so every pre-slice-B fold is byte-identical.
ct_bound_fold := fn(e : ptr(Expr), cx : ptr(LCtx)) -> i64 {
  mut res := -1
  match deref(e) {
    Expr::Num(v, s, n) => { res = i64(v) }
    Expr::Var(s, n) => { res = ct_bound_value(cx.src, s, n) }
    Expr::Bin(op, l, r) => {
      lv := ct_bound_fold(l, cx)
      rv := ct_bound_fold(r, cx)
      ## independent guard-then-act `if`s (a nested if…else inside an if-then is not a lowerable
      ## shape under the self-host lower); the zero-divisor is a loud compile-time error.
      mut dz := false
      if (op == 19 or op == 29) and lv >= 0 and rv == 0 { dz = true }
      if dz { panic("selfhost: division by zero in a comptime-for range bound") }
      if lv >= 0 and rv >= 0 and dz == false {
        if op == 16 { res = unchecked (lv + rv) }
        if op == 17 { res = lv - rv }
        if op == 18 { res = unchecked (lv * rv) }
        if op == 19 { res = lv / rv }
        if op == 29 { res = unchecked (lv % rv) }
      }
    }
    _ => {}
  }
  res
}

## Resolve the concrete type named by a `typeinfo(X)` range-bound expression. The expression AST keeps
## the call as the Field base, so this uses the same GuardTP substitution as the other typeinfo folds.
## A concrete `X` is returned unchanged; a generic parameter is replaced by its active instance type.
comptime_range_typeinfo_arg := fn(base : ptr(Expr), cx : ptr(LCtx), a : rt::Arena) -> CSpan {
  tp := GuardTP(gp_s = cx.gp_s, gp_l = cx.gp_l, its = cx.it_s, itl = cx.it_l,
               gp2_s = cx.gp2_s, gp2_l = cx.gp2_l, its2 = cx.it2_s, itl2 = cx.it2_l,
               gp3_s = cx.gp3_s, gp3_l = cx.gp3_l, its3 = cx.it3_s, itl3 = cx.it3_l)
  ## `.fields.len` / `.variants.len` leaves one Field wrapper around the call in `base`; `.n` passes
  ## the call directly. Peel exactly that one wrapper, matching `guard_field_count`'s AST shape.
  mut scrut := base
  inner := guard_field_base(base)
  if unchecked bitcast(usize, inner) != 0 { scrut = inner }
  guard_typeinfo_arg_type(scrut, ptr(tp), cx.src, a)
}

## The typeinfo member count used by a `comptime for` RANGE bound. This is deliberately shared by
## arrays, tuples, structs, and enums so the selected type's count cannot drift from the CompFor path.
## -1 means the expression names a type with no countable typeinfo member.
comptime_typeinfo_count := fn(ts : usize, tl : usize, cx : ptr(LCtx)) -> i64 {
  if tl == 0 { return 0 - 1 }
  if str_at((cx.src + ts), 1) == "[" { return i64(parse_arr_len(cx.src, ts, tl)) }
  bnt := base_type_name(cx.src, ts, tl)
  sd := struct_decl_of(cx.decls, cx.src, bnt.s, bnt.n)
  if sd >= 0 {
    sdd := deref(decl_at(Decl, rt::vec_get(deref(cx.decls), usize(sd))))
    mut fc := 0
    mut f := sdd.fields_head
    while f != 0 { fc = fc + 1 ; f = deref(fld_p(f)).next }
    return i64(fc)
  }
  ed := enum_decl_of(cx.decls, cx.src, bnt.s, bnt.n)
  if ed >= 0 {
    edd := deref(decl_at(Decl, rt::vec_get(deref(cx.decls), usize(ed))))
    mut vc := 0
    mut vf := edd.fields_head
    while vf != 0 { vc = vc + 1 ; vf = deref(fld_p(vf)).next }
    return i64(vc)
  }
  if str_at((cx.src + ts), 1) == "(" {
    mut cc := 0
    mut going := true
    while going {
      ca := typearg_at(cx.src, ts, 0, cc)
      if ca.n == 0 { going = false } else { cc = cc + 1 }
    }
    return i64(cc)
  }
  0 - 1
}

## Evaluate a `comptime for` RANGE bound to a compile-time integer. A `typeinfo(X).n` / `.len` bound
## resolves against the TYPE NAMED BY X, not automatically against the enclosing instance `cx.it`.
## Any other bound (a literal / module const / const arithmetic) goes through `global_init_value`.
pub comptime_range_bound := fn(e : ptr(Expr), cx : ptr(LCtx)) -> i64 {
  ## slice B: inside a generic-operator expansion, a bound over the comptime parameter folds
  ## against the binding FIRST (`N/64` → `3`); a non-foldable bound takes the ordinary path.
  if ct_bind_depth() > 0 {
    bfv := ct_bound_fold(e, cx)
    if bfv >= 0 { return bfv }
  }
  fp := field_place_parts(e)
  if unchecked bitcast(usize, fp.base) != 0 {
    fnm := str_at((cx.src + fp.fs), fp.fl)
    ## `typeinfo(X).n` / `.len` — the comptime MEMBER COUNT of X (§Comptime 5.1). The AST preserves the
    ## typeinfo call as `fp.base`; resolve that argument through generic substitutions before counting.
    if fnm == "n" or fnm == "len" {
      rt := comptime_range_typeinfo_arg(fp.base, cx, deref(cx.mar))
      cnt := comptime_typeinfo_count(rt.s, rt.n, cx)
      if cnt >= 0 { return cnt }
    }
  }
  global_init_value(e, cx.decls, cx.src)
}
