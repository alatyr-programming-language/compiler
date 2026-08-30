## selfhost::ast — the shared AST + token types.
##
## The single source of truth for the data that flows BETWEEN passes: the lexer's
## `Token`, and the parser's `Expr` / `Arm` / `Decl` / `FieldDecl` / `Stmt`. Each
## back-end pass (`nameres` / `sema` / `comptime` / `lower`) references these as
## `ast::Expr`, `ast::Decl`, … rather than redeclaring its own copy, so a value built
## by the parser flows into the back end UNCHANGED (one type identity across the tree).
##
## Sharing works because the `selfhost/` files are sibling submodules of the anonymous
## package root: a `pub` declaration here propagates up to the root, so any sibling can
## name it by the qualified path `ast::<Name>` (Modules §3/§4; proven by the cross-module
## runtime probe — a sibling's `pub` struct constructs + links + runs).
##
## Pass-specific error/state types (`parser::ParseErr`, `sema::CheckErr`, `parser::PC`,
## `lower::SlotEntry`/`LCtx`) stay in their own module — they are not shared AST.
vec := alloc::vec

## A lexer token: its kind tag, and the source byte span `[start, start+len)` of its
## lexeme. Kinds: 0 EOF, 1 ident, 2 keyword, 3 int, 5 := , 6 -> , 8 : , 9 , , 10 ( 11 )
## 12 { 13 } 16 + 17 - 18 * 19 / 20 == 24 < 25 > 26 <= 27 >= 28 != 30 ; 38 => .
pub Token := struct { kind : u8, start : usize, len : usize }

pub LocalTypeSpan := struct { s : usize, n : usize }

## Recover a local binding's declared type from its name token in the closed source package without
## widening `Stmt.Assign`, whose payload shape is a bootstrap-sensitive self-host invariant. The
## grammar permits `:=`, `=`, or `: Type` / `: Type =` immediately after the name. A valid type
## contains no assignment token, so the first `=` closes its complete source span. For the no-initializer
## form, the physical line/semicolon/closing-brace closes the type span. The parser has no newline tokens,
## but source spans retain them, so this remains AST-neutral and works for both initialized and uninitialized
## locals.
pub local_type_span := fn(src : ptr(u8), s : usize, n : usize) -> LocalTypeSpan {
  mut p := s + n
  end := p + 512
  mut c := (src + p).str_at(1)
  while p < end and (c == " " or c == "\n" or c == "\t" or c == "\r") {
    p += 1
    c = (src + p).str_at(1)
  }
  if c != ":" { return LocalTypeSpan(s = 0, n = 0) }
  p += 1
  if (src + p).str_at(1) == "=" { return LocalTypeSpan(s = 0, n = 0) }
  c = (src + p).str_at(1)
  while p < end and (c == " " or c == "\n" or c == "\t" or c == "\r") {
    p += 1
    c = (src + p).str_at(1)
  }
  ts := p
  mut terminated := false
  mut depth := 0
  while p < end {
    c2 := (src + p).str_at(1)
    if c2 == "(" or c2 == "[" { depth += 1 }
    if c2 == ")" or c2 == "]" {
      if depth > 0 { depth -= 1 }
    }
    if depth == 0 and (c2 == "=" or c2 == "\n" or c2 == ";" or c2 == "}") {
      terminated = true
      break
    }
    p = p + 1
  }
  if terminated == false { return LocalTypeSpan(s = 0, n = 0) }
  mut te := p
  while te > ts {
    tail := (src + te - 1).str_at(1)
    if tail == " " or tail == "\n" or tail == "\t" or tail == "\r" { te = te - 1 }
    else { return LocalTypeSpan(s = ts, n = te - ts) }
  }
  LocalTypeSpan(s = ts, n = te - ts)
}

## Whether a binding is the exact no-initializer form `name : T`, as opposed to `name : T = v`.
## This is source metadata rather than an AST field so the existing bootstrap-sensitive Stmt.Assign
## layout remains unchanged. Returns false for `:=`, plain `=`, malformed, or multiline declarations.
pub local_is_uninit := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  mut p := s + n
  end := p + 512
  mut c := (src + p).str_at(1)
  while p < end and (c == " " or c == "\t" or c == "\r") {
    p += 1
    c = (src + p).str_at(1)
  }
  if c != ":" { return false }
  p += 1
  mut depth := 0
  while p < end {
    c = (src + p).str_at(1)
    if c == "(" or c == "[" { depth += 1 }
    if c == ")" or c == "]" {
      if depth > 0 { depth -= 1 }
    }
    if depth == 0 and c == "=" { return false }
    if depth == 0 and (c == "\n" or c == ";" or c == "}") { return true }
    p += 1
  }
  false
}

## Grammar §130 line 287 / OP-2 — the compound-assignment OPERATOR the source wrote just after the
## place's name span (`+ - * / % & | ^`), or `""` when it wrote anything else (`=`, `:=`, `==`, a bare
## binary expression). The parser desugars `x op= e` into `Stmt.Assign(x, Bin(op, x, e))`, which ERASES
## the surface token — the same front-end-only erasure `local_is_mut` / `local_is_uninit` recover from
## source, and for the same reason (the Stmt.Assign layout is bootstrap-sensitive).
##
## This is the SINGLE source of the compound-operator table and, together with
## `assign_is_reassign` below, the source-level assignment-form recovery used by `sema`, `fmt`, and
## `lower`.
## Before it existed, `sema` and `fmt` each carried a private binding/reassignment probe, while `lower`
## carried a narrower global-write probe. The first two delegated compound-glyph recognition to this
## table, but `lower::local_is_plain_assign` independently listed only `+ - * / %` and skipped fewer
## whitespace forms, so the consumers could disagree for `&=`, `|=`, `^=`, or a newline before the
## operator. The full `assign_is_reassign` predicate below now owns the source-level
## binding/reassignment decision, so these consumers cannot drift. The parser's token-kind predicate
## remains separate because it runs before AST construction and answers a different question.
##
## The SECOND byte must be `=`, so a bare `x - 50` expression statement is not mistaken for `x -= 50`,
## and `x == y` / `x != y` / `x <= y` are excluded by the operator set itself.
pub compound_assign_op_at := fn(src : ptr(u8), ns : usize, nl : usize) -> str {
  mut p := ns + nl
  end := p + 512
  mut c := (src + p).str_at(1)
  while p < end and (c == " " or c == "\n" or c == "\t" or c == "\r") {
    p += 1
    c = (src + p).str_at(1)
  }
  if (src + p + 1).str_at(1) != "=" { return "" }
  if c == "+" or c == "-" or c == "*" or c == "/" { return c }
  if c == "%" or c == "&" or c == "|" or c == "^" { return c }
  ""
}

## Whether the source at `[ns, ns+nl)` is an ASSIGNMENT (`x = v`, `x += v`) rather than a
## DECLARATION (`x := v`, `x : T = v`, `x : T`). The parser erases this distinction from
## `Stmt::Assign`; keep the recovery in one place so sema, lower, and fmt cannot drift.
pub assign_is_reassign := fn(src : ptr(u8), ns : usize, nl : usize) -> bool {
  mut p := ns + nl
  end := p + 512
  mut c := (src + p).str_at(1)
  while p < end and (c == " " or c == "\n" or c == "\t" or c == "\r") {
    p = p + 1
    c = (src + p).str_at(1)
  }
  if c == ":" { return false }
  if compound_assign_op_at(src, ns, nl).len != 0 { return true }
  if c == "=" and (src + p + 1).str_at(1) != "=" { return true }
  false
}

## Whether a local binding name is immediately preceded by the `mut` declaration marker. The
## parser intentionally erases this front-end-only token from `Stmt.Assign`; source spans keep it
## recoverable without changing the bootstrap-sensitive statement layout.
pub local_is_mut := fn(src : ptr(u8), name_s : usize) -> bool {
  if name_s < 3 { return false }
  mut p := name_s
  mut scanning := true
  while p > 0 and scanning {
    c := (src + p - 1).str_at(1)
    if c == " " or c == "\n" or c == "\t" or c == "\r" { p = p - 1 }
    else { scanning = false }
  }
  if p < 3 { return false }
  (src + p - 3).str_at(3) == "mut"
}

## Whether a binding carries the `comptime` modifier. The parser deliberately keeps modifiers out of
## the bootstrap-sensitive AST nodes, so consumers recover this source fact beside `local_is_mut`.
## Walk only the adjacent declaration-prefix words; this accepts `pub comptime name` and
## `comptime pub name` without mistaking an earlier, unrelated `comptime` for the binding's modifier.
pub binding_is_comptime := fn(src : ptr(u8), name_s : usize) -> bool {
  mut p := name_s
  mut scanning := true
  while scanning {
    while p > 0 {
      c := (src + p - 1).str_at(1)
      if c == " " or c == "\n" or c == "\t" or c == "\r" { p = p - 1 }
      else { break }
    }
    if p >= 8 and (src + p - 8).str_at(8) == "comptime" {
      if p == 8 { return true }
      c8 := (src + p - 9).str_at(1)
      if c8 == " " or c8 == "\n" or c8 == "\t" or c8 == "\r" { return true }
    }
    if p >= 3 and (src + p - 3).str_at(3) == "pub" {
      if p == 3 { p = p - 3 } else {
        c3 := (src + p - 4).str_at(1)
        if c3 == " " or c3 == "\n" or c3 == "\t" or c3 == "\r" { p = p - 3 }
        else { scanning = false }
      }
    } else if p >= 3 and (src + p - 3).str_at(3) == "mut" {
      if p == 3 { p = p - 3 } else {
        c3 := (src + p - 4).str_at(1)
        if c3 == " " or c3 == "\n" or c3 == "\t" or c3 == "\r" { p = p - 3 }
        else { scanning = false }
      }
    } else { scanning = false }
  }
  false
}

## The prelude tryable enums `Result(T, E)` / `Option(T)` — the passes return these (e.g.
## `parse_decl -> Result(usize, ParseErr)`, `?`). Stage-0 supplies them as prelude built-ins, but
## the SELF-HOST lower resolves an enum by its DECL in the compiled tree (`enum_decl_of`), so for
## SELF-COMPILATION the tree must define them: without a decl `fn_returns_enum` is false and a
## Result-returning fn is mis-lowered as a SCALAR return (the `EnumLit` falls to its placeholder →
## handle 0; the parser then hands `lower` only null decl handles). Defined as type-functions (the
## generic-enum form `selfhost_driver_result_e2e` proves compiles); the type args are erased — the
## lean self-host treats both as 2-word {disc, payload} enums (`Ok`/`Some` = 0, `Err`/`None` = 1).
pub Result := fn(T : type, E : type) -> type { enum { Ok(T), Err(E) } }
pub Option := fn(T : type) -> type { enum { Some(T), None } }

## The expression AST: an integer literal, an identifier reference (name span), a binary
## node (operator byte + two children — arithmetic 16 `+` 17 `-` 18 `*` 19 `/` 29 `%`,
## comparison 20 `==` 24 `<` 25 `>` 26 `<=` 27 `>=` 28 `!=`, and the BOOLEAN ops 40 `and`
## 41 `or` 42 `not` — `not` is a prefix unary modelled as `Bin(42, x, x)` with both slots the
## same operand; lower short-circuits `and`/`or`), an `if`/`else` (cond, then, else), a `match`
## (scrutinee + arena-linked arm-list head, 0 = none), or a **call** `name(a0, …, a5)`
## (callee name span + an `nargs` count + the arena-linked argument list head `args_head`,
## 0 = no args). Each argument is an `Arg` node (an `Expr` pointer + `next`), so a call
## carries up to **6** arguments — the System V integer argument registers
## (%rdi %rsi %rdx %rcx %r8 %r9). >6 would need stack args (deferred; lower logs the cap).
##
## Two struct forms (struct tier): a **struct construction** `S(f0 = e0, …, fN = eN)`
## (`StructLit` — the struct name span `[s, s+n)` + an `nfields` count + the arena-linked
## field-value list head `fields_head` (an `Arg` list, 0 = no fields), mirroring `Call`'s shape;
## SIMPLIFICATION: each field word-sized — sub-word packing is deferred, see lower.al's layout
## note), and a **field read** `p.f` (`Field` — the base expression + the field name span; lower
## resolves the base to its struct's frame base slot and `f` to its declaration-order field index).
## ENUM tier (enum tier): an enum-variant construction `E.V(a0, …, aN)`
## (`EnumLit` — the enum TYPE name span + the variant name span + an `nargs` count + the
## arena-linked payload-value list head `args_head` (an `Arg` list, 0 = no payloads), mirroring
## `Call`/`StructLit`). Lower lays an enum value out as a discriminant word (the variant's
## declaration index) at word 0 followed by `max_arity` payload words (SIMPLIFICATION: each
## payload word-sized, fixed layout — see lower.al's layout note). Distinguished at parse
## time from a field read `p.f` by a `(` following the `.variant` (field read has no `(`).
## The field-/payload-value lists reuse the `Arg` node (an `Expr` pointer + `next`) — the same
## arena-linked machinery a `Call`'s arguments use — so field/payload arity is general (N).
pub Expr := enum {
  ## INTEGER literal or compiler-synthesized word constant. `v` is the 64-bit value/pattern;
  ## `raw_s`/`raw_n` are the source span of a written integer token and are both zero for a
  ## comptime-folded result, sentinel, char value, unary-minus helper, tuple index, or other
  ## compiler-created number. Keeping the span on the one numeric AST variant lets `fmt` replay
  ## the author's base and separators without making any backend guess from the value.
  Num(i64, usize, usize),
  ## A BOOLEAN literal `true`/`false`, carrying its value as 1/0. Represented distinctly from `Num`
  ## so `check` can TYPE it `bool` (not `int`) — `x : bool = true` must be accepted while the
  ## AST-identical-by-value `x : bool = 1` stays a type error. Everywhere ELSE (lower, comptime,
  ## const-init, tail analysis) it behaves EXACTLY like `Num(v)`: a word-sized 0/1 scalar constant.
  BoolLit(i64),
  Var(usize, usize),
  Bin(u8, ptr(Expr), ptr(Expr)),
  If(ptr(Expr), ptr(Expr), ptr(Expr)),
  Match(ptr(Expr), ptr(mut Arm)),
  Call(usize, usize, usize, ptr(mut Arg)),
  StructLit(usize, usize, usize, ptr(mut Arg)),
  Field(ptr(Expr), usize, usize),
  EnumLit(usize, usize, usize, usize, usize, ptr(mut Arg)),
  ## POINTER tier: `ptr(<place>)` (the address of a local-var place; lower `leaq`s its
  ## frame slot) and `deref(<ptr>)` (a load through a pointer value; lower loads `(%reg)`).
  ## A `deref(p) = v` STORE is `Stmt::DerefAssign`. Pointer values are word-sized scalars.
  AddrOf(ptr(Expr)),
  Deref(ptr(Expr)),
  ## STRING tier: a string literal `"…"`, or the byte payload of `embed("path")`. The first
  ## two fields are the semantic payload location and length: an ordinary literal uses the
  ## INNER source span `[s, s+n)` and an embed uses the ABSOLUTE arena address of its baked
  ## bytes. The third field is the unique LABEL INDEX assigned at parse time (a counter in
  ## `PC`) — lower emits the bytes once into `.rodata` as `.Lstr<idx>` and materializes the
  ## value as a 2-word `{ptr, len}` pair. The final two fields are optional raw source metadata
  ## `[path_s, path_s+path_n)` for the string-literal argument of `embed`; they are zero for
  ## ordinary string literals. Keeping this span alongside the baked payload lets `fmt` emit
  ## the canonical path without changing the bytes consumed by lower/rodata.
  StrLit(usize, usize, usize, usize, usize),
  ## ARRAY tier: a fixed-size array literal `[e0, e1, …, eN]` (`ArrayLit` — an element
  ## COUNT + the arena-linked element list head `elems_head` (an `Arg` list, 0 = empty),
  ## mirroring `Call`'s argument list), and an element read `a[i]` (`Index` — the base
  ## expression + the index expression). Lower lays an array value out as N contiguous
  ## word-sized elements (element `i` at byte offset `i * 8`, size `N * 8` — the same
  ## word-sized SIMPLIFICATION the struct tier uses; sub-word / aggregate-element arrays
  ## are deferred). An element write `a[i] = v` is `Stmt::IndexAssign`. The index is a
  ## RUNTIME value (lower computes the element address `base + i * 8` via SIB addressing),
  ## so it is the first place a member offset is dynamic rather than a static field index.
  ## A constant-index nested field write `s.a[i].f = v` is represented by the ordinary
  ## Index/Field path and receives a dedicated conservative DA/codegen slice when `a` is a
  ## fixed array field of simple structs. Dynamic indices and deeper aggregate paths remain
  ## fail-loud frontiers. NO bounds checking (the toy grammar is `unchecked`-style — out-of-range is UB).
  ArrayLit(usize, ptr(mut Arg)),
  Index(ptr(Expr), ptr(Expr)),
  ## TRYABLE tier (`?` operator): `<inner>?` over a tryable enum value (`Result`/`Option`,
  ## both ordinary user enums). CONVENTION: the SUCCESS variant is at discriminant index 0
  ## (e.g. `Ok`/`Some` declared first), any other discriminant is a FAILURE. Lower evaluates
  ## `inner` to an enum value (discriminant + payload word); if the discriminant is non-zero
  ## (failure), it delivers the WHOLE enum as the enclosing function's return value and jumps
  ## to the epilogue (the enclosing fn must return the same enum type); if zero (success), the
  ## `?` expression's value is the success payload word (payload word 0). So `x := f()?` binds
  ## `x` to the success payload, or returns the failure from the enclosing fn. (Spec: Control
  ## Flow §8 / Tryable §2.2 — the toy form keeps the success=variant-0 convention without the
  ## full Tryable protocol; the inner enum and the fn return type must match.)
  Try(ptr(Expr)),
  ## FLOAT tier: a floating-point literal `1.5` (token kind 39). The two fields are the literal's
  ## SOURCE span `[s, s+n)` (the verbatim text, e.g. "1.5"). Lower emits it once into `.rodata` as
  ## `.Lflt<idx>: .double <text>` — the ASSEMBLER computes the IEEE-754 bits, so the compiler needs
  ## no float arithmetic of its own — and loads the bits (`movsd .Lflt<idx>(%rip), %xmm0`). An `f64`
  ## value is a word-sized bit pattern that rides the ordinary value stack/slots; only the arithmetic
  ## (`addsd`/…), comparison (`ucomisd`), and conversions (`cvttsd2si`/`cvtsi2sd`) use the xmm regs.
  FloatLit(usize, usize),
  ## RANGE-SLICE tier: `base[lo..hi]` — a sub-VIEW of a `str` (spec §3.5 sub-slicing; the array/
  ## `Slice(T)` counterpart is deferred). Semantically `sub(base, lo, hi - lo)`: lower produces the
  ## 2-word {ptr = base.ptr + lo, len = hi - lo} pair, reusing the `sub`-view machinery
  ## (`emit_sub_pair`). Parsed in the postfix `[ … ]` when a `..` (kind 31) follows the low bound.
  Slice(ptr(Expr), ptr(Expr), ptr(Expr)),
  ## COMPTIME field access `base.(f)` — `f` is a comptime value (a `typeinfo` field/variant
  ## bound by a `comptime for`). Inside the unroll it resolves to a concrete member of `base`.
  ## The two fields are the base expr and the index expr (`f`). Only meaningful inside a `comptime
  ## for` body; the unroll rewrites it to a plain `Field`/element access for the current member.
  CompField(ptr(Expr), ptr(Expr)),
  ## VERIFICATION MODE: `unchecked <expr>` — a scoped verification mode (Types §4.2, CG-6/CG-7).
  ## Wraps the inner expression to mark it as lowered in the UNCHECKED mode: within it the comptime
  ## fact `verify.checked` (CT-11) reads FALSE, so a library operator's `comptime if verify.checked`
  ## guard (num.al's overflow/underflow/div-by-zero traps) is comptime-absent and the raw wrapping
  ## instruction remains. All passes treat it TRANSPARENTLY (recurse into the inner, same type/frame/
  ## value); only the lower's `verify.checked` fold consults the current mode set while emitting the
  ## inner. (The block form `unchecked { … }` is a statement; this is the expression form.)
  Unchecked(ptr(Expr)),
  ## FN-6 function VALUE `fn(sig){body}` in expression position. Fields mirror a fn Decl: fnpos (the
  ## `fn` src offset = unique label id), params head, ret-type span, body stmt head, trailing value. A
  ## driver-level pass (`driver`'s lift) rewrites it to FnRef + appends a synthetic fn decl.
  Lambda(usize, ptr(mut Param), usize, usize, usize, ptr(Expr)),
  ## Reference to a lifted lambda as a value → code pointer `leaq <mod>__lam<fnpos>(%rip)`. Leaf.
  FnRef(usize, usize, usize),
  ## SUB-WORD pointer `bitcast(ptr(<sub-word scalar>), v)` PRESERVED (not identity-erased) so a
  ## `deref` LOAD/STORE through it narrows the machine move to the pointee width (`movzbq`/`movb`
  ## …) instead of a full 8-byte `movq` that would read/clobber the 7 neighbouring bytes. Fields:
  ## the inner VALUE expr (bitcast is bit-identity, so this node lowers EXACTLY to the inner value —
  ## transparent to every other pass) and the POINTEE type-name source span `[s, s+n)` (fed to
  ## `scalar_byte_size`). The parser creates it ONLY for a KNOWN sub-word pointee; a word-sized /
  ## aggregate / unknown pointee stays identity-erased, so the node NEVER appears in the compiler's
  ## own reached tree (`src/` reads bytes via `bytes(s)[i]` slice views, not sub-word deref) — the
  ## fixpoint stays byte-identical.
  Bitcast(ptr(Expr), usize, usize),
  ## LOOP-AS-EXPRESSION (Control Flow §3/§6/§7.2): an infinite `loop { … }` used in VALUE position
  ## (`total := loop { … break v … }`). The single field is the body statement-list head (same as
  ## `Stmt::Loop`'s body). Its value is the common type of its reachable `break v` exits (§7.2); a
  ## `loop` with no reachable `break` has type `Never` (§3). Lower emits the identical loop structure
  ## as `Stmt::Loop` but marks the loop frame value-bearing, so each `break <expr>` inside leaves its
  ## value on the stack at the done-label (the consuming decl/assign/return pops it — the stack model
  ## the `Expr::If` arm uses). `src/`+`lib/` never use a loop in value position → dormant, fixpoint-safe.
  Loop(ptr(mut Stmt)),
}

## One `match` arm. The `wild` field is the arm KIND discriminant: 0 = integer/enum-variant
## literal (`lit` holds the integer value; `vs`/`vl` the variant name span when nonzero), 1 = the
## `_` wildcard, 2 = a `comptime for` variant-arm TEMPLATE, 3 = a comptime-variant `T.(v)` pattern,
## 4 = a str-literal pattern (`lit` holds the `StrLit` node handle), 5 = a **half-open range**
## pattern `lo..hi` (`lit` = lo, `hi` = hi — matches `lo <= x < hi`, Control Flow §5.4), 6 = an
## **inclusive range** pattern `lo..=hi` (`lit` = lo, `hi` = hi — matches `lo <= x <= hi`). Range
## arms are SCALAR-only (integer/char) and dispatch to a bounds check, never a discriminant compare.
## An **OR-pattern** `p | q | r => body` (§5.4) is PURE SURFACE SUGAR: the parser expands it to one
## arm per alternative (in order, all sharing the same `body`/`body_stmts`), so no arm-level OR field
## exists — lowering/sema see the expanded arm list, exactly as the spec requires. v1 OR alternatives
## do NOT bind (an alternative that introduces a payload binding is ill-formed — the parser rejects it).
## `lit` (the literal value for an integer
## arm), the arm body expression, and `next` (arena-linked; 0 = end). For an **enum variant
## pattern** `V(x, …, z) => …` the variant name span is `vs`/`vl` (0/0 = not a variant pattern,
## i.e. an integer/wildcard arm), `bn` the payload BINDING count, and `binds_head` the
## arena-linked binding-name list head (a `Bind` list, 0 = none) — general arity, mirroring the
## construction `Arg` lists. Lower resolves the variant name to its declaration index for the
## discriminant compare, and binds each payload name to the scrutinee's payload slot (word
## `i+1`) within the arm body.
##
## For an **expression-position** match (the `Expr::Match` form) the arm body is the expression
## `body` and `body_stmts` is 0. For a **statement-position** match (the `Stmt::Match` form) the
## arm body is a STATEMENT LIST whose head handle is `body_stmts` (0 = empty); `body` is unused
## (a dummy `Expr` pointer). The two forms never mix within one arm — the parser sets exactly one.
pub Arm := struct {
  wild : u8, lit : i64, body : ptr(Expr), next : ptr(mut Arm),
  vs : usize, vl : usize, binds_head : ptr(mut Bind),
  body_stmts : ptr(mut Stmt),
  hi : i64,                     ## range-pattern upper bound (wild 5/6); `lit` is the lower bound
}

## `Arm`-list plumbing (§6 ptr-typing). `Arm.next` and the arm-list HEADS in the `Expr::Match` /
## `Stmt::Match` / `Stmt::CompMatch` enum payloads are `ptr(mut Arm)` (absolute pointers). `arm_p` is the
## typed IDENTITY accessor — an arm read is `deref(arm_p(h))` / `deref(arm_p(h)).field`, so the lean lower
## resolves the pointee STRUCT from `arm_p`'s return type (an `Arm` is read as a struct copy, NEVER matched,
## so the enum-scrutinee resolution gap that blocks `Stmt` does not apply here). The pass-plumbing params
## that thread an arm-head (`head_in`/`ah`/`head`, several of which also name Arg/Stmt heads) stay `usize`
## handles — they hold the pointer bits and resolve through `arm_p`; the checker is lenient on usize<->ptr.
pub arm_p := fn(p : ptr(mut Arm)) -> ptr(mut Arm) { p }
pub arm_null := fn() -> ptr(mut Arm) { unchecked bitcast(ptr(mut Arm), 0) }

## A match variant-pattern **payload binding** (arena-linked): its source name span `[ns, ns+nl)`
## and `next` (0 = end). Walked in declaration order — binding `i` aliases the scrutinee's
## payload word `i+1`.
pub Bind := struct { ns : usize, nl : usize, next : ptr(mut Bind) }

## Typed accessors for a `Bind` reached through a `ptr(mut Bind)` (§6 ptr-typing). A field read of
## `deref(p)` on a POINTER-TO-STRUCT PARAM lowers via the `ek = 7` pointee path (the param carries the
## pointee type), whereas `deref(<field-read/return local>).f` does NOT resolve the pointee struct — so
## every `Bind`-list walk routes its reads through these one-arg helpers instead of a local aggregate copy.
pub bnd_ns := fn(p : ptr(mut Bind)) -> usize { deref(p).ns }
pub bnd_nl := fn(p : ptr(mut Bind)) -> usize { deref(p).nl }
pub bnd_next := fn(p : ptr(mut Bind)) -> ptr(mut Bind) { deref(p).next }

## A top-level binding, discriminated by `kind`: 0 a **value** binding `name := <expr>`
## (`value` = the expr); 1 a **function** `name := fn(p0 : T, …, p5 : T) -> R { … }`
## (`value` = the trailing return expr, `body_stmts` = the body statement list,
## `params_head`/`arity` the params); 2 a **struct** `Name := struct { … }`; 3 an **enum**
## `Name := enum { … }` (`fields_head` = the field/variant list head). `is_fn` mirrors
## `kind == 1`. The parameters are an **arena-linked `Param` list** (`params_head`, 0 = none),
## `arity` their count — up to **6** (the System V integer argument registers); >6 would need
## stack args (deferred).
## GENERICS tier: a **generic function** has a leading comptime type
## parameter `T : type` — its type annotation is the literal `type`. `is_generic` marks
## such a decl. The type parameter is COMPTIME: it consumes NO runtime register/slot (it is
## erased at the call). A generic fn is monomorphized — lower emits one specialized copy per
## distinct concrete type it is called with, the label mangled `<module>__<fn>__<typetag>`
## (the type-argument lexeme as the suffix), and routes each call to the right instance. The
## type parameter is still counted in `params_head`/`arity` (param 0), so the value parameters
## are params 1..arity; lower spills value param `i` (i≥1) from argument register `i-1`.
##
## A **generic STRUCT** `Name(T) := struct { … }` (generic-struct tier) also sets
## `is_generic` — its single type parameter `T` is parsed-and-skipped (its NAME need not be
## recorded: a field type may reference `T`, e.g. `buf : [T; 8]` or `f : T`, but for a WORD-SIZED
## `T` (u64/i64/any pointer-sized type) every instance's layout is IDENTICAL — the field offsets
## depend only on each field's `wsize` (1 for a scalar field, N for `[T; N]`), the same regardless
## of which word-sized `T` is plugged in). It is MONOMORPHIZED per concrete element type: an
## instantiation `Name(u64)` / `Name(i64)` constructs a value whose layout lower resolves against
## the SAME `Name` struct decl by name (the instantiation surface records just the bare struct name
## `Name`, the `(u64)` type-arg being ERASED like a generic fn's). The milestone is the RECOGNIZED,
## INSTANTIATED, ACCESSED generic struct at ≥2 concrete element types; size-VARYING layout for an
## aggregate element type is deferred (it would plug `T`'s `struct_words` into the field sizes).
pub Decl := struct {
  name_start : usize, name_len : usize,
  value : ptr(Expr),
  is_fn : bool, kind : u8, arity : usize,
  is_generic : bool,            ## generic fn (first param `T : type`) OR generic struct `Name(T)`; monomorphized per type
  params_head : ptr(mut Param),  ## fn params: arena-linked Param list head (0/null = none)
  body_stmts : ptr(mut Stmt),   ## fn body: arena-linked Stmt list head (0/null = none); `value` is the trailing return expr
  fields_head : ptr(mut FieldDecl),  ## struct field / enum variant list head (0/null = none)
  ret_ts : usize,               ## fn return type span start (the `R` of `-> R`); 0/0 = none
  ret_tl : usize,               ## fn return type span length
  ## MODULE tier: the source span of the MODULE this decl belongs to (the name after a
  ## `module <name>` top-level directive; 0/0 = the implicit default module). Lower MANGLES
  ## a function's emitted label to `<module>__<fn>` so two modules may each define a `helper`
  ## without their symbols colliding (Modules §1/§3, the real Stage-0's per-submodule mangling
  ## in miniature). A same-module call `f(…)` resolves to `<this-module>__f`; a cross-module
  ## qualified call `other::f(…)` (a `::`-path callee whose head is a module name, NOT `mem`)
  ## resolves to `other__f`.
  mod_start : usize, mod_len : usize,
  ## COMPTIME `when`-GUARD (Comptime §7.1; CT-5): the guard predicate expression `when <pred>` this
  ## declaration carries, or 0/null when it has none. A closed (target-gating) predicate is folded at
  ## emit time (`lower::decl_guard_fold`); a decl whose predicate folds FALSE is neutered to an inert
  ## no-op before name-resolution/emission (Comptime §9 two-phase). Appended LAST so every existing
  ## field offset is unchanged; `src/`+`lib/` carry no `when` (it stays 0) → the self-host GAS is
  ## byte-identical → the TOOL-1 fixpoint holds. Set by the parser for a `fn`-sig / inferred-`:=` guard.
  when_cond : ptr(Expr),
  ## TYPE-ALIAS to a GENERIC INSTANCE (TYP-10 slice C, Types §7: `u128 ≡ uint(128)`): when this
  ## kind-0 decl's RHS is exactly ONE bare-ident call with no top-level `=` in its args — the
  ## `u128 := uint(128)` shape — the parser records the RHS's full source span (`uint(128)`)
  ## here (0/0 = not alias-shaped). The decl stays an ordinary value binding in every other
  ## respect (`ret_tl` keeps its 0, so all global-value paths are byte-identical); the span is
  ## consulted ONLY by type-position lookups (`lower_layout::alias_rhs`), which fire solely when
  ## the callee head resolves to a GENERIC struct type-function — a plain `x := f(1)` global's
  ## head does not, so its recorded span is inert. Appended LAST (the `when_cond` precedent).
  alias_ts : usize, alias_tl : usize,
}

## A captured struct **field** or enum **variant** (arena-linked): its name span, payload
## arity (`arity` — fields are 0; an enum variant `V(T, T)` is 2), and `next` (0 = end).
## `ts`/`tl` is the **type annotation span** `[ts, ts+tl)` — for a struct field `name : T`
## it is `T`'s ident span (sema resolves it to a `Ty`); for an enum variant it is the FIRST
## payload type span (0/0 = no payload), enough for the integer-payload checks the toy
## grammar uses (full per-payload enum type lists are deferred).
##
## STRUCT-WITH-ARRAY-FIELD tier: `wsize` is the field's SIZE IN WORDS — 1 for a
## scalar field `name : T`, and `N` for a fixed-array field `name : [T; N]` (a multi-word
## field). Lower lays struct fields out at CUMULATIVE word offsets (field `k` starts after the
## sum of the prior fields' `wsize`s), so a struct `{ buf : [u64; 8], len : u64 }` puts `len`
## at word offset 8, not 1; the struct's total size is the sum of all `wsize`s. A scalar-only
## struct has every `wsize == 1`, so the cumulative offset equals the declaration index — the
## pre-existing word-sized layout, byte-identical. For an enum variant `wsize` is unused (1).
## TYP-10 slice A: `wsize == 0` is the COMPUTED-LENGTH sentinel — a `[T; <expr>]` field whose
## length expression references a comptime VALUE parameter of a generic type-function
## (`[u64; N/64]` in `fn(comptime N : u64) -> type {…}`); the layout folds it per instantiation
## (`lower_layout::ct_arr_len` / `eff_field_wsize`), so a literal-length field is unchanged.
pub FieldDecl := struct { ns : usize, nl : usize, arity : usize, next : ptr(mut FieldDecl), ts : usize, tl : usize, wsize : usize }

## `FieldDecl`-list plumbing (§6 ptr-typing). `Decl.fields_head` / `FieldDecl.next` are `ptr(mut
## FieldDecl)`. `fld_p` is the typed IDENTITY accessor: a walk reads a node via `deref(fld_p(h))` (or
## `deref(fld_p(h)).next`) so the lean lower resolves the pointee struct from `fld_p`'s RETURN type
## (`deref_call_struct_span` fallback) — a bare `deref(<field-read local>)` does NOT resolve it. `fld_null`
## is the empty-list / end sentinel. A literal `0` still works for a `ptr(mut FieldDecl)` STRUCT FIELD
## (null ptr; verified check+run), so only reassigned LOCALS need `fld_null()`.
pub fld_p := fn(p : ptr(mut FieldDecl)) -> ptr(mut FieldDecl) { p }
pub fld_null := fn() -> ptr(mut FieldDecl) { unchecked bitcast(ptr(mut FieldDecl), 0) }

## A function **parameter** (arena-linked): its source name span `[ns, ns+nl)`, its type
## annotation span `[ts, ts+tl)` (the `T` of `name : T` — sema resolves it to a `Ty` to
## type-check a call's argument against the parameter), and `next` (0 = end). The list is
## walked in declaration order, so parameter `i` is spilled from / passed in arg register `i`.
## AGGREGATE-PARAM tier: a struct/array param is passed BY REFERENCE (the caller
## passes the aggregate's word-0 address; the callee dereferences). For a struct param `p : P`,
## `ts`/`tl` is the struct TYPE name span `P` (lower resolves its layout) and `pmode` is 0.
## The PASSING MODE `pmode` (a u8, NOT a new word — repurposes the old `is_arr : bool` slot so
## `Param` stays at 8 words; growing it to 9 destabilizes the self-host fixpoint, see):
##   0 = an ordinary value parameter (`in`/default) — a scalar passed by value, or an aggregate
##       passed by reference (the aggregate-ness is decided by the TYPE, not `pmode`);
##   1 = an ARRAY parameter `a : [T; N]` (`ts`/`tl` is the ELEMENT type span `T`; lower resolves
##       the element layout/stride; the length `N` is not needed — access is a runtime index, no
##       bounds check) — passed by reference like a struct;
##   2 = an `out` / `in out` SCALAR parameter (the `out`/`in out` modifier was present and the
##       type is not an array): passed BY REFERENCE (the slot holds a POINTER to the caller's
##       scalar) so a write `r = v` in the callee is visible to the caller. For an aggregate `out`
##       param `pmode` is also 2, but bind_param's TYPE branches already pass it by reference and
##       ignore `pmode` (aggregate writes are caller-visible for free).
##   3 = a SLICE-VARIADIC parameter `name : ...T` (Functions §7.2) — the trailing rest WITH a
##       concrete element type `T` (`ts`/`tl` is the element type span). The call site gathers the
##       call's trailing args into one contiguous block + passes a `{ptr, len}` slice; `bind_param`
##       binds it as a by-reference `[T]` slice (`ek 5`, `is_ref`, `snl 1`), identical to a
##       `Slice(T)` param — so `for x in name` / `name[i]` / `name.len()` read it uniformly.
## For a POINTER param `p : ptr([mut] T)`, `ts`/`tl` is `ptr` (so sema/lower see a pointer) and
## `pps`/`ppl` is the POINTEE type span `T` (0/0 for a non-pointer) — lower uses it so a
## `match deref(p)` over a `ptr(Enum)` resolves the enum's variants (the arena-AST shape).
pub Param := struct { ns : usize, nl : usize, next : ptr(mut Param), ts : usize, tl : usize, pmode : u8, pps : usize, ppl : usize }

## `Param`-list plumbing (§6 ptr-typing). `Decl.params_head` / `Param.next` are `ptr(mut Param)`;
## `param_p` is the typed IDENTITY accessor (walks read `deref(param_p(h))` so the pointee resolves via
## the return-type fallback), `param_null` the empty/end sentinel. See `fld_p`/`fld_null` for the recipe.
pub param_p := fn(p : ptr(mut Param)) -> ptr(mut Param) { p }
pub param_null := fn() -> ptr(mut Param) { unchecked bitcast(ptr(mut Param), 0) }

## A function-call **argument** (arena-linked): the argument expression + `next` (0 = end).
## Walked in declaration order — argument `i` is delivered in System V integer register `i`.
pub Arg := struct { e : ptr(Expr), next : ptr(mut Arg) }

## `Arg`-list plumbing (§6 ptr-typing). `Arg.next` and the arg-list HEADS in the `Expr::Call` /
## `StructLit` / `EnumLit` / `ArrayLit` enum payloads (call args / struct fields / enum payloads / array
## elements) are `ptr(mut Arg)`. `arg_p` is the typed IDENTITY accessor — an arg read is
## `deref(arg_p(h))` / `deref(arg_p(h)).e` / `.next`, so the lean lower resolves the pointee STRUCT from
## `arg_p`'s return type (an `Arg` is read as a struct copy, never matched). The pass-plumbing params +
## carrier struct fields that thread an arg-head (`args_head`/`ehead`/`phead`/`head`/`ah`, `EFull.phead`,
## `CallInfo.ah`, …) stay `usize` handles — they hold the pointer bits and resolve through `arg_p`
## (the checker is lenient on usize<->ptr); only the LINK field + the enum-payload heads carry the ptr type.
pub arg_p := fn(p : ptr(mut Arg)) -> ptr(mut Arg) { p }
pub arg_null := fn() -> ptr(mut Arg) { unchecked bitcast(ptr(mut Arg), 0) }

## A struct-literal **field initializer** `f = v` collected AT PARSE (arena-linked): the field
## NAME span `[fs, fs+fl)`, the value expr, and `next` (0 = end). Used ONLY transiently inside the
## struct-literal parse to REORDER named field values into the struct's DECLARATION order (TYP-8
## — construction is BY NAME, not by source position). The reordered result is an ordinary `Arg` list
## stored on the `StructLit` node, so no other pass ever sees a `FInit` — it is parser-internal, and
## the emitted AST is byte-identical for an already-in-declaration-order literal (fixpoint-neutral).
pub FInit := struct { fs : usize, fl : usize, e : ptr(Expr), next : ptr(mut FInit) }
pub finit_p := fn(p : ptr(mut FInit)) -> ptr(mut FInit) { p }
pub finit_null := fn() -> ptr(mut FInit) { unchecked bitcast(ptr(mut FInit), 0) }

## A function-body statement: a local binding / reassignment `name (:= | =) <expr>`
## (Assign: name span, value, next), a `while <cmp> { <stmts> }` loop (While: cond,
## body head, next), or a **struct field mutation** `var.field = <expr>` (FieldAssign:
## the base var's name span `[bns, bns+bnl)`, the field name span `[fns, fns+fnl)`, the
## value expr, and `next`). Lower resolves the base var to its struct frame base slot and
## `field` to its declaration-order index, then stores the value into that field's slot —
## the store dual of the `Field` READ expr. (Only `var.field = e` for a struct LOCAL is
## supported; a general place chain `a.b.c = e` or element assign `a[i].f = e` is deferred.)
##
## CONTROL FLOW STATEMENTS (statement-flow tier): an **early return**
## `return <cmp>` (Return: the value expr, next) — lower delivers it in `%rax` and jumps to
## the function epilogue; a statement-position **if/else** `if <cmp> { <stmts> } [ else
## { <stmts> } ]` (If: the condition expr, the then statement-list head, the else
## statement-list head — 0 = no else, next) — the branch bodies are STATEMENT LISTS (side
## effects), no value left; a statement-position **match** `match <cmp> { <pat> => { <stmts> }
## ; … }` (Match: the scrutinee expr, the arm-list head, next) — each arm BODY is a statement
## list (the `Arm.body_stmts` field), the dispatch is the discriminant/literal shape of the
## expression match but each arm runs side effects rather than yielding a value.
##
## A counted **for loop** `for <i> in <lo> .. <hi> { <stmts> }` (For: the loop-variable name
## span `[ns, ns+nl)`, the `lo` and `hi` bound expressions, the body statement-list head, and
## `next`). Lower desugars it to a counted while: bind `i := lo`, then `while i < hi { body ;
## i = i + 1 }` — `i` is an int local visible in the body. The bounds are half-open (`lo`
## inclusive, `hi` exclusive), matching the lexer's `..` range token (kind 31).
##
## `next` links the arena-linked sequence (0 = end).
pub Stmt := enum {
  Assign(usize, usize, ptr(Expr), ptr(mut Stmt)),
  While(ptr(Expr), ptr(mut Stmt), ptr(mut Stmt)),
  FieldAssign(usize, usize, usize, usize, ptr(Expr), ptr(mut Stmt)),
  Return(ptr(Expr), ptr(mut Stmt)),
  If(ptr(Expr), ptr(mut Stmt), ptr(mut Stmt), ptr(mut Stmt)),
  Match(ptr(Expr), ptr(mut Arm), ptr(mut Stmt)),
  For(usize, usize, ptr(Expr), ptr(Expr), ptr(mut Stmt), ptr(mut Stmt)),
  ## POINTER tier: a store through a pointer `deref(p) = <expr>` — the `ptr` expression,
  ## the value expression, and `next`. Lower lowers the value, lowers the pointer, and stores
  ## the value `movq %val, (%ptr)`. The store dual of the `Deref` READ expression.
  DerefAssign(ptr(Expr), ptr(Expr), ptr(mut Stmt)),
  ## ARRAY tier: an element write `a[i] = <expr>` — the base array expression, the index
  ## expression, the value expression, and `next`. Lower computes the element address
  ## `base + i * 8` (the index a RUNTIME value, SIB addressing) and stores the value. The
  ## store dual of the `Index` READ expression. (Only `arr[i] = e` for an array LOCAL base
  ## is supported; a nested place like `a[i].f = e` is deferred.)
  IndexAssign(ptr(Expr), ptr(Expr), ptr(Expr), ptr(mut Stmt)),
  ## ARRAY-OF-AGGREGATE tier: an element-field write `a[i].f = <expr>` — the array base
  ## expression, the index expression, the field NAME span `[fs, fs+fl)`, the value expression,
  ## and `next`. Lower computes the element address (`emit_index_addr`), subtracts the field
  ## offset (`f * 8`, the down-growing convention), and stores the value. The store dual of the
  ## `Field(Index(...), f)` READ expression — for an array whose element type is a struct.
  IndexFieldAssign(ptr(Expr), ptr(Expr), usize, usize, ptr(Expr), ptr(mut Stmt)),
  ## NESTED-FIELD tier: a store to a MULTI-level field place `o.i.v = <expr>` — the place is a nested
  ## `Field(Field(Var(o), i), v)` expression, then the value + `next`. Lower resolves the place's frame
  ## slot via `field_slot` (which walks the nested `Field` recursively) and stores. The store dual of a
  ## nested `Field` READ. (Single-level `o.f = e` stays the lighter `FieldAssign`.)
  FieldPathAssign(ptr(Expr), ptr(Expr), ptr(mut Stmt)),
  ## CONTROL FLOW: an infinite `loop { <stmts> }` (Loop: the body statement-list head, next) —
  ## lower emits a back-edge with no guard; the only way out is a `break`. A `break` statement
  ## (Break: value, depth, next) exits an enclosing `loop`/`while`/`for` — lower jumps to that loop's
  ## done-label. `value` (0 = none) is the `break <expr>` loop-expression value (§7.2); `depth` is the
  ## LOOP-NESTING count to the target (0 = the nearest enclosing loop = a bare/`break`; N = a labeled
  ## `break name` whose target is N loops out — the parser resolves the `@label(name)` to a lexical
  ## nesting depth, §7.1). A `continue` statement (Continue: depth, next) skips to the next iteration of
  ## the target loop — lower jumps to that loop's CONTINUE target (a `while`'s guard, a `loop`'s top, or
  ## a `for`'s increment, so the index still advances); `depth` resolves `continue name` the same way.
  ## The depth-0 emit is byte-identical to the pre-label lowering (`src/`+`lib/` use only bare
  ## `break`/`continue` with no value → depth 0, value 0 → fixpoint-neutral).
  Loop(ptr(mut Stmt), ptr(mut Stmt)),
  Break(ptr(Expr), usize, ptr(mut Stmt)),
  Continue(usize, ptr(mut Stmt)),
  ## A bare EXPRESSION statement `f(args)` / `mod::f(args)` / `expr?` — a call (or any
  ## expression) evaluated for its side effects, its result DISCARDED (ExprStmt: the expression,
  ## next). Distinguished from a trailing return expression by being followed by more of the
  ## body (the body parser treats the LAST expr before `}` as the return; anything earlier is an
  ## ExprStmt). Lower emits the expression and drops the result. The pervasive statement shape in
  ## the passes (`lexer::lex_all(lx, toks)`, `vec::push(out, d)`, `sb?`).
  ExprStmt(ptr(Expr), ptr(mut Stmt)),
  ## COMPTIME control flow: `comptime if <cond> { then } else { else }` (CompIf: the condition
  ## expr, the then-statement-list head, the else-statement-list head (0 = none), next). The lean
  ## lower EVALUATES the condition at compile time and emits ONLY the taken branch's statements
  ## (arch/verify predicates: `target.arch == Arch.x86_64` → then, other arches / `verify.checked`
  ## → else). A condition it cannot fold at compile time (`match typeinfo(T)` — needs the typeinfo
  ## value) emits NEITHER branch (deferred to the full comptime evaluator). `comptime for` /
  ## `comptime match` are still consumed as no-ops by the parser (not represented here yet).
  CompIf(ptr(Expr), ptr(mut Stmt), ptr(mut Stmt), ptr(mut Stmt)),
  ## COMPTIME iteration `comptime for <var> in typeinfo(T).fields { body }` (CompFor: the loop-var
  ## name span `[vs, vs+vl)`, `is_variants` (0 = `.fields`, 1 = `.variants`), the body-statement-list
  ## head, next). The lean lower UNROLLS it over the instance type's FieldDecl/variant list (in a
  ## monomorphized instance where T's concrete type is known): for each member it emits the body with
  ## the loop var bound, resolving `<var>.type` (the member's type, a comptime TYPE value) and
  ## `v.(<var>)` (`CompField` → the member access). A range-based `comptime for i in lo .. hi` (the
  ## array-length case) is NOT this node — the parser consumes it as a no-op (deferred).
  CompFor(usize, usize, u8, ptr(mut Stmt), ptr(mut Stmt)),
  ## COMPTIME kind-dispatch `comptime match typeinfo(T) { Struct(_) => … Enum(_) => … _ => … }`
  ## (CompMatch: the scrutinee `typeinfo(T)`, the arm-list head, next). The lower EVALUATES T's KIND
  ## (struct/enum/array/scalar, in a mono instance) and emits ONLY the arm whose variant name matches
  ## (or the `_` arm). The sibling of `comptime if (match typeinfo(T) {…})`; derive's `eq`/`lt` use it.
  CompMatch(ptr(Expr), ptr(mut Arm), ptr(mut Stmt)),
  ## COMPTIME RANGE iteration `comptime for <var> in <lo> .. <hi> { body }` (CompForRange: the loop-var
  ## name span `[vs, vs+vl)`, the `lo`/`hi` bound exprs (compile-time integer constants), the
  ## body-statement-list head, next). The lower UNROLLS it at compile time: for each `k` in `lo..hi` it
  ## emits the body with `<var>` bound to the COMPTIME CONSTANT `k` (a `Var` use of the loop var emits
  ## the immediate). The compile-time work is fully erased — no runtime loop. Distinct from the
  ## typeinfo `CompFor` (which iterates a type's members, not a numeric range).
  CompForRange(usize, usize, ptr(Expr), ptr(Expr), ptr(mut Stmt), ptr(mut Stmt)),
  ## VERIFICATION-MODE block `unchecked { <stmts> }` (Grammar §130: `unchecked (expr | block)`; the
  ## STATEMENT form — the expression form is `Expr::Unchecked`). Lowers its body statement-list head with
  ## `verify.checked` FALSE (overflow/bounds guards comptime-absent), restoring the mode after. Carries
  ## the body-list head + `next`. `src/` uses only the EXPRESSION form (`unchecked { base + off }` in a
  ## value position), never this statement form, so it is dormant for the self-host build.
  Unchecked(ptr(mut Stmt), ptr(mut Stmt)),
  ## AMBIENT-ALLOCATOR scope `alloc::with(A) { <stmts> }` (MEM-5 / Memory §5.2.1; Grammar §130
  ## `alloc-with-region`): establishes the allocator place `A` (an `Arena` value or `ptr(mut Arena)`) as
  ## the ambient allocator for the body. A call in the body that OMITS an allocator parameter (a
  ## `ptr(mut Arena)` param, Functions §5.5) has `ptr(A)`/`A` injected. Carries the allocator EXPR + the
  ## body-list head + `next`. `src/` uses explicit allocator args, never this scope → dormant.
  AllocWith(ptr(Expr), ptr(mut Stmt), ptr(mut Stmt)),
}

## `Stmt`-list plumbing (§6 ptr-typing). Every `Stmt` variant's `next` (and the nested stmt-list heads
## — `While`/`For`/`Loop`/`CompFor` bodies, `If`/`CompIf` then/else) plus `Decl.body_stmts` /
## `Arm.body_stmts` are `ptr(mut Stmt)` (absolute pointers). `stmt_p` is the typed IDENTITY accessor:
## the dispatch reads `st := deref(stmt_p(Stmt, h))` then `match st { Stmt::… }`, and the leading `Stmt`
## type-arg lets the seed's `call_first_enum_span` bind `st` as an enum local (ek 3) so the match resolves — a plain
## `deref(<field-read local>)` would not (the reason `Stmt` needed the lower change first). The overloaded
## stmt-head plumbing params (`head`/`list_head`/`body_head`/`bh`, which also name Arm/Arg heads) stay
## `usize` handles — they hold the pointer bits and resolve through `stmt_p` (checker lenient on usize<->ptr).
## NOTE the leading `T : type` param: the read is `deref(stmt_p(Stmt, h))`, so the CALL's first arg is the
## enum type name `Stmt` — which the FROZEN seed's `call_first_enum_span` already resolves (the node_ptr
## first-arg-type-name convention). This binds `st := deref(stmt_p(Stmt, h))` as an enum local with NO
## reseed (the return-type fallback in `deref_call_enum_span` would also work, but only once the seed has
## it — a reseed; the type-arg form needs nothing new in the seed). `T` is comptime-erased.
pub stmt_p := fn(T : type, p : ptr(mut Stmt)) -> ptr(mut Stmt) { p }
pub stmt_null := fn() -> ptr(mut Stmt) { unchecked bitcast(ptr(mut Stmt), 0) }

## ── STRUCTURED-LABEL SOURCE SPANS ────────────────────────────────────────────────────────────────
## The control-flow AST intentionally stores only the resolved LOOP DEPTH on Break/Continue and keeps
## loop variants at their bootstrap-stable arities.  A formatter still needs the authored `@label(name)`
## and target NAME, so retain those source spans in a side table keyed by the node pointer.  This follows
## the FN-6 expression-callee site set below: no pass that only needs control-flow semantics sees a new
## enum field, while fmt can recover the exact spelling.  The key is updated on every parser/clone
## construction, including the unlabeled case, so an arena address reused by a second parse cannot retain
## stale metadata.  Bounded + fail-loud keeps a large source from silently changing targets in fmt.
pub LabelSpan := struct { s : usize, n : usize }
mut LABEL_NODE : [usize; 4096] = [0; 4096]
mut LABEL_START : [usize; 4096] = [0; 4096]
mut LABEL_LEN : [usize; 4096] = [0; 4096]
mut LABEL_N := 0

label_mark := fn(k : usize, s : usize, n : usize) {
  if k == 0 { return }
  mut i := 0
  while i < LABEL_N {
    if LABEL_NODE[i] == k {
      LABEL_START[i] = s
      LABEL_LEN[i] = n
      return
    }
    i = i + 1
  }
  ## Unlabeled control-flow nodes need no table entry.  Still clear a matching old key above so a reused
  ## arena address cannot inherit a label from an earlier parse.
  if s == 0 or n == 0 { return }
  if LABEL_N >= 4096 { panic("selfhost: control-label metadata table exhausted (limit 4096)") }
  LABEL_NODE[LABEL_N] = k
  LABEL_START[LABEL_N] = s
  LABEL_LEN[LABEL_N] = n
  LABEL_N = LABEL_N + 1
}

label_lookup := fn(k : usize) -> LabelSpan {
  mut i := 0
  while i < LABEL_N {
    if LABEL_NODE[i] == k { return LabelSpan(s = LABEL_START[i], n = LABEL_LEN[i]) }
    i = i + 1
  }
  LabelSpan(s = 0, n = 0)
}

pub stmt_label_mark := fn(p : ptr(mut Stmt), s : usize, n : usize) {
  label_mark(unchecked bitcast(usize, p), s, n)
}
pub stmt_label_span := fn(p : ptr(mut Stmt)) -> LabelSpan {
  label_lookup(unchecked bitcast(usize, p))
}
pub expr_label_mark := fn(p : ptr(Expr), s : usize, n : usize) {
  label_mark(unchecked bitcast(usize, p), s, n)
}
pub expr_label_span := fn(p : ptr(Expr)) -> LabelSpan {
  label_lookup(unchecked bitcast(usize, p))
}

## ── FN-6 EXPRESSION-CALLEE SITE SET ────────────────────────────────────────────────────────────────
## `Expr::Call` carries its callee as a NAME SPAN, not an expression, and its arity is a self-host
## BOOTSTRAP INVARIANT (170 `Expr::Call(cs, cl, n, ah)` match arms across parser/sema/driver/lower and
## the three non-x86 back ends — a fifth field is not reachable from one lane, and a NEW `Expr` variant
## would fall to the `_` arm of every generic walker, so a lambda in the arguments would never be
## LIFTED and a generic argument never MONOMORPHIZED).
##
## So a call through an EXPRESSION callee (`fs[0](10)`, `t.fs[0](41)`) is represented as an ORDINARY
## `Expr::Call` whose ARGUMENT 0 IS THE CALLEE EXPRESSION — exactly the shape the parser's UFCS desugar
## already builds for `recv.m(args)` (`Call(m, [recv, args…])`) — with the callee NAME SPAN borrowed
## from the callee expression's ROOT VARIABLE (`fs` in `fs[0]`, `t` in `t.fs[0]`). Borrowing a real,
## BOUND name is what keeps `check` happy without a sema change: the undefined-callee diagnostic
## exempts a callee that resolves to a local/param, and no `fn` declares that name so the arity check
## stays unresolved. Every generic AST walker then sees a normal call and recurses into ALL of its
## children, the callee included.
##
## This set is what tells the two apart in the LOWER, unambiguously and WITHOUT magic in the node: the
## parser records the call site's borrowed name-span START (`cs`) here. A source byte offset is UNIQUE
## per occurrence — the `fs` of `fs[0](10)` occurs once — so the key can never collide with an ordinary
## call's callee span, it survives AST CLONING for a generic instance (the clone copies `cs`), and it
## needs no new node field. Bounded + fail-loud: a program with more than `512` expression-callee sites
## is rejected rather than silently mis-lowered.
mut ECALLEE_K : [usize; 512] = [0; 512]
mut ECALLEE_N : usize = 0

## Record the call site whose callee NAME SPAN starts at `k` as an EXPRESSION-callee call. Idempotent —
## the driver parses the package more than once (the enum pre-scan pass discards its AST), and the same
## site then re-registers with the same key.
pub ecallee_mark := fn(k : usize) {
  mut i := 0
  while i < ECALLEE_N {
    if ECALLEE_K[i] == k { return }
    i = i + 1
  }
  if ECALLEE_N >= 512 { panic("selfhost: FN-6 - too many expression-callee call sites (limit 512)") }
  ECALLEE_K[ECALLEE_N] = k
  ECALLEE_N = ECALLEE_N + 1
}

## Is the call whose callee NAME SPAN starts at `k` an EXPRESSION-callee call (argument 0 IS the callee)?
pub ecallee_is := fn(k : usize) -> bool {
  mut i := 0
  while i < ECALLEE_N {
    if ECALLEE_K[i] == k { return true }
    i = i + 1
  }
  false
}
