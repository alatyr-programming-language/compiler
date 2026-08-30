## selfhost::parser — recursive-descent parser, tokens → AST.
##
## The second promoted pass: it consumes the `selfhost::lexer` token stream (a
## `Vec(Token)` with the kinds documented there) and builds a recursive,
## arena-allocated expression AST, returning `Result(_, ParseErr)` and threading
## failure with `?`. The grammar covered here is the arithmetic-expression core plus a
## program of `name := <expr>` bindings — the proven shape (`tests/selfhost_alatyr_*_e2e`:
## expr / decls / nameres), promoted verbatim. Scale to the full Alatyr grammar
## (fn/struct/enum/if/while/for) pass by pass.
##
## The token + AST types now live in the shared `selfhost::ast` module (sibling submodule);
## the parser **references** them via a single listed member projection `(…) := ast`
## (Modules §4.1.1) rather than redeclaring its own copies, so a value it builds flows into
## the back-end passes with one type identity across the tree. Token kinds used: 0 EOF, 1 ident, 2 kw, 3 int, 5 := ,
## 6 -> , 8 : , 9 , , 10 ( 11 ) 12 { 13 } 16 + 17 - 18 * 19 / 20 == 24 < 25 > 26 <= 27 >=
## 28 != 30 ; 38 => .
vec := alloc::vec
(Arg, Arm, Bind, Decl, Expr, FieldDecl, FInit, LabelSpan, Param, Stmt, Token) := ast
fld_null := ast::fld_null
(param_p, param_null) := ast
stmt_null := ast::stmt_null
arm_p := ast::arm_p
arg_p := ast::arg_p
stmt_p := ast::stmt_p
stmt_label_mark := ast::stmt_label_mark
stmt_label_span := ast::stmt_label_span
expr_label_mark := ast::expr_label_mark
expr_label_span := ast::expr_label_span
## FN-6 expression-callee site set (the marker the LOWER reads back — see `ast.al`).
ecallee_mark := ast::ecallee_mark

## A parse failure: an expected-but-missing token kind, or unexpected end of input.
pub ParseErr := enum { Expected(u8), Eof }

## The parse cursor: the token vector, the source base address (to read literal spans),
## the current token index, the arena the AST nodes are allocated from, and `nstr` — a
## monotonically increasing counter assigning each STRING literal a unique label index
## (`.Lstr0`, `.Lstr1`, …), so lower emits one `.rodata` entry per distinct literal
## occurrence and a `StrLit` references its own entry deterministically.
pub PC := struct {
  toks : ptr(rt::Vec),                ## the lean rt token store (handles to {kind,start,len} records)
  src : ptr(u8),
  idx : usize,
  arena : ptr(mut rt::Arena),
  nstr : usize,
  ## MODULE tier: the source span of the module a subsequent decl belongs to. Updated by a
  ## top-level `module <name>` directive in `parse_program` and stamped onto each `Decl`
  ## (`mod_start`/`mod_len`) so lower can mangle the function label per module. 0/0 until the
  ## first `module` directive — the implicit default module (lower maps it to the prefix
  ## `main`, so a single-source program's `main` mangles to `main__main`, which `_start` calls).
  mod_s : usize, mod_l : usize,
  ## ENUM-TYPE NAME TABLE (blocker-A two-pass): a `rt::Vec` of packed (name_start, name_len) pairs —
  ## the names of every kind-3 enum-type decl across ALL modules, pre-collected in a first parse pass
  ## (module order is getdents, not dependency-sorted, so a decls-so-far check is unsound). Lets
  ## `p_factor` fire the generic-enum-ctor rewrite ONLY when the head ident IS an enum type, so a
  ## call-then-UFCS `f(args).method(…)` (head NOT an enum) parses as an ordinary Call. An EMPTY table
  ## (len 0 — the single-pass / pre-scan-pass paths) means "unknown" → keep the old always-fire
  ## behavior (byte-identical). Never dereferenced when empty (short-circuited).
  enums : ptr(rt::Vec),
}

## Token access goes through these two accessors (not `vec::` directly) so the token STORAGE
## can be swapped without touching the parser body: today they read the `alloc::vec` token
## vector; the rt migration repoints them at the lean `rt` token store. `tok_at` returns the
## 3-word `Token` by value (the `%rax:%rdx:%rcx` return convention).
tok_at := fn(pc : PC, i : usize) -> Token {
  ## A read AT OR PAST the end returns the EOF sentinel (kind 0) instead of indexing an
  ## unwritten slot. The lexer appends a real EOF token, so an in-range read never needs this;
  ## but a recursive-descent peek can look one past the last token (e.g. checking the token after
  ## a closing `}` at end-of-input), and the lean `rt::Vec` has no bounds check — an OOB
  ## `vec_get` would read a zero/garbage handle and `rec_get` would dereference it (SEGV). Every
  ## parser loop already terminates on `kind == 0`, so a synthetic EOF here makes past-end peeks
  ## stop cleanly rather than crash.
  if i >= rt::vec_len(deref(pc.toks)) { return Token(kind = 0, start = 0, len = 0) }
  h := rt::vec_get(deref(pc.toks), i)
  return Token(kind = unchecked u8(rt::rec_get(h, 0)), start = rt::rec_get(h, 1), len = rt::rec_get(h, 2))
}
ntoks := fn(pc : PC) -> usize { rt::vec_len(deref(pc.toks)) }

## The token under the cursor.
pub cur := fn(pc : PC) -> Token { tok_at(pc, pc.idx) }

## Is the cursor on the **keyword** `w`? The lexer tags every keyword with one kind (2,
## `is_kw`), so keyword **identity** is resolved here by comparing the token's lexeme to
## `w` (`str_at` over the source span). This is what lets the parser branch on `if` /
## A bare built-in SCALAR or `str` type NAME — the set of `bitcast` targets that stay IDENTITY-erased
## (a register no-op / a 2-word value the return-slot coercion already types). Everything else that is
## a bare identifier is a USER type name (a struct), whose `bitcast` target must be PRESERVED so a
## local bound from it is typed by the TARGET struct (else its fields resolve against the SOURCE type).
scalar_or_str_name := fn(src : ptr(u8), s : usize, n : usize) -> bool {
  if n == 0 { return true }
  t := str_at((src + s), n)
  t == "u8" or t == "u16" or t == "u32" or t == "u64" or t == "usize"
    or t == "i8" or t == "i16" or t == "i32" or t == "i64" or t == "isize"
    or t == "f32" or t == "f64" or t == "bool" or t == "char" or t == "str"
    or t == "bits8" or t == "bits16" or t == "bits32" or t == "bits64" or t == "type"
}

## `else` / `while` / `fn` over the single keyword token.
tok_kw := fn(pc : PC, w : str) -> bool {
  t := cur(pc)
  if t.kind != 2 { return false }
  str_eq(str_at(pc.src + t.start, t.len), w)
}

## String-literal scan result. `len` is the decoded UTF-8 byte length, not the raw source span.
## Keeping this as a small value lets parser call sites validate the same byte stream that all
## backends later emit. In particular, `\xHH` contributes one decoded byte while occupying four
## source bytes, and an escaped byte must still be valid UTF-8 when it is part of `str`.
StringScan := struct { ok : bool, len : usize }

hex_digit := fn(c : u8) -> usize {
  if c >= 48 and c <= 57 { return usize(c - 48) }
  if c >= 65 and c <= 70 { return usize(c - 65) + 10 }
  if c >= 97 and c <= 102 { return usize(c - 97) + 10 }
  16
}

## Scan and validate a string's decoded byte stream. Plain source bytes are already UTF-8 bytes;
## simple escapes decode to their one-byte values and `\xHH` decodes to the specified byte. The
## validator rejects overlong encodings, surrogates, truncated sequences, and invalid continuation
## bytes, so `"\\xff"` is a compile error instead of a str carrying invalid UTF-8.
scan_string := fn(base : usize, n : usize) -> StringScan {
  mut i := 0
  mut out := 0
  mut need := 0
  mut lo := 128
  mut hi := 191
  while i < n {
    mut b := 0
    if bytes(str_at(base + i, 1))[0] == 92 {
      if i + 1 >= n { return StringScan(ok = false, len = 0) }
      esc := bytes(str_at(base + i + 1, 1))[0]
      if esc == 120 {
        if i + 3 >= n { return StringScan(ok = false, len = 0) }
        h1 := hex_digit(bytes(str_at(base + i + 2, 1))[0])
        h2 := hex_digit(bytes(str_at(base + i + 3, 1))[0])
        if h1 >= 16 or h2 >= 16 { return StringScan(ok = false, len = 0) }
        b = h1 * 16 + h2
        i += 4
      } else {
        if esc == 110 { b = 10 }
        else if esc == 116 { b = 9 }
        else if esc == 114 { b = 13 }
        else if esc == 48 { b = 0 }
        else if esc == 92 or esc == 39 or esc == 34 { b = esc }
        else { b = esc }
        i += 2
      }
    } else {
      b = usize(bytes(str_at(base + i, 1))[0])
      i += 1
    }
    if need != 0 {
      if b < lo or b > hi { return StringScan(ok = false, len = 0) }
      need -= 1
      lo = 128
      hi = 191
    } else if b <= 127 {
    } else if b >= 194 and b <= 223 {
      need = 1
    } else if b == 224 {
      need = 2
      lo = 160
    } else if b >= 225 and b <= 236 {
      need = 2
    } else if b == 237 {
      need = 2
      hi = 159
    } else if b >= 238 and b <= 239 {
      need = 2
    } else if b == 240 {
      need = 3
      lo = 144
    } else if b >= 241 and b <= 243 {
      need = 3
    } else if b == 244 {
      need = 3
      hi = 143
    } else {
      return StringScan(ok = false, len = 0)
    }
    out += 1
  }
  if need != 0 { return StringScan(ok = false, len = 0) }
  StringScan(ok = true, len = out)
}

## rt-style AST-node allocator + reader (fixpoint). These replace the generic
## `allocate`/`get` allocator protocol for the AST arena: the lean self-host lower compiles a
## monomorphic bump + a generic `bitcast` accessor (the `decl_at` shape), but NOT the generic
## `allocate` (it returns `Result(Handle(T), AllocError)`) / `get` (it takes a generic `Handle(T)`
## and returns a `scoped` ptr). So the tree must store its AST on this leaner pair to compile
## itself. `node_alloc` keeps the SAME handle semantics as `allocate` — a byte OFFSET into the
## arena, 8-aligned — so it is interchangeable with the remaining `get` readers during migration.
node_alloc := fn(in out a : rt::Arena, sz : usize) -> usize {
  rem := a.off % 8
  mut aligned := a.off
  if rem != 0 { aligned = a.off + (8 - rem) }
  if aligned + sz > a.cap { panic("AST: out of memory") }
  a.off = aligned + sz
  return aligned
}
## A typed pointer to the node at arena OFFSET `h` (the `get` reader's lean replacement). Mirrors
## `lower::decl_at` but resolves an offset against the arena base (decls use absolute handles).
node_ptr := fn(T : type, a : rt::Arena, h : usize) -> ptr(mut T) {
  base_int := unchecked bitcast(usize, a.base)
  return unchecked bitcast(ptr(mut T), base_int + h)
}

## Allocate one `Expr` node in the arena and return a pointer to it.
pub newnode := fn(a : ptr(mut rt::Arena), val : Expr) -> ptr(mut Expr) {
  idx := node_alloc(deref(a), 64)
  np := node_ptr(Expr, deref(a), idx)
  deref(np) = val
  np
}

## `embed("path")` — the reproducible comptime file-embed builtin (Comptime §2.4; prelude/stdlib
## appendix §160 `embed(comptime path : str) -> [u8; N]`; Assembly §9 `embed("path")` → `[u8; N]`).
## At PARSE TIME it opens+reads the file at `path` and BAKES its bytes into the program as a
## read-only byte sequence, so the build is reproducible ("hashed into the build"; the lockfile-hash
## tracking is a separate follow-up — the baked bytes themselves are deterministic).
##
## PATH BASE (assumption; the spec fixes the signature but not the resolution base, and the
## `PC` carries no per-expression source-file path): the path is handed to `open(2)` VERBATIM, so a
## RELATIVE path resolves against the compiler's current working directory and an ABSOLUTE path is
## used as-is. This is deterministic for a fixed invocation.
##
## REPRESENTATION: the value reuses the `str` machinery — it becomes a
## `StrLit(ss, N, lbl, path_s, path_n)` whose `ss` is the ABSOLUTE arena address of the baked bytes
## (NOT a source offset), whose `lbl` carries the EMBED marker in its LOW residue
## (`lbl % 1000000 >= embed_label_base`), and whose final two fields retain the raw source span of
## the path literal. `lower`'s rodata
## pass keys on to emit the bytes as a `.byte` list read from `ss` (any binary byte — NUL / high /
## newline). The residue marker is invariant under the closure-hoist label RENUMBER (`driver` adds a
## multiple of 1000000 to a cloned literal's label), so an embed inside a hoisted closure is still
## recognized; a plain `>= 1e9` threshold WOULD collide with those renumbered labels. Every other
## `StrLit` consumer (value push, `.len`, `bytes()`, the frame-slot assign) uses only `lbl` + the
## length `N`, never `src + ss`, so embed rides the existing str paths unchanged: `embed(...).len ==
## N`, `bytes(embed(...))[i]` is byte `i`, and it is passable where a `u8` slice is expected. A
## missing / unopenable file FAILS LOUD (`panic` → non-zero build); an embed is never silently empty.
## (The embed label `embed_label_base + pc.nstr` assumes a program has < 500000 string literals — the
## renumber design already caps a module at 1000000; the whole compiler uses ~6.5k.)
embed_label_base := 500000

## Build a `StrLit` for `embed(<path>)`: `[ps, ps+pn)` is the path's INNER span in `pc.src`. Reads the
## file's bytes into the compile arena via the PROVEN arena primitives (`node_alloc`/`node_ptr`, as
## `newnode` uses — a direct `rt::bump(deref(ptr))` mis-lowers, hence not used). All `panic`s are
## top-level `if`-guards (the shape `node_alloc` uses), never nested in a loop.
embed_strlit := fn(in out pc : PC, ps : usize, pn : usize) -> ptr(mut Expr) {
  ## NUL-terminated C path in the arena (open needs a C string; the path span is into the shared
  ## source buffer, not NUL-terminated). Copy the path bytes verbatim — a plain path, no escapes.
  mut pb := rt::strbuf(deref(pc.arena), pn + 16)
  mut i := 0
  while i < pn {
    kb := rt::push_byte(pb, bytes(str_at(pc.src + ps + i, 1))[0])
    i = i + 1
  }
  kn := rt::push_byte(pb, 0)                               ## NUL terminator
  pathaddr := unchecked bitcast(usize, rt::strbuf_base(pb))
  fd := rt::sys_open(2, pathaddr, 0, 0)                    ## open(path, O_RDONLY, 0)
  if fd < 0 { panic("selfhost: embed cannot open file") }
  ufd := unchecked bitcast(usize, fd)
  szr := rt::sys_lseek(8, ufd, 0, 2)                       ## lseek(fd, 0, SEEK_END) → byte length
  if szr < 0 { panic("selfhost: embed cannot size file") }
  rw := rt::sys_lseek(8, ufd, 0, 0)                        ## lseek(fd, 0, SEEK_SET) → rewind
  sz := unchecked bitcast(usize, szr)
  ## Reserve `sz` bytes in the arena (8-aligned; `node_alloc` panics on OOM) and take the region's
  ## absolute address, then read the file's bytes into it (chunked until EOF / `sz` filled).
  h := node_alloc(deref(pc.arena), sz)
  pbuf := node_ptr(u8, deref(pc.arena), h)
  addr := unchecked bitcast(usize, pbuf)
  mut total := 0
  mut done := false
  while done == false {
    nr := rt::sys_read(0, ufd, addr + total, sz - total)
    if nr <= 0 { done = true } else { total = total + unchecked bitcast(usize, nr) }
  }
  cc := rt::sys_close(3, ufd)
  lbl := embed_label_base + pc.nstr
  pc.nstr = pc.nstr + 1
  return newnode(pc.arena, Expr.StrLit(addr, total, lbl, ps, pn))
}

## Allocate a `Stmt` in the arena and return its **handle index** (so `next`/body links
## are plain `usize`, not pointers — the arena-linked-list technique).
pub snode := fn(a : ptr(mut rt::Arena), val : Stmt) -> ptr(mut Stmt) {
  idx := node_alloc(deref(a), 96)
  p := node_ptr(Stmt, deref(a), idx)
  deref(p) = val
  p
}

## Store a `Decl` into the lean `rt` arena `da`, returning its BASE address as the decl HANDLE.
## A `Decl` is too wide for a register return, so `parse_decl` hands back this handle and `lower`
## reads it via `deref(decl_at(Decl, h))`. A `deref(p) = d` through a `ptr(Decl)` writes the
## record in NORMAL (upward) layout at `p` — `[p, p + size(Decl))` — so the handle must be the
## bumped region's BASE (`s`), keeping the whole record inside the reservation. (An earlier
## `top = s + size - 8` handle made the upward store spill `size - 8` bytes ABOVE the reservation;
## that was invisible in a single-module compile — free space follows the last record — but in a
## multi-module `compile_pair` the next allocation (`rt_toksb`) sat in that spill and clobbered
## every field above word 0. `selfhost_driver_genxmod_e2e` is the regression guard.)
dnode := fn(in out da : rt::Arena, d : Decl) -> usize {
  s := rt::bump(da, size(Decl))
  p : ptr(mut Decl) = unchecked bitcast(ptr(mut Decl), s)
  deref(p) = d
  return s
}

## Allocate a match `Arm` in the arena and return its handle index (arm lists link via
## `next`, like statement lists).
anode := fn(a : ptr(mut rt::Arena), val : Arm) -> ptr(mut Arm) {
  idx := node_alloc(deref(a), 96)
  p := node_ptr(Arm, deref(a), idx)
  deref(p) = val
  p
}

## Allocate a `FieldDecl` (struct field / enum variant) in the arena; returns its handle.
fnode := fn(a : ptr(mut rt::Arena), val : FieldDecl) -> ptr(mut FieldDecl) {
  idx := node_alloc(deref(a), 96)
  p := node_ptr(FieldDecl, deref(a), idx)
  deref(p) = val
  p
}

## Allocate a `Param` (fn parameter) in the arena; returns its handle (params link via `next`).
pub pnode := fn(a : ptr(mut rt::Arena), val : Param) -> ptr(mut Param) {
  idx := node_alloc(deref(a), 64)
  p := node_ptr(Param, deref(a), idx)
  deref(p) = val
  p
}
## Overwrite param `h`'s `.next` (reconstruct + store), the standalone form of the parser's inline
## param-link. `pub` so the driver's FN-6 capture pass can link appended capture params HERE (in the
## parser module) — the identical store mis-lowers in the driver module (a cross-module codegen quirk,
## the mirror of the driver-reads-decls-fine / parser-doesn't one), writing a pointer instead of copying.
pub set_param_next := fn(a : ptr(mut rt::Arena), h : ptr(mut Param), nx : ptr(mut Param)) {
  pm := deref(param_p(h))
  upd := Param(ns = pm.ns, nl = pm.nl, next = nx, ts = pm.ts, tl = pm.tl, pmode = pm.pmode, pps = pm.pps, ppl = pm.ppl)
  deref(param_p(h)) = upd
}

## Allocate an `Arg` (call argument / struct-field value / enum-payload value) in the arena;
## returns its handle (args link via `next`). One `Arg`-list machinery serves all three.
pub gnode := fn(a : ptr(mut rt::Arena), val : Arg) -> ptr(mut Arg) {
  idx := node_alloc(deref(a), 64)
  p := node_ptr(Arg, deref(a), idx)
  deref(p) = val
  p
}
## Divergent failure with a message. A thin wrapper so a `panic(msg)` raised from inside a
## struct-returning helper (`reorder_struct_fields`) is lowered as the RECOGNIZED inline-abort builtin:
## a bare `panic` that is the trailing/aggregate-return expression of such a helper otherwise lowers as
## an ordinary call to an undefined `parser__panic`. Here `panic` is a NON-tail statement (the `return 0`
## is the tail), so it takes the recognized path (message → fd 2, then exit 1); `return 0` never runs.
sfail := fn(msg : str) -> usize {
  panic(msg)
  return 0
}

## The BUFFER OFFSET at which the module currently being parsed BEGINS. The driver concatenates every
## module — the AMBIENT stdlib modules first, the user's file last — into ONE buffer and hands every `PC`
## the SAME `pc.src` base, so counting newlines from offset 0 counts every EARLIER module's text as well.
## That is what made a parser-level located reject report a wildly wrong line: an error on line 3 of a
## 4-line file read "line 3" when the file was plain, "line 152" once it declared a `struct` (which pulls
## in `lib/base/derive.al` + the prelude), and "line 2369" once it mentioned `Option(ptr(u64))`. The
## module NAME and the quoted snippet were right all along — only the number was junk.
##
## Held in a MODULE GLOBAL rather than a `PC` field: `PC` is already at the frozen seed's 8-word
## aggregate-value limit (a 9th field is silently dropped — the same reason `P_STRUCTS_TBL` lives here),
## so this follows that established precedent. Set via `set_module_base` before each module's
## `parse_program`; `0` means "the whole buffer is the module", which is both the single-source paths'
## correct value and the safe default if a call site forgets (that is exactly today's behavior).
mut P_MOD_BASE := 0
## Tell the parser where the module about to be parsed starts in the shared buffer (the driver's `soff`).
pub set_module_base := fn(off : usize) { P_MOD_BASE = off }

## The 1-based SOURCE LINE of a byte offset into `pc.src`, counted by scanning the newlines before it —
## from the CURRENT MODULE's base (`P_MOD_BASE`), so the number is FILE-relative, matching both the
## module name this reject already prints and the file-relative lines `driver`'s sema/parse diagnostics
## report. The parser carries no line table (locations live in the driver), and this runs ONLY on a
## reject path that is about to abort, so the O(offset) scan costs nothing on any accepted program.
src_line_at := fn(pc : PC, off : usize) -> i64 {
  mut ln : i64 = 1
  ## a base past the offset can only mean a stale/foreign base — fall back to the whole buffer rather
  ## than skipping the scan entirely (a wrong-but-old number beats no number).
  mut p := P_MOD_BASE
  if p > off { p = 0 }
  while p < off {
    if str_eq(str_at(pc.src + p, 1), "\n") { ln = ln + 1 }
    p = p + 1
  }
  return ln
}

## LOCATED fail-loud parse reject: render `<what> [module M, at line N, near \`<source>\`]` into the AST arena
## (the `at line N` spelling matches the driver's sema/parse diagnostics — `alatyr: check: … at line N in M`
## — so ONE e2e location assertion covers both diagnostic families)
## and `panic` it — the module name, the 1-based line, and the next 24 source bytes at the offending
## offset, so the user sees WHERE without a line table. Mirrors `sfail` (the `panic` is a NON-tail
## statement, so it lowers as the recognized inline-abort builtin); the message is built with the same
## `rt::strbuf` + `push_int` machinery `synth_hof_name` already uses in this module. Never returns.
reject_at := fn(in out pc : PC, what : str, off : usize) -> usize {
  mut mb := rt::strbuf(deref(pc.arena), 512)
  k1 := rt::push_str(mb, what)
  k2 := rt::push_str(mb, " [module ")
  k5 := rt::push_str(mb, str_at(pc.src + pc.mod_s, pc.mod_l))
  k6 := rt::push_str(mb, ", at line ")
  k3 := rt::push_int(mb, src_line_at(pc, off))
  k7 := rt::push_str(mb, ", near `")
  mut snl := 24
  srcend := tok_at(pc, ntoks(pc) - 1).start
  if off + snl > srcend { snl = srcend - off }
  k8 := rt::push_str(mb, str_at(pc.src + off, snl))
  k4 := rt::push_str(mb, "`]")
  mbi := unchecked bitcast(usize, rt::strbuf_base(mb))
  mbp := unchecked bitcast(ptr(u8), mbi)
  panic(str_at(mbp, rt::buf_len(mb)))
  return 0
}

## LOCATED reject for the BALANCED-TRUNCATION class: the token stream ENDED at a point where the
## grammar REQUIRES a continuation (`x :=`, `x := 1 +`, `x : u64`, `f := fn() ->`, `x := rt::`,
## `x := y.`, `x := if`, …). The residual-delimiter-depth check at the tail of `parse_program` is
## structurally blind to these — the delimiters are BALANCED, nothing is left open — and every
## recursive-descent loop here stops on the synthetic EOF (`tok_at`), so the construct's missing
## continuation is simply never noticed. Measured on the pre-fix compiler: sixteen such shapes
## SEGV'd (rc 139, no message, no position — `p_factor` recursing on the EOF sentinel until the
## stack ran out) and five were SILENTLY ACCEPTED (the declaration vanished and the program built
## and ran), which I11 names the forbidden outcome.
##
## Reports at the LAST REAL TOKEN — the `:=` / `+` / `->` / `::` / `.` the author actually typed —
## not at the EOF sentinel, whose span is the zero-length end of the buffer (`reject_at`'s `near`
## snippet would then be empty and the line number would be the file's last, not the construct's).
## At every call site `pc.idx` sits ON the EOF sentinel, so `pc.idx - 1` is that token; the guard on
## its kind falls back to the vector's last token for a call site whose cursor has run PAST the end.
reject_eof := fn(in out pc : PC, what : str) -> usize {
  mut off := tok_at(pc, ntoks(pc) - 1).start
  if pc.idx > 0 {
    pt := tok_at(pc, pc.idx - 1)
    if pt.kind != 0 { off = pt.start }
  }
  ## a NON-tail call, so `reject_at`'s `panic` keeps the recognized inline-abort lowering (see `sfail`)
  zre := reject_at(pc, what, off)
  return 0
}

## LOCATED reject for "the grammar requires a specific token HERE" — at the CURSOR when a token is
## actually there (the MID-FILE spelling of a truncation: the scan stopped on the next declaration's
## `:=`), and at the last real token when the cursor sits on the EOF sentinel, whose span is the
## zero-length end of the buffer — reporting there prints the line AFTER the file's last and an empty
## `near`, which is measurably less useful than naming the construct.
reject_here := fn(in out pc : PC, what : str) -> usize {
  if cur(pc).kind == 0 {
    zh0 := reject_eof(pc, what)
  }
  zh1 := reject_at(pc, what, cur(pc).start)
  return 0
}

## Does token `i` start EXACTLY where token `i-1` ends — i.e. are the two ADJACENT in the source, with
## no whitespace, newline or comment between? The lexer emits NO newline tokens, so adjacency is the
## only thing that tells a CALL POSTFIX (`xs[0](10)`, `mk()(41)`) apart from a following STATEMENT that
## merely begins with a `(`: `src/lower_layout.al:547` ends a line with `bytes(str_at(…))[0]` and opens
## the next with `(c >= 97 and c <= 122) or …`, which must keep parsing as two separate expressions.
tok_adjacent := fn(pc : PC, i : usize) -> bool {
  if i == 0 { return false }
  pt := tok_at(pc, i - 1)
  return tok_at(pc, i).start == pt.start + pt.len
}

## Does the source gap between the previous token and the current token contain a NEWLINE? The
## lexer intentionally keeps newline out of the token stream, but Grammar §2 permits it as an
## `item-sep` in array constructors. Keep this as source-span metadata rather than widening Token
## (which would alter the bootstrap-sensitive 3-word record and every parser consumer).
tok_gap_has_newline := fn(pc : PC) -> bool {
  if pc.idx == 0 { return false }
  prev := tok_at(pc, pc.idx - 1)
  curr := tok_at(pc, pc.idx)
  mut p := prev.start + prev.len
  while p < curr.start {
    if str_eq(str_at(pc.src + p, 1), "\n") { return true }
    p += 1
  }
  false
}

## Is the `(`-group AT THE CURSOR the head of a following BINDING (`(A, B) := m` / `(a, b) = v` /
## `(x) : T`) rather than a call-argument list applied to the expression just parsed? The lexer emits
## NO newline tokens, so the `(` that opens the next declaration/statement directly abuts the previous
## expression — scan the balanced group and look at the token past it. Exactly the disambiguation
## `parse_decl`'s module-alias branch performs for `name := mod::path` followed by `(A, B) := mod`.
paren_group_is_binding := fn(pc : PC) -> bool {
  nt := ntoks(pc)
  mut depth := 0
  mut k := pc.idx
  while k < nt {
    kk := tok_at(pc, k).kind
    if kk == 10 { depth = depth + 1 }
    else if kk == 11 {
      depth = depth - 1
      if depth == 0 {
        k = k + 1
        break
      }
    }
    k = k + 1
  }
  mut res := false
  if k < nt {
    nk := tok_at(pc, k).kind
    if nk == 5 { res = true }
    if nk == 21 { res = true }
    if nk == 8 { res = true }
  }
  return res
}

## Allocate a `FInit` (a struct-literal field initializer `f = v` collected at parse) in the arena;
## returns its handle. Used only transiently to reorder named fields into declaration order.
finode := fn(a : ptr(mut rt::Arena), val : FInit) -> ptr(mut FInit) {
  idx := node_alloc(deref(a), 64)
  p := node_ptr(FInit, deref(a), idx)
  deref(p) = val
  p
}
finit_p := ast::finit_p

## Synthesize the SPAN of an identifier a parse-time desugar needs as a call CALLEE (`@alloc` →
## `alloc_into`) but which is NOT a token in the user source: write the name into the persistent AST
## arena and REBASE its address into a `src`-relative handle (`base_abs - src`, modular — via `rt::off`,
## an underflowing pointer difference, CG-8) — exactly the span form `(src + s)` recovers at lower
## time (mirrors lower's `subst_enum_ret_span`). Returns the rebased start; the caller supplies the
## (constant) length. The written bytes live in the arena for the rest of compilation.
synth_ident_span := fn(in out pc : PC, nm : str) -> usize {
  mut sb := rt::strbuf(deref(pc.arena), 32)
  k := rt::push_str(sb, nm)
  base_abs := unchecked bitcast(usize, rt::strbuf_base(sb))
  unchecked (base_abs - pc.src)   ## INTENTIONAL modular underflow (base_abs may be < src) — the rebase seam
}

## Overwrite arg `h`'s `.next`. `pub` for the driver's FN-6 capture call-rewrite (the store must run in
## the parser module — it mis-lowers in the driver module, writing a pointer instead of copying).
pub set_arg_next := fn(a : ptr(mut rt::Arena), h : ptr(mut Arg), nx : ptr(mut Arg)) {
  am := deref(arg_p(h))
  upd := Arg(e = am.e, next = nx)
  deref(arg_p(h)) = upd
}

## ---- FN-6 §6.2 — AST DEEP-CLONE (per-closure HOF specialization) --------------------------------
## Clone an Expr / Stmt / Param / Arg tree into FRESH arena nodes so a generic higher-order fn `H`
## can be SPECIALIZED for one capturing closure WITHOUT mutating the shared `H` decl that other
## (non-capturing) call sites still use. All node stores run HERE (the parser module) — the identical
## stores mis-lower in the driver (the cross-module codegen quirk that `set_param_next`/`set_arg_next`
## already dodge), so the driver calls these and gets back fresh handles. `ok` is set FALSE (never
## reset true) on any variant not handled — the caller then DECLINES the specialization fail-loud
## (never a partial / stale-pointer clone that would be a silent miscompile).
expr_null := fn() -> ptr(Expr) { unchecked bitcast(ptr(Expr), 0) }
arg_null := fn() -> ptr(mut Arg) { unchecked bitcast(ptr(mut Arg), 0) }

## ---- Structured-label resolution (Control Flow §2.1/§7.1) ---------------------------------------
## Labels are FUNCTION-scoped names attached with `@label(name)` to a loop (§2.1). Rather than store a
## name on every loop node (which would touch every AST-walk pass), the parser resolves a `break name` /
## `continue name` to a LOOP-NESTING DEPTH at parse time: as the parser descends into `loop`/`while`/`for`
## bodies it maintains a stack, one frame per enclosing loop, holding that loop's `@label` name span (0/0
## when unlabeled). `break name` finds the nearest enclosing frame whose name matches and records the
## depth (0 = innermost). The EMIT side (lower) mirrors this with its own loop-frame stack, so index
## arithmetic lines up. `P_PEND_*` carries a pending `@label(name)` from the attribute to the loop it
## precedes. Depth 0 (bare break/continue) is the pre-label lowering byte-for-byte (self-host = neutral).
mut P_LBL_S : [usize; 64] = [0; 64]
mut P_LBL_L : [usize; 64] = [0; 64]
mut P_LOOP_SP := 0
mut P_PEND_S := 0
mut P_PEND_L := 0
## Resolve an identifier token (span `[s, s+n)`) to a loop-nesting depth if it names an in-scope
## structured label; returns depth (0 = innermost enclosing loop) or -1 if it is NOT a label in scope
## (so the caller treats the identifier as an ordinary value expression, §7.1 disambiguation).
lbl_depth := fn(src : usize, s : usize, n : usize) -> i64 {
  mut i := P_LOOP_SP
  while i > 0 {
    i = i - 1
    if P_LBL_L[i] != 0 and str_eq(str_at(src + P_LBL_S[i], P_LBL_L[i]), str_at(src + s, n)) {
      return i64((P_LOOP_SP - 1) - i)
    }
  }
  return 0 - 1
}
## Push a loop frame (its `@label` name span, or the pending one) as the parser enters a loop body.
lbl_push := fn() {
  if P_LOOP_SP < 64 {
    P_LBL_S[P_LOOP_SP] = P_PEND_S
    P_LBL_L[P_LOOP_SP] = P_PEND_L
    P_LOOP_SP = P_LOOP_SP + 1
  }
  P_PEND_S = 0
  P_PEND_L = 0
}
lbl_pop := fn() { if P_LOOP_SP > 0 { P_LOOP_SP = P_LOOP_SP - 1 } }

pub clone_args := fn(a : ptr(mut rt::Arena), ah : ptr(mut Arg), ok : ptr(mut bool)) -> ptr(mut Arg) {
  mut head := arg_null()
  mut tail := arg_null()
  mut g := ah
  while unchecked bitcast(usize, g) != 0 {
    am := deref(arg_p(g))
    ce := clone_expr(a, am.e, ok)
    ng := gnode(a, Arg(e = ce, next = 0))
    if unchecked bitcast(usize, head) == 0 { head = ng } else { set_arg_next(a, tail, ng) }
    tail = ng
    g = am.next
  }
  head
}

pub clone_expr := fn(a : ptr(mut rt::Arena), e : ptr(Expr), ok : ptr(mut bool)) -> ptr(Expr) {
  if unchecked bitcast(usize, e) == 0 { return expr_null() }
  mut r := expr_null()
  match deref(e) {
    Expr::Num(v, s, n) => { r = newnode(a, Expr.Num(v, s, n)) }
    Expr::BoolLit(v) => { r = newnode(a, Expr.BoolLit(v)) }
    Expr::Var(s, n) => { r = newnode(a, Expr.Var(s, n)) }
    Expr::StrLit(s, n, ix, ps, pn) => { r = newnode(a, Expr.StrLit(s, n, ix, ps, pn)) }
    Expr::FloatLit(s, n) => { r = newnode(a, Expr.FloatLit(s, n)) }
    Expr::FnRef(fp, ms, ml) => { r = newnode(a, Expr.FnRef(fp, ms, ml)) }
    Expr::Bin(op, l, rr) => { cl := clone_expr(a, l, ok); cr := clone_expr(a, rr, ok); r = newnode(a, Expr.Bin(op, cl, cr)) }
    Expr::Unchecked(inner) => { ci := clone_expr(a, inner, ok); r = newnode(a, Expr.Unchecked(ci)) }
    Expr::Bitcast(inner, bps, bpl) => { ci := clone_expr(a, inner, ok); r = newnode(a, Expr.Bitcast(ci, bps, bpl)) }
    Expr::AddrOf(inner) => { ci := clone_expr(a, inner, ok); r = newnode(a, Expr.AddrOf(ci)) }
    Expr::Deref(inner) => { ci := clone_expr(a, inner, ok); r = newnode(a, Expr.Deref(ci)) }
    Expr::Try(inner) => { ci := clone_expr(a, inner, ok); r = newnode(a, Expr.Try(ci)) }
    Expr::Field(b, fs, fl) => { cb := clone_expr(a, b, ok); r = newnode(a, Expr.Field(cb, fs, fl)) }
    Expr::Index(b, ix) => { cb := clone_expr(a, b, ok); cix := clone_expr(a, ix, ok); r = newnode(a, Expr.Index(cb, cix)) }
    Expr::Slice(b, lo, hi) => { cb := clone_expr(a, b, ok); clo := clone_expr(a, lo, ok); chi := clone_expr(a, hi, ok); r = newnode(a, Expr.Slice(cb, clo, chi)) }
    Expr::If(c, th, el) => { cc := clone_expr(a, c, ok); ct := clone_expr(a, th, ok); ce := clone_expr(a, el, ok); r = newnode(a, Expr.If(cc, ct, ce)) }
    Expr::Call(cs, cl, n, ah) => { cah := clone_args(a, ah, ok); r = newnode(a, Expr.Call(cs, cl, n, cah)) }
    Expr::StructLit(cs, cl, n, ah) => { cah := clone_args(a, ah, ok); r = newnode(a, Expr.StructLit(cs, cl, n, cah)) }
    Expr::EnumLit(es, el, vs, vl, n, ah) => { cah := clone_args(a, ah, ok); r = newnode(a, Expr.EnumLit(es, el, vs, vl, n, cah)) }
    Expr::ArrayLit(n, ah) => { cah := clone_args(a, ah, ok); r = newnode(a, Expr.ArrayLit(n, cah)) }
    Expr::Loop(b) => { cb := clone_stmts(a, b, ok); r = newnode(a, Expr.Loop(cb)); ls := expr_label_span(e); expr_label_mark(r, ls.s, ls.n) }
    _ => { deref(ok) = false }
  }
  r
}

## Clone ONE statement (its `next` is set to 0 — the caller links the spine); the original's `next`
## handle is written to `nxout` so the spine walker advances without a second match.
clone_one_stmt := fn(a : ptr(mut rt::Arena), st : ptr(mut Stmt), ok : ptr(mut bool), nxout : ptr(mut usize)) -> ptr(mut Stmt) {
  x := deref(stmt_p(Stmt, st))
  mut r := stmt_null()
  match x {
    Stmt::Assign(ns, nl, v, nx) => { deref(nxout) = unchecked bitcast(usize, nx); cv := clone_expr(a, v, ok); r = snode(a, Stmt.Assign(ns, nl, cv, 0)) }
    Stmt::Return(rv, nx) => { deref(nxout) = unchecked bitcast(usize, nx); mut crv := expr_null(); if unchecked bitcast(usize, rv) != 0 { crv = clone_expr(a, rv, ok) }; r = snode(a, Stmt.Return(crv, 0)) }
    Stmt::ExprStmt(e, nx) => { deref(nxout) = unchecked bitcast(usize, nx); ce := clone_expr(a, e, ok); r = snode(a, Stmt.ExprStmt(ce, 0)); ls := stmt_label_span(st); stmt_label_mark(r, ls.s, ls.n) }
    Stmt::If(c, th, el, nx) => { deref(nxout) = unchecked bitcast(usize, nx); cc := clone_expr(a, c, ok); cth := clone_stmts(a, th, ok); cel := clone_stmts(a, el, ok); r = snode(a, Stmt.If(cc, cth, cel, 0)) }
    Stmt::While(c, b, nx) => { deref(nxout) = unchecked bitcast(usize, nx); cc := clone_expr(a, c, ok); cb := clone_stmts(a, b, ok); r = snode(a, Stmt.While(cc, cb, 0)); ls := stmt_label_span(st); stmt_label_mark(r, ls.s, ls.n) }
    Stmt::For(fns, fnl, lo, hi, b, nx) => { deref(nxout) = unchecked bitcast(usize, nx); mut clo := expr_null(); if unchecked bitcast(usize, lo) != 0 { clo = clone_expr(a, lo, ok) }; mut chi := expr_null(); if unchecked bitcast(usize, hi) != 0 { chi = clone_expr(a, hi, ok) }; cb := clone_stmts(a, b, ok); r = snode(a, Stmt.For(fns, fnl, clo, chi, cb, 0)); ls := stmt_label_span(st); stmt_label_mark(r, ls.s, ls.n) }
    Stmt::Loop(b, nx) => { deref(nxout) = unchecked bitcast(usize, nx); cb := clone_stmts(a, b, ok); r = snode(a, Stmt.Loop(cb, 0)); ls := stmt_label_span(st); stmt_label_mark(r, ls.s, ls.n) }
    Stmt::Unchecked(b, nx) => { deref(nxout) = unchecked bitcast(usize, nx); cb := clone_stmts(a, b, ok); r = snode(a, Stmt.Unchecked(cb, 0)) }
    Stmt::Break(bv, bd, nx) => { deref(nxout) = unchecked bitcast(usize, nx); mut cbv := expr_null(); if unchecked bitcast(usize, bv) != 0 { cbv = clone_expr(a, bv, ok) }; r = snode(a, Stmt.Break(cbv, bd, 0)); ls := stmt_label_span(st); stmt_label_mark(r, ls.s, ls.n) }
    Stmt::Continue(cd, nx) => { deref(nxout) = unchecked bitcast(usize, nx); r = snode(a, Stmt.Continue(cd, 0)); ls := stmt_label_span(st); stmt_label_mark(r, ls.s, ls.n) }
    Stmt::DerefAssign(p, v, nx) => { deref(nxout) = unchecked bitcast(usize, nx); cp := clone_expr(a, p, ok); cv := clone_expr(a, v, ok); r = snode(a, Stmt.DerefAssign(cp, cv, 0)) }
    Stmt::IndexAssign(b, ix, v, nx) => { deref(nxout) = unchecked bitcast(usize, nx); cb := clone_expr(a, b, ok); cix := clone_expr(a, ix, ok); cv := clone_expr(a, v, ok); r = snode(a, Stmt.IndexAssign(cb, cix, cv, 0)) }
    Stmt::FieldAssign(bns, bnl, ffs, ffl, fv, nx) => { deref(nxout) = unchecked bitcast(usize, nx); cfv := clone_expr(a, fv, ok); r = snode(a, Stmt.FieldAssign(bns, bnl, ffs, ffl, cfv, 0)) }
    Stmt::FieldPathAssign(pl, fpv, nx) => { deref(nxout) = unchecked bitcast(usize, nx); cpl := clone_expr(a, pl, ok); cfpv := clone_expr(a, fpv, ok); r = snode(a, Stmt.FieldPathAssign(cpl, cfpv, 0)) }
    Stmt::IndexFieldAssign(b, ix, ffs, ffl, v, nx) => { deref(nxout) = unchecked bitcast(usize, nx); cb := clone_expr(a, b, ok); cix := clone_expr(a, ix, ok); cv := clone_expr(a, v, ok); r = snode(a, Stmt.IndexFieldAssign(cb, cix, ffs, ffl, cv, 0)) }
    Stmt::AllocWith(ae, b, nx) => { deref(nxout) = unchecked bitcast(usize, nx); cae := clone_expr(a, ae, ok); cb := clone_stmts(a, b, ok); r = snode(a, Stmt.AllocWith(cae, cb, 0)) }
    _ => { deref(nxout) = 0; deref(ok) = false }
  }
  r
}

## Clone a Stmt LIST, linking the fresh nodes via `set_stmt_next` (the safe link store).
pub clone_stmts := fn(a : ptr(mut rt::Arena), head : ptr(mut Stmt), ok : ptr(mut bool)) -> ptr(mut Stmt) {
  mut nhead := stmt_null()
  mut ntail := stmt_null()
  mut st := head
  while unchecked bitcast(usize, st) != 0 {
    mut nx := 0
    ns := clone_one_stmt(a, st, ok, ptr(nx))
    if unchecked bitcast(usize, nhead) == 0 { nhead = ns } else { set_stmt_next(a, ntail, ns) }
    ntail = ns
    st = unchecked bitcast(ptr(mut Stmt), nx)
  }
  nhead
}

## Clone a Param chain (fresh nodes; names/types/pmode copied verbatim), linked via `set_param_next`.
pub clone_params := fn(a : ptr(mut rt::Arena), ph : ptr(mut Param), ok : ptr(mut bool)) -> ptr(mut Param) {
  mut head := param_null()
  mut tail := param_null()
  mut p := ph
  while unchecked bitcast(usize, p) != 0 {
    pm := deref(param_p(p))
    np := pnode(a, Param(ns = pm.ns, nl = pm.nl, next = 0, ts = pm.ts, tl = pm.tl, pmode = pm.pmode, pps = pm.pps, ppl = pm.ppl))
    if unchecked bitcast(usize, head) == 0 { head = np } else { set_param_next(a, tail, np) }
    tail = np
    p = pm.next
  }
  head
}

## RENUMBER the string-literal labels in a CLONED expression tree: rewrite each `StrLit`'s label
## index `ix` to `base + ix`. A deep clone copies each `StrLit(ss, sl, ix, path_s, path_n)` VERBATIM (same `ix`), so
## the original decl AND the clone would both emit `.Lstr<ix>: .ascii …` → a DUPLICATE-symbol
## assembler error. Shifting the clone's labels by a large per-clone `base` (unique, far above any
## real label) makes the clone reference a fresh `.Lstr<base+ix>` that the rodata walk emits once for
## the clone — both label + reference read the SAME (mutated) node, so they always agree. Only ever
## called on HOF-specialization clones (the sole source of duplicate labels); the normal tree is
## untouched (fixpoint-safe). Covers exactly the Expr variants `clone_expr` produces. (FloatLit is
## keyed by source span, not a label index — no HOF clone carries a float literal today.)
pub renum_str_expr := fn(a : ptr(mut rt::Arena), e : ptr(Expr), base : usize) {
  if unchecked bitcast(usize, e) == 0 { return }
  match deref(e) {
    Expr::StrLit(s, n, ix, ps, pn) => { deref(unchecked bitcast(ptr(mut Expr), e)) = Expr.StrLit(s, n, base + ix, ps, pn) }
    Expr::Bin(op, l, rr) => { renum_str_expr(a, l, base); renum_str_expr(a, rr, base) }
    Expr::Unchecked(inner) => { renum_str_expr(a, inner, base) }
    Expr::Bitcast(inner, bps, bpl) => { renum_str_expr(a, inner, base) }
    Expr::AddrOf(inner) => { renum_str_expr(a, inner, base) }
    Expr::Deref(inner) => { renum_str_expr(a, inner, base) }
    Expr::Try(inner) => { renum_str_expr(a, inner, base) }
    Expr::Field(b, fs, fl) => { renum_str_expr(a, b, base) }
    Expr::Index(b, ix) => { renum_str_expr(a, b, base); renum_str_expr(a, ix, base) }
    Expr::Slice(b, lo, hi) => { renum_str_expr(a, b, base); renum_str_expr(a, lo, base); renum_str_expr(a, hi, base) }
    Expr::If(c, th, el) => { renum_str_expr(a, c, base); renum_str_expr(a, th, base); renum_str_expr(a, el, base) }
    Expr::Call(cs, cl, n, ah) => { renum_str_args(a, ah, base) }
    Expr::StructLit(cs, cl, n, ah) => { renum_str_args(a, ah, base) }
    Expr::EnumLit(es, el, vs, vl, n, ah) => { renum_str_args(a, ah, base) }
    Expr::ArrayLit(n, ah) => { renum_str_args(a, ah, base) }
    Expr::Loop(b) => { renum_str_stmts(a, b, base) }
    _ => {}
  }
}
renum_str_args := fn(a : ptr(mut rt::Arena), ah : ptr(mut Arg), base : usize) {
  mut g := ah
  while unchecked bitcast(usize, g) != 0 {
    am := deref(arg_p(g))
    renum_str_expr(a, am.e, base)
    g = am.next
  }
}
## RENUMBER string-literal labels across a cloned STATEMENT list (mirrors `clone_one_stmt`'s variants).
pub renum_str_stmts := fn(a : ptr(mut rt::Arena), head : ptr(mut Stmt), base : usize) {
  mut st := head
  while unchecked bitcast(usize, st) != 0 {
    x := deref(stmt_p(Stmt, st))
    mut nx := 0
    match x {
      Stmt::Assign(ns, nl, v, n2) => { nx = unchecked bitcast(usize, n2); renum_str_expr(a, v, base) }
      Stmt::Return(rv, n2) => { nx = unchecked bitcast(usize, n2); if unchecked bitcast(usize, rv) != 0 { renum_str_expr(a, rv, base) } }
      Stmt::ExprStmt(e, n2) => { nx = unchecked bitcast(usize, n2); renum_str_expr(a, e, base) }
      Stmt::If(c, th, el, n2) => { nx = unchecked bitcast(usize, n2); renum_str_expr(a, c, base); renum_str_stmts(a, th, base); renum_str_stmts(a, el, base) }
      Stmt::While(c, b, n2) => { nx = unchecked bitcast(usize, n2); renum_str_expr(a, c, base); renum_str_stmts(a, b, base) }
      Stmt::For(fns, fnl, lo, hi, b, n2) => { nx = unchecked bitcast(usize, n2); if unchecked bitcast(usize, lo) != 0 { renum_str_expr(a, lo, base) }; if unchecked bitcast(usize, hi) != 0 { renum_str_expr(a, hi, base) }; renum_str_stmts(a, b, base) }
      Stmt::Loop(b, n2) => { nx = unchecked bitcast(usize, n2); renum_str_stmts(a, b, base) }
      Stmt::Unchecked(b, n2) => { nx = unchecked bitcast(usize, n2); renum_str_stmts(a, b, base) }
      Stmt::Break(bv, bd, n2) => { nx = unchecked bitcast(usize, n2); if unchecked bitcast(usize, bv) != 0 { renum_str_expr(a, bv, base) } }
      Stmt::Continue(cd, n2) => { nx = unchecked bitcast(usize, n2) }
      Stmt::DerefAssign(p, v, n2) => { nx = unchecked bitcast(usize, n2); renum_str_expr(a, p, base); renum_str_expr(a, v, base) }
      Stmt::IndexAssign(b, ix, v, n2) => { nx = unchecked bitcast(usize, n2); renum_str_expr(a, b, base); renum_str_expr(a, ix, base); renum_str_expr(a, v, base) }
      Stmt::FieldAssign(bns, bnl, ffs, ffl, fv, n2) => { nx = unchecked bitcast(usize, n2); renum_str_expr(a, fv, base) }
      Stmt::FieldPathAssign(pl, fpv, n2) => { nx = unchecked bitcast(usize, n2); renum_str_expr(a, pl, base); renum_str_expr(a, fpv, base) }
      Stmt::IndexFieldAssign(b, ix, ffs, ffl, v, n2) => { nx = unchecked bitcast(usize, n2); renum_str_expr(a, b, base); renum_str_expr(a, ix, base); renum_str_expr(a, v, base) }
      Stmt::AllocWith(ae, b, n2) => { nx = unchecked bitcast(usize, n2); renum_str_expr(a, ae, base); renum_str_stmts(a, b, base) }
      _ => { nx = 0 }
    }
    st = unchecked bitcast(ptr(mut Stmt), nx)
  }
}

## Synthesize a unique HOF-clone callee name `__hoflam<fnpos>` into the arena, returning its
## `src`-relative START handle (the rebase `base_abs - src_int`, matching `synth_ident_span`); the
## total byte length is written to `lenout`. `fnpos` (the closure's `fn` src offset = its lifted-fn
## label id) makes distinct closures get distinct clone names.
pub synth_hof_name := fn(a : ptr(mut rt::Arena), src_int : usize, fnpos : usize, lenout : ptr(mut usize)) -> usize {
  mut sb := rt::strbuf(deref(a), 64)
  rt::push_str(sb, "__hoflam")
  total := rt::push_int(sb, i64(fnpos))
  base_abs := unchecked bitcast(usize, rt::strbuf_base(sb))
  deref(lenout) = total
  unchecked (base_abs - src_int)
}

## Allocate a `Bind` (match variant-pattern payload binding) in the arena; returns its handle
## (binds link via `next`).
bnode := fn(a : ptr(mut rt::Arena), val : Bind) -> ptr(mut Bind) {
  idx := node_alloc(deref(a), 64)
  p := node_ptr(Bind, deref(a), idx)
  deref(p) = val
  p
}

## The null `Bind` pointer (the empty-list / end-of-list sentinel). `Arm.binds_head` and
## `Bind.next` are `ptr(mut Bind)` (§6 ptr-typing); an absent list is a null pointer, tested
## via `unchecked bitcast(usize, p) == 0` (word-based null, no runtime cost).
bind_null := fn() -> ptr(mut Bind) { unchecked bitcast(ptr(mut Bind), 0) }

## Parser-local compatibility shim for the shared Grammar §2.4 machinery in `lexrt`; `lit_val_at`
## below supplies the parser's source-located diagnostic layer. The historical call-site name stays.
## It handles `0x`/`0o`/`0b` and decimal forms, including the grammar's `_` separators.
## `0X`/`0O`/`0B` are recognized by the shared helper, which lets `int_lit_err` reject them as a
## grammar does not define — its terminals are the lowercase `"0x"`/`"0o"`/`"0b"`, and where the
## spec wants both cases it says so, e.g. `exp ::= ("e" | "E")`).
lit_base := fn(s : str) -> usize {
  lexrt::lit_base(s)
}

## The value of one digit byte, or 99 when `c` is not a digit in ANY base (so a caller comparing
## against its own base rejects it). Hex letters are accepted in both cases (`hex-digit`, §2.4).
digit_val := fn(c : usize) -> usize {
  lexrt::digit_val(c)
}

## Decode an INTEGER LITERAL token's text through the shared lexer helper (Grammar §2.4 `int`): `dec-int`, or a
## base-prefixed `hex-int` `0x…` / `oct-int` `0o…` / `bin-int` `0b…`, with the non-significant `_`
## digit separator legal in every base (SYN-3). The reading is `bytes(s)[i]` (the spec str→`[u8]`
## byte view, appendix 160 §3.5), so this lowers identically under Stage-0 AND the self-host lower —
## no `parse_uint`/`Option` (a Stage-0-only stdlib fn the lean lower cannot resolve, since prelude
## `Option` has no decl in the tree).
##
## NON-FAILING by construction: `_` and any byte that is not a digit of the literal's base are
## skipped. That is NOT a licence to accept them — `int_lit_err` is the gate, and EVERY parser path
## that decodes a literal validates with it FIRST and rejects located. Decoding stays total so a
## malformed token can never take the compiler down mid-parse. The accumulation stays CHECKED
## arithmetic on purpose: `int_lit_err` code 3 already rejected everything above 2^64-1, so the
## multiply cannot overflow from a validated call — and if a future path ever decoded without
## validating, a trap (loud) is the outcome to prefer over a wrapped value (silent).
##
## Before this, only base 10 and `0x` were decoded and the lexer stopped the token at the first
## non-decimal byte, so `0b1000` -> 0, `0o777` -> 0 and `1_000` -> 1: a SILENT WRONG VALUE.
dec_val := fn(s : str) -> usize {
  lexrt::dec_val(s)
}

## Validate an INTEGER LITERAL token's text against Grammar §2.4 and return a reason code —
## 0 well formed · 1 a base prefix with no digit of that base right after it (`0b`, `0x_1`:
## `hex-int ::= "0x" hex-digit { hex-digit | "_" }` — a `_` may SEPARATE digits, never lead them)
## · 2 a byte that is not a digit of this literal's base (`0b12`, `0o8`, `0xZ`, and any letter
## glued to a decimal run) · 4 an UPPERCASE base prefix `0X`/`0O`/`0B`, which the grammar's
## terminals do not define.
##
## The lexer consumes a prefixed literal's body greedily (`[0-9A-Za-z_]*`) precisely so that these
## live inside ONE token and can be reported here, located, instead of silently splitting into a
## number plus a stray identifier.
int_lit_err := fn(s : str) -> usize {
  lexrt::int_lit_err(s)
}

## Validate a FLOAT literal token through the shared Grammar §2.4 helper. The lexer keeps malformed
## decimal/hex exponent tails in one kind-39 token; this wrapper supplies the parser's located error
## boundary while preserving the original source span for valid decimal exponent spelling.
float_lit_err := fn(s : str) -> usize {
  lexrt::float_lit_err(s)
}

## Decode the integer literal spanning `[ts, ts+tl)` of the source, REJECTING a malformed one with a
## located diagnostic (module + line + the offending text) rather than truncating it. The single
## gate every literal-decoding path in the parser goes through.
lit_val_at := fn(in out pc : PC, ts : usize, tl : usize) -> usize {
  s := str_at(pc.src + ts, tl)
  e := int_lit_err(s)
  if e == 1 { reject_at(pc, "selfhost: an integer literal's base prefix must be followed by a digit of that base - Grammar §2.4 `hex-int`/`oct-int`/`bin-int`; `_` separates digits, it may not lead them", ts) }
  if e == 2 { reject_at(pc, "selfhost: this digit is not valid for the integer literal's base - Grammar §2.4: `0b` binary (0-1), `0o` octal (0-7), `0x` hex (0-9 a-f A-F), otherwise decimal", ts) }
  if e == 3 { reject_at(pc, "selfhost: integer literal out of range - it does not fit in 64 bits (Types §9.1/§11: an out-of-range literal is a COMPILE ERROR, never a silent wrap)", ts) }
  if e == 4 { reject_at(pc, "selfhost: an UPPERCASE integer base prefix is not an Alatyr literal - Grammar §2.4 spells them `0x` / `0o` / `0b` in lowercase (the digits themselves may be uppercase)", ts) }
  return dec_val(s)
}

## Decode a CHAR literal token's codepoint (a `'c'` span, `start` at the opening `'`, content at
## `start+1`). A backslash escape (`\n`/`\t`/`\r`/`\0`) maps to its control byte; any other escaped
## byte (`\\`/`\'`/`\"`) is that literal byte; a plain byte is its own value. ASCII/byte range only
## (a `char` is a codepoint; multi-byte UTF-8 source in a char literal is not decoded — v1 byte-level).
char_lit_val := fn(src : ptr(u8), start : usize, len : usize) -> i64 {
  b0 := bytes(str_at((src + start + 1), 1))[0]
  if b0 == 92 {
    b1 := bytes(str_at((src + start + 2), 1))[0]
    if b1 == 110 { return 10 }
    if b1 == 116 { return 9 }
    if b1 == 114 { return 13 }
    if b1 == 48 { return 0 }
    return i64(b1)
  }
  i64(b0)
}

## Read the integer literal under the cursor from its source span — any of the four bases of
## Grammar §2.4, `_` separators included, and a malformed one REJECTED located (`lit_val_at`).
int_at := fn(in out pc : PC) -> i64 {
  t := cur(pc)
  i64(lit_val_at(pc, t.start, t.len))
}

## Overwrite an `Arm`'s `.next` / `.body` / `.body_stmts` (reconstruct the struct with the one
## field changed and store it back) — the standalone form of the parser's inline arm-link idiom,
## used by the `match`-arm loops to splice OR-pattern alternatives (§5.4) into the arm list and to
## wire the shared body onto each alternative. Same "build a local, store through the pointer"
## shape the surrounding code uses (a non-place struct ctor cannot store directly through a ptr).
set_arm_next := fn(a : ptr(mut rt::Arena), h : ptr(mut Arm), nx : ptr(mut Arm)) {
  o := deref(arm_p(h))
  deref(arm_p(h)) = Arm(wild = o.wild, lit = o.lit, body = o.body, next = nx, vs = o.vs, vl = o.vl, binds_head = o.binds_head, body_stmts = o.body_stmts, hi = o.hi)
}
set_arm_body := fn(a : ptr(mut rt::Arena), h : ptr(mut Arm), b : ptr(Expr)) {
  o := deref(arm_p(h))
  deref(arm_p(h)) = Arm(wild = o.wild, lit = o.lit, body = b, next = o.next, vs = o.vs, vl = o.vl, binds_head = o.binds_head, body_stmts = o.body_stmts, hi = o.hi)
}
set_arm_body_stmts := fn(a : ptr(mut rt::Arena), h : ptr(mut Arm), bs : ptr(mut Stmt)) {
  o := deref(arm_p(h))
  deref(arm_p(h)) = Arm(wild = o.wild, lit = o.lit, body = o.body, next = o.next, vs = o.vs, vl = o.vl, binds_head = o.binds_head, body_stmts = bs, hi = o.hi)
}

## Read a scalar-literal pattern ENDPOINT under the cursor and advance past it (Control Flow §5.4):
## a char literal `'a'` (kind 41, decoded to its codepoint), a negative integer `-N` (kind 17 then
## digits), or a plain integer. Used for a bare literal arm and for BOTH bounds of a range pattern.
pat_endpoint := fn(in out pc : PC) -> i64 {
  t := cur(pc)
  if t.kind == 41 { pc.idx = pc.idx + 1; return char_lit_val(pc.src, t.start, t.len) }
  if t.kind == 17 { pc.idx = pc.idx + 1; v := pat_int(pc); pc.idx = pc.idx + 1; return 0 - v }
  v := pat_int(pc); pc.idx = pc.idx + 1
  v
}

## The endpoint's numeric value when the cursor really is on an INT-LITERAL token (kind 3),
## otherwise 0 — WITHOUT moving the cursor either way (the caller advances).
## `parse_pat_alt`'s final `else` is a catch-all: both arm loops reach it for shapes they do not
## classify as wildcard / variant / str, so a NON-literal token lands here and the historic
## behaviour (`dec_val` silently skipping every non-digit byte -> 0) is what keeps those parses
## alive. Keeping the tolerant 0 here — instead of routing every endpoint through the now-strict
## `int_at` — confines the new located rejects to tokens the lexer really did emit as literals.
pat_int := fn(in out pc : PC) -> i64 {
  if cur(pc).kind != 3 { return 0 }
  return int_at(pc)
}

## Parse ONE `match` pattern alternative (Control Flow §5.2/§5.4) and return a fresh `Arm` whose
## `body`/`body_stmts` are placeholders (a dummy `Num(0)` / 0) and `next = 0`. Handles the wildcard
## `_` (wild 1), `true`/`false` + integer + char literals (wild 0), a str literal (wild 4), negative
## literals, RANGE patterns `lo..hi` (half-open, wild 5) / `lo..=hi` (inclusive, wild 6) with `lit`=lo
## and `hi`=hi, and enum-variant patterns (bare / `::`-qualified / `.`-spelled / comptime `T.(v)`, with
## payload bindings). The caller wires the real body and, for an OR-pattern, links the alternatives so
## they share one body (§5.4). This is the SINGLE pattern-parsing site shared by BOTH the expression-
## and statement-form match-arm loops, keeping them in lockstep by construction.
parse_pat_alt := fn(in out pc : PC) -> ptr(mut Arm) {
  mut w : u8 = 0
  mut lit : i64 = 0
  mut hi : i64 = 0
  mut vs := 0
  mut vl := 0
  mut bhead := bind_null()
  mut btail := bind_null()
  wt := cur(pc)
  if wt.kind == 1 and str_eq(str_at(pc.src + wt.start, wt.len), "_") { w = 1; pc.idx = pc.idx + 1 }
  else if wt.kind == 1 and str_eq(str_at(pc.src + wt.start, wt.len), "true") { lit = 1; pc.idx = pc.idx + 1 }
  else if wt.kind == 1 and str_eq(str_at(pc.src + wt.start, wt.len), "false") { lit = 0; pc.idx = pc.idx + 1 }
  else if wt.kind == 1 {
    ## an enum-variant pattern `V` / `V(x, …)` — the variant name span, then N payload BINDING idents.
    vs = wt.start; vl = wt.len; pc.idx = pc.idx + 1
    ## `Enum::Variant` — skip the `::`-path prefix; the VARIANT (last segment) is what's matched.
    while cur(pc).kind == 7 {
      pc.idx = pc.idx + 1
      vt := cur(pc); vs = vt.start; vl = vt.len; pc.idx = pc.idx + 1
    }
    ## `.`-qualified: `.(v)` is the comptime-variant pattern `T.(v)` (wild 3); `.Variant` is the
    ## dot-spelled qualified pattern (keep the tail ident as the variant).
    if cur(pc).kind == 22 {
      pc.idx = pc.idx + 1
      if cur(pc).kind == 10 {
        pc.idx = pc.idx + 1
        cvv := cur(pc); vs = cvv.start; vl = cvv.len; pc.idx = pc.idx + 1
        pc.idx = pc.idx + 1
        w = 3
      } else {
        dt := cur(pc); vs = dt.start; vl = dt.len; pc.idx = pc.idx + 1
      }
    }
    if cur(pc).kind == 10 {
      pc.idx = pc.idx + 1
      while cur(pc).kind != 11 and cur(pc).kind != 0 {
        bt := cur(pc); pc.idx = pc.idx + 1
        bnew := bnode(pc.arena, Bind(ns = bt.start, nl = bt.len, next = bind_null()))
        if unchecked bitcast(usize, bhead) == 0 { bhead = bnew } else {
          bold := deref(btail)
          bupd := Bind(ns = bold.ns, nl = bold.nl, next = bnew)
          deref(btail) = bupd
        }
        btail = bnew
        if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }
      }
      pc.idx = pc.idx + 1
    }
  }
  else if wt.kind == 4 {
    ## a str-literal pattern `"fn" => …` (§5.4): register a rodata label, store the StrLit node
    ## handle in `lit`, mark wild 4 (dispatch is a byte-compare against a str scrutinee).
    slbl := pc.nstr
    pc.nstr = pc.nstr + 1
    sspan := wt.len - 2
    sinfo := scan_string(pc.src + wt.start + 1, sspan)
    if not sinfo.ok { reject_at(pc, "selfhost: string literal is not valid UTF-8 (including its escapes) — Grammar §2.4", wt.start) }
    slnode := newnode(pc.arena, Expr.StrLit(wt.start + 1, sinfo.len, slbl, 0, 0))
    lit = i64(slnode)
    w = 4
    pc.idx = pc.idx + 1
  }
  else {
    ## a scalar literal (int / char / negative) LOW endpoint, then an OPTIONAL range tail. `lo..hi`
    ## is half-open (wild 5, `lo <= x < hi`); `lo..=hi` is inclusive (wild 6, `lo <= x <= hi`) — the
    ## same two forms as range iteration (§5.4/§6), endpoints comptime-constant scalars.
    lit = pat_endpoint(pc)
    if cur(pc).kind == 31 { pc.idx = pc.idx + 1; hi = pat_endpoint(pc); w = 5 }
    else if cur(pc).kind == 37 { pc.idx = pc.idx + 1; hi = pat_endpoint(pc); w = 6 }
  }
  dummy := newnode(pc.arena, Expr.Num(0, 0, 0))
  anode(pc.arena, Arm(wild = w, lit = lit, body = dummy, next = 0, vs = vs, vl = vl, binds_head = bhead, body_stmts = 0, hi = hi))
}

## Is the cursor on a pointer intrinsic `mem :: (addr|val) (` — the `::`-path shape this toy
## grammar recognizes as `ptr` / `deref`? Checks ident `mem` (kind 1), `::` (kind 7),
## an `addr`/`val` ident (kind 1), then `(` (kind 10). Bounds-guarded against the token end.
is_mem_intrinsic := fn(pc : PC) -> bool {
  nt := ntoks(pc)
  if pc.idx + 1 >= nt { return false }
  t0 := tok_at(pc, pc.idx)
  if t0.kind != 1 { return false }
  nm := str_at(pc.src + t0.start, t0.len)
  is_pd := str_eq(nm, "ptr") or str_eq(nm, "deref")
  if not is_pd { return false }
  tok_at(pc, pc.idx + 1).kind == 10                      ## '('
}

## GENERIC-STRUCT instantiation tier: is the cursor on a generic-struct CONSTRUCTION prefix
## `( typename ) (` — the `Vec(u64)(…)` double-paren form? The cursor is positioned ON the first
## `(` (the head struct-name ident already consumed). The shape is `(` (kind 10), an ident naming
## the concrete type (kind 1), `)` (kind 11), then a SECOND `(` (kind 10) opening the field list.
## The trailing `(` is what distinguishes a type-arg `Vec(u64)(…)` from an ordinary single-arg call
## `f(x)` (whose `x` is not followed by `)(`). The type argument is COMPTIME and ERASED — with a
## word-sized `T` every instance shares the `Vec` layout, so the construction resolves against the
## bare `Vec` struct decl by name (the `StructLit` keeps the head name span). Bounds-guarded.
## A GENERIC-STRUCT instantiation `Name(T, …)(field = e, …)` — the head ident, a type-argument
## list `(T)` / `(K, V)` (comptime, erased), then the construction `(…)`. Recognized by a
## paren-balanced `(…)` immediately followed by a SECOND `(` (the ctor). `after` = the index of
## that second `(`, so the caller skips the WHOLE type-arg list (was `+3` = a SINGLE type-arg,
## which drifted on a 2-type-arg `HashMapIter(K, V)(…)`). A plain call `f(a, b)` (no 2nd `(`)
## returns false → parsed as a Call. `is_i` false / `after` 0 when not a generic instantiation.
GInst := struct { is_i : bool, after : usize }
is_generic_inst := fn(pc : PC) -> GInst {
  nt := ntoks(pc)
  if pc.idx + 1 >= nt or tok_at(pc, pc.idx).kind != 10 { return GInst(is_i = false, after = 0) }
  if tok_at(pc, pc.idx + 1).kind == 11 { return GInst(is_i = false, after = 0) }   ## empty `()` — not a type app
  ## A generic TYPE-ARG list holds TYPES (identifiers) or — TYP-10 slice A — a comptime VALUE
  ## argument (an integer literal, `uint(192)`). A literal first token is NOT immediately an
  ## ordinary call `f(9)` anymore; it is decided AFTER the paren scan below: a literal-led group
  ## is a generic instantiation ONLY when the second `(` opens a STRUCT LITERAL (`(field = …)`).
  ## Without the remaining guard, a binding `q := f(9)` followed on the next line by a
  ## `(`-expression (`(q + 32)`) mis-parsed as `f(9)(q+32)` (the `(9)` taken as erased type-args,
  ## `(q+32)` as the call args) — dropping the `9` and the real args, a silent miscompile.
  fak := tok_at(pc, pc.idx + 1).kind
  mut i := pc.idx
  mut depth := 0
  while i < nt {
    k := tok_at(pc, i).kind
    if k == 10 { depth = depth + 1 }
    else if k == 11 { depth = depth - 1; if depth == 0 { i = i + 1; break } }
    i += 1
  }
  ## `i` is just past the type-arg `)`; a generic-struct construction has a SECOND `(` here.
  if i >= nt or tok_at(pc, i).kind != 10 { return GInst(is_i = false, after = 0) }
  ## A LITERAL first argument (`uint(192)(words = …)`) — a comptime VALUE instantiation (TYP-10;
  ## a `comptime N : u64` type-function parameter). Admit it ONLY when the second `(` opens a
  ## struct literal (an `ident =` field pair) — the `f(9)` / next-line `(q + 32)` call shape has
  ## no `=` there, so the old miscompile guard keeps firing for it.
  if fak == 3 or fak == 39 or fak == 4 {
    if i + 2 < nt and tok_at(pc, i + 1).kind == 1 and tok_at(pc, i + 2).kind == 21 {
      return GInst(is_i = true, after = i)
    }
    return GInst(is_i = false, after = 0)
  }
  GInst(is_i = true, after = i)
}

## A GENERIC-ENUM construction `G(T, …) . Variant ( … )` — the head type `G` followed by a
## type-argument list `(T, …)` (one OR MORE args, paren-balanced), then `. Variant (` (an enum
## variant ctor). Distinguished from a call-then-field `f(args).field` by the `(` AFTER the
## `.Variant`. `pc` is positioned at the `(` after the head ident. Returns whether it matches AND
## the token index just past the type-arg list's `)` (so the caller can skip exactly to the `.`).
GEnum := struct { is_g : bool, after : usize }
is_generic_enum_ctor := fn(pc : PC) -> GEnum {
  nt := ntoks(pc)
  if pc.idx >= nt or tok_at(pc, pc.idx).kind != 10 { return GEnum(is_g = false, after = 0) }
  ## An EMPTY paren group `()` is NEVER a generic type application — a generic type needs ≥1 type
  ## argument (`Result(T,E)`, `Option(T)`). So `mk().sum()` is a call-then-method, not `mk` applied to
  ## zero type args; bail so the head parses as an ordinary `Call` (then p_field's UFCS path). This is
  ## exact (not a heuristic): a zero-arity generic instantiation has no meaning in the grammar.
  if pc.idx + 1 < nt and tok_at(pc, pc.idx + 1).kind == 11 { return GEnum(is_g = false, after = 0) }
  ## paren-balance from the opening `(` to its matching `)`
  mut i := pc.idx
  mut depth := 0
  while i < nt {
    k := tok_at(pc, i).kind
    if k == 10 { depth = depth + 1 }
    else if k == 11 { depth = depth - 1; if depth == 0 { i = i + 1; break } }
    i += 1
  }
  ## now `i` is just past the type-arg `)`; require `. ident` (the variant ctor) — the variant may be
  ## PARENTHESIZED (`Option(u64).Some(x)`, `.` `ident` `(`) or NULLARY (`Option(u64).None`, `.` `ident`
  ## with no trailing `(`). Both normalize the generic-instance base to the bare enum name `Var("E")`
  ## so `p_field` builds the `EnumLit`; the head-is-enum guard at the call site prevents mis-firing on
  ## a non-enum `Foo(x).bar`. WITHOUT the nullary form a `G(T).None` argument sized as a scalar Field
  ## (the disc) → a by-ref enum param received the disc VALUE as its pointer → NULL deref.
  if i + 1 >= nt { return GEnum(is_g = false, after = 0) }
  ok := tok_at(pc, i).kind == 22 and tok_at(pc, i + 1).kind == 1
  GEnum(is_g = ok, after = i)
}

## Was the enum-type-name table PRE-COLLECTED (a non-null pointer)? A NULL table means "unknown"
## (a single-pass path did no pre-scan) → callers keep the old always-treat-`ident(…).V(…)`-as-enum-ctor
## behavior. A NON-null table — even if EMPTY (a pre-scan that found zero enum types) — is authoritative:
## `is_enum_name` then decides, so a no-enum program's `f(x).m()` correctly parses as a call+UFCS.
enums_known := fn(pc : PC) -> bool { return unchecked bitcast(usize, pc.enums) != 0 }
## Does the enum-type-name table contain the ident `[s, s+n)`? Scans the packed (start, len) pairs
## (compared by TEXT over `pc.src` — a decl name and a use span both index the shared source).
is_enum_name := fn(pc : PC, s : usize, n : usize) -> bool {
  ev := deref(pc.enums)
  cnt := rt::vec_len(ev)
  mut i := 0
  while i + 1 < cnt {
    es := rt::vec_get(ev, i)
    el := rt::vec_get(ev, i + 1)
    if str_eq(str_at(pc.src + es, el), str_at(pc.src + s, n)) { return true }
    i += 2
  }
  false
}

## STRUCT FIELD-ORDER TABLE (by-name construction, TYP-8) — held in a MODULE GLOBAL rather than a
## `PC` field: adding a 9th field to `PC` pushed it past the frozen seed's 8-word aggregate-value limit
## (the seed then dropped the store of the extra field). The table is a `rt::Vec` of usize, packed as one
## variable-length RECORD per kind-2 struct decl — `name_start, name_len, nfields, then nfields × (field
## name_start, field name_len)` — pre-collected across ALL modules by the driver in the SAME first parse
## pass that fills the enum-name table (getdents module order is not dependency-sorted, so a decls-so-far
## scan is unsound). Lets the struct-literal parse resolve each `f = v` field to its DECLARATION-ORDER
## index and emit the value list in declaration order (a parse desugar), so `P(y = 6, x = 5)` writes `y`
## to the `y` slot regardless of source position — every backend's positional struct-assign is then
## correct with no per-backend change. `0` (single-pass / pre-scan paths) means "unknown" → the old
## positional behavior (byte-identical for an already-in-order literal). Names compared by TEXT over the
## shared source `pc.src`. The driver sets it via `set_structs_tbl` (`0` for PASS 1, the table for PASS 2).
mut P_STRUCTS_TBL := 0

## Set the struct field-order table pointer (a `usize` handle; `0` = none). Called by the driver.
pub set_structs_tbl := fn(p : usize) { P_STRUCTS_TBL = p }

## Whether the struct field-order table is present (non-zero).
structs_known := fn() -> bool { return P_STRUCTS_TBL != 0 }

## The table as a `rt::Vec` (valid only when `structs_known()`); isolated so the bitcast/deref is one place.
structs_tbl := fn() -> rt::Vec { return deref(unchecked bitcast(ptr(rt::Vec), P_STRUCTS_TBL)) }

## Locate the RECORD offset (index into the packed table) of the struct type named `[s, s+n)`, or -1 if
## absent. Each record is `name_start, name_len, mod_start, mod_len, nfields, then nfields × (fns, fnl,
## def_start, def_len)`; the scan strides record-by-record using the stored `nfields`. Names compared by
## TEXT over the shared `pc.src`.
##
## Modules §3 (TYPE-ANCESTOR): candidates are RANKED by the module being parsed (`pc.mod_s/mod_l`)
## through the one shared rank — this module and its ancestors nearest-first — instead of taking the
## FIRST same-named record in table order. That first-wins scan is what made a struct literal in a
## CHILD module get checked against an unrelated sibling's same-named struct: a legal
## `Box(a = 40, b = 2)` was rejected as "unknown field name" whenever the decoy sorted first, and the
## reordering desugar wrote the values into the wrong slots whenever it sorted last. Rank -1 for every
## candidate (a name declared only outside the §3 chain — the ambient prelude case) keeps the
## historical first-match answer.
struct_rec_of := fn(pc : PC, s : usize, n : usize) -> i64 {
  if structs_known() == false { return 0 - 1 }
  sv := structs_tbl()
  cnt := rt::vec_len(sv)
  mut i := 0
  mut first := 0 - 1
  mut best := 0 - 1
  mut besti := 0 - 1
  while i + 5 <= cnt {
    ns := rt::vec_get(sv, i)
    nl := rt::vec_get(sv, i + 1)
    ms := rt::vec_get(sv, i + 2)
    ml := rt::vec_get(sv, i + 3)
    nf := rt::vec_get(sv, i + 4)
    if str_eq(str_at(pc.src + ns, nl), str_at(pc.src + s, n)) {
      if first < 0 { first = i64(i) }
      r := lower_layout::type_mod_rank_from(pc.src, ms, ml, pc.mod_s, pc.mod_l)
      if r > best { best = r ; besti = i64(i) }
    }
    i = i + 5 + nf * 4
  }
  if best >= 0 { return besti }
  first
}

## The declaration-order INDEX of the field named `[fs, fs+fl)` within the struct RECORD at offset `rec`
## (from `struct_rec_of`), or -1 if the struct has no such field (an unknown-field diagnostic at the call
## site). `rec` points at the record's `name_start`; the field entries begin at `rec + 5` (the header is
## `ns, nl, ms, ml, nf`).
struct_field_idx := fn(pc : PC, rec : usize, fs : usize, fl : usize) -> i64 {
  sv := structs_tbl()
  nf := rt::vec_get(sv, rec + 4)
  mut k := 0
  while k < nf {
    fns := rt::vec_get(sv, rec + 5 + k * 4)
    fnl := rt::vec_get(sv, rec + 5 + k * 4 + 1)
    if str_eq(str_at(pc.src + fns, fnl), str_at(pc.src + fs, fl)) { return i64(k) }
    k += 1
  }
  0 - 1
}

## The number of declared fields in the struct RECORD at offset `rec` (from `struct_rec_of`).
struct_nfields := fn(rec : usize) -> usize { rt::vec_get(structs_tbl(), rec + 4) }

## The struct-field DEFAULT source span for the field at declaration INDEX `k` within the RECORD at
## `rec`. The record header is 5 words (`ns, nl, ms, ml, nf`); each field entry is 4 words
## `fns, fnl, def_start, def_len`; `def_len == 0` = no default
## (TYP-8/§9.4). The captured span was source-scanned by `driver::collect_struct_table` and is a slice
## of the same `pc.src` base, so a re-lex over `[ds, ds+dl)` rebases spans correctly (`relex_default`).
FDef := struct { ds : usize, dl : usize }
struct_field_def := fn(rec : usize, k : usize) -> FDef {
  sv := structs_tbl()
  FDef(ds = rt::vec_get(sv, rec + 5 + k * 4 + 2), dl = rt::vec_get(sv, rec + 5 + k * 4 + 3))
}

## The declaration-order INDEX of a struct literal field whose NAME is the FInit node at handle `fih`,
## within the struct RECORD at offset `urec`. A thin scalar-returning shim over `struct_field_idx` so
## the FInit deref stays isolated (a `deref(finit_p(...)).field` is the proven read shape). Returns -1
## for a field the struct has no such name for (an unknown-field diagnostic at the call site).
finit_field_idx := fn(pc : PC, urec : usize, fih : usize) -> i64 {
  fi := deref(finit_p(unchecked bitcast(ptr(mut FInit), fih)))
  return struct_field_idx(pc, urec, fi.fs, fi.fl)
}
## The value-expr of the FInit node at handle `fih` (isolated deref).
finit_expr := fn(fih : usize) -> ptr(Expr) {
  fi := deref(finit_p(unchecked bitcast(ptr(mut FInit), fih)))
  return fi.e
}
## The `next` handle of the FInit node at handle `fih` (isolated deref).
finit_next := fn(fih : usize) -> usize {
  fi := deref(finit_p(unchecked bitcast(ptr(mut FInit), fih)))
  return unchecked bitcast(usize, fi.next)
}

## Re-lex + parse a struct-field DEFAULT expression from its source span `[ds, ds+dl)` (a slice of
## `pc.src`, source-scanned by `driver::collect_struct_table`) into a value `Expr`. Mirrors the driver's
## per-module lex discipline `lex_rt(str_at(base+off, len), off, …)` with `base_off == ds`, so the
## default's own string/ident spans stay valid against the shared `pc.src` base. Used by the by-name
## struct-literal reorder (`p_factor`) to FILL an omitted field that carries a default (TYP-8/§9.4).
## The default class is a comptime/constant expression (Types §9.4 — a *type-level* default, applied at
## construction; it cannot reference sibling instance fields), so a plain `p_or` parse resolves it.
relex_default := fn(in out pc : PC, ds : usize, dl : usize) -> ptr(Expr) {
  tcap := dl + 16
  mut dtoks := rt::Vec(data = rt::bump(deref(pc.arena), tcap * 8), len = 0, cap = tcap)
  zt := lexrt::lex_rt(str_at(pc.src + ds, dl), ds, dtoks, deref(pc.arena))
  mut dpc := PC(toks = ptr(dtoks), src = pc.src, idx = 0, arena = pc.arena, nstr = pc.nstr, mod_s = pc.mod_s, mod_l = pc.mod_l, enums = pc.enums)
  e := p_or(dpc)
  pc.nstr = dpc.nstr
  e
}

## factor := int | ident | '(' expr ')'
## `alloc::with(pc.arena)` makes the cursor's arena the ambient, so the `newnode`
## calls elide it — `newnode(pc.arena, Expr.Num(v))` rather than `newnode(pc.arena, Expr.Num(v))`.
p_factor := fn(in out pc : PC) -> ptr(mut Expr) {
    ## THE ROOT OF THE BALANCED-TRUNCATION SEGVs. `p_factor` is the only place a VALUE is read, and
    ## none of its branches matches the EOF sentinel (kind 0), so the fall-through at the bottom
    ## treated EOF as the `(` of a parenthesized expression: it advanced the cursor past the end and
    ## called `p_or` again, which came straight back here — unbounded recursion until the stack ran
    ## out. That is why `x :=`, `x := 1 +`, `x : u64`, `x := -`, `x := not`, `x := (`, `x := if`,
    ## `x := while`, `x := match`, `x := for`, `x := 1 ==`, `x := true and`, `x := S(a =`,
    ## `x := match y { 1 =>`, `x : u64 =` and `x : ptr(` ALL exited 139 with no message and no
    ## position: one defect wearing sixteen faces. A value is mandatory wherever this is entered, so
    ## end-of-input here is a located reject, at the token that demanded the value.
    if cur(pc).kind == 0 {
      zfe := reject_eof(pc, "selfhost: the input ends where a VALUE was required - a `:=`/`=` needs its value, a binary or unary operator needs its right operand, and `if`/`while`/`match`/`for` need their subject; the file stops before it (a truncated file, a partial copy, or a bad merge)")
    }
    ## A leading `-` (kind 17) is UNARY negation `-x` (a negative literal `-1`, or `-expr`). The lean
    ## lexer has no negative-number token and `-` is otherwise only the BINARY subtract (which needs
    ## a left operand), so without this a leading `-` falls through and mis-parses (drifting into the
    ## next statement). Lower it via the proven binary-subtract path: `Num(0) - <factor>` (Bin op 17).
    ## Using `p_factor` for the operand makes unary `-` bind tighter than `*`/`+` (so `-a * b` is
    ## `(0 - a) * b`), matching the usual precedence.
    if cur(pc).kind == 17 {
      pc.idx = pc.idx + 1
      uzero := newnode(pc.arena, Expr.Num(0, 0, 0))
      uinner := p_factor(pc)
      ## Unary negation `-x` = `0 - x` is 2's-complement negation — INHERENTLY modular (a "negative
      ## literal" `-17` on a u64 is the wrap `2^64-17`), so it must NOT trap under the checked `-`
      ## underflow guard (I11 / CG-8). Wrap in `Expr.Unchecked` so the subtraction lowers guard-free;
      ## a genuine binary `a - b` (not via this prefix path) keeps the guard.
      subn := newnode(pc.arena, Expr.Bin(17, uzero, uinner))
      return newnode(pc.arena, Expr.Unchecked(subn))
    }
    ## A leading `~` (kind 46) is UNARY bitwise NOT (one's complement, Grammar §130 / bitwise
    ## family `& | ^ ~`). Desugared to `x ^ (-1)`: XOR with the all-ones word (`Num(0 - 1)` is the
    ## i64 bit-pattern 0xFFFF…FF, the same all-ones sentinel the parser already uses) is exactly the
    ## complement, and reuses the existing bitwise-xor lowering (op 36) on EVERY backend — no new
    ## lower op. Binds like unary `-` (via `p_factor`) so `~a & b` is `(~a) & b` and `~~x` is `x`.
    ## XOR has no overflow/underflow guard, so (unlike unary `-`) no `Unchecked` wrapper is needed.
    ## Width follows the operand; exact for u64/usize (narrow-type masking is a follow-up).
    if cur(pc).kind == 46 {
      pc.idx = pc.idx + 1
      tinner := p_factor(pc)
      tones := newnode(pc.arena, Expr.Num(0 - 1, 0, 0))
      return newnode(pc.arena, Expr.Bin(36, tinner, tones))
    }
    ## `unchecked <expr>` — a scoped verification mode (Types §4.2, CG-6/CG-7). Wrap the inner
    ## expression in `Expr.Unchecked` so the lower knows to lower it with `verify.checked` FALSE
    ## (a library operator's overflow/underflow/div-by-zero guard is then comptime-absent, leaving
    ## the raw wrapping instruction). All other passes treat the wrapper transparently.
    if tok_kw(pc, "unchecked") {
      pc.idx = pc.idx + 1
      uinner := p_factor(pc)
      return newnode(pc.arena, Expr.Unchecked(uinner))
    }
    ## FN-6 — a function VALUE `fn(sig) { body }` in EXPRESSION position (grammar `fn-value ::= fn-sig
    ## block`). First slice: SCALAR params (`name : T`; type tokens skipped to `,`/`)`). Builds an
    ## `Expr::Lambda`; the driver's lift pass lifts it to a synthetic top-level fn + FnRef.
    if tok_kw(pc, "fn") {
      lfnpos := cur(pc).start
      pc.idx = pc.idx + 1                 ## 'fn'
      ## `fn` is ALWAYS followed by its parameter list `(`. Unchecked, this second unconditional skip
      ## stepped over whatever was there (the EOF sentinel included) and the param loop then exited at
      ## once, yielding a well-formed-looking lambda with no parameters. Same guard, same reason, as
      ## the top-level fn decl in `parse_decl`.
      if cur(pc).kind != 10 {
        zlp := reject_here(pc, "selfhost: `fn` must be followed by a PARAMETER LIST `(...)` - the input ends or continues with something else (a truncated file, a partial copy, or a bad merge)")
      }
      llparen := cur(pc).start            ## the `(` that opens the list (for the unclosed reject)
      pc.idx = pc.idx + 1                 ## '('
      mut lphead := param_null()
      mut lptail := param_null()
      while cur(pc).kind != 11 and cur(pc).kind != 0 {
        lpn := cur(pc); pc.idx = pc.idx + 1     ## param name
        pc.idx = pc.idx + 1                     ## ':'
        lpt := cur(pc)                          ## type head token
        while cur(pc).kind != 9 and cur(pc).kind != 11 and cur(pc).kind != 0 { pc.idx = pc.idx + 1 }
        lpnew := pnode(pc.arena, Param(ns = lpn.start, nl = lpn.len, next = 0, ts = lpt.start, tl = lpt.len, pmode = 0, pps = 0, ppl = 0))
        if unchecked bitcast(usize, lphead) == 0 { lphead = lpnew } else {
          lold := deref(lptail)
          ## build the updated Param in a LOCAL first, THEN store — a `deref(ptr) = Param(...)` inline
          ## struct-ctor store mis-lowers in the seed (the store-through-pointer scar), so the `.next`
          ## link was silently dropped and a 2+-param lambda saw only its first parameter (§1 spill
          ## count reads `d.arity`). Mirrors the top-level fn param-link (see below at ~2819).
          lupd := Param(ns = lold.ns, nl = lold.nl, next = lpnew, ts = lold.ts, tl = lold.tl, pmode = lold.pmode, pps = lold.pps, ppl = lold.ppl)
          deref(lptail) = lupd
        }
        lptail = lpnew
        if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }   ## ','
      }
      ## The list MUST be closed by `)` — see the top-level fn decl for why this is reported as the
      ## UNBALANCED class rather than as a missing body.
      if cur(pc).kind != 11 {
        zll := reject_at(pc, "selfhost: the input ends inside an unclosed `(`, `{` or `[` - the parser reached end-of-input while a group was still open, so this declaration and everything after it is NOT part of the program (a truncated file, a partial copy, or a bad merge); close the group", llparen)
      }
      pc.idx = pc.idx + 1                 ## ')'
      mut lrt := Token(kind = 0, start = 0, len = 0)
      if cur(pc).kind == 6 {              ## '->'
        pc.idx = pc.idx + 1
        ## `->` must be followed by a RETURN TYPE. At EOF `lrt` captured the zero-length EOF sentinel
        ## and the residue skip below ran off the end.
        if cur(pc).kind == 0 {
          zla := reject_eof(pc, "selfhost: a `->` must be followed by a RETURN TYPE - the input ends after it (a truncated file, a partial copy, or a bad merge)")
        }
        lrt = cur(pc)
        ## STOP the residue skip at a `:=` (kind 5) as well. A return type never contains one, but the
        ## NEXT DECLARATION does — and without this stop a lambda truncated after its signature scanned
        ## forward over the following declarations until it found SOME `{`, silently swallowing them.
        while cur(pc).kind != 12 and cur(pc).kind != 0 and cur(pc).kind != 5 { pc.idx = pc.idx + 1 }
      }
      ## The body MUST open with `{`.
      if cur(pc).kind != 12 {
        zlb := reject_here(pc, "selfhost: a `fn` SIGNATURE must be followed by a braced BODY `{ ... }` - the input ends or continues with something else, so this function has no body (a truncated file, a partial copy, or a bad merge)")
      }
      pc.idx = pc.idx + 1                 ## '{'
      mut lshead := 0
      mut lstail := 0
      mut lbody := newnode(pc.arena, Expr.Num(0 - 1, 0, 0))
      while cur(pc).kind != 13 and cur(pc).kind != 0 {
        if cur(pc).kind == 30 { pc.idx = pc.idx + 1 }
        else if stmt_starts(pc) {
          ls := p_stmt(pc)
          if lshead == 0 { lshead = ls } else { set_stmt_next(pc.arena, stmt_last(lstail, pc.arena), ls) }
          lstail = ls
        } else {
          le := p_or(pc)
          if cur(pc).kind == 13 or cur(pc).kind == 0 { lbody = le }
          else {
            les := snode(pc.arena, Stmt.ExprStmt(le, 0))
            if lshead == 0 { lshead = les } else { set_stmt_next(pc.arena, stmt_last(lstail, pc.arena), les) }
            lstail = les
          }
        }
      }
      pc.idx = pc.idx + 1                 ## '}'
      return newnode(pc.arena, Expr.Lambda(lfnpos, lphead, lrt.start, lrt.len, lshead, lbody))
    }
    ## `[@label(name)] loop { … }` in VALUE position — loop-as-expression (Control Flow §3/§6/§7.2):
    ## `total := loop { … break v … }` (and the labeled `total := @label(outer) loop { … }`). The body is
    ## a statement list; a `break <expr>` inside delivers the loop's value (lower marks the frame
    ## value-bearing). `while`/`for` are statement-only for a value (§7.2), so only `loop` is here.
    if (cur(pc).kind == 33 and tok_at(pc, pc.idx + 1).kind == 1 and str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "label")) or tok_kw(pc, "loop") {
      if cur(pc).kind == 33 {
        pc.idx = pc.idx + 2               ## '@' 'label'
        pc.idx = pc.idx + 1               ## '('
        lnm := cur(pc); pc.idx = pc.idx + 1
        pc.idx = pc.idx + 1               ## ')'
        P_PEND_S = lnm.start
        P_PEND_L = lnm.len
      }
      loop_label_s := P_PEND_S
      loop_label_l := P_PEND_L
      pc.idx = pc.idx + 1                 ## 'loop'
      pc.idx = pc.idx + 1                 ## '{'
      lbl_push()
      lbody := p_stmts(pc)
      lbl_pop()
      pc.idx = pc.idx + 1                 ## '}'
      lexpr := newnode(pc.arena, Expr.Loop(lbody))
      expr_label_mark(lexpr, loop_label_s, loop_label_l)
      return lexpr
    }
    ## `if <cmp> { <cmp> } else { <cmp> }` — keyword-identity branch (kinds: 12 `{`, 13 `}`)
    if tok_kw(pc, "if") {
      pc.idx = pc.idx + 1                 ## 'if'
      cond := p_or(pc)
      ## The branch body MUST open with `{`. Unchecked, the skip below consumed whatever followed the
      ## condition and `p_or` read the NEXT DECLARATION as the then-branch, so a truncation MID-FILE
      ## (`x := if` with the rest of the file after it) swallowed `main` outright: measured rc 139 on
      ## the pre-fix compiler for the tail form and rc 139 mid-file. An expression-`if` always has a
      ## braced then-branch (`if_is_stmt_form` routed the statement spelling elsewhere), so this
      ## cannot reject anything the grammar admits.
      if cur(pc).kind != 12 {
        zif := reject_here(pc, "selfhost: an `if` CONDITION must be followed by a braced branch `{ ... }` - the input ends or continues with something else, so the condition has no body (a truncated file, a partial copy, or a bad merge)")
      }
      pc.idx = pc.idx + 1                 ## '{'
      then := p_or(pc)
      pc.idx = pc.idx + 1                 ## '}'
      pc.idx = pc.idx + 1                 ## 'else'
      ## `else if …` in EXPRESSION position: the else BRANCH is itself an if-EXPRESSION, so recurse
      ## rather than demanding a `{`. Without this the three blind skips below consumed the `if` as
      ## the branch's `{`, read the NESTED CONDITION as the else-VALUE and then swallowed the real
      ## `{`, drifting the cursor: measured before the fix, `v := if r == 1 { 10 } else if r == 2
      ## { 42 } else { 30 }` and the same chain in a function's TAIL position were both rejected with
      ## `parse: unexpected token `else` (expected a name)`. The STATEMENT spelling already chains
      ## this way (`p_stmt` recurses on `else if`); this is the value dual, so an `if … else if …
      ## else …` chain now parses on both paths.
      if tok_kw(pc, "if") {
        eif := p_factor(pc)
        return newnode(pc.arena, Expr.If(cond, then, eif))
      }
      pc.idx = pc.idx + 1                 ## '{'
      els := p_or(pc)
      pc.idx = pc.idx + 1                 ## '}'
      return newnode(pc.arena, Expr.If(cond, then, els))
    }
    ## `match <cmp> { <int|_> => <cmp> ; … }` — arms in an arena-linked list (38 `=>`,
    ## 30 `;`, `_` wildcard ident). The form the self-host lexer's own dispatch uses.
    if tok_kw(pc, "match") {
      pc.idx = pc.idx + 1                 ## 'match'
      scrut := p_or(pc)
      ## The arm list MUST open with `{`. Unchecked this skipped ONE token and started reading arms
      ## from whatever followed, which mid-file consumed the rest of the program: measured on the
      ## pre-fix compiler, `x := match` as a MIDDLE line left `main` undeclared and yet `check`
      ## returned 0 — the build only failed at LINK time with `undefined reference to ...__main`.
      ## That silent `check` is exactly the outcome I11 forbids.
      if cur(pc).kind != 12 {
        zmt := reject_here(pc, "selfhost: a `match` SUBJECT must be followed by a braced arm list `{ ... }` - the input ends or continues with something else, so the match has no arms (a truncated file, a partial copy, or a bad merge)")
      }
      pc.idx = pc.idx + 1                 ## '{'
      mut ahead := 0
      mut atail := 0
      while cur(pc).kind != 13 and cur(pc).kind != 0 {
        mut w : u8 = 0
        mut lit := 0
        mut vs := 0
        mut vl := 0
        mut bn := 0
        mut bhead := bind_null()
        mut btail := bind_null()
        wt := cur(pc)
        ## `comptime for var in typeinfo(T).variants { T.(var)(p…) => <expr> }` — a comptime
        ## VARIANT-ARM TEMPLATE in EXPRESSION-match position (derive's `eq`). Marked `wild = 2`;
        ## the lower unrolls it per variant. The arm body is an EXPRESSION (`p_or`), not a block.
        if wt.kind == 2 and str_eq(str_at(pc.src + wt.start, wt.len), "comptime") {
          pc.idx = pc.idx + 1                 ## 'comptime'
          pc.idx = pc.idx + 1                 ## 'for'
          cfv := cur(pc); pc.idx = pc.idx + 1 ## loop var
          pc.idx = pc.idx + 1                 ## 'in'
          cfit := p_or(pc)                    ## typeinfo(T).variants
          pc.idx = pc.idx + 1                 ## '{'
          pc.idx = pc.idx + 1                 ## 'T'
          pc.idx = pc.idx + 1                 ## '.'
          pc.idx = pc.idx + 1                 ## '('
          pc.idx = pc.idx + 1                 ## the comptime var
          pc.idx = pc.idx + 1                 ## ')'
          if cur(pc).kind == 10 {
            pc.idx = pc.idx + 1               ## '(' payload bindings
            while cur(pc).kind != 11 and cur(pc).kind != 0 {
              bt := cur(pc); pc.idx = pc.idx + 1
              bnew := bnode(pc.arena, Bind(ns = bt.start, nl = bt.len, next = bind_null()))
              if unchecked bitcast(usize, bhead) == 0 { bhead = bnew } else {
                bold := deref(btail)
                bupd := Bind(ns = bold.ns, nl = bold.nl, next = bnew)
                deref(btail) = bupd
              }
              btail = bnew
              bn += 1
              if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }
            }
            pc.idx = pc.idx + 1               ## ')'
          }
          pc.idx = pc.idx + 1                 ## '=>'
          tbe := p_or(pc)                     ## EXPRESSION body
          pc.idx = pc.idx + 1                 ## '}' (comptime-for body close)
          anew2 := anode(pc.arena, Arm(wild = 2, lit = 0, body = tbe, next = 0, vs = cfv.start, vl = cfv.len, binds_head = bhead, body_stmts = 0, hi = 0))
          if ahead == 0 { ahead = anew2 } else {
            ap2 := arm_p(atail)
            old2 := deref(ap2)
            upd2 := Arm(wild = old2.wild, lit = old2.lit, body = old2.body, next = anew2, vs = old2.vs, vl = old2.vl, binds_head = old2.binds_head, body_stmts = old2.body_stmts, hi = old2.hi)
            deref(ap2) = upd2
          }
          atail = anew2
          if cur(pc).kind == 30 { pc.idx = pc.idx + 1 }
        }
        else {
        ## Parse the arm's pattern (one alternative), collect any OR-pattern `|`-alternatives, then
        ## the shared body (§5.4). `parse_pat_alt` handles `_`/literals/char/str/negative/RANGE/variant.
        first := parse_pat_alt(pc)
        mut gtail := first
        mut isor := false
        ## OR-pattern `p | q | … => body` (§5.4): the `|`-separated alternatives share ONE body — pure
        ## surface sugar expanded to one arm per alternative (below). v1 alternatives do NOT bind: a
        ## binding alternative is ill-formed (fail loud, never a silent miscompile).
        while cur(pc).kind == 35 {
          pc.idx = pc.idx + 1              ## '|'
          isor = true
          altn := parse_pat_alt(pc)
          am_alt := deref(arm_p(altn))
          if unchecked bitcast(usize, am_alt.binds_head) != 0 {
            panic("parse: an OR-pattern alternative may not bind a payload (Control Flow §5.4)")
          }
          set_arm_next(pc.arena, gtail, altn)
          gtail = altn
        }
        ## the FIRST alternative of an OR may not bind either (an OR arm binds inconsistently, §5.4).
        if isor {
          am_first := deref(arm_p(first))
          if unchecked bitcast(usize, am_first.binds_head) != 0 {
            panic("parse: an OR-pattern alternative may not bind a payload (Control Flow §5.4)")
          }
        }
        pc.idx = pc.idx + 1              ## '=>'
        abody := p_or(pc)
        ## wire the shared body onto every alternative and splice the chain into the arm list, in order.
        mut g := first
        while g != 0 {
          gm := deref(arm_p(g))
          set_arm_body(pc.arena, g, abody)
          if ahead == 0 { ahead = g } else { set_arm_next(pc.arena, atail, g) }
          atail = g
          g = gm.next
        }
        ## optional arm separator: `;` (kind 30) OR `,` (kind 9). Only `,` was unhandled — a
        ## comma-separated EXPRESSION match (`r := match x { 7 => 42, _ => 0 }`, the natural
        ## int/str-match syntax) left `pc` parked on the `,`, so the next loop iteration parsed
        ## the comma as a bogus pattern and desynced into unbounded p_factor recursion (a compiler
        ## stack-overflow CRASH). The `;` path is byte-identical (fixpoint-neutral). The loop still
        ## exits on `}` (kind 13), so a `,` AFTER the match (a call arg `f(match…{…}, y)`) is left
        ## for the outer parser.
        if cur(pc).kind == 30 or cur(pc).kind == 9 { pc.idx = pc.idx + 1 }
        }
      }
      pc.idx = pc.idx + 1                 ## '}'
      return newnode(pc.arena, Expr.Match(scrut, ahead))
    }
    ## POINTER intrinsics `ptr(<place>)` / `deref(<ptr>)` — a `::`-path call whose
    ## head ident is `mem` and tail ident is `addr` or `val` (kinds: 1 ident, 7 `::`, 10 `(`,
    ## 11 `)`). `ptr(e)` → `AddrOf(e)` (the address of a place), `deref(e)` → `Deref(e)`
    ## (a load through a pointer). Recognized here so any other `mem` usage stays an ordinary
    ## ident. The deeper peeks are bounds-guarded by `vec::vlen`.
    if is_mem_intrinsic(pc) {
      head := cur(pc); pc.idx = pc.idx + 1  ## 'ptr' / 'deref'
      pc.idx = pc.idx + 1                 ## '('
      ## `ptr(mut <place>)` — the `mut` is a borrow-mutability qualifier on the PLACE, not part
      ## of the place expression; skip it so the inner is the bare `Var`/`Index` place (else it
      ## parses as `MutType(place)` and `emit_addr_of` — which matches a `Var`/`Index` — falls to
      ## the placeholder `0`, silently dropping the address).
      if tok_kw(pc, "mut") { pc.idx = pc.idx + 1 }
      inner := p_or(pc)
      pc.idx = pc.idx + 1                 ## ')'
      if str_eq(str_at(pc.src + head.start, head.len), "ptr") {
        return newnode(pc.arena, Expr.AddrOf(inner))
      }
      return newnode(pc.arena, Expr.Deref(inner))
    }
    ## An ARRAY literal `[e0, e1, …, eN]` (kinds: 14 `[`, 15 `]`, 9 `,`). The elements are
    ## parsed into an arena-linked `Arg` list (the same machinery a call's args use). Lower
    ## binds a frame region of N words and stores each element; element `i` at offset `i*8`.
    if cur(pc).kind == 14 {
      pc.idx = pc.idx + 1                 ## '['
      mut nel := 0
      mut ehead := 0
      mut etail := 0
      while cur(pc).kind != 15 and cur(pc).kind != 0 {
        ee := p_or(pc)
        enew := gnode(pc.arena, Arg(e = ee, next = 0))
        if ehead == 0 { ehead = enew } else {
          ep := arg_p(etail)
          eold := deref(ep)
          eupd := Arg(e = eold.e, next = enew)
          deref(ep) = eupd
        }
        etail = enew
        nel += 1
        if cur(pc).kind == 9 {
          pc.idx = pc.idx + 1                           ## ',' between elements
        } else if cur(pc).kind == 30 {
          ## The `[e ; n]` FILL form (a `;`, kind 30, after the FIRST element). `n` must be an
          ## integer LITERAL (kind 3). Desugar to `[e, e, …, e]` (n copies) right here — reusing
          ## the `ArrayLit` node + lowering with ZERO codegen/AST change (fixpoint-safe: `src/`
          ## uses no fill form). All copies share the single element node `ee` (each just re-emits
          ## it — fine for the constant fills the stdlib uses, e.g. `[0; 256]`). P3.
          pc.idx = pc.idx + 1                           ## ';'
          if cur(pc).kind != 3 { panic("selfhost: array-fill count must be an integer literal") }
          filln := int_at(pc)
          pc.idx = pc.idx + 1                           ## the count literal
          if filln == 0 {
            ## `[e; 0]` — a ZERO-element array type/literal (spec Types §6.5): the FIRST element was
            ## already pushed above, so drop it to make the literal truly empty (size 0). Without this
            ## `[e; 0]` silently parsed as a ONE-element array (a wrong layout for `[T; 0]`).
            nel = 0
            ehead = 0
            etail = 0
          } else {
            mut fi := 1
            while fi < filln {
              fnew := gnode(pc.arena, Arg(e = ee, next = 0))
              ep := arg_p(etail)
              eold := deref(ep)
              eupd := Arg(e = eold.e, next = fnew)
              deref(ep) = eupd
              etail = fnew
              nel += 1
              fi += 1
            }
          }
        } else if tok_gap_has_newline(pc) {
          ## Grammar §2 item-sep: the lexer drops newline tokens, so consume no token here. A
          ## plain space remains invalid and continues to the located malformed-array reject.
        } else if cur(pc).kind != 15 and cur(pc).kind != 0 {
          ## After an element only `,`, `;`, `]`, or a source newline is valid. Anything else is a
          ## malformed array literal — emit a clean diagnostic instead of calling `p_or` on the stray
          ## token, which would drift the cursor and mis-parse the rest.
          panic("selfhost: malformed array literal — expected `,`, `;`, newline, or `]`")
        }
      }
      pc.idx = pc.idx + 1                 ## ']'
      return newnode(pc.arena, Expr.ArrayLit(nel, ehead))
    }
    k := cur(pc).kind
    if k == 3 {
      nt := cur(pc)
      v := int_at(pc)
      pc.idx = pc.idx + 1
      return newnode(pc.arena, Expr.Num(v, nt.start, nt.len))
    }
    ## a CHAR literal `'c'` (token kind 41) — its codepoint IS an integer value, so lower it as a
    ## `Num`; `char` is a scalar over `bits32` and a char value flows exactly like an int (render via
    ## `display`'s `Char` arm / `push_char`). Escapes decoded by `char_lit_val`.
    if k == 41 {
      ct := cur(pc)
      pc.idx = pc.idx + 1
      return newnode(pc.arena, Expr.Num(char_lit_val(pc.src, ct.start, ct.len), 0, 0))
    }
    ## a FLOAT literal (token kind 39) — carry its source span for the `.double` rodata emission.
    ## The span is emitted VERBATIM into the `.double` directive, so a `_` separator (legal in a
    ## float per Grammar §2.4 / SYN-3, since `float ::= dec-int "." dec-int` and `dec-int` admits
    ## `_`) would reach `as` as `.double 1_0.5` — not something the assembler accepts, and not
    ## something this parser can strip (the FloatLit carries an OFFSET into the source, not text).
    ## Reject it located rather than emit an asm the user did not write.
    if k == 39 {
      ft := cur(pc)
      if float_lit_err(str_at(pc.src + ft.start, ft.len)) != 0 {
        reject_at(pc, "selfhost: malformed FLOAT literal - Grammar §2.4 requires `dec-int . dec-int [e/E [+-] dec-int]`, `dec-int e/E [+-] dec-int`, or a C-style `0x...p/P[+-]dec-int` hex float", ft.start)
      }
      mut fi := 0
      while fi < ft.len {
        if bytes(str_at(pc.src + ft.start + fi, 1))[0] == 95 {
          reject_at(pc, "selfhost: a `_` digit separator in a FLOAT literal is not supported yet (Grammar §2.4 allows it; the float's source text is emitted verbatim into `.double`) - write the digits without `_`", ft.start)
        }
        fi = fi + 1
      }
      pc.idx = pc.idx + 1
      return newnode(pc.arena, Expr.FloatLit(ft.start, ft.len))
    }
    ## A STRING literal (lexer kind 4) — its token span covers the surrounding quotes, so the
    ## INNER bytes are `[start+1, start+len-1)` (len-2 source chars). Assign it a fresh label
    ## index (`pc.nstr`) and produce a `StrLit(inner_start, decoded_len, label_idx, 0, 0)`. The scanner
    ## validates UTF-8 and counts each decoded byte, including the one-byte result of `\xHH`; the
    ## raw span remains in the AST so each backend can emit/decode the source escape itself.
    if k == 4 {
      st := cur(pc)
      pc.idx = pc.idx + 1
      lbl := pc.nstr
      pc.nstr = pc.nstr + 1
      span := st.len - 2
      sinfo := scan_string(pc.src + st.start + 1, span)
      if not sinfo.ok { reject_at(pc, "selfhost: string literal is not valid UTF-8 (including its escapes) — Grammar §2.4", st.start) }
      return newnode(pc.arena, Expr.StrLit(st.start + 1, sinfo.len, lbl, 0, 0))
    }
    ## `in` / `out` are CONTEXTUAL keywords — modifiers only in a parameter list (`in out a`) or a
    ## `for … in` head. Used as a VALUE (a parameter named `out` passed as a call argument, e.g.
    ## `cstr(a, out)`), the lexer still tags them kind 2, so treat that here as an identifier (Var/
    ## Call by name). Without this the kind-2 token fell through to the `'(' expr ')'` path below,
    ## which consumed it as if it were `(` and over-ran to EOF — the §1.0 CLI `run_cli`-dropped bug.
    ## Scoped to `in`/`out` ONLY (other keywords keep their fall-through, so the tree is unaffected).
    mut k2id := false
    if k == 2 {
      kl := str_at(pc.src + cur(pc).start, cur(pc).len)
      if str_eq(kl, "in") or str_eq(kl, "out") { k2id = true }
    }
    if k == 1 or k2id {
      t := cur(pc)
      pc.idx = pc.idx + 1
      ## `true` / `false` — boolean literals. They are lexed as identifiers (not keywords), so
      ## intercept them here: a `bool` is an int 1/0 at the machine level, so produce a `Num`
      ## (the lower emits the immediate). Otherwise they would be mis-parsed as variable
      ## references and read a bogus frame slot.
      lx := str_at(pc.src + t.start, t.len)
      if str_eq(lx, "true") { return newnode(pc.arena, Expr.BoolLit(1)) }
      if str_eq(lx, "false") { return newnode(pc.arena, Expr.BoolLit(0)) }
      ## `embed("path")` — the reproducible comptime file-embed builtin (Comptime §2.4 / appendix
      ## §160 / Assembly §9). The single argument MUST be a string LITERAL (a comptime-known path);
      ## the file is read+baked here at parse time (see `embed_strlit`). Recognized like `bitcast`
      ## (an OP-1 prelude word-function, not a keyword), so it never sees a run-time value.
      if str_eq(lx, "embed") and cur(pc).kind == 10 {
        pc.idx = pc.idx + 1               ## '('
        if cur(pc).kind != 4 { panic("selfhost: embed requires a string-literal path argument") }
        pt := cur(pc)
        pc.idx = pc.idx + 1               ## the string-literal path
        if cur(pc).kind != 11 { panic("selfhost: embed takes exactly one string-literal argument") }
        pc.idx = pc.idx + 1               ## ')'
        return embed_strlit(pc, pt.start + 1, pt.len - 2)
      }
      ## `bitcast(T, v)` — a same-size reinterpretation (Types/ABI). At the machine level the bits
      ## are unchanged (a `usize`↔`ptr` / `isize`→`ptr` cast is a register no-op), so it lowers to
      ## just the VALUE: skip the target type up to the top-level `,` (paren-balanced, since a
      ## `ptr(mut T)` type holds parens), parse the value, and return it.
      ##
      ## EXCEPTION (soundness): when the target is `ptr( [mut] <sub-word scalar> )` — a pointer to a
      ## 1/2/4-byte scalar — the pointee width is PRESERVED in an `Expr::Bitcast` node so a `deref`
      ## load/store through it narrows the machine move to the pointee width (else a full 8-byte
      ## `movq` reads/clobbers the 7 neighbouring bytes). The node lowers exactly to the inner value.
      ## Only a KNOWN sub-word pointee triggers it, so a word-sized / aggregate / unknown pointee (all
      ## the compiler's own bitcasts) stays identity-erased → the node never appears in the reached
      ## tree → fixpoint-neutral. While scanning the target type, capture the pointee name span (the
      ## last ident at paren-depth 1 of a `ptr(…)` head).
      if str_eq(str_at(pc.src + t.start, t.len), "bitcast") and cur(pc).kind == 10 {
        pc.idx = pc.idx + 1               ## '('
        mut bdepth := 0
        mut sawptr := false               ## the target head is `ptr`
        mut sawparen := false             ## the target text contains a `(` (not a lone ident)
        mut pps := 0                      ## pointee type-name span start (0 = none)
        mut ppl := 0
        mut hts := 0                      ## target HEAD type-name span (first depth-0 ident)
        mut htl := 0
        mut tgt_s := cur(pc).start         ## FULL target-type span start (first target token)
        mut tgt_e := cur(pc).start         ## …and end (updated to the last token before the `,`)
        while cur(pc).kind != 0 and not (cur(pc).kind == 9 and bdepth == 0) {
          if cur(pc).kind == 10 { bdepth = bdepth + 1; sawparen = true }
          else if cur(pc).kind == 11 { bdepth = bdepth - 1 }
          else if cur(pc).kind == 1 {
            if bdepth == 0 and htl == 0 { hts = cur(pc).start; htl = cur(pc).len }
            if bdepth == 0 and str_eq(str_at(pc.src + cur(pc).start, cur(pc).len), "ptr") { sawptr = true }
            else if bdepth == 1 and sawptr { pps = cur(pc).start; ppl = cur(pc).len }
          }
          tgt_e = cur(pc).start + cur(pc).len
          pc.idx = pc.idx + 1
        }
        pc.idx = pc.idx + 1               ## ','
        bv := p_or(pc)                    ## the value — bitcast is identity (same bits)
        pc.idx = pc.idx + 1               ## ')'
        if sawptr and scalar_width::subword_bytes(pc.src, pps, ppl) != 0 {
          return newnode(pc.arena, Expr.Bitcast(bv, pps, ppl))
        }
        ## An aggregate→aggregate reinterpret to a bare USER type name (a struct — NOT a scalar/`str`/
        ## `ptr(…)`/generic target): PRESERVE the target in an `Expr::Bitcast` carrying the struct-NAME
        ## span, so a local bound from it (`y := bitcast(B, x)`) is typed by `B` and `y.field` resolves
        ## against `B` (identity erasure kept the SOURCE type → its fields silently read wrong words).
        ## Scalar/`str`/`ptr`/parenthesized-generic targets stay identity-erased (str_at unaffected).
        if not sawparen and htl != 0 and not scalar_or_str_name(pc.src, hts, htl) {
          return newnode(pc.arena, Expr.Bitcast(bv, hts, htl))
        }
        ## A `bitcast(ptr( [mut] <UserType>), v)` to a POINTER-to-user-type target: PRESERVE the
        ## FULL `ptr(…)` target span in an `Expr::Bitcast`, so a bare (un-annotated) local bound from it
        ## (`vp := bitcast(ptr(Struct), addr)`) can be typed as a pointer-to-struct (ek 7) by
        ## `collect_slots` (`bitcast_ptrstruct_span`), rather than collapsing to a bare scalar whose
        ## `deref(vp)`/`vp.f` read zeros. The node lowers to the inner value (bit-identity), so annotated
        ## locals + inline `deref(bitcast(…))` are UNCHANGED. Only USER pointee names are preserved
        ## (`ptr(usize)` etc. stay identity-erased); the pointee KIND (struct vs enum) is resolved later
        ## with `decls` — an enum pointee simply doesn't infer ek 7.
        if sawptr and ppl != 0 and not scalar_or_str_name(pc.src, pps, ppl) {
          return newnode(pc.arena, Expr.Bitcast(bv, tgt_s, tgt_e - tgt_s))
        }
        return bv
      }
      ## `<width>(v)` — a primitive scalar CONVERSION (`usize(i)`, `i64(n)`, `u8(b)`, `f64(i)`, …).
      ## These are NO LONGER swallowed to identity here: they parse as an ordinary single-arg `Call`
      ## (the path below), and `lower::emit_gas` intercepts the callee name. Among native INTEGER
      ## widths the conversion is identity at the machine level (every value already lives in a 64-bit
      ## word, `unchecked`), so the lower emits just the value — byte-identical to the former swallow.
      ## But a FLOAT conversion (`f64(i)` int→float, `u64(f)` float→int) is a REAL instruction
      ## (`cvtsi2sd`/`cvttsd2si`), which the lower can only emit if it sees the cast node — hence the
      ## node is preserved rather than dropped at parse time. (`f64`/`f32` were never in the swallow
      ## list, so they already parsed as calls; this just makes the integer widths consistent.)
      ## A CROSS-MODULE qualified call `mod::f(…)` (MODULE tier): the head ident `t` (the
      ## module name) followed by `::` (kind 7), a tail ident `f` (kind 1), then `(` (kind 10).
      ## (A `ptr`/`deref` intrinsic was already matched earlier in `p_factor`, so this
      ## never sees `mem`.) The callee is captured as ONE source span covering `mod::f` — from
      ## `t.start` through the end of the tail ident — so `str_at` yields the literal `"mod::f"`;
      ## lower detects the `::` and splits it into the mangled symbol `mod__f`. The arguments are
      ## the same arena-linked `Arg` list a bare call uses.
      ## LOOKAHEAD for a qualified path `t (:: ident)+ (` — one or MORE `::segment` steps, so a
      ## multi-segment stdlib path `std::io::write(…)` is captured whole (lower mangles every `::`
      ## to `__`). Walk a copy of the cursor (`j`) over the `::ident` chain WITHOUT committing; the
      ## last ident before the `(` is the tail fn/type, the rest is the module path. A 2-segment
      ## `mod::f(` walks the chain once → identical to the former first-`::` split (no behaviour
      ## change for the all-2-segment self-host source). A qualified path NOT followed by `(` (a
      ## value path) is left for the fall-through, so the cursor is only advanced once confirmed.
      ## Track the LAST segment's span as SCALARS (`tseg_start`/`tseg_len`) — not a `Token` local
      ## reassigned in the loop (the lean self-host lower does not reassign a struct local from a
      ## by-value struct-returning call; scalar fields do reassign).
      mut jla := pc.idx
      mut tseg_start := t.start
      mut tseg_len := t.len
      while tok_at(pc, jla).kind == 7 and tok_at(pc, jla + 1).kind == 1 {
        seg := tok_at(pc, jla + 1)
        tseg_start = seg.start
        tseg_len = seg.len
        jla += 2
      }
      ## A `::` with NO segment ident after it is a truncated path (`x := rt::`). The walk above only
    ## steps over a `:: ident` PAIR, so a dangling `::` left `jla == pc.idx`, the head fell through to
    ## a bare `Var`, and the orphan `::` was absorbed by the decl-level alias lookahead — the
    ## declaration was accepted with a nonsense alias span and the truncation vanished (measured: the
    ## tail form built rc 0 and ran to 42). Reject it located, at the `::`.
    if tok_at(pc, jla).kind == 7 and tok_at(pc, jla + 1).kind == 0 {
      zpe := reject_eof(pc, "selfhost: a `::` must be followed by a path SEGMENT name - the input ends after it, so this qualified path is incomplete (a truncated file, a partial copy, or a bad merge)")
    }
    if jla > pc.idx and tok_at(pc, jla).kind == 10 {
        pc.idx = jla                      ## consume the `::segment …` chain (cursor now at `(`)
        callee_len := tseg_start + tseg_len - t.start   ## span covers the whole `a::b::…::f`
        pc.idx = pc.idx + 1               ## '('
        ## A qualified STRUCT CONSTRUCTION `mod::Type(field = e, …)` — distinguished, like the
        ## bare path, by an `=` (kind 21) after the first field-name ident. Types resolve GLOBALLY
        ## (one decl vector; `struct_decl_of` strips the `mod::` head), so the `StructLit` keeps the
        ## BARE TAIL name `Type` — the same node a bare `Type(field = e, …)` ctor produces. (Real
        ## pass code writes `ast::Decl(...)`; this builds it identically to an unqualified ctor.)
        is_qstruct := cur(pc).kind == 1 and tok_at(pc, pc.idx + 1).kind == 21
        if is_qstruct {
          mut qfnf := 0
          mut qfhead := 0
          mut qftail := 0
          while cur(pc).kind != 11 and cur(pc).kind != 0 {
            pc.idx = pc.idx + 1           ## field name
            pc.idx = pc.idx + 1           ## '='
            qfe := p_or(pc)
            qfnew := gnode(pc.arena, Arg(e = qfe, next = 0))
            if qfhead == 0 { qfhead = qfnew } else {
              qfp := arg_p(qftail)
              qfold := deref(qfp)
              qfupd := Arg(e = qfold.e, next = qfnew)
              deref(qfp) = qfupd
            }
            qftail = qfnew
            qfnf += 1
            if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }   ## ',' between fields
          }
          pc.idx = pc.idx + 1             ## ')'
          return newnode(pc.arena, Expr.StructLit(tseg_start, tseg_len, qfnf, qfhead))
        }
        mut qn := 0
        mut qhead := 0
        mut qtail := 0
        while cur(pc).kind != 11 and cur(pc).kind != 0 {
          qe := p_or(pc)
          qnew := gnode(pc.arena, Arg(e = qe, next = 0))
          if qhead == 0 { qhead = qnew } else {
            qp := arg_p(qtail)
            qold := deref(qp)
            qupd := Arg(e = qold.e, next = qnew)
            deref(qp) = qupd
          }
          qtail = qnew
          qn += 1
          if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }   ## ',' between args
        }
        pc.idx = pc.idx + 1               ## ')'
        return newnode(pc.arena, Expr.Call(t.start, callee_len, qn, qhead))
      }
      ## A qualified VALUE path (`ser::SerError`) is an ordinary factor when it is not followed by
      ## `(`. Consume its `::segment` tail so the enclosing call-argument loop sees the real delimiter
      ## (`,` / `)`) instead of re-entering p_factor on the `::` token. Expr::Var has no separate path
      ## node and the type/value consumers resolve qualified names by their tail, so retain the LAST
      ## segment as the Var span. The generic enum-constructor path above is intentionally separate:
      ## `Result(T, E).Ok(...)` must skip its type-argument list and let p_field build the EnumLit, while
      ## this branch only handles a path that has no call/constructor suffix.
      if jla > pc.idx {
        pc.idx = jla
        return newnode(pc.arena, Expr.Var(tseg_start, tseg_len))
      }
      ## GENERIC-ENUM construction `G(T, …).Variant(…)` (e.g. `Result(Decl, ParseErr).Ok(x)` /
      ## `Option(usize).Some(x)`): skip the type-argument list (comptime, erased) so the cursor
      ## lands on the `.Variant(…)`, which `p_field`'s enum-ctor path then builds against the bare
      ## type name `t` (the head). Checked BEFORE the generic-STRUCT inst (which needs `(` after the
      ## type args); here a `.` follows, so the two never collide.
      ge := is_generic_enum_ctor(pc)
      ## Fire the generic-enum-ctor rewrite only when the head `t` IS a known enum type (or the table
      ## is empty = unknown → old behavior). Otherwise `t(args).method(…)` is a call-then-UFCS: fall
      ## through so `t(args)` parses as an ordinary Call (its args survive) and p_field desugars the
      ## `.method(…)` as UFCS on that call result.
      if ge.is_g and (enums_known(pc) == false or is_enum_name(pc, t.start, t.len)) {
        pc.idx = ge.after                  ## cursor now at the '.' before the variant
        return newnode(pc.arena, Expr.Var(t.start, t.len))
      }
      ## GENERIC-STRUCT instantiation `Vec(u64)(field = e, …)` — the head ident `t` (`Vec`)
      ## followed by a type-argument list `(u64)` then the construction `(…)`. The type argument
      ## is comptime + erased: skip the `(u64)` so the cursor lands on the SECOND `(`, which the
      ## struct-construction path below handles against the bare struct name `t` (word-sized `T` →
      ## the same `Vec` layout). So `Vec(u64)(…)` and `Vec(i64)(…)` both build a `StructLit(Vec, …)`.
      gin := is_generic_inst(pc)
      if gin.is_i { pc.idx = gin.after }   ## skip the WHOLE type-arg list `(T)` / `(K, V)` → cursor at the ctor `(`
      ## The lexer omits NEWLINE, so a bare module alias can be followed immediately in the token
      ## stream by a one-element (or multi-element) listed projection: `rt` then `(Expr) := ast`.
      ## Do not consume that group as call arguments. Ordinary `name(args)` remains unchanged; the
      ## balanced-group lookahead only classifies a group whose following token is a binding operator.
      mut is_call := false
      if cur(pc).kind == 10 and paren_group_is_binding(pc) == false { is_call = true }
      ## `ident ( …args… )` — a call (kinds: 10 `(`, 11 `)`, 9 `,`), OR a struct
      ## construction `ident ( field = expr , … )` distinguished by an `=` (kind 21) after
      ## the first argument's field-name ident. A bare ident is a variable reference. The
      ## arguments are parsed into an arena-linked `Arg` list (up to 6 — the System V integer
      ## argument registers; >6 is not supported here).
      if is_call {
        pc.idx = pc.idx + 1               ## '('
        ## struct-lit lookahead: `(` ident `=` …  — a field assignment, not a call arg. Also the
        ## ZERO-named-field constructor `TypeName()` (spec Types §6.5 / §9.4 / grammar §130 struct-ctor
        ## with an EMPTY field-init list): an empty `()` whose HEAD `t` is a KNOWN CONCRETE struct in the
        ## field-order table (`struct_rec_of >= 0`) is CONSTRUCTION — an empty struct `Z()` (zero-size
        ## StructLit) or an all-defaulted struct `W()` (PASS B fills every field from its default). The
        ## gate is TIGHT: struct + fn share one namespace (`name := value`), so a table hit means `t` IS a
        ## struct, never a same-named 0-arg function — a real call stays a call (`struct_rec_of < 0`), and
        ## a generic instantiation `Vec(u64)` never reaches here with empty parens (is_generic_inst skips
        ## its type-args; a generic struct is a `fn`, kind-1, absent from the kind-2 struct table).
        is_struct := (cur(pc).kind == 1 and tok_at(pc, pc.idx + 1).kind == 21)
                     or (cur(pc).kind == 11 and struct_rec_of(pc, t.start, t.len) >= 0)
        if is_struct {
          ## `field = expr` pairs are collected into a transient `FInit` list (each carrying the field
          ## NAME span), then REORDERED into the struct's DECLARATION order (by-name construction,
          ## TYP-8): `P(y = 6, x = 5)` and `P(x = 5, y = 6)` both emit values in `x, y` order, so the
          ## positional struct-assign every backend already does is correct. The reorder is inlined here
          ## with scalar-only locals (a multi-word-struct-returning helper mis-lowers under the seed).
          mut fihead := 0
          mut fitail := 0
          while cur(pc).kind != 11 and cur(pc).kind != 0 {
            fnm := cur(pc)                ## the field NAME token (span used to resolve its decl index)
            pc.idx = pc.idx + 1           ## field name
            pc.idx = pc.idx + 1           ## '='
            fe := p_or(pc)
            finew := finode(pc.arena, FInit(fs = fnm.start, fl = fnm.len, e = fe, next = 0))
            if fihead == 0 { fihead = unchecked bitcast(usize, finew) } else {
              fip := finit_p(unchecked bitcast(ptr(mut FInit), fitail))
              fiold := deref(fip)
              deref(fip) = FInit(fs = fiold.fs, fl = fiold.fl, e = fiold.e, next = finew)
            }
            fitail = unchecked bitcast(usize, finew)
            if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }   ## ',' between fields
          }
          pc.idx = pc.idx + 1             ## ')'
          ## Build the value `Arg` list in DECLARATION order. `fhead`/`ftail` are the emitted list; the
          ## inline link store mirrors the historical struct-ctor idiom exactly.
          mut fnf := 0
          mut fhead := 0
          mut ftail := 0
          rec := struct_rec_of(pc, t.start, t.len)
          if rec < 0 {
            ## Struct type not in the field-order table (forward-ref / generic-inst head / single-pass
            ## path): keep the provided order verbatim (historical positional behavior — an in-declaration-
            ## order literal is byte-identical, so src/lib + the fixpoint are unaffected).
            mut g := fihead
            while g != 0 {
              fnew := gnode(pc.arena, Arg(e = finit_expr(g), next = 0))
              if fhead == 0 { fhead = fnew } else { fp := arg_p(ftail); fo := deref(fp); deref(fp) = Arg(e = fo.e, next = fnew) }
              ftail = fnew
              fnf += 1
              g = finit_next(g)
            }
          } else {
            urec := usize(rec)
            ## PASS A — reject an unknown field name + find the highest declaration index PROVIDED (a
            ## provider is an explicit `f = v`). Trailing fields above the highest MATERIALIZED index (see
            ## `hi`) with no provider and no default are dropped = suffix partial init (v1).
            mut lastprov : i64 = 0 - 1
            mut g1 := fihead
            while g1 != 0 {
              fidx := finit_field_idx(pc, urec, g1)
              if fidx < 0 { sfail("selfhost: unknown field name in struct construction (no such field on this struct type)") }
              if fidx > lastprov { lastprov = fidx }
              g1 = finit_next(g1)
            }
            ## A DEFAULTED field (spec Types §9.4 / TYP-8) is ALWAYS materialized when omitted, at ANY
            ## position — so the reordered list must extend to the highest index that has EITHER a provider
            ## OR a default. `hi` = max(lastprov, highest-defaulted-index).
            nf := i64(struct_nfields(urec))
            mut hi := lastprov
            mut dk : i64 = 0
            while dk < nf {
              df := struct_field_def(urec, usize(dk))
              if df.dl > 0 and dk > hi { hi = dk }
              dk += 1
            }
            ## PASS B — emit values in declaration order 0..=hi. Each slot resolves to EXACTLY one of:
            ## the single explicit provider (`m == 1`); the field's DEFAULT re-lexed at this site when
            ## omitted (`m == 0` and `def_len > 0`); else a non-trailing gap with no default → loud reject
            ## (`m == 0`, no default); a duplicate (`m > 1`) → loud reject. Never a silent wrong value.
            mut k : i64 = 0
            while k <= hi {
              mut fval := expr_null()
              mut m := 0
              mut g2 := fihead
              while g2 != 0 {
                if finit_field_idx(pc, urec, g2) == k { fval = finit_expr(g2); m += 1 }
                g2 = finit_next(g2)
              }
              if m > 1 { sfail("selfhost: duplicate field name in struct construction (the same field written twice)") }
              if m == 0 {
                df := struct_field_def(urec, usize(k))
                if df.dl > 0 { fval = relex_default(pc, df.ds, df.dl) }
                else { sfail("selfhost: struct construction leaves a non-trailing field unwritten (a gap before a later written or defaulted field) - provide the field, give it a default, or reorder") }
              }
              fnew := gnode(pc.arena, Arg(e = fval, next = 0))
              if fhead == 0 { fhead = fnew } else { fp := arg_p(ftail); fo := deref(fp); deref(fp) = Arg(e = fo.e, next = fnew) }
              ftail = fnew
              fnf += 1
              k += 1
            }
          }
          return newnode(pc.arena, Expr.StructLit(t.start, t.len, fnf, unchecked bitcast(ptr(mut Arg), fhead)))
        }
        mut nargs := 0
        mut ahead := 0
        mut atail := 0
        while cur(pc).kind != 11 and cur(pc).kind != 0 {
          ae := p_or(pc)
          anew := gnode(pc.arena, Arg(e = ae, next = 0))
          if ahead == 0 { ahead = anew } else {
            gp := arg_p(atail)
            gold := deref(gp)
            gupd := Arg(e = gold.e, next = anew)
            deref(gp) = gupd
          }
          atail = anew
          nargs += 1
          if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }   ## ',' between args
        }
        pc.idx = pc.idx + 1               ## ')'
        return newnode(pc.arena, Expr.Call(t.start, t.len, nargs, ahead))
      }
      return newnode(pc.arena, Expr.Var(t.start, t.len))
    }
    ## '(' expr ')'  — a parenthesized expression, OR a TUPLE literal `(a, b, …)` (a `,` follows the
    ## first element). A tuple is an N-word aggregate, so it is built as an `ArrayLit` (the same node
    ## as `[a, b]`) and reuses the array machinery — element `N` is read by the `t.N` postfix
    ## (lowered to `Index(t, Num(N))`). Element types may differ (each is one word); only scalar/
    ## pointer tuple elements are supported (a struct/str element would need a strided layout).
    pc.idx = pc.idx + 1                                    ## '('
    e := p_or(pc)
    if cur(pc).kind == 9 {
      ## TUPLE literal — collect `e` plus the comma-separated rest into an `Arg` list + ArrayLit,
      ## mirroring the `[a, b]` array-literal loop EXACTLY (the first element flows through the same
      ## append path, ehead starts 0).
      mut ehead := 0
      mut etail := 0
      mut nel := 0
      mut cure : ptr(Expr) = e
      mut going := true
      while going {
        enew := gnode(pc.arena, Arg(e = cure, next = 0))
        if ehead == 0 { ehead = enew } else {
          ep := arg_p(etail)
          eold := deref(ep)
          eupd := Arg(e = eold.e, next = enew)
          deref(ep) = eupd
        }
        etail = enew
        nel += 1
        if cur(pc).kind == 9 {
          pc.idx = pc.idx + 1                              ## ','
          cure = p_or(pc)
        } else {
          going = false
        }
      }
      pc.idx = pc.idx + 1                                  ## ')'
      return newnode(pc.arena, Expr.ArrayLit(nel, ehead))
    }
    ## Whether the token being consumed as the group's `)` REALLY is one (kind 11). The skip below is
    ## unconditional (the grammar guarantees it on a well-formed group), but several enclosing pattern /
    ## arm parsers re-enter here on a partly-consumed group and leave the cursor elsewhere; the trailing
    ## reject only trusts a group that actually closed.
    isclose := cur(pc).kind == 11
    pc.idx = pc.idx + 1                                    ## ')'
    ## FN-6 — a PARENTHESIZED expression IMMEDIATELY APPLIED, `(<expr>)(args)`: an IIFE
    ## `(fn(…){…})(args)` or a parenthesized name `(add1)(41)`. NOT representable — `Expr::Call`
    ## carries a callee NAME SPAN, not an expression — and left unhandled the `(args)` was silently
    ## DROPPED, leaking the fn value (its CODE ADDRESS) as the result, wrong ARITY and all (a SILENT
    ## MISCOMPILE). Caught HERE rather than in `p_field` because a parenthesized `(name)` yields a
    ## plain `Expr::Var`, indistinguishable afterwards from a bare name. Reject fail-loud, located;
    ## bind the callee to a name first (`g := <expr>` then `g(args)` — the working indirect-call path).
    ## The lexer emits NO newline tokens, so the `(` opening a following destructure binding
    ## (`(A, B) := m`) abuts this expression: that group is excluded (`paren_group_is_binding`).
    if cur(pc).kind == 10 {
      mut pskip := paren_group_is_binding(pc)
      if isclose == false { pskip = true }
      padj := tok_adjacent(pc, pc.idx)
      if padj == false { pskip = true }
      if pskip == false {
        if expr_is_lambda(e) { reject_at(pc, "selfhost: FN-6 - an immediately-invoked function value `(fn(...){...})(...)` is unsupported; bind it to a name first", cur(pc).start) }
        ## A parenthesized BARE NAME is just that name: `(add1)(41)` IS `add1(41)`. Drop the parentheses
        ## and build the ORDINARY named call right here, so the whole existing pipeline applies unchanged
        ## — overload resolution, generics, the fn-VALUE slot path when the name is a local, and (the
        ## point of the exercise) `check`'s ARITY diagnostic, which is what now rejects `(add1)(41, 99, 7)`.
        pvn := enum_type_span(e)
        if pvn.n != 0 { return p_pcall(pc, pvn) }
        ## A parenthesized ELEMENT read `(fs[0])(10)` is the expression-callee form — leave it to
        ## `p_field`'s trailing guard (the parentheses carry no meaning once the group has closed), which
        ## sees the very same `Index` base a bare `fs[0](10)` produces.
        if expr_is_index(e) == false {
          reject_at(pc, "selfhost: FN-6 - a call through this PARENTHESIZED callee is unsupported: only a bare name `(f)(args)` or an ELEMENT read `(fs[i])(args)` is. Bind the callee to a name first: `g := <callee>` then `g(args)`", cur(pc).start)
        }
      }
    }
    e
}

## postfix := factor { '.' ident [ '(' args ')' ] }  — a field read `base.f` (token kind
## 22 `.`), OR an **enum-variant construction** `E.V(a0, a1)` distinguished by a `(` (kind
## 10) following the `.variant` ident. A field read chains left-to-right so `a.b.c` nests
## `Field(Field(a, b), c)`; lower resolves each `.f` to the base struct's declaration-order
## field offset. The enum form requires the base be a `Var` (the enum TYPE name) — its span
## becomes the `EnumLit`'s enum-type span; the variant name + ≤2 payload args follow.
p_field := fn(in out pc : PC) -> ptr(mut Expr) {
    mut base := p_factor(pc)
    ## FN-6 — an IMMEDIATELY-INVOKED function value `(fn(…){…})(args)` (IIFE) is not representable:
    ## `Expr::Call`'s callee is a NAME span, not an expression, so a call APPLIED to a parenthesized
    ## lambda cannot be built. Left unhandled, the trailing `(args)` was silently dropped and the lambda
    ## code-pointer leaked out as the value (a SILENT MISCOMPILE — the process exit was the low byte of
    ## the lambda's address). Reject fail-loud (like the float-literal panic below); bind the lambda to a
    ## name first (`f := fn(…){…}; f(args)`), which lifts + calls it through the indirect-call path.
    ## NOTE: nested `if`s, NOT `if a and expr_is_lambda(base)` — a comparison AND-ed with a fn call
    ## mis-lowers under the seed (the documented lean-lower `and` gotcha), silently skipping the guard.
    ## STILL LIVE, though `p_factor`'s parenthesized-callee reject now catches the usual spelling first:
    ## that one requires the `(` to be ADJACENT to the closing `)`, so a spaced `(fn(…){…}) (args)` still
    ## arrives here and is rejected with this message.
    if cur(pc).kind == 10 {
      if expr_is_lambda(base) { panic("selfhost: FN-6 — an immediately-invoked function value `(fn(...){...})(...)` is unsupported; bind it to a name first") }
    }
    while cur(pc).kind == 22 or cur(pc).kind == 14 or cur(pc).kind == 32 {
      ## `base ?` — the TRYABLE `?` operator (token kind 32). A postfix unary that wraps the
      ## base in `Expr::Try` (chains left-to-right with `.field`/`[idx]`, so `f()?` binds the
      ## `?` to the call). Lower checks the inner enum's discriminant: a failure (non-zero)
      ## returns the whole enum from the enclosing fn; a success (0) yields the payload.
      if cur(pc).kind == 32 {
        pc.idx = pc.idx + 1               ## '?'
        base = newnode(pc.arena, Expr.Try(base))
      } else {
      ## `base [ idx ]` — an element READ (token 14 `[`, 15 `]`). Chains left-to-right with
      ## the `.field` postfix so `a[i].f` / `m[i][j]` nest naturally; lower computes the
      ## runtime element address. The index is a full expression (`p_or`).
      if cur(pc).kind == 14 {
        pc.idx = pc.idx + 1               ## '['
        idx := p_or(pc)
        ## `base[lo..hi]` — a RANGE SLICE (a `..`, kind 31, after the low bound). Both bounds are
        ## full expressions; build `Slice(base, lo, hi)` (lower emits the {ptr+lo, hi-lo} sub-view).
        ## Without this the `..` was consumed as the `]` and the leftover `hi]` DRIFTED the cursor,
        ## swallowing the following top-level decl.
        if cur(pc).kind == 31 {
          pc.idx = pc.idx + 1             ## '..'
          hi := p_or(pc)
          pc.idx = pc.idx + 1             ## ']'
          base = newnode(pc.arena, Expr.Slice(base, idx, hi))
        } else {
          pc.idx = pc.idx + 1             ## ']'
          base = newnode(pc.arena, Expr.Index(base, idx))
        }
      } else {
      pc.idx = pc.idx + 1                 ## '.'
      ## A `.` with NOTHING after it is a truncated field path (`x := y.`). Unchecked, `fld` below
      ## was bound to the EOF sentinel — a zero-length name at the end of the buffer — and the
      ## `Field` node was built from it, so the declaration was ACCEPTED and the program built and
      ## ran (measured rc 0, ran to 42). A member name is mandatory here. (The check must come AFTER
      ## the `.` is consumed: before it, the cursor is on the `.` itself.)
      if cur(pc).kind == 0 {
        zde := reject_eof(pc, "selfhost: a `.` must be followed by a FIELD, variant or tuple-element name - the input ends after it, so this member access is incomplete (a truncated file, a partial copy, or a bad merge)")
      }
      if cur(pc).kind == 10 {
        ## `base.(f)` — COMPTIME field access: the member is a comptime value `f` (a
        ## `typeinfo` field bound by a `comptime for`). The unroll rewrites it per member.
        pc.idx = pc.idx + 1               ## '('
        cfidx := p_or(pc)
        pc.idx = pc.idx + 1               ## ')'
        base = newnode(pc.arena, Expr.CompField(base, cfidx))
      } else {
      fld := cur(pc); pc.idx = pc.idx + 1 ## variant / field name
      ## A `.<int>` access (`fld` is an int literal, kind 3): TUPLE INDEXING `t.N` — lowered as an
      ## element read `Index(base, Num(N))`, since a tuple is an N-word aggregate (reusing the array
      ## machinery). A real struct field is always an identifier, so a `.<int>` is unambiguous —
      ## EXCEPT when the base is itself an int literal, which is a mis-lexed FLOAT (`1.5` lexes as
      ## `1` `.` `5`); floats are not supported, so diagnose that cleanly.
      if fld.kind == 3 {
        if expr_is_num(base) { panic("selfhost: float literals like 1.5 are not supported") }
        ni := i64(lit_val_at(pc, fld.start, fld.len))
        ix := newnode(pc.arena, Expr.Num(ni, 0, 0))
        base = newnode(pc.arena, Expr.Index(base, ix))
      }
      ## `E.V(...)` — enum-variant construction (a `(` after the `.name`). The enum TYPE
      ## name span comes from the base `Var`. Parse 0/1/2 comma-separated payload args.
      else if cur(pc).kind == 10 {
        en := enum_type_span(base)
        pc.idx = pc.idx + 1               ## '('
        ## N comma-separated payload args into an arena-linked `Arg` list (general arity).
        mut pnp := 0
        mut phead := 0
        mut ptail := 0
        while cur(pc).kind != 11 and cur(pc).kind != 0 {
          pe := p_or(pc)
          pnew := gnode(pc.arena, Arg(e = pe, next = 0))
          if phead == 0 { phead = pnew } else {
            pp := arg_p(ptail)
            pold := deref(pp)
            pupd := Arg(e = pold.e, next = pnew)
            deref(pp) = pupd
          }
          ptail = pnew
          pnp += 1
          if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }   ## ',' between payload args
        }
        pc.idx = pc.idx + 1               ## ')'
        ## `base.name(args)` where `base` is NOT a simple `Var` (`enum_type_span` → 0/0) is a UFCS
        ## method call on a COMPLEX receiver EXPRESSION — `mk().sum()`, `arr[i].g(y)`, `deref(p).h()`.
        ## It CANNOT be an enum-variant construction (those always have a bare type-name `Var` head,
        ## even generic ones — `is_generic_enum_ctor` rewrites `Result(T,E).Ok` to `Var("Result")`).
        ## Desugar to `Call(name, [base, args…])` right here, PREPENDING the receiver EXPRESSION as
        ## argument 0, so the receiver expr survives (the `EnumLit` form keeps only a name SPAN, which
        ## a complex receiver has none of; the emit-time UFCS desugar can only rebuild a `Var` from
        ## that span, losing a call/index/deref receiver). A simple-`Var` receiver keeps the `EnumLit`
        ## path (emit distinguishes enum-ctor vs UFCS via `enum_decl_of`).
        ## Keep the `EnumLit` (enum-ctor) shape ONLY when the base `Var` NAMES A KNOWN ENUM TYPE
        ## (`E.V(…)`); a `Var` naming a VALUE (`b.getv()` / `sb.write_buf()`) is a UFCS method call,
        ## so desugar it to `Call(method, [receiver, args…])` right here — the SAME node the emit-side
        ## UFCS fallback builds, but produced up front so ALL the call machinery sees a real `Call`:
        ## the slot-binding pass then sizes a `name := recv.m()` binding by the METHOD's return type
        ## (scalar / struct / str), not as a bogus enum slot whose `variant_index` was -1 (which
        ## mis-emitted the whole call as the constant `$-1`). Mirrors the enum-vs-call decision at the
        ## generic-ctor site (`enums_known == false` → assume ctor, the pre-scan pass whose result is
        ## discarded; the real pass knows the enum set and decides by `is_enum_name`). `src/` has no
        ## `<value>.method(…)` UFCS call (it uses qualified calls), so this is fixpoint-neutral.
        mut is_ctor := false
        if en.n != 0 {
          if enums_known(pc) == false { is_ctor = true }
          else if is_enum_name(pc, en.s, en.n) { is_ctor = true }
          ## `x86_64.<mnemonic>(…)` — an arch instruction INTRINSIC (num.al's `@inline` operators)
          ## also rides the `EnumLit` shape: the emit-side arch-intrinsic path matches it there (a
          ## base-Var named `x86_64`), so keep it an `EnumLit`, NOT a UFCS `Call` (which would emit an
          ## undefined `call <mnemonic>`). `x86_64` is a namespace ident, never a real value receiver.
          else if str_eq(str_at(pc.src + en.s, en.n), "x86_64") { is_ctor = true }
        }
        if is_ctor {
          base = newnode(pc.arena, Expr.EnumLit(en.s, en.n, fld.start, fld.len, pnp, phead))
        } else {
          ba := gnode(pc.arena, Arg(e = base, next = phead))
          base = newnode(pc.arena, Expr.Call(fld.start, fld.len, pnp + 1, ba))
        }
      } else {
        ## `E.V` with NO `(` — a NULLARY enum-variant construction (`Box.Empty`, `Opt.None`) when the
        ## base `Var` NAMES A KNOWN ENUM TYPE: emit an `EnumLit` with an empty payload (np 0) so a
        ## binding `x := E.V` sizes as the full enum (disc + max-payload words) and by-ref passing
        ## works — a plain `Field` sized it as a 1-word scalar (the disc), so passing it to a by-ref
        ## enum param passed the disc VALUE as the pointer → NULL deref. Any other `.name` (a struct
        ## FIELD read, the base a value) stays a `Field`. Mirrors the parenthesized enum-ctor decision
        ## (`is_enum_name`); `src/` constructs nullary variants via `E.V()` or matches them, not bare
        ## `E.V` in value position, so this stays fixpoint-neutral.
        ennv := enum_type_span(base)
        mut is_nullary_ctor := false
        if ennv.n != 0 and enums_known(pc) and is_enum_name(pc, ennv.s, ennv.n) { is_nullary_ctor = true }
        if is_nullary_ctor {
          base = newnode(pc.arena, Expr.EnumLit(ennv.s, ennv.n, fld.start, fld.len, 0, 0))
        } else {
          base = newnode(pc.arena, Expr.Field(base, fld.start, fld.len))
        }
      }
      }
      }
      }
    }
    ## FN-6 — a CALL POSTFIX applied to a callee that is NOT a bare name (`fs[i](x)`, `t.fs[0](x)`,
    ## `mk()(x)`, `(f)(x)`, `a.b(x)(y)`) is NOT REPRESENTABLE: `Expr::Call` carries a callee NAME SPAN,
    ## not an expression. Left unhandled the trailing `(args)` was silently DROPPED and the callee's
    ## fn value — its CODE ADDRESS — leaked out as the result (a SILENT MISCOMPILE: `fs[0](10)` on
    ## `[add1, dbl]` returned the address of `add1`, and a wrong ARITY was accepted with it). Reject
    ## fail-loud, located. A bare-NAME callee never reaches here: `p_factor`'s ident branch consumes
    ## its own `(args)` into an `Expr::Call`, and the `.m(args)` UFCS / `E.V(args)` ctor postfixes are
    ## consumed by the loop above — so this fires only on the unrepresentable shapes. The workaround
    ## is to bind the callee first (`g := fs[i]` then `g(x)`), which lowers through the WORKING
    ## indirect-call path (the machinery is fine; only this parse was missing).
    ## EXCLUDED: the lexer emits NO newline tokens, so the `(` opening a following DESTRUCTURE binding
    ## (`(A, B) := m`, `(a, b) = v`, `(x) : T`) directly abuts this expression; that group is the next
    ## declaration, not a call postfix (`paren_group_is_binding`, the same lookahead `parse_decl` uses),
    ## and is left for the caller EXACTLY as before — so every accepted program parses byte-identically.
    ## The guard is an ALLOWLIST, not a denylist: it fires only when the base is one of the shapes a
    ## call postfix is UNAMBIGUOUSLY applied to — an element read `a[i]`, a call result `f()`, a field
    ## read `s.f`, a load `deref(p)`, a sub-view `a[lo..hi]`, a `x?`. Everything else that can reach a
    ## `(` here is a parser RE-ENTRY, not a call: a bare `Var` is a name an enclosing arm/pattern parser
    ## re-reads (a comptime-match KIND arm `Array(_) => …` is seen this way while a nested `match` arm
    ## body is parsed — the parenthesized `(add1)(41)` form is caught in `p_factor` instead, where the
    ## parentheses are still visible), and a `CompField` is the COMPTIME-VARIANT PATTERN `T.(v)(pa)`
    ## (the enum derives in `lib/base/derive.al` / `lib/alloc/fmt.al`), whose trailing `(pa)` is
    ## the arm's payload BINDING list.
    ## SUPPORTED since this lane: an ELEMENT callee `fs[i](x)` / `t.fs[0](x)` — see `p_ecallee` for the
    ## representation (argument 0 IS the callee expression; the callee NAME SPAN is borrowed from the
    ## chain's ROOT VARIABLE and recorded in `ast::ecallee_mark`). Every OTHER non-name callee keeps the
    ## located reject: a call RESULT `mk()(x)` (its borrowed root name would be the inner call's callee,
    ## whose declared ARITY `check` would then compare against this call's argument count and wrong-reject
    ## — a sema dependency, not a lowering one), a `deref(p)(x)`, a sub-view, a `x?` (no fn TYPE is
    ## recoverable for those, so the arity could not be checked), and any chain with no root `Var`.
    if cur(pc).kind == 10 {
      mut callee := false
      if expr_is_index(base) { callee = true }
      if expr_is_call(base) { callee = true }
      if expr_is_field(base) { callee = true }
      if expr_is_deref(base) { callee = true }
      if expr_is_slice(base) { callee = true }
      if expr_is_try(base) { callee = true }
      nextdecl := paren_group_is_binding(pc)
      if nextdecl { callee = false }
      adj := tok_adjacent(pc, pc.idx)
      if adj == false { callee = false }
      if callee {
        mut done := false
        if expr_is_index(base) {
          rn := expr_root_name(base)
          if rn.n != 0 {
            base = p_ecallee(pc, base, rn)
            done = true
          }
        }
        if done == false {
          reject_at(pc, "selfhost: FN-6 - a call through this callee shape is unsupported: only an ELEMENT callee rooted in a named place works (`fs[i](x)`, `t.fs[0](x)`). Bind the callee to a name first: `g := <callee>` then `g(args)`", cur(pc).start)
        }
        ## a FURTHER adjacent `(` — a call applied to THIS call's result — is the still-unsupported
        ## call-result callee: reject rather than silently drop the trailing argument list.
        if cur(pc).kind == 10 {
          if tok_adjacent(pc, pc.idx) {
            if paren_group_is_binding(pc) == false {
              reject_at(pc, "selfhost: FN-6 - a call through a CALL RESULT (`f(a)(b)`) is unsupported: bind the result to a name first (`g := f(a)` then `g(b)`)", cur(pc).start)
            }
          }
        }
      }
    }
    base
}

## FN-6 — parse the argument list of a call through a PARENTHESIZED BARE NAME (`(add1)(41)`) and build
## the ORDINARY named `Expr::Call` for it. The cursor sits on the `(` of the argument list; `nm` is the
## name span the group parenthesized. Byte-identical to the ident branch's own argument loop — the node
## is exactly the one `add1(41)` produces, so nothing downstream can tell the two spellings apart.
p_pcall := fn(in out pc : PC, nm : NSpan) -> ptr(mut Expr) {
  pc.idx = pc.idx + 1                                    ## '('
  mut nargs := 0
  mut ahead := 0
  mut atail := 0
  while cur(pc).kind != 11 and cur(pc).kind != 0 {
    ae := p_or(pc)
    anew := gnode(pc.arena, Arg(e = ae, next = 0))
    if ahead == 0 { ahead = anew } else {
      gp := arg_p(atail)
      gold := deref(gp)
      gupd := Arg(e = gold.e, next = anew)
      deref(gp) = gupd
    }
    atail = anew
    nargs += 1
    if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }         ## ',' between args
  }
  pc.idx = pc.idx + 1                                    ## ')'
  newnode(pc.arena, Expr.Call(nm.s, nm.n, nargs, ahead))
}

## FN-6 — parse the argument list of a call through an EXPRESSION callee and build its node. The cursor
## sits on the `(`; `callee` is the already-parsed callee expression and `rn` its ROOT VARIABLE name span.
##
## REPRESENTATION (see `ast::ecallee_mark` for why): an ORDINARY `Expr::Call` whose ARGUMENT 0 IS THE
## CALLEE EXPRESSION and whose callee NAME SPAN is the root variable's — the SAME node shape the UFCS
## desugar above builds for `recv.m(args)`. So every generic AST walker (the lambda LIFT, the capture
## analysis, the generic MONO collection, `check`'s unbound-name walk) recurses into the callee and the
## arguments exactly as it does for any call, and `check` accepts the borrowed name because it resolves
## to a bound local/param. `ecallee_mark` records the site so the LOWER — and only the lower — can tell
## it apart from a genuine call to that name (`fs(10)`), which it must, since the borrowed name usually
## HAS a slot of its own (the array's base).
p_ecallee := fn(in out pc : PC, callee : ptr(mut Expr), rn : NSpan) -> ptr(mut Expr) {
  pc.idx = pc.idx + 1                                    ## '('
  mut nargs := 0
  chead := gnode(pc.arena, Arg(e = callee, next = 0))
  mut atail := chead
  while cur(pc).kind != 11 and cur(pc).kind != 0 {
    ae := p_or(pc)
    anew := gnode(pc.arena, Arg(e = ae, next = 0))
    gp := arg_p(atail)
    gold := deref(gp)
    gupd := Arg(e = gold.e, next = anew)
    deref(gp) = gupd
    atail = anew
    nargs += 1
    if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }         ## ',' between args
  }
  pc.idx = pc.idx + 1                                    ## ')'
  ecallee_mark(rn.s)
  newnode(pc.arena, Expr.Call(rn.s, rn.n, nargs + 1, chead))
}

## The BASE expression of a `Field(base, f)` node (0 for anything else) — its own single-arm probe, like
## `index_parts` (a nested deref-match mis-lowers under the seed).
field_base_expr := fn(e : ptr(Expr)) -> ptr(Expr) {
  match deref(e) {
    Expr::Field(b, fs, fl) => { b }
    _ => { unchecked bitcast(ptr(Expr), 0) }
  }
}

## The ROOT VARIABLE name span of a postfix chain — the head identifier of `a[i]`, `t.f[i]`, `a[i][j]`,
## `t.a.b[i]`. 0/0 when the chain does not bottom out in a bare `Var` (a call result, a `deref`, a
## literal head), which is exactly when the expression-callee form is NOT taken.
expr_root_name := fn(e : ptr(Expr)) -> NSpan {
  mut node := unchecked bitcast(ptr(Expr), e)
  mut r := NSpan(s = 0, n = 0)
  mut going := true
  mut steps := 0
  while going and steps < 16 {
    v := enum_type_span(node)
    if v.n != 0 {
      r = v
      going = false
    } else {
      ip := index_parts(node)
      if unchecked bitcast(usize, ip.b) != 0 {
        node = ip.b
      } else {
        fb := field_base_expr(node)
        if unchecked bitcast(usize, fb) != 0 { node = fb } else { going = false }
      }
    }
    steps = steps + 1
  }
  r
}

## A type-name span (the `E` of `E.V(...)`) recovered from a base `Var` expression — the
## deref-match on the base pointer stays in a helper taking the pointer directly (the
## lowerable shape, mirroring lower.al's `struct_lit_info`). A non-`Var` base yields 0/0
## (an enum ctor on a non-type base is not part of the supported grammar).
NSpan := struct { s : usize, n : usize }
enum_type_span := fn(base : ptr(Expr)) -> NSpan {
  match deref(base) {
    Expr::Var(s, n) => { NSpan(s = s, n = n) }
    _ => { NSpan(s = 0, n = 0) }
  }
}

## The trailing FIELD name of a `Field` expr (`typeinfo(T).fields` → "fields") — used by the
## `comptime for` parser to tell `.fields` from `.variants`. 0/0 if `e` is not a `Field`.
field_tail_name := fn(e : ptr(Expr)) -> NSpan {
  match deref(e) {
    Expr::Field(b, fs, fl) => { NSpan(s = fs, n = fl) }
    _ => { NSpan(s = 0, n = 0) }
  }
}

## Is `e` an integer literal? Used to tell a mis-lexed FLOAT (`1.5` → `1 . 5`, base is `Num`) apart
## from tuple indexing `t.N` (base is a place) in the `.<int>` postfix.
expr_is_num := fn(e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Num(v, s, n) => { true }
    _ => { false }
  }
}
## Whether `e` is an inline function VALUE (FN-6 lambda) — used to reject an immediately-invoked
## `(fn(…){…})(args)` fail-loud (the call postfix on a non-name value is not representable).
expr_is_lambda := fn(e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Lambda(lfp, lph, lrs, lrl, lbh, lval) => { true }
    _ => { false }
  }
}
## Base kinds a call postfix is UNAMBIGUOUSLY applied to (see `p_field`'s trailing guard): an element
## read `a[i]`, a call result `f()`, a field read `s.f`, a load `deref(p)`, a sub-view `a[lo..hi]`, a
## `x?`. Each is its own single-arm probe (the shape the lean lower resolves), never one wide match.
expr_is_index := fn(e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Index(ib, ii) => { true }
    _ => { false }
  }
}
expr_is_call := fn(e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Call(cs, cl, cn, ca) => { true }
    _ => { false }
  }
}
expr_is_field := fn(e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Field(fb, fs, fl) => { true }
    _ => { false }
  }
}
expr_is_deref := fn(e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Deref(dp) => { true }
    _ => { false }
  }
}
expr_is_slice := fn(e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Slice(sb, sl, sh) => { true }
    _ => { false }
  }
}
expr_is_try := fn(e : ptr(Expr)) -> bool {
  match deref(e) {
    Expr::Try(ti) => { true }
    _ => { false }
  }
}

## The base + index expression pointers of an `Index(base, idx)` node, recovered from the
## `Index` expr that `p_field` builds for `arr[i]`. The deref-match on the `Index` pointer
## stays in this helper (a direct param) — the lowerable shape (like `enum_type_span`). A
## non-`Index` expr yields both pointers null (0) — not part of the supported store grammar.
IxParts := struct { b : ptr(Expr), i : ptr(Expr) }
index_parts := fn(e : ptr(Expr)) -> IxParts {
  match deref(e) {
    Expr::Index(b, i) => { IxParts(b = b, i = i) }
    _ => {
      z := unchecked bitcast(ptr(Expr), 0)
      IxParts(b = z, i = z)
    }
  }
}

## The array base + index + field-name span of a `Field(Index(arr, idx), fs, fl)` node — the
## parsed shape of `a[i].f`. Used to record an `IndexFieldAssign` STORE. The two nested
## deref-matches (`Field` then its base `Index`) stay isolated in pointer-PARAM helpers — the
## lowerable shape. A non-`Field`/non-`Index`-base expr yields null pointers (not in the grammar).
IFParts := struct { arr : ptr(Expr), idx : ptr(Expr), fs : usize, fl : usize }
idx_field_parts := fn(e : ptr(Expr)) -> IFParts {
  z := unchecked bitcast(ptr(Expr), 0)
  mut res := IFParts(arr = z, idx = z, fs = 0, fl = 0)
  match deref(e) {
    Expr::Field(base, fs, fl) => {
      ip := index_parts(base)
      res = IFParts(arr = ip.b, idx = ip.i, fs = fs, fl = fl)
    }
    _ => {}
  }
  res
}

## SYN-4 (Grammar §2.6) — the operator-name BINDING-HEAD exception. A binary-operator glyph at the
## cursor whose IMMEDIATELY-following token is `:=` (kind 5) or `:` (kind 8) is the NAME of an
## operator-function declaration (`+ := fn(…)`, `/ : T = …`), not a continuation of the expression
## on the preceding line — `op :=` / `op :` is never a valid mid-expression sequence (an operand can
## begin with neither `:=` nor `:`). Stopping the binary-operator fold here is therefore correct
## WITHOUT any newline token: the preceding newline stays a statement/declaration separator (the
## Go/Swift-style deterministic continuation rule, restricted to the sub-case that needs no line
## tracking). This resolves the mis-parse of an operator-def decl written on its own line after a
## bare-identifier value decl (`f64 := bits64` ⏎ `+ := fn(…)` was folded into `bits64 + fn(…)`,
## producing a parse error). Fixpoint-neutral: current src/lib never place `op :=`/`op :` in a
## continuation position (such input cannot parse), so the guard is dormant on the self-host tree.
op_binding_head := fn(pc : PC) -> bool {
  k := tok_at(pc, pc.idx + 1).kind
  return k == 5 or k == 8
}

## term := postfix { ('*' | '/' | '%') postfix }
## `%` (modulo, token kind 29) binds at the same precedence as `*`/`/` (the term level);
## its `Bin` carries op byte 29 (the same kind the lexer/sema/lower agree on).
p_term := fn(in out pc : PC) -> ptr(mut Expr) {
    mut lhs := p_field(pc)
    while (cur(pc).kind == 18 or cur(pc).kind == 19 or cur(pc).kind == 29) and not op_binding_head(pc) {
      k := cur(pc).kind
      pc.idx = pc.idx + 1
      rhs := p_field(pc)
      lhs = newnode(pc.arena, Expr.Bin(k, lhs, rhs))
    }
    lhs
}

## expr := term { ('+' | '-') term }
p_expr := fn(in out pc : PC) -> ptr(mut Expr) {
    mut lhs := p_term(pc)
    while (cur(pc).kind == 16 or cur(pc).kind == 17) and not op_binding_head(pc) {
      k := cur(pc).kind
      pc.idx = pc.idx + 1
      rhs := p_term(pc)
      lhs = newnode(pc.arena, Expr.Bin(k, lhs, rhs))
    }
    lhs
}

## The bitwise operators (kinds 34 `&`, 35 `|`, 36 `^`) occupy THREE DISTINCT precedence
## tiers per Grammar §4 (levels 5/6/7), tightest→loosest: `&` (5) > `^` (6) > `|` (7), each
## left-associative, all sitting BELOW arithmetic (`+`/`-`/`*`/`/`) and ABOVE comparison. So
## `a | b & c` = `a | (b & c)` (NOT `(a|b)&c`), `a ^ b & c` = `a ^ (b & c)`, `a | b ^ c` =
## `a | (b ^ c)`; and `status / 256 & 255` is `(status/256) & 255`, `a & b == c` is
## `(a & b) == c`. (Earlier these collapsed into ONE left-assoc tier — a defect vs the spec:
## unparenthesized `a | b & c` mis-grouped as `(a|b)&c`.) The node is `Bin(kind, l, r)`
## carrying the token kind as its op byte; the lower emits `andq`/`orq`/`xorq`. Shift operators
## are intentionally absent — the language has none (OP-2/OP-6: named `shl`/`shr`/… ops). Every
## mixed-bitwise site in `src/`/`lib/` is fully parenthesized, so the tier split is
## fixpoint-neutral. Grammar §4 P3.

## band := expr { '&' expr }  — bitwise AND (kind 34), TIGHTEST bitwise tier (§4 level 5),
## just above arithmetic.
p_band := fn(in out pc : PC) -> ptr(mut Expr) {
    mut lhs := p_expr(pc)
    while cur(pc).kind == 34 and not op_binding_head(pc) {
      pc.idx = pc.idx + 1
      rhs := p_expr(pc)
      lhs = newnode(pc.arena, Expr.Bin(34, lhs, rhs))
    }
    lhs
}

## bxor := band { '^' band }  — bitwise XOR (kind 36), §4 level 6 (between `&` and `|`).
p_bxor := fn(in out pc : PC) -> ptr(mut Expr) {
    mut lhs := p_band(pc)
    while cur(pc).kind == 36 and not op_binding_head(pc) {
      pc.idx = pc.idx + 1
      rhs := p_band(pc)
      lhs = newnode(pc.arena, Expr.Bin(36, lhs, rhs))
    }
    lhs
}

## bor := bxor { '|' bxor }  — bitwise OR (kind 35), LOOSEST bitwise tier (§4 level 7),
## just below comparison.
p_bor := fn(in out pc : PC) -> ptr(mut Expr) {
    mut lhs := p_bxor(pc)
    while cur(pc).kind == 35 and not op_binding_head(pc) {
      pc.idx = pc.idx + 1
      rhs := p_bxor(pc)
      lhs = newnode(pc.arena, Expr.Bin(35, lhs, rhs))
    }
    lhs
}

## cmp := 'not' cmp | bor [ ('==' | '<' | '>' | '<=' | '>=' | '!=') bor ]
## The comparison level sits below the bitwise tiers (§4 level 8). Comparisons are
## NON-ASSOCIATIVE (Grammar §4): AT MOST ONE comparison operator per level — `a < b < c` is
## ill-formed and REJECTED at the Parse stage (use `(a < b) == c` to group explicitly). The
## operator kinds are the lexer's: 20 `==`, 24 `<`, 25 `>`, 26 `<=`, 27 `>=`, 28 `!=`; the node
## is a `Bin` carrying that kind (a later sema/eval pass gives it boolean meaning).
## A leading `not` (keyword) is boolean negation — a prefix unary that binds tighter than
## `and`/`or` but applies to a whole comparison (`not a == b` = `not (a == b)`); it parses
## another `p_cmp` operand and yields `Bin(42, operand, dummy)` (op byte 42 = `not`; the lower
## negates ONLY the left operand, so the right slot is a fresh `Num(0)` placeholder). The right
## slot MUST NOT reuse `operand` — an AST walk that visits both children (e.g. the `.rodata`
## string-literal pass) would then emit `operand`'s literals TWICE, producing duplicate `.Lstr`
## labels (the assembler rejects a redefined symbol).
p_cmp := fn(in out pc : PC) -> ptr(mut Expr) {
    if tok_kw(pc, "not") {
      pc.idx = pc.idx + 1
      operand := p_cmp(pc)
      dummy := newnode(pc.arena, Expr.Num(0, 0, 0))
      return newnode(pc.arena, Expr.Bin(42, operand, dummy))
    }
    mut lhs := p_bor(pc)
    if (cur(pc).kind == 20 or cur(pc).kind == 24 or cur(pc).kind == 25
      or cur(pc).kind == 26 or cur(pc).kind == 27 or cur(pc).kind == 28) and not op_binding_head(pc) {
      k := cur(pc).kind
      ## `<<` / `>>` (two adjacent `<` or `>`, kind 24/25) is an attempted GLYPH shift — Alatyr has none
      ## (OP-2/OP-6: shifts are the named call/UFCS ops). Left unchecked the second `<`/`>` mis-parsed as a
      ## comparison RHS and silently produced garbage. Fail LOUD with the fix. `<` then `-N` (compare with a
      ## negative) is `<` then kind-17, not another `<`, so this fires only on a real `<<`/`>>`. src uses no
      ## `<<`/`>>` → dormant → fixpoint-neutral.
      if (k == 24 or k == 25) and pc.idx + 1 < ntoks(pc) and tok_at(pc, pc.idx + 1).kind == k {
        panic("selfhost: bit shifts have no `<<`/`>>` glyph — use the named call/UFCS operations `shl(v, n)` / `shr(v, n)` (OP-6)")
      }
      pc.idx = pc.idx + 1
      rhs := p_bor(pc)
      lhs = newnode(pc.arena, Expr.Bin(k, lhs, rhs))
      ## Comparisons are NON-ASSOCIATIVE (Grammar §4 level 8): a SECOND comparison operator at
      ## this level (`a < b < c`) is ill-formed — REJECT rather than fold left-assoc. A
      ## legitimately-parenthesized `(a < b) == (c < d)` is unaffected: each `<` is consumed
      ## inside its own parenthesized primary, so only the single top-level `==` reaches here.
      if (cur(pc).kind == 20 or cur(pc).kind == 24 or cur(pc).kind == 25
        or cur(pc).kind == 26 or cur(pc).kind == 27 or cur(pc).kind == 28) and not op_binding_head(pc) {
        panic("selfhost: comparison operators are non-associative — `a < b < c` is ill-formed; parenthesize explicitly, e.g. `(a < b) == c` (Grammar §4)")
      }
    }
    lhs
}

## and := cmp { 'and' cmp }  — boolean conjunction, BELOW comparison (looser than `<`/`==`),
## tighter than `or`. `and`/`or`/`not` are keywords (the lexer tags them kind 2, resolved by
## lexeme via `tok_kw`). The node is `Bin(40, l, r)` (op byte 40 = `and`); lower short-circuits.
p_and := fn(in out pc : PC) -> ptr(mut Expr) {
    mut lhs := p_cmp(pc)
    while tok_kw(pc, "and") {
      pc.idx = pc.idx + 1
      rhs := p_cmp(pc)
      lhs = newnode(pc.arena, Expr.Bin(40, lhs, rhs))
    }
    lhs
}

## or := and { 'or' and }  — boolean disjunction, the LOOSEST expression level (the new
## top of the expression grammar). The node is `Bin(41, l, r)` (op byte 41 = `or`); lower
## short-circuits. Every "full expression" position (if-cond, match-scrutinee, call arg,
## struct-field / enum-payload value, paren body, assign / return / while-cond / trailing
## return) parses through `p_or`, so a boolean expression is accepted wherever a value is.
p_or := fn(in out pc : PC) -> ptr(mut Expr) {
    mut lhs := p_and(pc)
    while tok_kw(pc, "or") {
      pc.idx = pc.idx + 1
      rhs := p_and(pc)
      lhs = newnode(pc.arena, Expr.Bin(41, lhs, rhs))
    }
    lhs
}

## Whether the token at index `i` starts a statement (a lightweight, position-explicit form
## of `stmt_starts` used for the brace-peek that distinguishes a STATEMENT-position `if`/`match`
## — whose branch/arm bodies are statement lists — from a tail EXPRESSION `if`/`match` whose
## body is a single value expression). A statement begins with a `while`/`return`/`if`/`match`
## keyword (kind 2, lexeme), an `ident :=`/`ident =` (kinds 5/21), or a field mutation
## `ident . ident =`. Bounds-guarded against the end of the token stream.
tok_kw_at := fn(pc : PC, i : usize, w : str) -> bool {
  nt := ntoks(pc)
  if i >= nt { return false }
  t := tok_at(pc, i)
  if t.kind != 2 { return false }
  str_eq(str_at(pc.src + t.start, t.len), w)
}
stmt_starts_at := fn(pc : PC, i : usize) -> bool {
  nt := ntoks(pc)
  if i >= nt { return false }
  if tok_kw_at(pc, i, "while") { return true }
  if tok_kw_at(pc, i, "for") { return true }
  if tok_kw_at(pc, i, "loop") { return true }
  if tok_kw_at(pc, i, "break") { return true }
  if tok_kw_at(pc, i, "continue") { return true }
  if tok_kw_at(pc, i, "return") { return true }
  if tok_kw_at(pc, i, "defer") { return true }
  if tok_kw_at(pc, i, "mut") { return true }
  if tok_kw_at(pc, i, "if") { return true }
  if tok_kw_at(pc, i, "match") { return true }
  if tok_at(pc, i).kind != 1 { return false }
  ## Keep this brace-peek classifier aligned with the full statement-list classifier: a
  ## `deref(p) = v` branch is a statement even though its head is followed by `(`, not `=`.
  ## Reuse the balanced lookahead at this arbitrary token index rather than copying its table.
  mut probe := pc
  probe.idx = i
  if deref_assign_starts(probe) { return true }
  if i + 1 >= nt { return false }
  k1 := tok_at(pc, i + 1).kind
  ## `ident : T = v` — a typed binding (the `:` after the name).
  if k1 == 8 { return true }
  if k1 == 5 or is_assign_tok(k1) { return true }
  ## `ident [ … ] =` — an array element-write statement (bracket-balanced scan to the `]`,
  ## then an `=`). Also a DEEP array-element write `ident [ … ] . f … = …` / `ident [ … ] . f [ … ] = …`
  ## (a postfix chain of `.field` / `[ … ]` after the first `]`, ending in `=`) — the store dual whose
  ## LHS begins `ident [`. A tail `ident [ … ]` / `ident [ … ] . f + …` READ (no `=`) is NOT a
  ## statement start (the chain scan stops at the non-place token → the closing `== 21` check fails).
  if k1 == 14 {
    mut j := i + 1               ## the '['
    mut depth := 0
    while j < nt {
      kk := tok_at(pc, j).kind
      if kk == 14 { depth = depth + 1 }
      else if kk == 15 {
        depth = depth - 1
        if depth == 0 { j = j + 1; break }
      }
      j += 1
    }
    if j >= nt { return false }
    ## consume any postfix `.field` / `[ … ]` chain after the first `]`; stop at the first non-place token.
    mut cgoing := true
    while cgoing and j < nt {
      kk := tok_at(pc, j).kind
      if kk == 22 {
        if j + 1 >= nt or tok_at(pc, j + 1).kind != 1 { cgoing = false } else { j = j + 2 }
      } else if kk == 14 {
        mut d3 := 0
        while j < nt {
          k3 := tok_at(pc, j).kind
          if k3 == 14 { d3 = d3 + 1 }
          else if k3 == 15 { d3 = d3 - 1; if d3 == 0 { j = j + 1; break } }
          j += 1
        }
      } else { cgoing = false }
    }
    if j >= nt { return false }
    return is_assign_tok(tok_at(pc, j).kind)
  }
  if k1 != 22 { return false }
  if i + 3 >= nt { return false }
  k2 := tok_at(pc, i + 2).kind
  k3 := tok_at(pc, i + 3).kind
  k2 == 1 and is_assign_tok(k3)
}

## Is the `if` under the cursor a STATEMENT (its then-block body is a statement list) rather
## than a tail EXPRESSION (a single value expr in the braces)? Scan forward from `if` to the
## first `{` (kind 12 — the cond in this grammar has no braces, only int/var/paren/arith/cmp)
## and peek the token just inside it: if that token starts a statement (`return`/`while`/`if`/
## `match`/`ident :=`/`ident =`/`ident . ident =`), it is a statement-position if. So
## `if a < b { b } else { a }` (body `b`, not a statement) parses as a tail if-EXPRESSION, while
## `if n < 10 { return 1 }` parses as a statement-if.
if_is_stmt_form := fn(pc : PC) -> bool {
  nt := ntoks(pc)
  mut i := pc.idx
  while i < nt and tok_at(pc, i).kind != 12 { i = i + 1 }
  ## i is at the first '{' (or past end); peek the token after it — a statement body (`return`,
  ## `x = …`, a nested `if`/`while`, …) marks a statement-if.
  if stmt_starts_at(pc, i + 1) { return true }
  ## Scan the then-block `{ … }` for two signals. (1) Is the branch a statement LIST rather than a
  ## single value expression? The lean parser has no multi-statement block-expression, so a value-if
  ## branch is ONE expression; two STATEMENTS are detected as two adjacent primaries with NO binary
  ## operator between them — a value-END token (`)` `]` ident int str) at the block's top level
  ## immediately FOLLOWED by a value-START token (ident kw int str). So `{ f(a)  g(b) }` (a call then
  ## a call = two statements → statement-if) is distinguished from `{ f(a) + g(b) }` (one expression,
  ## `+` between → value-if) and `{ at(b, i) }` (one call → value-if). Top level = outside nested
  ## braces/parens/brackets. (2) Whether an `else` follows the matching `}` — an `if` with NO `else`
  ## yields no value, so it cannot be a tail value-if (e.g. the guard `if oom { panic(…) }`); without
  ## this the if-EXPRESSION parser would blindly consume a non-existent `else { … }` and drift.
  ## The scan traverses the WHOLE `if … else if … else …` chain (re-entering on each `else`): when
  ## a top-level branch `}` is followed by `else`, depth drops to 0 (between branches) and the next
  ## branch's `{` re-raises it. Two terminal signals decide: (3) a value-END/value-START adjacency at
  ## a branch's top level = a statement LIST → statement-if (returns immediately); (4) what follows the
  ## ENTIRE chain — a tail value-if is the LAST thing in its block (only `}`/EOF after), so an `if`
  ## whose chain is FOLLOWED BY MORE CODE (a call, a binding, another statement) is a statement-if
  ## even when every branch is a single call (e.g. emit_fn's `if renum { emit_enum_value(…) } else if
  ## rstruct { … } else { … }` before the trailing `emit_label(…)`). Only a tail if-with-else falls
  ## through to the value-if classification.
  mut j := i + 1
  mut depth := 1
  mut pdepth := 0
  mut bdepth := 0
  mut prev := 0
  mut closed := false
  mut had_terminal_else := false
  while j < nt {
    k := usize(tok_at(pc, j).kind)
    if k == 12 {
      depth = depth + 1
      ## (1') Signal (1) applied to EVERY branch of the chain, not only the first. `depth == 1`
      ## immediately AFTER the increment means depth was 0, and depth is 0 only BETWEEN branches
      ## (the `}` handler below drops it there when an `else` follows) — so this `{` opens a LATER
      ## branch. Peek the token just inside it with the SAME predicate the pre-loop check applies to
      ## the first branch: a statement head there means that branch is a statement LIST, so the whole
      ## chain is a statement-if. Without this, a chain whose FIRST branch body is a single bare CALL
      ## (not a statement head, so the pre-loop peek says nothing) and whose LATER branches are
      ## assignments / nested ifs / `return`s fell through to signal (4) and was classified as a tail
      ## value-if whenever it was the LAST thing in its block. That is the desync: `p_or` then read
      ## the statement branches as value expressions, its blind `pc.idx + 1` skips walked over the
      ## `=`, and the cursor drifted OUT of the enclosing function — surfacing as
      ## `parse: unexpected token `=` (expected `:=`)` at the next top-level-looking line, many lines
      ## PAST the construct. Measured on this compiler before the fix: rejected in a `while`/`for`/
      ## `loop` body, an `unchecked` / `alloc::with` block, a nested `else if` arm, a lambda body and
      ## a function's tail position; and SILENTLY WRONG (I11) in two shapes — `else { if … else … }`
      ## last in a `while` body dropped both assignments (returned 0 where 5 was due), and a chain
      ## last in a `match` arm took the MIDDLE arm where the terminal `else` was the true one
      ## (returned 5 where 6 was due).
      if depth == 1 and stmt_starts_at(pc, j + 1) { return true }
    }
    else if k == 13 {
      if depth == 1 {
        ## closing a top-level branch block; continue through an `else` / `else if` chain
        if tok_kw_at(pc, j + 1, "else") {
          ## a plain `else {` is a TERMINAL else (the chain yields a value in every case →
          ## a value-if is possible); an `else if` is a conditional continuation and CANNOT
          ## complete a value-if on its own (no value when all conditions are false).
          if not tok_kw_at(pc, j + 2, "if") { had_terminal_else = true }
          depth = 0                  ## between branches; the else's `{` re-raises depth
        } else {
          closed = true
          j += 1
          break
        }
      } else {
        depth = depth - 1
      }
    }
    else if k == 10 { pdepth = pdepth + 1 }
    else if k == 11 { pdepth = pdepth - 1 }
    else if k == 14 { bdepth = bdepth + 1 }
    else if k == 15 { bdepth = bdepth - 1 }
    if depth == 1 and pdepth == 0 and bdepth == 0 {
      pe := prev == 1 or prev == 3 or prev == 4 or prev == 11 or prev == 15
      cs := k == 1 or k == 2 or k == 3 or k == 4
      if pe and cs { return true }
      prev = k
    } else {
      prev = 0
    }
    j += 1
  }
  if not closed { return true }
  ## No terminal `else` (no `else` at all, or the chain ends in a conditional `else if`) → the
  ## construct yields no value in every case, so it is a statement-if.
  if not had_terminal_else { return true }
  ## Has a terminal `else`: a tail value-if is the last thing in its block (`}`/EOF follows the
  ## chain); anything else following means more statements come → a statement-if.
  kk := usize(tok_at(pc, j).kind)
  if kk == 13 or kk == 0 { return false }
  true
}

## Is the `match` under the cursor a STATEMENT (its arm bodies are statement lists `=> { … }`)
## rather than a tail EXPRESSION (`=> <cmp>`)? The first `{` after `match` is the MATCH block,
## so the differentiator is the FIRST arm: scan forward to the first `=>` (kind 38) and check
## whether the token after it is `{` (kind 12) — a statement-match arm body is braced, an
## expression-match arm body is a bare expression. So `match e { 0 => 1 ; _ => 2 }` parses as a
## tail match-EXPRESSION, while `match e { 0 => { r = 1 } … }` parses as a statement-match.
match_is_stmt_form := fn(pc : PC) -> bool {
  nt := ntoks(pc)
  mut i := pc.idx
  while i < nt and tok_at(pc, i).kind != 38 { i = i + 1 }
  ## i is at the first '=>' (or past end); a braced arm body (`{` after) is a statement match
  if i + 1 >= nt { return false }
  tok_at(pc, i + 1).kind == 12
}

## A function-body statement (used inside a fn binding's `{ … }`): `while <cmp> { <stmts> }`,
## a `for <i> in <lo> .. <hi> { <stmts> }` counted loop,
## an early `return <cmp>`, a statement-position `if <cmp> { <stmts> } [ else { <stmts> } ]`,
## Compound-assignment: the `Bin` op code for a compound-assign token kind, else -1 (not compound).
## Grammar §130 line 287 lists EIGHT glyphs and OP-2 pins the set as exactly the binary glyph
## operators `+ - * / % & | ^` (no `and=`/`or=`, no shift compound). The token kind → `Bin` op map:
## `+=`(40)→`+`(16), `-=`(41)→`-`(17), `*=`(44)→`*`(18), `/=`(45)→`/`(19),
## `%=`(47)→`%`(29), `&=`(48)→`&`(34), `|=`(49)→`|`(35), `^=`(50)→`^`(36).
## Lets `x op= e` desugar to `Assign(x, Bin(op, x, e))` (and the field form to `FieldAssign`)
## uniformly across all eight operators. The last four were absent both here and in the lexer, so
## `x &= m` matched no statement head at all: the line fell to the trailing-return expression path
## and the STORE was SILENTLY DROPPED — `x` kept its old value with a clean compile (I11).
compound_op := fn(k : usize) -> i64 {
  if k == 40 { return 16 }
  if k == 41 { return 17 }
  if k == 44 { return 18 }
  if k == 45 { return 19 }
  if k == 47 { return 29 }
  if k == 48 { return 34 }
  if k == 49 { return 35 }
  if k == 50 { return 36 }
  return -1
}

## Is token kind `k` an ASSIGNMENT operator — the plain store `=` (21) or any of the eight
## compound-assign glyphs? The single predicate the statement-head lookaheads share, so the
## accepted set cannot drift between them (it did: three sites each spelled out four kinds).
is_assign_tok := fn(k : usize) -> bool {
  if k == 21 { return true }
  return compound_op(k) >= 0
}

## Is the place expression `e` safely RE-READABLE — may the compound-assignment desugar
## `place op= rhs` -> `place = place op rhs` clone the place as the READ and still honour
## Memory §1's normative "the place is evaluated once"? A place built only from a name, an
## integer (a tuple projection index), a field/tuple projection, an index, a dereference, or
## arithmetic over those re-reads identically: nothing observable can happen twice. The test is
## a WHITELIST, not a call blacklist, so a place shape this parser does not enumerate FAILS it
## rather than silently becoming a double evaluation. `a[f()] op= e` is therefore a located
## reject, never the second `f()` call the textual rewrite `a[f()] = a[f()] + e` performs
## (measured on the seed: the rewrite runs `f` twice, the compound form must run it once).
place_reread_ok := fn(e : ptr(Expr)) -> bool {
  if unchecked bitcast(usize, e) == 0 { return false }
  mut r := false
  match deref(e) {
    Expr::Var(vs, vn) => { r = true }
    Expr::Num(nv, ns, nn) => { r = true }
    Expr::Field(fb, fs, fl) => { r = place_reread_ok(fb) }
    Expr::Index(ib, ix) => { r = place_reread_ok(ib) and place_reread_ok(ix) }
    Expr::Deref(di) => { r = place_reread_ok(di) }
    Expr::Bin(bop, bl, br) => { r = place_reread_ok(bl) and place_reread_ok(br) }
    _ => { r = false }
  }
  r
}

## The VALUE a place-assignment statement stores, given the already-parsed LHS place expression
## `place`. Consumes the assignment token and parses the right-hand side. For a plain `=` the
## value is the rhs; for a compound `op=` (Grammar §130 line 287) it is `Bin(op, <place>, rhs)`
## with the place READ cloned — OP-2's sugar, derived ONCE here so all the place forms share it.
## Every place form except a bare name and `name.field` used to require kind 21 in its
## statement-head lookahead, so `a[i] += 1`, `deref(p) += 1`, `t.0 += 1`, `o.i.v += 1` and
## `a[i].f += 1` matched NO statement head at all: each was parsed as the enclosing function's
## trailing RETURN expression and the STORE WAS SILENTLY DROPPED (measured: `a[1] += 2` on
## `[10,100,30]` left `a[1]` at 100 and compiled clean — a wrong value, I11).
p_place_val := fn(in out pc : PC, place : ptr(Expr)) -> ptr(mut Expr) {
  co := compound_op(cur(pc).kind)
  coff := cur(pc).start
  pc.idx = pc.idx + 1                   ## '=' or 'op='
  rhs := p_or(pc)
  if co < 0 { return rhs }
  if not place_reread_ok(place) {
    zr := reject_at(pc, "selfhost: compound assignment needs a re-readable place - Memory §1 evaluates the place ONCE, so a place holding a call (`a[f()] += 1`) cannot be desugared by re-reading it; bind the index to a local first", coff)
  }
  mut cok := true
  rd := clone_expr(pc.arena, place, ptr(mut cok))
  newnode(pc.arena, Expr.Bin(u8(co), rd, rhs))
}

## a statement-position `match <cmp> { <pat> => { <stmts> } ; … }`, a struct field mutation
## `var.field = <cmp>`, or `name (:= | =) <cmp>` (local binding / reassignment — both `Assign`).
## Returns the new statement's arena handle (its `next` is linked by `p_stmts`).
## ---- DEFER chain helpers (below) shall not be re-entered before this point ---------------------
## The next-statement handle (`nx`) of statement `h` — a parser-side chain walk (the safe READ mirror
## of `set_stmt_next`'s per-variant stores). EXHAUSTIVE over `Stmt` so the walk always terminates.
p_stmt_nx := fn(h : usize, a : rt::Arena) -> usize {
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::Assign(ns, nl, v, nx) => { nx }
    Stmt::While(c, b, nx) => { nx }
    Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { nx }
    Stmt::FieldPathAssign(pl, pv, nx) => { nx }
    Stmt::Return(rv, nx) => { nx }
    Stmt::If(c, th, el, nx) => { nx }
    Stmt::Match(sc, ah, nx) => { nx }
    Stmt::For(fns, fnl, flo, fhi, fb, nx) => { nx }
    Stmt::DerefAssign(p, v, nx) => { nx }
    Stmt::IndexAssign(b, i, v, nx) => { nx }
    Stmt::IndexFieldAssign(b, i, fs, fl, v, nx) => { nx }
    Stmt::Loop(b, nx) => { nx }
    Stmt::Unchecked(b, nx) => { nx }
    Stmt::AllocWith(ae, b, nx) => { nx }
    Stmt::Break(bv, bd, nx) => { nx }
    Stmt::Continue(cd, nx) => { nx }
    Stmt::ExprStmt(e, nx) => { nx }
    Stmt::CompIf(c, th, el, nx) => { nx }
    Stmt::CompFor(vs, vl, iv, b, nx) => { nx }
    Stmt::CompForRange(vs, vl, lo, hi, b, nx) => { nx }
    Stmt::CompMatch(sc, ah, nx) => { nx }
  }
}
## The LAST statement of the chain beginning at `h` (walks `.next`). For the zero-step case — every
## statement that ISN'T a `defer { }` block (a single node) — returns `h` unchanged, so a parent list
## linked via `set_stmt_next(arena, stmt_last(tail), s)` is byte-identical to the plain
## `set_stmt_next(arena, tail, s)` for ALL existing source. A `defer { }` desugars to a multi-node
## chain (`__deferblk()` → block statements → `__deferblkend()`), and this lets the parent list append
## to the chain's TAIL so the markers + block statements stay intact in the list.
stmt_last := fn(h : ptr(mut Stmt), a : rt::Arena) -> ptr(mut Stmt) {
  mut cur := unchecked bitcast(usize, h)
  mut res := h
  while unchecked bitcast(usize, res) != 0 {
    cur = unchecked bitcast(usize, res)
    res = unchecked bitcast(ptr(mut Stmt), p_stmt_nx(cur, a))
  }
  unchecked bitcast(ptr(mut Stmt), cur)
}
## Does expression `e` contain a `?` (Expr::Try) anywhere in its tree? A recursive scan used ONLY by
## the `defer { }` validator (`defer_stmts_clean`) to reject an early-exit (`?`) inside a cleanup block.
## Exhaustive over `Expr` (including an expression-position match's arm bodies and a value-position
## `loop`'s statement list) so a `?` at ANY depth within the block is caught. A LAMBDA's body is NOT
## recursed — a `?` inside a lambda early-exits the lambda, not the cleanup, so it is not a hazard.
defer_expr_try := fn(e : ptr(Expr)) -> bool {
  mut res := false
  match deref(e) {
    Expr::Try(inner) => { res = true }
    Expr::Bin(op, l, r) => { if defer_expr_try(l) or defer_expr_try(r) { res = true } }
    Expr::If(c, t, el) => { if defer_expr_try(c) or defer_expr_try(t) or defer_expr_try(el) { res = true } }
    Expr::Match(sc, ah) => { mut arm := ah ; while arm != 0 { am := deref(arm_p(arm)) ; if defer_expr_try(am.body) { res = true } ; arm = am.next } }
    Expr::Field(b, fs, fl) => { res = defer_expr_try(b) }
    Expr::Index(b, i) => { if defer_expr_try(b) or defer_expr_try(i) { res = true } }
    Expr::Deref(p) => { res = defer_expr_try(p) }
    Expr::AddrOf(p) => { res = defer_expr_try(p) }
    Expr::Unchecked(x) => { res = defer_expr_try(x) }
    Expr::Bitcast(x, ts, tl) => { res = defer_expr_try(x) }
    Expr::Slice(b, lo, hi) => { if defer_expr_try(b) or defer_expr_try(lo) or defer_expr_try(hi) { res = true } }
    Expr::Call(cs, cl, na, ah) => { mut g := ah ; while g != 0 { ga := deref(arg_p(g)) ; if defer_expr_try(unchecked bitcast(ptr(Expr), ga.e)) { res = true } ; g = ga.next } }
    Expr::StructLit(cs, cl, na, ah) => { mut g := ah ; while g != 0 { ga := deref(arg_p(g)) ; if defer_expr_try(unchecked bitcast(ptr(Expr), ga.e)) { res = true } ; g = ga.next } }
    Expr::EnumLit(es, el, vs, vl, na, ah) => { mut g := ah ; while g != 0 { ga := deref(arg_p(g)) ; if defer_expr_try(unchecked bitcast(ptr(Expr), ga.e)) { res = true } ; g = ga.next } }
    Expr::ArrayLit(na, ah) => { mut g := ah ; while g != 0 { ga := deref(arg_p(g)) ; if defer_expr_try(unchecked bitcast(ptr(Expr), ga.e)) { res = true } ; g = ga.next } }
    Expr::CompField(b, i) => { if defer_expr_try(b) or defer_expr_try(i) { res = true } }
    Expr::Loop(b) => { res = defer_stmts_clean(b) }
    _ => {}
  }
  res
}
## Validates a `defer { … }` block: TRUE iff it contains NO control flow that would skip the rest of
## the cleanup — no `return`/`break`/`continue` statement and no `?` expression, at ANY nesting depth
## (recursing into every nested statement block: while/loop/for/if/match-arm/unchecked/alloc-with and
## the comptime forms). A jump out of a cleanup would leave the remainder of the block unrun / jump
## into the enclosing scope's stale labels — a SILENT partial-cleanup miscompile; reject it (the defer
## handler panics). EXHAUSTIVE over `Stmt` so the walk always terminates.
defer_stmts_clean := fn(head : ptr(mut Stmt), a : rt::Arena) -> bool {
  mut s := head
  mut ok := true
  while s != 0 and ok {
    st := deref(stmt_p(Stmt, s))
    match st {
      Stmt::Return(rv, nx) => { ok = false ; s = nx }
      Stmt::Break(bv, bd, nx) => { ok = false ; s = nx }
      Stmt::Continue(cd, nx) => { ok = false ; s = nx }
      Stmt::While(c, b, nx) => { if defer_expr_try(c) or defer_stmts_clean(b, a) == false { ok = false } ; s = nx }
      Stmt::Loop(b, nx) => { if defer_stmts_clean(b, a) == false { ok = false } ; s = nx }
      Stmt::If(c, th, el, nx) => { if defer_expr_try(c) or defer_stmts_clean(th, a) == false or defer_stmts_clean(el, a) == false { ok = false } ; s = nx }
      Stmt::Match(sc, ah, nx) => { mut arm := ah ; while arm != 0 and ok { am := deref(arm_p(arm)) ; if defer_expr_try(sc) or defer_stmts_clean(am.body_stmts, a) == false { ok = false } ; arm = am.next } ; s = nx }
      Stmt::For(fns, fnl, flo, fhi, fb, nx) => { if defer_expr_try(flo) or defer_expr_try(fhi) or defer_stmts_clean(fb, a) == false { ok = false } ; s = nx }
      Stmt::DerefAssign(p, v, nx) => { if defer_expr_try(p) or defer_expr_try(v) { ok = false } ; s = nx }
      Stmt::IndexAssign(b, i, v, nx) => { if defer_expr_try(b) or defer_expr_try(i) or defer_expr_try(v) { ok = false } ; s = nx }
      Stmt::IndexFieldAssign(b, i, fs, fl, v, nx) => { if defer_expr_try(b) or defer_expr_try(i) or defer_expr_try(v) { ok = false } ; s = nx }
      Stmt::FieldAssign(bns, bnl, fns, fnl, fv, nx) => { if defer_expr_try(fv) { ok = false } ; s = nx }
      Stmt::FieldPathAssign(pl, v, nx) => { if defer_expr_try(pl) or defer_expr_try(v) { ok = false } ; s = nx }
      Stmt::Assign(ns, nl, v, nx) => { if defer_expr_try(v) { ok = false } ; s = nx }
      Stmt::ExprStmt(e, nx) => { if defer_expr_try(e) { ok = false } ; s = nx }
      Stmt::Unchecked(b, nx) => { if defer_stmts_clean(b, a) == false { ok = false } ; s = nx }
      Stmt::AllocWith(ae, b, nx) => { if defer_expr_try(ae) or defer_stmts_clean(b, a) == false { ok = false } ; s = nx }
      Stmt::CompIf(c, th, el, nx) => { if defer_expr_try(c) or defer_stmts_clean(th, a) == false or defer_stmts_clean(el, a) == false { ok = false } ; s = nx }
      Stmt::CompFor(vs, vl, iv, b, nx) => { if defer_stmts_clean(b, a) == false { ok = false } ; s = nx }
      Stmt::CompForRange(vs, vl, lo, hi, b, nx) => { if defer_expr_try(lo) or defer_expr_try(hi) or defer_stmts_clean(b, a) == false { ok = false } ; s = nx }
      Stmt::CompMatch(sc, ah, nx) => { mut arm := ah ; while arm != 0 and ok { am := deref(arm_p(arm)) ; if defer_expr_try(sc) or defer_stmts_clean(am.body_stmts, a) == false { ok = false } ; arm = am.next } ; s = nx }
    }
  }
  ok
}

## Recover the physical terminator of a local `name : T` declaration with NO initializer. The lexer
## intentionally emits no newline tokens, but the source span still gives us the statement boundary.
## Returning 0 means this is an initialized `name : T = v` or a non-typed assignment. This helper is
## deliberately limited to a declaration whose type and terminator share the same source line; a
## multiline type remains fail-loud rather than being guessed.
local_uninit_end := fn(pc : PC, ns : usize, nl : usize) -> usize {
  mut p := ns + nl
  end := p + 512
  mut c := (pc.src + p).str_at(1)
  while p < end and (c == " " or c == "\t" or c == "\r") {
    p += 1
    c = (pc.src + p).str_at(1)
  }
  if c != ":" { return 0 }
  p += 1
  mut depth := 0
  while p < end {
    c = (pc.src + p).str_at(1)
    if c == "(" or c == "[" { depth += 1 }
    if c == ")" or c == "]" {
      if depth > 0 { depth -= 1 }
    }
    if depth == 0 and c == "=" { return 0 }
    if depth == 0 and (c == "\n" or c == ";" or c == "}") { return p }
    p += 1
  }
  0
}

## The TOKEN COUNT of a leading module-path HEAD at the cursor — the `:: ident` pairs of
## `ident (:: ident)+` — or 0 when the cursor is not a qualified path.
qual_path_head_toks := fn(pc : PC) -> usize {
  if cur(pc).kind != 1 { return 0 }
  mut i := pc.idx
  mut h := 0
  while tok_at(pc, i + 1).kind == 7 and tok_at(pc, i + 2).kind == 1 { i = i + 2 ; h = h + 2 }
  h
}

## Is the cursor a QUALIFIED PLACE assignment — `geo::G = v`, `geo::G op= v`, `geo::TAB[i] = v`
## (Modules §2: `::` navigates namespaces, so a qualified module global is an ordinary place)? Returns
## the HEAD token count to skip, else 0. Skipping the head lets every statement form below see the
## FINAL segment exactly where it expects a bare name, and `lower` recovers the head by scanning the
## source immediately before that segment — the same source-metadata recovery `local_is_mut` and
## `decl_is_pub` use, so no bootstrap-sensitive AST field is added. Without this the line matched no
## statement head at all: it was parsed as a trailing RETURN expression and the STORE was silently
## dropped (`geo::G = 42` emitted a dead load and no store). `src/` writes no qualified global, so this
## branch is dormant for the self-host build.
qual_place_assign_head := fn(pc : PC) -> usize {
  h := qual_path_head_toks(pc)
  if h == 0 { return 0 }
  i := pc.idx + h                       ## the FINAL segment
  k := tok_at(pc, i + 1).kind
  if is_assign_tok(k) { return h }   ## = / += -= *= /= %= &= |= ^=
  if k != 14 { return 0 }                                              ## '['
  nt := ntoks(pc)
  mut j := i + 1
  mut depth := 0
  mut scanning := true
  while j < nt and scanning {
    kk := tok_at(pc, j).kind
    if kk == 14 { depth = depth + 1 }
    else if kk == 15 {
      depth = depth - 1
      if depth == 0 { j = j + 1 ; scanning = false }
    }
    if scanning { j += 1 }
  }
  if j >= nt { return 0 }
  if is_assign_tok(tok_at(pc, j).kind) { return h }
  0
}

p_stmt := fn(in out pc : PC) -> usize {
  ## `geo::G = …` / `geo::TAB[i] = …` — a QUALIFIED PLACE. Consume the module-path HEAD so every
  ## statement form below keys on the final segment (see `qual_place_assign_head`).
  qph := qual_place_assign_head(pc)
  if qph != 0 { pc.idx = pc.idx + qph }
  ## `@alloc(A) [mut] name := init` — the dynamic-allocation storage attribute (Memory §2.4):
  ## desugar to `name := alloc_into(A, init)`. `alloc_into` (base/alloc.al) allocates a `T` through the
  ## allocator value `A`, writes `init`, traps on capacity exhaustion (I11), and returns the binding's
  ## `Handle(T)` — so `name` binds `Handle(T)`, with `T` inferred from `init` (a struct/enum literal or a
  ## typed value; a bare scalar literal is a follow-up). The callee `alloc_into` is not a source token, so
  ## its span is synthesized (rebased) via `synth_ident_span`. `@alloc` never appears in `src/`, so this
  ## branch is dormant for the self-host build → the TOOL-1 fixpoint is byte-identical.
  if cur(pc).kind == 33 and tok_at(pc, pc.idx + 1).kind == 1 and str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "alloc") {
    pc.idx = pc.idx + 2                 ## '@' 'alloc'
    pc.idx = pc.idx + 1                 ## '('
    arena_e := p_or(pc)
    pc.idx = pc.idx + 1                 ## ')'
    if tok_kw(pc, "mut") { pc.idx = pc.idx + 1 }
    nm := cur(pc)
    pc.idx = pc.idx + 1                 ## binding name
    ## optional `: T` annotation — skip to the binding `:=` (kind 5) / `=` (kind 21).
    if cur(pc).kind == 8 { while cur(pc).kind != 5 and cur(pc).kind != 21 and cur(pc).kind != 0 { pc.idx = pc.idx + 1 } }
    pc.idx = pc.idx + 1                 ## ':=' / '='
    init_e := p_or(pc)
    ai_s := synth_ident_span(pc, "alloc_into")
    init_arg := gnode(pc.arena, Arg(e = init_e, next = 0))
    arena_arg := gnode(pc.arena, Arg(e = arena_e, next = init_arg))
    ## A bare integer-literal init has no inferable type (spec §3.4: a literal with no context takes the
    ## target's native SIGNED integer, `isize`). `alloc_into`'s `T` is inferred from `init` for a
    ## struct/enum literal or a typed var, but NOT for a bare `Num` — so for that case pass an EXPLICIT
    ## `isize` type argument (`alloc_into(isize, a, init)`, the working explicit-T path); otherwise keep
    ## the implicit-T form (`alloc_into(a, init)`).
    mut is_num := false
    match deref(init_e) { Expr::Num(nv, ns, nn) => { is_num = true } _ => {} }
    if is_num {
      ts := synth_ident_span(pc, "isize")
      ty_e := newnode(pc.arena, Expr.Var(ts, 5))
      ty_arg := gnode(pc.arena, Arg(e = ty_e, next = arena_arg))
      calln := newnode(pc.arena, Expr.Call(ai_s, 10, 3, ty_arg))
      return snode(pc.arena, Stmt.Assign(nm.start, nm.len, calln, 0))
    }
    callq := newnode(pc.arena, Expr.Call(ai_s, 10, 2, arena_arg))
    return snode(pc.arena, Stmt.Assign(nm.start, nm.len, callq, 0))
  }
  ## `unchecked { <stmts> }` — the STATEMENT verification-mode block (Grammar §130: `unchecked (expr |
  ## block)`). Parse the braced statement list and wrap it in `Stmt.Unchecked`; the lower lowers the
  ## body with `verify.checked` FALSE. Only the BLOCK form (a `{` follows `unchecked`) is a statement;
  ## the EXPRESSION form `unchecked <expr>` in value position stays in `p_factor` (unchanged), so `src/`
  ## — which uses only `unchecked { <expr> }` in value positions — is byte-identical (fixpoint-neutral).
  if tok_kw(pc, "unchecked") and tok_at(pc, pc.idx + 1).kind == 12 {
    pc.idx = pc.idx + 1                 ## 'unchecked'
    pc.idx = pc.idx + 1                 ## '{'
    ubody := p_stmts(pc)
    pc.idx = pc.idx + 1                 ## '}'
    return snode(pc.arena, Stmt.Unchecked(ubody, 0))
  }
  ## `alloc::with(A) { <stmts> }` — the AMBIENT-ALLOCATOR scope (MEM-5 / Grammar §130 alloc-with-region).
  ## `A` becomes the ambient allocator for the body; a call in the body omitting an allocator param gets
  ## it injected (Functions §5.5). `src/` uses explicit allocator args → dormant for the self-host build.
  if cur(pc).kind == 1 and str_eq(str_at(pc.src + cur(pc).start, cur(pc).len), "alloc") and tok_at(pc, pc.idx + 1).kind == 7 and tok_at(pc, pc.idx + 2).kind == 1 and str_eq(str_at(pc.src + tok_at(pc, pc.idx + 2).start, tok_at(pc, pc.idx + 2).len), "with") and tok_at(pc, pc.idx + 3).kind == 10 {
    pc.idx = pc.idx + 4                 ## 'alloc' '::' 'with' '('
    aexpr := p_or(pc)
    pc.idx = pc.idx + 1                 ## ')'
    pc.idx = pc.idx + 1                 ## '{'
    wbody := p_stmts(pc)
    pc.idx = pc.idx + 1                 ## '}'
    return snode(pc.arena, Stmt.AllocWith(aexpr, wbody, 0))
  }
  ## `mut name … = v` — a mutable binding. The self-host compiler binds every local to a frame
  ## slot regardless (mutability is the front end's concern, not lowering's), so the `mut`
  ## marker is skipped here and the rest parses as an ordinary binding.
  mut had_mut := false
  if tok_kw(pc, "mut") { pc.idx = pc.idx + 1; had_mut = true }
  ## `comptime <block>` — a compile-time statement (`comptime for`/`comptime match` over
  ## `typeinfo(T)`). The lean lower does not emit comptime code; consume and return a dummy
  ## no-op (ExprStmt 0). Scan past the keyword to the first `{`, then balance braces.
  if tok_kw(pc, "comptime") {
    pc.idx = pc.idx + 1   ## 'comptime'
    if had_mut { reject_at(pc, "selfhost: `comptime mut` is invalid — a comptime binding is immutable (Comptime §2.2)", cur(pc).start) }
    if tok_kw(pc, "mut") { reject_at(pc, "selfhost: `comptime mut` is invalid — a comptime binding is immutable (Comptime §2.2)", cur(pc).start) }
    ## `comptime if <cond> { then } [else { else }]` — parse into a `CompIf` AST node so the lower
    ## can EVALUATE the condition and emit the taken branch (arch/verify predicates). The condition
    ## is a full expression (`p_or` — handles `target.arch == Arch.x86_64` and a parenthesized
    ## `(match typeinfo(T) { … })`); the branches are statement lists (a nested `comptime if`/`for`
    ## inside recurses through `p_stmts`). `comptime for`/`comptime match` fall through to the skip.
    if tok_kw(pc, "if") {
      pc.idx = pc.idx + 1                 ## 'if'
      ccond := p_or(pc)
      pc.idx = pc.idx + 1                 ## '{'
      cthen := p_stmts(pc)
      pc.idx = pc.idx + 1                 ## '}'
      mut celse := 0
      if tok_kw(pc, "else") {
        pc.idx = pc.idx + 1               ## 'else'
        pc.idx = pc.idx + 1               ## '{'
        celse = p_stmts(pc)
        pc.idx = pc.idx + 1               ## '}'
      }
      return snode(pc.arena, Stmt.CompIf(ccond, cthen, celse, 0))
    }
    ## `comptime for <var> in typeinfo(T).fields/.variants { body }` — a COLLECTION comptime-for,
    ## parsed into a `CompFor` node the lower unrolls over the instance type's members. A RANGE form
    ## (`comptime for i in lo .. hi`, the array-length case) has a `..` before the body `{` — detected
    ## by lookahead — and falls through to the no-op skip (deferred). `is_variants` from the iter's
    ## trailing `.fields`/`.variants`.
    if tok_kw(pc, "for") {
      mut la := pc.idx
      mut lpd := 0
      mut isrange := false
      mut hasparen := false
      while la < ntoks(pc) {
        lk := tok_at(pc, la).kind
        if lk == 12 and lpd == 0 { break }
        if lk == 10 { lpd = lpd + 1; hasparen = true }
        else if lk == 11 { if lpd > 0 { lpd = lpd - 1 } }
        else if lk == 31 and lpd == 0 { isrange = true }
        la += 1
      }
      ## PACK form `comptime for v in <packname> { body }` (Functions §7.1) — the iterator is a bare
      ## variadic-param name (NO `..`, so not a range; NO `(`, so not a `typeinfo(...)` collection).
      ## Parse into a `CompForRange` whose lo is a `Var(packname)` and whose HI is NULL — the pack-mode
      ## marker the lower recognizes to unroll over the call's trailing pack args (`cx.pack_args`),
      ## binding `v` to each in turn (no runtime loop; monomorphized).
      if isrange == false and hasparen == false {
        pc.idx = pc.idx + 1               ## 'for'
        pvtok := cur(pc); pc.idx = pc.idx + 1   ## loop var
        pc.idx = pc.idx + 1               ## 'in'
        pitok := cur(pc); pc.idx = pc.idx + 1   ## pack name (bare ident)
        plo := newnode(pc.arena, Expr.Var(pitok.start, pitok.len))
        pc.idx = pc.idx + 1               ## '{'
        pkbody := p_stmts(pc)
        pc.idx = pc.idx + 1               ## '}'
        pnull := unchecked bitcast(ptr(Expr), 0)
        return snode(pc.arena, Stmt.CompForRange(pvtok.start, pvtok.len, plo, pnull, pkbody, 0))
      }
      if isrange == false {
        pc.idx = pc.idx + 1               ## 'for'
        vtok := cur(pc); pc.idx = pc.idx + 1   ## loop var
        pc.idx = pc.idx + 1               ## 'in'
        iter := p_or(pc)                  ## typeinfo(T).fields / .variants
        pc.idx = pc.idx + 1               ## '{'
        cfbody := p_stmts(pc)
        pc.idx = pc.idx + 1               ## '}'
        itn := field_tail_name(iter)
        mut isvar : u8 = 0
        if itn.n != 0 and str_eq(str_at(pc.src + itn.s, itn.n), "variants") { isvar = 1 }
        return snode(pc.arena, Stmt.CompFor(vtok.start, vtok.len, isvar, cfbody, 0))
      } else {
        ## RANGE form `comptime for i in lo .. hi { body }` — parse the bounds + body into a
        ## `CompForRange` node; the lower UNROLLS it at compile time (the loop var binds each constant).
        ## Mirrors the runtime `for i in lo .. hi` parse (`lo`/`hi` via `p_or`, split on `..` kind 31).
        pc.idx = pc.idx + 1               ## 'for'
        rvtok := cur(pc); pc.idx = pc.idx + 1   ## loop var
        pc.idx = pc.idx + 1               ## 'in'
        rlo := p_or(pc)                   ## lo bound
        pc.idx = pc.idx + 1               ## '..'
        rhi := p_or(pc)                   ## hi bound
        pc.idx = pc.idx + 1               ## '{'
        crbody := p_stmts(pc)
        pc.idx = pc.idx + 1               ## '}'
        return snode(pc.arena, Stmt.CompForRange(rvtok.start, rvtok.len, rlo, rhi, crbody, 0))
      }
    }
    ## `comptime match typeinfo(T) { Struct(_) => {…} … _ => {…} }` — a COMPTIME kind-dispatch parsed
    ## into `CompMatch`; the lower evaluates T's kind + emits the matching arm. Each arm is
    ## `<Kind|_> [(_)] => { stmts }` (the payload wildcard is ignored — the arm branches on the KIND).
    if tok_kw(pc, "match") {
      pc.idx = pc.idx + 1                 ## 'match'
      cmscrut := p_or(pc)                 ## typeinfo(T)
      pc.idx = pc.idx + 1                 ## '{'
      mut cmhead := 0
      mut cmtail := 0
      while cur(pc).kind != 13 and cur(pc).kind != 0 {
        mut cw : u8 = 0
        mut cvs := 0
        mut cvl := 0
        ct := cur(pc)
        if ct.kind == 1 and str_eq(str_at(pc.src + ct.start, ct.len), "_") { cw = 1; pc.idx = pc.idx + 1 }
        else { cvs = ct.start; cvl = ct.len; pc.idx = pc.idx + 1 }   ## kind name (Struct/Enum/Array)
        if cur(pc).kind == 10 {           ## optional `(_)` — skip balanced parens
          mut cd := 0
          while cur(pc).kind != 0 {
            ck2 := cur(pc).kind
            if ck2 == 10 { cd = cd + 1 }
            else if ck2 == 11 { cd = cd - 1; if cd == 0 { pc.idx = pc.idx + 1; break } }
            pc.idx = pc.idx + 1
          }
        }
        pc.idx = pc.idx + 1               ## '=>'
        ## The arm body is either a `{ stmts }` block OR a BARE statement (a nested `comptime match`/
        ## `comptime if`, an expression — e.g. `Scalar(b,k) => comptime match k {…}`). A bare body has
        ## no leading `{`; parse it as ONE statement (`p_stmt`, which handles the comptime forms + exprs)
        ## so it is not mis-consumed as a block (the former unconditional `{`-skip ate the `comptime`
        ## keyword and DRIFTED, corrupting the enclosing decl — why `alloc::fmt::display` lost its
        ## generic-ness). A block body keeps the multi-statement `p_stmts` path.
        mut cmbody := 0
        if cur(pc).kind == 12 {
          pc.idx = pc.idx + 1               ## '{'
          cmbody = p_stmts(pc)
          pc.idx = pc.idx + 1               ## '}'
        } else {
          cmbody = p_stmt(pc)
        }
        dummycm := newnode(pc.arena, Expr.Num(0, 0, 0))
        anewcm := anode(pc.arena, Arm(wild = cw, lit = 0, body = dummycm, next = 0, vs = cvs, vl = cvl, binds_head = bind_null(), body_stmts = cmbody, hi = 0))
        if cmhead == 0 { cmhead = anewcm } else {
          apcm := arm_p(cmtail)
          oldcm := deref(apcm)
          updcm := Arm(wild = oldcm.wild, lit = oldcm.lit, body = oldcm.body, next = anewcm, vs = oldcm.vs, vl = oldcm.vl, binds_head = oldcm.binds_head, body_stmts = oldcm.body_stmts, hi = oldcm.hi)
          deref(apcm) = updcm
        }
        cmtail = anewcm
        if cur(pc).kind == 30 { pc.idx = pc.idx + 1 }
      }
      pc.idx = pc.idx + 1                 ## '}'
      return snode(pc.arena, Stmt.CompMatch(cmscrut, cmhead, 0))
    }
    ## A comptime binding uses the ordinary binding parser below. Validate its head before entering
    ## the legacy fallback, which is retained only for unsupported comptime block syntax.
    mut comptime_binding := false
    mut has_name := cur(pc).kind == 1
    if cur(pc).kind == 2 {
      cn := str_at(pc.src + cur(pc).start, cur(pc).len)
      has_name = str_eq(cn, "in") or str_eq(cn, "out")
    }
    if has_name {
      k1 := tok_at(pc, pc.idx + 1).kind
      if k1 == 5 or k1 == 8 or is_assign_tok(k1) { comptime_binding = true }
    }
    if not comptime_binding {
      if not has_name { reject_at(pc, "selfhost: expected a comptime binding or comptime control statement", cur(pc).start) }
      reject_at(pc, "selfhost: expected a binding after `comptime`", cur(pc).start)
    }
    if not comptime_binding {
    ## Scan to the comptime BODY's `{` — the first `{` at PAREN-DEPTH 0. A `comptime if (match
    ## typeinfo(T) { … }) { … }` condition wraps its OWN `{ arms }` inside `(…)`; a naive
    ## first-`{` scan stopped there and balance-consumed the MATCH arms, leaving `) { body }`
    ## unconsumed → the body drifted (a 2+-statement body then parse-errored). Tracking paren depth
    ## skips any `{` inside the condition's parens so only the real body `{` (depth 0) is matched.
    mut pdepth := 0
    while cur(pc).kind != 0 {
      ck := cur(pc).kind
      if ck == 12 and pdepth == 0 { break }   ## the body '{' (paren depth 0) — stop ON it
      if ck == 10 { pdepth = pdepth + 1 }
      else if ck == 11 { if pdepth > 0 { pdepth = pdepth - 1 } }
      pc.idx = pc.idx + 1
    }
    if cur(pc).kind == 12 {
      pc.idx = pc.idx + 1   ## '{'
      mut depth := 1
      while depth != 0 and cur(pc).kind != 0 {
        if cur(pc).kind == 12 { depth = depth + 1 }
        else if cur(pc).kind == 13 { depth = depth - 1 }
        pc.idx = pc.idx + 1
      }
    }
    ## `comptime if <cond> { then } else { else }` — consume any `else` chain too (a comptime-`if`
    ## nests `else { comptime if … }` for the type-dispatch cascade in `base/derive`). WITHOUT this
    ## the `else` block was left dangling after the then-block → the `else` token parse-errored.
    while tok_kw(pc, "else") {
      pc.idx = pc.idx + 1   ## 'else'
      ## skip to the else-block's `{` at paren depth 0 (an `else comptime if (match …) { … }` puts
      ## the condition's own braces inside parens, like the head-`if`), then balance-consume it.
      mut epd := 0
      while cur(pc).kind != 0 {
        eck := cur(pc).kind
        if eck == 12 and epd == 0 { break }
        if eck == 10 { epd = epd + 1 }
        else if eck == 11 { if epd > 0 { epd = epd - 1 } }
        pc.idx = pc.idx + 1
      }
      if cur(pc).kind == 12 {
        pc.idx = pc.idx + 1   ## '{'
        mut edepth := 1
        while edepth != 0 and cur(pc).kind != 0 {
          if cur(pc).kind == 12 { edepth = edepth + 1 }
          else if cur(pc).kind == 13 { edepth = edepth - 1 }
          pc.idx = pc.idx + 1
        }
      }
    }
    dummy := newnode(pc.arena, Expr.Num(0, 0, 0))
    return snode(pc.arena, Stmt.ExprStmt(dummy, 0))
    }
  }
  ## `defer (expr | block)` (Control Flow §9.3 / Memory §5.8) — register a cleanup action that runs
  ## LIFO on every NORMAL exit of the enclosing scope (fall-through / `break` / `continue` / `return` /
  ## the `?` early-exit), never on trap/panic (no unwinding). The x86 lower models NESTED-block scopes
  ## (a defer inside an `if`/`loop`/`match` arm drains at that block's exit) via per-block frames; the
  ## compiler's own tree carries NO `defer`, so these paths are never taken when compiling the tree.
  ## `defer <expr>` is desugared to a synthetic marker CALL `__defer(<expr>)` that STAYS in the body
  ## statement list, so every downstream pass (sema leak/linearity, the frame-scans, `.rodata`) sees the
  ## action's variable uses + literals FOR FREE (a marker is an ordinary `Call` node — no new `Stmt`
  ## variant, no match to touch anywhere). The x86 lower INTERCEPTS the marker in `emit_stmts`: it does
  ## NOT emit it inline; it registers `<expr>` under the CURRENT frame and emits the pending defers LIFO
  ## at the block/fn exit, preserving the return registers across them.
  ## `defer { S1; S2 }` (a BLOCK action) desugars to a 3-part chain: `__deferblk()` (the marker this
  ## statement returns) → the block's statements (REMAIN in the chain as ordinary statements, so every
  ## scan — sema slots/rodata — sees them for free) → `__deferblkend()` (the tail). The lower registers
  ## the WHOLE chain (from the marker to the end marker) as ONE deferred unit and emits it at LIFO drain
  ## time, so S1 then S2 run TOGETHER at the block's LIFO position (NOT as two separate defers).
  ## Fail-loud (never a silently-skipped cleanup — a dropped cleanup is a miscompile) on the shapes this
  ## slice does NOT model: a `defer` LEXICALLY INSIDE a `defer { }` (a cleanup inside a cleanup), and any
  ## control flow inside a `defer { }` (return/break/continue/`?` — jumping out would skip the rest of the
  ## cleanup / jump into stale labels). A defer that follows an early-exit-capable statement in the same
  ## block is rejected in `emit_stmts` (the ordering guard). `src/`+`lib/` carry NO `defer`, so no marker
  ## is ever produced and the defer paths (here and in the lower) are never taken compiling the tree.
  if tok_kw(pc, "defer") {
    if P_DEFER_BLK_NEST != 0 { panic("selfhost: defer — a `defer` lexically inside a `defer { }` action is ill-formed (a cleanup cannot register a cleanup)") }
    pc.idx = pc.idx + 1                 ## 'defer'
    if cur(pc).kind == 12 {
      ## `defer { S1; S2 }` — the BLOCK action form.
      P_DEFER_BLK_NEST = 1
      pc.idx = pc.idx + 1                 ## '{'
      dblk := p_stmts(pc)                 ## parses the statements; does NOT consume the closing '}'
      pc.idx = pc.idx + 1                 ## '}'
      P_DEFER_BLK_NEST = 0
      ## Validate: reject return/break/continue/`?` anywhere inside (recursive walker over all nested
      ## statement blocks + expressions). A non-clean cleanup would be silently-partially-run — fail loud.
      if defer_stmts_clean(dblk, pc.arena) == false {
        panic("selfhost: defer — a `defer { }` action may not contain return/break/continue or `?`; a cleanup must run to completion (fail-loud rather than a partially-run cleanup)")
      }
      ## Desugar to `__deferblk()` → {block statements} → `__deferblkend()` and return the `__deferblk()`
      ## marker (the chain HEAD); the parent statement-list builder links to the chain TAIL (via stmt_last),
      ## so the block statements stay inline in the chain and every scan pass sees them.
      bs := synth_ident_span(pc, "__deferblk")
      bcall := newnode(pc.arena, Expr.Call(bs, 10, 0, 0))
      bstart := snode(pc.arena, Stmt.ExprStmt(bcall, 0))
      be := synth_ident_span(pc, "__deferblkend")
      bcall2 := newnode(pc.arena, Expr.Call(be, 13, 0, 0))
      bend := snode(pc.arena, Stmt.ExprStmt(bcall2, 0))
      if unchecked bitcast(usize, dblk) == 0 {
        set_stmt_next(pc.arena, bstart, bend)
      } else {
        set_stmt_next(pc.arena, bstart, dblk)                    ## marker → first block statement
        set_stmt_next(pc.arena, stmt_last(dblk, pc.arena), bend) ## last block stmt → end marker
      }
      return bstart
    }
    dact := p_or(pc)                    ## the cleanup expression (a call, overwhelmingly)
    darg := gnode(pc.arena, Arg(e = dact, next = 0))
    dcs := synth_ident_span(pc, "__defer")
    dcall := newnode(pc.arena, Expr.Call(dcs, 7, 1, darg))
    return snode(pc.arena, Stmt.ExprStmt(dcall, 0))
  }
  ## `@label(name) <loop>` (Control Flow §2.1/§6, CF-4): the structured-label attribute precedes a
  ## loop. Record the pending name span; the loop handler immediately below consumes it via `lbl_push`,
  ## making `break name` / `continue name` inside the loop resolvable (§7.1). Kind 33 = `@`. NB: do NOT
  ## recurse into p_stmt here — a recursive `in out pc` call mis-lowers in the seed and corrupts the
  ## cursor (the labeled loop's condition got dropped); instead fall through to the loop handlers below.
  if cur(pc).kind == 33 and tok_at(pc, pc.idx + 1).kind == 1 and str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "label") {
    pc.idx = pc.idx + 2                 ## '@' 'label'
    pc.idx = pc.idx + 1                 ## '('
    lnm := cur(pc); pc.idx = pc.idx + 1 ## the label name
    pc.idx = pc.idx + 1                 ## ')'
    P_PEND_S = lnm.start
    P_PEND_L = lnm.len
  }
  if tok_kw(pc, "while") {
    loop_label_s := P_PEND_S
    loop_label_l := P_PEND_L
    pc.idx = pc.idx + 1
    cond := p_or(pc)
    pc.idx = pc.idx + 1                 ## '{'
    lbl_push()
    body := p_stmts(pc)
    lbl_pop()
    pc.idx = pc.idx + 1                 ## '}'
    wstmt := snode(pc.arena, Stmt.While(cond, body, 0))
    stmt_label_mark(wstmt, loop_label_s, loop_label_l)
    return wstmt
  }
  ## `loop { <stmts> }` — an infinite loop (exited only by `break`). The body is a statement
  ## list; lower emits a back-edge with no guard.
  if tok_kw(pc, "loop") {
    loop_label_s := P_PEND_S
    loop_label_l := P_PEND_L
    pc.idx = pc.idx + 1                 ## 'loop'
    pc.idx = pc.idx + 1                 ## '{'
    lbl_push()
    body := p_stmts(pc)
    lbl_pop()
    pc.idx = pc.idx + 1                 ## '}'
    lstmt := snode(pc.arena, Stmt.Loop(body, 0))
    stmt_label_mark(lstmt, loop_label_s, loop_label_l)
    return lstmt
  }
  ## `break [name] [<expr>]` (Control Flow §7): exit an enclosing loop, optionally targeting a labeled
  ## loop (`break name`) and/or yielding a value (`break v` — §7.2, loop-as-expression). §7.1
  ## disambiguation: an identifier right after `break` that RESOLVES to an in-scope structured label is
  ## the target; otherwise it (and the rest) is the value expression. Depth 0 + no value = the classic
  ## bare `break` (byte-identical lowering).
  if tok_kw(pc, "break") {
    pc.idx = pc.idx + 1                 ## 'break'
    mut bdepth : usize = 0
    mut break_label_s : usize = 0
    mut break_label_l : usize = 0
    if cur(pc).kind == 1 {
      d := lbl_depth(pc.src, cur(pc).start, cur(pc).len)
      if d >= 0 { bdepth = usize(d); break_label_s = cur(pc).start; break_label_l = cur(pc).len; pc.idx = pc.idx + 1 }   ## consume the label name
    }
    mut bval := expr_null()
    if cur(pc).kind != 13 and cur(pc).kind != 30 and cur(pc).kind != 0 { bval = p_or(pc) }
    bstmt := snode(pc.arena, Stmt.Break(bval, bdepth, 0))
    stmt_label_mark(bstmt, break_label_s, break_label_l)
    return bstmt
  }
  ## `continue [name]` — skip to the next iteration of the target loop (§7.1). `continue name` targets a
  ## labeled LOOP; a bare `continue` targets the nearest loop (depth 0). Carries no value (§7.2).
  if tok_kw(pc, "continue") {
    pc.idx = pc.idx + 1                 ## 'continue'
    mut cdepth : usize = 0
    mut continue_label_s : usize = 0
    mut continue_label_l : usize = 0
    if cur(pc).kind == 1 {
      d := lbl_depth(pc.src, cur(pc).start, cur(pc).len)
      if d >= 0 { cdepth = usize(d); continue_label_s = cur(pc).start; continue_label_l = cur(pc).len; pc.idx = pc.idx + 1 }
    }
    cstmt := snode(pc.arena, Stmt.Continue(cdepth, 0))
    stmt_label_mark(cstmt, continue_label_s, continue_label_l)
    return cstmt
  }
  ## `return <cmp>` — an early return statement.
  if tok_kw(pc, "return") {
    pc.idx = pc.idx + 1                 ## 'return'
    ## A BARE `return` (no value) — `if cond { return }` in a unit fn — is followed directly by
    ## the block close `}` (kind 13), a `;` separator (kind 30), or EOF. Without this guard the
    ## handler always parsed `p_or`, which on a `}` drifted the cursor and silently swallowed the
    ## block's closing brace (and, in turn, the following decl). Synthesize a `Num(0)` value (a
    ## unit fn ignores %rax) so the AST shape stays uniform and the lower emits a harmless push.
    if cur(pc).kind == 13 or cur(pc).kind == 30 or cur(pc).kind == 0 {
      ## Bind the synthesized value node to a TEMP first — an inline `newnode(…)` nested as a
      ## constructor argument inside `Stmt.Return(…)` inside `snode(…)` mis-lowers (the nested
      ## multi-word `Expr.Num(0)` arg yields a stray handle, not the node pointer). Mirrors the
      ## proven `dummy := newnode(…)` pattern in the match-arm handler.
      z := newnode(pc.arena, Expr.Num(0, 0, 0))
      return snode(pc.arena, Stmt.Return(z, 0))
    }
    rv := p_or(pc)
    return snode(pc.arena, Stmt.Return(rv, 0))
  }
  ## `if <cmp> { <stmts> } [ else { <stmts> } ]` — a statement-position if. The branch
  ## bodies are STATEMENT LISTS (parsed with `p_stmts`), not single expressions. An `else`
  ## is optional (else_head = 0 when absent).
  if tok_kw(pc, "if") {
    pc.idx = pc.idx + 1                 ## 'if'
    cond := p_or(pc)
    pc.idx = pc.idx + 1                 ## '{'
    then_head := p_stmts(pc)
    pc.idx = pc.idx + 1                 ## '}'
    mut else_head := 0
    if tok_kw(pc, "else") {
      pc.idx = pc.idx + 1               ## 'else'
      ## `else if …` — the else branch is a single nested `if` STATEMENT (parsed recursively),
      ## so an arbitrary `if … else if … else …` chain works without a brace per level. The
      ## else-list is then a one-element list (the nested if's `next` is 0); lower walks it.
      if tok_kw(pc, "if") {
        else_head = p_stmt(pc)
      } else {
        pc.idx = pc.idx + 1             ## '{'
        else_head = p_stmts(pc)
        pc.idx = pc.idx + 1             ## '}'
      }
    }
    return snode(pc.arena, Stmt.If(cond, then_head, else_head, 0))
  }
  ## `match <cmp> { <pat> => { <stmts> } ; … }` — a statement-position match. Each arm BODY is
  ## a STATEMENT LIST (in braces), parsed with `p_stmts`. The pattern parsing (int literal /
  ## wildcard `_` / enum variant `V(x, …)`) mirrors the expression match in `p_factor`; the arm
  ## carries its body statement-list head in `body_stmts` (with a dummy `body` expr).
  if tok_kw(pc, "match") {
    pc.idx = pc.idx + 1                 ## 'match'
    scrut := p_or(pc)
    pc.idx = pc.idx + 1                 ## '{'
    mut ahead := 0
    mut atail := 0
    while cur(pc).kind != 13 and cur(pc).kind != 0 {
      mut w : u8 = 0
      mut lit := 0
      mut vs := 0
      mut vl := 0
      mut bn := 0
      mut bhead := bind_null()
      mut btail := bind_null()
      wt := cur(pc)
      ## `comptime for <var> in typeinfo(T).variants { <T.(var)(p...)> => body }` — a COMPTIME
      ## VARIANT-ARM TEMPLATE (enum derive). Parse the inner arm `T.(var)(bindings) => body` and
      ## mark it `wild = 2`; the lower UNROLLS it into one real arm per variant of the scrutinee's
      ## enum (in a mono instance). `vs/vl` = the loop var name (marks the payload as comptime-typed
      ## for the recursive `hash(p)`); the bindings + body come from the template.
      if wt.kind == 2 and str_eq(str_at(pc.src + wt.start, wt.len), "comptime") {
        pc.idx = pc.idx + 1                 ## 'comptime'
        pc.idx = pc.idx + 1                 ## 'for'
        cfv := cur(pc); pc.idx = pc.idx + 1 ## loop var
        pc.idx = pc.idx + 1                 ## 'in'
        cfiter := p_or(pc)                  ## typeinfo(T).variants
        pc.idx = pc.idx + 1                 ## '{'  (the comptime-for body)
        ## the template arm `T.(var)(p...) => body`: skip `T . ( var )`, parse `( bindings )`.
        pc.idx = pc.idx + 1                 ## 'T'
        pc.idx = pc.idx + 1                 ## '.'
        pc.idx = pc.idx + 1                 ## '('
        pc.idx = pc.idx + 1                 ## the comptime var ident
        pc.idx = pc.idx + 1                 ## ')'
        if cur(pc).kind == 10 {
          pc.idx = pc.idx + 1               ## '(' payload bindings
          while cur(pc).kind != 11 and cur(pc).kind != 0 {
            bt := cur(pc); pc.idx = pc.idx + 1
            bnew := bnode(pc.arena, Bind(ns = bt.start, nl = bt.len, next = bind_null()))
            if unchecked bitcast(usize, bhead) == 0 { bhead = bnew } else {
              bold := deref(btail)
              bupd := Bind(ns = bold.ns, nl = bold.nl, next = bnew)
              deref(btail) = bupd
            }
            btail = bnew
            bn += 1
            if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }
          }
          pc.idx = pc.idx + 1               ## ')'
        }
        pc.idx = pc.idx + 1                 ## '=>'
        pc.idx = pc.idx + 1                 ## '{'
        tbody := p_stmts(pc)
        pc.idx = pc.idx + 1                 ## '}' (arm body)
        pc.idx = pc.idx + 1                 ## '}' (comptime-for body)
dummyc := newnode(pc.arena, Expr.Num(0, 0, 0))
        anewc := anode(pc.arena, Arm(wild = 2, lit = 0, body = dummyc, next = 0, vs = cfv.start, vl = cfv.len, binds_head = bhead, body_stmts = tbody, hi = 0))
        if ahead == 0 { ahead = anewc } else {
          apc := arm_p(atail)
          oldc := deref(apc)
          updc := Arm(wild = oldc.wild, lit = oldc.lit, body = oldc.body, next = anewc, vs = oldc.vs, vl = oldc.vl, binds_head = oldc.binds_head, body_stmts = oldc.body_stmts, hi = oldc.hi)
          deref(apc) = updc
        }
        atail = anewc
        if cur(pc).kind == 30 { pc.idx = pc.idx + 1 }
      }
      else {
      ## Parse the arm's pattern (one alternative) + any OR-pattern `|`-alternatives (§5.4), then the
      ## shared `{ … }` statement body. `parse_pat_alt` mirrors the expr-match arm parser exactly.
      first := parse_pat_alt(pc)
      mut gtail := first
      mut isor := false
      ## OR-pattern `p | q | … => { … }` (§5.4): the alternatives share ONE body — pure surface sugar
      ## expanded to one arm per alternative. v1 alternatives do NOT bind: a binding alternative is
      ## ill-formed (fail loud).
      while cur(pc).kind == 35 {
        pc.idx = pc.idx + 1              ## '|'
        isor = true
        altn := parse_pat_alt(pc)
        am_alt := deref(arm_p(altn))
        if unchecked bitcast(usize, am_alt.binds_head) != 0 {
          panic("parse: an OR-pattern alternative may not bind a payload (Control Flow §5.4)")
        }
        set_arm_next(pc.arena, gtail, altn)
        gtail = altn
      }
      ## the FIRST alternative of an OR may not bind either (an OR arm binds inconsistently, §5.4).
      if isor {
        am_first := deref(arm_p(first))
        if unchecked bitcast(usize, am_first.binds_head) != 0 {
          panic("parse: an OR-pattern alternative may not bind a payload (Control Flow §5.4)")
        }
      }
      pc.idx = pc.idx + 1               ## '=>'
      pc.idx = pc.idx + 1               ## '{'
      sbody := p_stmts(pc)              ## arm body is a STATEMENT LIST
      pc.idx = pc.idx + 1               ## '}'
      ## wire the shared statement body onto every alternative and splice the chain into the arm list.
      mut g := first
      while g != 0 {
        gm := deref(arm_p(g))
        set_arm_body_stmts(pc.arena, g, sbody)
        if ahead == 0 { ahead = g } else { set_arm_next(pc.arena, atail, g) }
        atail = g
        g = gm.next
      }
      if cur(pc).kind == 30 { pc.idx = pc.idx + 1 }   ## optional ';'
      }
    }
    pc.idx = pc.idx + 1                 ## '}'
    return snode(pc.arena, Stmt.Match(scrut, ahead, 0))
  }
  ## `for <i> in <lo> .. <hi> { <stmts> }` — a counted for loop. `for`/`in` are keywords
  ## (kind 2, `tok_kw`); `..` is the range token (kind 31). The bounds are full expressions
  ## (`p_or`); the body is a statement list. Desugared to a counted while by lower.
  if tok_kw(pc, "for") {
    loop_label_s := P_PEND_S
    loop_label_l := P_PEND_L
    pc.idx = pc.idx + 1                 ## 'for'
    iv := cur(pc); pc.idx = pc.idx + 1 ## loop-variable ident
    pc.idx = pc.idx + 1                 ## 'in'
    lo := p_or(pc)
    if cur(pc).kind == 31 {
      ## RANGE form `for i in lo .. hi { … }` — the loop var is the integer index.
      pc.idx = pc.idx + 1               ## '..'
      hi := p_or(pc)
      pc.idx = pc.idx + 1               ## '{'
      lbl_push()
      fbody := p_stmts(pc)
      lbl_pop()
      pc.idx = pc.idx + 1               ## '}'
      fstmt := snode(pc.arena, Stmt.For(iv.start, iv.len, lo, hi, fbody, 0))
      stmt_label_mark(fstmt, loop_label_s, loop_label_l)
      return fstmt
    }
    ## ITERABLE form `for x in <slice> { … }` (no `..`) — `lo` is the iterable; the loop var binds
    ## each ELEMENT. Marked by a NULL `hi` (fhi == 0), which the lower desugars to a counted loop
    ## `__i = 0; while __i < s.len { x := s[__i] ; … ; __i += 1 }` over the slice's {ptr,len}.
    pc.idx = pc.idx + 1                 ## '{'
    lbl_push()
    ibody := p_stmts(pc)
    lbl_pop()
    pc.idx = pc.idx + 1                 ## '}'
    nullhi : ptr(mut Expr) = unchecked bitcast(ptr(mut Expr), 0)
    istmt := snode(pc.arena, Stmt.For(iv.start, iv.len, lo, nullhi, ibody, 0))
    stmt_label_mark(istmt, loop_label_s, loop_label_l)
    return istmt
  }
  ## `@label(name) <instruction>` — a DIRECT CODE-POINT label. Keep the existing Stmt::ExprStmt
  ## shape and recover the label through the AST side table, just like structured loop labels; this
  ## avoids widening the bootstrap-sensitive statement enum while letting lower emit a named GAS
  ## target. Sema validates the instruction/jump shape and the `unchecked` grant before emission.
  if P_PEND_L != 0 {
    code_label_s := P_PEND_S
    code_label_l := P_PEND_L
    code := p_or(pc)
    cstmt := snode(pc.arena, Stmt.ExprStmt(code, 0))
    stmt_label_mark(cstmt, code_label_s, code_label_l)
    P_PEND_S = 0
    P_PEND_L = 0
    return cstmt
  }
  ## `deref(p).field[index] = v` — an element WRITE through a pointer-derived struct array field.
  ## Keep this before the scalar field path below: both start with the same `deref(…).field` prefix,
  ## but this form must preserve the trailing Index node for lower's array-field address path.
  if deref_field_index_path_assign_starts(pc) {
    dipplace := p_field(pc)
    dipval := p_place_val(pc, dipplace)
    return snode(pc.arena, Stmt.FieldPathAssign(dipplace, dipval, 0))
  }
  if deref_field_index_assign_starts(pc) {
    difplace := p_field(pc)
    difval := p_place_val(pc, difplace)
    difix := index_parts(difplace)
    return snode(pc.arena, Stmt.IndexAssign(difix.b, difix.i, difval, 0))
  }
  ## `deref(p).field = v` / `deref(node.next).field = v` — a FIELD WRITE THROUGH a pointer (the store
  ## dual of the `deref(p).f` READ). Checked BEFORE the whole-value `deref(p) = v` store below: that
  ## branch assumed `=` DIRECTLY after `)` and blindly consumed the `.` as if it were `=`, so the field
  ## write silently became a no-op (`deref(m).used = nu` in the stdlib HashMap rehash miscompiled). Parse
  ## the LHS place via `p_field` (→ `Field(Deref(p), field)`, incl. a chained `.field` / a `deref(o.p)`
  ## pointer field), then `=`, then the value; record a `FieldPathAssign` — lower resolves the pointee +
  ## stores the field at `fi*8(ptr)`.
  if deref_field_assign_starts(pc) {
    dfplace := p_field(pc)              ## parses `deref(p).field` into Field(Deref(p), field)
    dfpval := p_place_val(pc, dfplace)
    return snode(pc.arena, Stmt.FieldPathAssign(dfplace, dfpval, 0))
  }
  ## `deref(p) = <cmp>` — a STORE through a pointer (a `DerefAssign` statement). The
  ## pointer factor `deref(p)` parses to a `Deref` expr; its inner pointer expression is
  ## then stored to, followed by `=` and the value. Recognized via the `deref` intrinsic
  ## shape (the same `is_mem_intrinsic` lookahead the expression form uses).
  if is_mem_intrinsic(pc) {
    pc.idx = pc.idx + 1                 ## 'deref' (a store target is always deref, not ptr)
    pc.idx = pc.idx + 1                 ## '('
    ptr := p_or(pc)
    pc.idx = pc.idx + 1                 ## ')'
    dplc := newnode(pc.arena, Expr.Deref(ptr))
    dval := p_place_val(pc, dplc)
    return snode(pc.arena, Stmt.DerefAssign(ptr, dval, 0))
  }
  ## `arr[i] = <cmp>` — an array element WRITE (a `[` after the base ident, then a
  ## bracket-balanced index, `]`, and `=`). Recorded as an `IndexAssign` (base + index +
  ## value). The base array expression is parsed through `p_field` so the index postfix is
  ## consumed, then the inner `Index` is unwrapped to recover the base + index; lower
  ## computes the runtime element address and stores the value.
  ## `a[i].f = <cmp>` — an array-of-struct element-FIELD write. `p_field` parses `a[i].f`
  ## into `Field(Index(arr, idx), f)`; unwrap it to recover the array base, index, and field
  ## span, then record an `IndexFieldAssign`. Checked BEFORE the whole-element form.
  ## `xs[i].f1.f2… = <cmp>` — a DEEP array-element nested-field write (>= 2 `.field` levels after the
  ## `]`). `p_field` parses the LHS into `Field(Field(Index(xs,i), f1), f2)`; record a `FieldPathAssign`
  ## — lower's `resolve_deep_idx_field` composes the combined element→field word offset and stores the
  ## scalar leaf. Checked BEFORE the depth-1 `a[i].f =` form (which records the lighter `IndexFieldAssign`
  ## for a SINGLE trailing field) and before `arr_field_index_assign_starts` (which has an inner `[`).
  if deep_idx_field_assign_starts(pc) {
    dplace := p_field(pc)               ## parses `xs[i].f1.f2` into Field(Field(Index(xs,i),f1),f2)
    dpval := p_place_val(pc, dplace)
    return snode(pc.arena, Stmt.FieldPathAssign(dplace, dpval, 0))
  }
  ## `xs[i].arr[j] = <cmp>` — a write into an ARRAY FIELD of an array-of-struct ELEMENT. `p_field`
  ## parses the LHS into `Index(Field(Index(xs,i), arr), j)`; `index_parts` unwraps the OUTER Index to
  ## recover the `Field`-based array base and the inner index, recorded as an `IndexAssign` — lower's
  ## `arr_field_elem` resolves the array-field word-0 address and stores element `j`. Checked BEFORE the
  ## depth-1 `a[i].f =` form (whose post-`]` lookahead requires `. ident =`, not `. ident [`).
  if arr_field_index_assign_starts(pc) {
    atarget := p_field(pc)              ## parses `xs[i].arr[j]` into Index(Field(Index(xs,i),arr), j)
    aval := p_place_val(pc, atarget)
    aix := index_parts(atarget)
    return snode(pc.arena, Stmt.IndexAssign(aix.b, aix.i, aval, 0))
  }
  if idx_field_assign_starts(pc) {
    ftarget := p_field(pc)              ## parses `a[i].f` into Field(Index(arr,idx), f)
    ifval := p_place_val(pc, ftarget)
    ifp := idx_field_parts(ftarget)
    return snode(pc.arena, Stmt.IndexFieldAssign(ifp.arr, ifp.idx, ifp.fs, ifp.fl, ifval, 0))
  }
  ## `v.field[i] = <cmp>` — a NESTED PLACE write (a struct field that is an array). `p_field`
  ## parses `v.field[i]` into `Index(Field(Var(v), field), idx)`; `index_parts` unwraps it to a
  ## `Field`-based `IndexAssign` (lower's `emit_index_addr` resolves the array field's word-0
  ## address). Checked BEFORE the plain `arr[i] =` form (which requires `ident [` directly).
  if field_index_assign_starts(pc) {
    ftarget := p_field(pc)              ## parses `v.field[i]` into Index(Field(Var(v),field), idx)
    fival := p_place_val(pc, ftarget)
    fix := index_parts(ftarget)
    return snode(pc.arena, Stmt.IndexAssign(fix.b, fix.i, fival, 0))
  }
  ## `t.N[i] = <cmp>` — an INDEX inside a tuple component's direct array. `p_field` parses the
  ## complete place as `Index(Index(Var(t), Num(N)), i)`; `index_parts` unwraps the outer index and
  ## preserves `Index(Var(t), Num(N))` as the base consumed by lower's byte-tuple address path.
  if tuple_array_index_assign_starts(pc) {
    ttarget := p_field(pc)
    tval := p_place_val(pc, ttarget)
    tix := index_parts(ttarget)
    return snode(pc.arena, Stmt.IndexAssign(tix.b, tix.i, tval, 0))
  }
  if index_assign_starts(pc) {
    target := p_field(pc)               ## parses `arr[i]` into an `Index(base, idx)`
    ival := p_place_val(pc, target)
    ix := index_parts(target)
    return snode(pc.arena, Stmt.IndexAssign(ix.b, ix.i, ival, 0))
  }
  ## `t.N.M = <cmp>` — a NESTED TUPLE-element write (both indices numeric, `.<int>.<int>`). `p_field`
  ## parses `t.N.M` into `Index(Index(Var(t), Num(N)), Num(M))`; `index_parts` unwraps the OUTER Index to
  ## recover the base `Index(Var(t), Num(N))` (tuple component N) and the inner index `Num(M)`, recorded
  ## as an `IndexAssign` — the STORE dual of the two-level tuple READ (lower resolves component N's word-0
  ## address, then stores `v` at word M within it). Checked BEFORE `field_path_assign_starts` (which needs
  ## `.ident.ident`, not numeric indices) and before the plain field forms. Only the exactly-two-level
  ## numeric shape (`t.N.M =`, no third `.`) is matched — deeper `t.A.B.C =` stays on the generic path.
  if tuple_nested_index_assign_starts(pc) {
    ttarget := p_field(pc)              ## parses `t.N.M` into Index(Index(Var(t),Num(N)),Num(M))
    tval := p_place_val(pc, ttarget)
    tix := index_parts(ttarget)
    return snode(pc.arena, Stmt.IndexAssign(tix.b, tix.i, tval, 0))
  }
  ## `t.N = <cmp>` — a ONE-level TUPLE-element write (numeric `.<int>`). `p_field` parses `t.N` into
  ## `Index(Var(t), Num(N))`; `index_parts` unwraps it to an `IndexAssign` — the STORE dual of the tuple
  ## READ `t.N` (lower's generic `emit_index_addr` resolves element N's word address, then stores `v`).
  ## Checked BEFORE the plain `var.field = …` block below (which would mis-treat the numeric `.N` as a
  ## struct FIELD name and record a bogus `FieldAssign`). A `.<ident> =` (a real struct field write) does
  ## NOT reach here — `tuple_index_assign_starts` requires an INT after the `.`, so `s.name = v` is safe.
  if tuple_index_assign_starts(pc) {
    starget := p_field(pc)              ## parses `t.N` into Index(Var(t), Num(N))
    sval := p_place_val(pc, starget)
    six := index_parts(starget)
    return snode(pc.arena, Stmt.IndexAssign(six.b, six.i, sval, 0))
  }
  ## `o.i.v = <cmp>` — a NESTED field mutation (≥2 `.field` levels). Parse the LHS place via `p_field`
  ## (→ `Field(Field(Var(o), i), v)`), then `=`, then the value; record a `FieldPathAssign`. Checked
  ## BEFORE the single-level `var.field =` (which only handles one field and would mis-parse `.v` as `=`).
  if field_path_assign_starts(pc) {
    place := p_field(pc)                ## parses `o.i.v` into a nested `Field`
    fpval := p_place_val(pc, place)
    return snode(pc.arena, Stmt.FieldPathAssign(place, fpval, 0))
  }
  nm := cur(pc)
  ## `var.field = <cmp>` — a struct field mutation (the `.` after the ident, an ident
  ## field name, then `=`). Recorded as a `FieldAssign` (base name span + field name span).
  if tok_at(pc, pc.idx + 1).kind == 22 {
    pc.idx = pc.idx + 1                 ## ident (base var)
    pc.idx = pc.idx + 1                 ## '.'
    fld := cur(pc); pc.idx = pc.idx + 1 ## field name
    ## `ident.field op= rhs` — desugar to FieldAssign(ident, field, Bin(op, Field(Var(ident), field), rhs))
    fco := compound_op(cur(pc).kind)
    if fco >= 0 {
      pc.idx = pc.idx + 1               ## 'op='
      rhs := p_or(pc)
      base_e := newnode(pc.arena, Expr.Var(nm.start, nm.len))
      cur_fv := newnode(pc.arena, Expr.Field(base_e, fld.start, fld.len))
      compound := newnode(pc.arena, Expr.Bin(u8(fco), cur_fv, rhs))
      return snode(pc.arena, Stmt.FieldAssign(nm.start, nm.len, fld.start, fld.len, compound, 0))
    }
    pc.idx = pc.idx + 1                 ## '='
    fval := p_or(pc)
    return snode(pc.arena, Stmt.FieldAssign(nm.start, nm.len, fld.start, fld.len, fval, 0))
  }
  pc.idx = pc.idx + 1                   ## ident
  ## `name : T` — an explicitly uninitialized local. Preserve the existing Stmt.Assign shape with a
  ## harmless sentinel value; sema and lower recover the no-initializer state from the source span, so
  ## no bootstrap-sensitive AST field is added. Leave `;`/`}`/the next line's token for the caller.
  uninit_end := local_uninit_end(pc, nm.start, nm.len)
  if uninit_end != 0 {
    while cur(pc).kind != 0 and cur(pc).start < uninit_end { pc.idx = pc.idx + 1 }
    z := newnode(pc.arena, Expr.Num(0, 0, 0))
    return snode(pc.arena, Stmt.Assign(nm.start, nm.len, z, 0))
  }
  ## `name : T = v` — a TYPED binding. The type annotation is sema's concern, not lowering's
  ## (lower sizes the slot from the value), so skip from the `:` to the binding `=` (kind 21).
  ## A type form holds no `=`, so a flat scan to the first `=` is unambiguous (`ptr(mut T)` /
  ## `Vec(u64)` / `[T; N]` are all spanned over). An untyped `name := v` has `:=` (kind 5) next,
  ## so this block does not fire.
  if cur(pc).kind == 8 {
    while cur(pc).kind != 21 and cur(pc).kind != 0 { pc.idx = pc.idx + 1 }
  }
  ## `name op= rhs` — compound assignment: desugar to Assign(name, Bin(op, Var(name), rhs)).
  nco := compound_op(cur(pc).kind)
  if nco >= 0 {
    pc.idx = pc.idx + 1                 ## 'op='
    rhs := p_or(pc)
    lhs := newnode(pc.arena, Expr.Var(nm.start, nm.len))
    compound := newnode(pc.arena, Expr.Bin(u8(nco), lhs, rhs))
    return snode(pc.arena, Stmt.Assign(nm.start, nm.len, compound, 0))
  }
  pc.idx = pc.idx + 1                   ## ':=' or '='
  val := p_or(pc)
  snode(pc.arena, Stmt.Assign(nm.start, nm.len, val, 0))
}

## Whether the cursor starts a statement: `while`, `ident (:= | =)`, or a struct field
## mutation `ident . ident =`. A bare expression (the trailing return) is NOT a statement —
## the fn binding parses it after the list. The field-mutation lookahead (`ident . ident =`)
## is distinguished from a field-READ in the trailing return expr (`p.x + …`, no trailing
## `=`) by requiring the `=` after the field name.
stmt_starts := fn(pc : PC) -> bool {
  ## `@alloc(A) name := init` — the allocation storage attribute leads a binding statement (§2.4).
  if cur(pc).kind == 33 and tok_at(pc, pc.idx + 1).kind == 1 and str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "alloc") { return true }
  ## `@label(name) <loop>` — the structured-label attribute leads a labeled loop STATEMENT (§2.1/§7.1).
  ## Without this, `@label(name) while/for` fell to the trailing-expression path and the loop-expression
  ## parser mis-consumed the `while`/`for` keyword as `loop` (dropping the guard → an infinite loop).
  if cur(pc).kind == 33 and tok_at(pc, pc.idx + 1).kind == 1 and str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "label") { return true }
  ## `unchecked { <stmts> }` — the statement verification-mode block (Grammar §130); the `{` distinguishes
  ## it from the expression form `unchecked <expr>` (a trailing value), which is not a statement start.
  if tok_kw(pc, "unchecked") and tok_at(pc, pc.idx + 1).kind == 12 { return true }
  ## `alloc::with(A) { … }` — the ambient-allocator scope leads a statement (MEM-5).
  if cur(pc).kind == 1 and str_eq(str_at(pc.src + cur(pc).start, cur(pc).len), "alloc") and tok_at(pc, pc.idx + 1).kind == 7 and tok_at(pc, pc.idx + 2).kind == 1 and str_eq(str_at(pc.src + tok_at(pc, pc.idx + 2).start, tok_at(pc, pc.idx + 2).len), "with") and tok_at(pc, pc.idx + 3).kind == 10 { return true }
  if tok_kw(pc, "while") { return true }
  if tok_kw(pc, "for") { return true }
  if tok_kw(pc, "loop") { return true }
  if tok_kw(pc, "break") { return true }
  if tok_kw(pc, "continue") { return true }
  if tok_kw(pc, "return") { return true }
  ## `defer <expr>` — a cleanup registration statement (Control Flow §9.3 / Memory §5.8).
  if tok_kw(pc, "defer") { return true }
  ## `mut name … = v` — a mutable binding statement (the marker leads).
  if tok_kw(pc, "mut") { return true }
  ## An `if`/`match` STARTS a statement only when its first brace body is a statement list
  ## (`block_is_stmt_form`); a tail `if a < b { b } else { a }` (body = a value expr) is NOT a
  ## statement — `parse_decl` parses it after the statement list as the trailing return expr.
  if tok_kw(pc, "if") { return if_is_stmt_form(pc) }
  if tok_kw(pc, "match") { return match_is_stmt_form(pc) }
  ## `comptime <block>` — a comptime statement (for/match over typeinfo); skip in stmt_starts.
  if tok_kw(pc, "comptime") { return true }
  ## `deref(p) = …` — a pointer-store statement (distinguished from a trailing `deref(p)`
  ## RETURN expression by the `=` after the closing `)`).
  if deref_assign_starts(pc) { return true }
  ## `deref(p).field[index] = …` — an indexed array-field write through a pointer-derived root.
  if deref_field_index_path_assign_starts(pc) { return true }
  if deref_field_index_assign_starts(pc) { return true }
  ## `deref(p).field = …` / `deref(node.next).field = …` — a FIELD write THROUGH a pointer
  ## (distinguished from a trailing `deref(p).field` READ by the `=` after the field path). Without
  ## this, `stmt_starts` returned false (a `deref(…)` head has `(` at idx+1, not `.`), so the line was
  ## parsed as a trailing RETURN expression and the store was silently dropped.
  if deref_field_assign_starts(pc) { return true }
  ## `xs[i].f1.f2… = …` — a DEEP array-element nested-field write (>= 2 fields after the `]`).
  ## Without this the line began `ident [` (not a recognized statement head) → it was parsed as a
  ## trailing RETURN expression and the write silently dropped. Checked before the depth-1 `a[i].f =`.
  if deep_idx_field_assign_starts(pc) { return true }
  ## `xs[i].arr[j] = …` — a write into an ARRAY FIELD of an array-of-struct element. Same drop as
  ## above (the `ident [` head was not a statement start) until recognized here.
  if arr_field_index_assign_starts(pc) { return true }
  ## `a[i].f = …` — an array-of-struct element-FIELD write (checked BEFORE the whole-element
  ## form so a `].f =` is not mistaken for `] =`).
  if idx_field_assign_starts(pc) { return true }
  ## `v.field[i] = …` — a NESTED PLACE write (a struct field that is an array). Checked before
  ## the plain `arr[i] =` form (which requires `ident [` directly, no `.field` before the `[`).
  if field_index_assign_starts(pc) { return true }
  ## `t.N[i] = …` — tuple-component array-element write; keep it ahead of the generic tuple numeric
  ## projections and plain `ident[` form because the base has a dotted numeric projection.
  if tuple_array_index_assign_starts(pc) { return true }
  ## `t.N.M = …` — a NESTED TUPLE-element write (numeric `.<int>.<int>`). Checked before the field
  ## forms (whose lookaheads require `.ident`, not a numeric index).
  if tuple_nested_index_assign_starts(pc) { return true }
  ## `t.N = …` — a ONE-level TUPLE-element write (numeric `.<int>`). Checked before the field forms
  ## (whose lookaheads require `.ident`, not a numeric index) so it is dispatched to `IndexAssign`.
  if tuple_index_assign_starts(pc) { return true }
  ## `o.i.v = …` — a NESTED field write (≥2 `.field` levels). Distinguished from a nested field READ
  ## in the trailing return (`o.i.v + …`, no `=`) by the `=` terminator.
  if field_path_assign_starts(pc) { return true }
  ## `arr[i] = …` — an array element-write statement (distinguished from a trailing `arr[i]`
  ## READ expression by the `=` after the closing `]`).
  if index_assign_starts(pc) { return true }
  ## `geo::G = …` / `geo::TAB[i] = …` — a QUALIFIED PLACE assignment (Modules §2).
  if qual_place_assign_head(pc) != 0 { return true }
  ## a statement starts with a NAME: an ident (kind 1) OR a contextual kw `in`/`out` used as an
  ## identifier (the p_factor dual — `in`/`out` are usable as binding names in statement position).
  if cur(pc).kind != 1 {
    if cur(pc).kind != 2 { return false }
    nmk := str_at(pc.src + cur(pc).start, cur(pc).len)
    if not (str_eq(nmk, "in") or str_eq(nmk, "out")) { return false }
  }
  k1 := tok_at(pc, pc.idx + 1).kind
  if k1 == 5 or is_assign_tok(k1) { return true }   ## := / = / += -= *= /= %= &= |= ^=
  ## `ident : T = v` — a TYPED binding statement (the `:` after the name). A type form holds
  ## no expression operator, so `ident :` in statement position is unambiguously a binding.
  if k1 == 8 { return true }
  if k1 != 22 { return false }
  ## `ident . ident =` — a struct field assignment statement. The two deeper peeks
  ## (`idx + 2`, `idx + 3`) only run when `.` follows, and are bounds-guarded against the
  ## end of the token stream (a field-READ in the trailing return ends before such an `=`).
  nt := ntoks(pc)
  if pc.idx + 3 >= nt { return false }
  k2 := tok_at(pc, pc.idx + 2).kind
  k3 := tok_at(pc, pc.idx + 3).kind
  k2 == 1 and is_assign_tok(k3)   ## field = / += -= *= /= %= &= |= ^=
}

## Is the cursor a pointer-store statement `deref(p) = …` (vs a trailing `deref(p)`
## RETURN expression with no following `=`)? Recognizes the `deref(` shape, then scans the
## parenthesized pointer expression to its matching `)` (paren-balanced) and checks for an `=`
## (kind 21) just after — present only for a store. Bounds-guarded against the token end.
deref_assign_starts := fn(pc : PC) -> bool {
  if not is_mem_intrinsic(pc) { return false }
  ## confirm it is `deref` (a store target), not `ptr`
  t0 := tok_at(pc, pc.idx)
  if not str_eq(str_at(pc.src + t0.start, t0.len), "deref") { return false }
  nt := ntoks(pc)
  ## scan from the `(` at idx+1 to its matching `)`, then look for `=`
  mut i := pc.idx + 1            ## the '(' of deref(
  mut depth := 0
  while i < nt {
    k := tok_at(pc, i).kind
    if k == 10 { depth = depth + 1 }
    else if k == 11 {
      depth = depth - 1
      if depth == 0 { i = i + 1; break }
    }
    i += 1
  }
  if i >= nt { return false }
  is_assign_tok(tok_at(pc, i).kind)   ## '=' / 'op=' just after the closing ')'
}

## Is the cursor an array element-write statement `arr[i] = …` (vs a trailing `arr[i]` /
## `arr[i] + …` RETURN expression with no top-level `=`)? Recognizes a base ident (kind 1)
## followed by `[` (kind 14), scans the bracket expression to its matching `]` (kind 15,
## bracket-balanced), and checks for an `=` (kind 21) just after. Bounds-guarded against the
## token end. (Only a single `arr[i] =` is recognized here — a nested `a[i].f =` is deferred.)
index_assign_starts := fn(pc : PC) -> bool {
  nt := ntoks(pc)
  if pc.idx + 1 >= nt { return false }
  if tok_at(pc, pc.idx).kind != 1 { return false }   ## base ident
  if tok_at(pc, pc.idx + 1).kind != 14 { return false }  ## '['
  mut i := pc.idx + 1            ## the '['
  mut depth := 0
  while i < nt {
    k := tok_at(pc, i).kind
    if k == 14 { depth = depth + 1 }
    else if k == 15 {
      depth = depth - 1
      if depth == 0 { i = i + 1; break }
    }
    i += 1
  }
  if i >= nt { return false }
  is_assign_tok(tok_at(pc, i).kind)   ## '=' / 'op=' just after the closing ']'
}

## Is the cursor a tuple-component array-element write `t.N[i] = …`? Recognizes a base identifier,
## one numeric tuple projection (`.N`), a balanced bracket expression, and `=` after the closing `]`.
## This is deliberately narrower than the general dotted-place grammar: `t.N.M = …` remains the
## existing nested tuple word-store shape, while `t.field[i] = …` remains the struct-field path.
tuple_array_index_assign_starts := fn(pc : PC) -> bool {
  nt := ntoks(pc)
  if pc.idx + 4 >= nt { return false }
  if tok_at(pc, pc.idx).kind != 1 { return false }
  if tok_at(pc, pc.idx + 1).kind != 22 { return false }
  if tok_at(pc, pc.idx + 2).kind != 3 { return false }
  if tok_at(pc, pc.idx + 3).kind != 14 { return false }
  mut i := pc.idx + 3
  mut depth := 0
  while i < nt {
    k := tok_at(pc, i).kind
    if k == 14 { depth = depth + 1 }
    else if k == 15 {
      depth = depth - 1
      if depth == 0 { i = i + 1; break }
    }
    i += 1
  }
  if i >= nt { return false }
  is_assign_tok(tok_at(pc, i).kind)
}

## Is the cursor a DEEP array-element nested-field write `xs[i].f1.f2… = …` (a base `ident [ … ]`
## element, then a run of `. ident` of length >= 2, then `=`)? The DEPTH-1 form `a[i].f = …`
## (exactly one field after the `]`) is handled by `idx_field_assign_starts` (→ `IndexFieldAssign`);
## only >= 2 fields route here (→ a `FieldPathAssign`, whose place `p_field` builds as
## `Field(Field(Index(xs,i), f1), f2)`, resolved by lower's `resolve_deep_idx_field`). An INNER `[`
## in the field run (`xs[i].arr[j] = …`) fails here — that is the `arr_field_index_assign_starts`
## shape. Distinguishes a deep-field STORE from a trailing READ (`xs[i].f1.f2 + …`, no `=`).
deep_idx_field_assign_starts := fn(pc : PC) -> bool {
  nt := ntoks(pc)
  if pc.idx + 1 >= nt { return false }
  if tok_at(pc, pc.idx).kind != 1 { return false }      ## base ident
  if tok_at(pc, pc.idx + 1).kind != 14 { return false } ## '[' directly after the base (no `.field` prefix)
  mut i := pc.idx + 1            ## the '['
  mut depth := 0
  while i < nt {
    k := tok_at(pc, i).kind
    if k == 14 { depth = depth + 1 }
    else if k == 15 {
      depth = depth - 1
      if depth == 0 { i = i + 1; break }
    }
    i += 1
  }
  ## `i` is just past the outer `]`; require a run of `. ident` (>= 2 fields), then `=`.
  mut nf := 0
  mut ok := true
  mut going := true
  while going and i < nt {
    k := tok_at(pc, i).kind
    if k == 22 {
      if i + 1 >= nt or tok_at(pc, i + 1).kind != 1 { ok = false; going = false }
      else { nf = nf + 1; i = i + 2 }
    } else if is_assign_tok(k) { going = false }   ## '=' / 'op=' — end of the field path
    else { ok = false; going = false }         ## '[' (inner index) / operator → a different form / a read
  }
  ok and nf >= 2 and i < nt and is_assign_tok(tok_at(pc, i).kind)
}

## Is the cursor an ARRAY-FIELD element write `xs[i].a.arr[j] = …` (a base `ident [ … ]` element,
## then one or more `. ident` fields, then an inner `[ … ]` index, then `=`)? The parsed shape is
## `Index(Field(…Field(Index(xs,i), a), arr), j)`, which `index_parts` unwraps to a `Field`-based
## `IndexAssign` (lower's `arr_field_elem` composes the element + every field offset + array index).
## Distinguished from a READ by the trailing `=`.
arr_field_index_assign_starts := fn(pc : PC) -> bool {
  nt := ntoks(pc)
  if pc.idx + 1 >= nt { return false }
  if tok_at(pc, pc.idx).kind != 1 { return false }      ## base ident
  if tok_at(pc, pc.idx + 1).kind != 14 { return false } ## '[' directly after the base (outer index)
  mut i := pc.idx + 1            ## the outer '['
  mut depth := 0
  while i < nt {
    k := tok_at(pc, i).kind
    if k == 14 { depth = depth + 1 }
    else if k == 15 {
      depth = depth - 1
      if depth == 0 { i = i + 1; break }
    }
    i += 1
  }
  ## `i` is just past the outer `]`; consume one or more `. ident` fields, then require the inner index.
  mut nf := 0
  while i + 1 < nt and tok_at(pc, i).kind == 22 and tok_at(pc, i + 1).kind == 1 {
    nf += 1
    i += 2
  }
  if nf == 0 or i >= nt or tok_at(pc, i).kind != 14 { return false }
  mut j := i                         ## the inner '['
  mut d2 := 0
  while j < nt {
    k := tok_at(pc, j).kind
    if k == 14 { d2 = d2 + 1 }
    else if k == 15 {
      d2 = d2 - 1
      if d2 == 0 { j = j + 1; break }
    }
    j += 1
  }
  if j >= nt { return false }
  is_assign_tok(tok_at(pc, j).kind)   ## '=' / 'op=' just after the inner closing ']'
}

## Is the cursor an array-of-struct element-FIELD write `a[i].f = …` or
## `struct.array[i].f = …` (vs a trailing READ)? Scan an optional dotted field prefix before
## the bracket, then bracket-balance to `]`, and require `. ident =` afterward. The parser's
## `p_field`/`idx_field_parts` paths already preserve the array-field base expression.
idx_field_assign_starts := fn(pc : PC) -> bool {
  nt := ntoks(pc)
  if pc.idx + 1 >= nt { return false }
  if tok_at(pc, pc.idx).kind != 1 { return false }      ## base ident
  mut bi := pc.idx + 1
  while bi + 1 < nt and tok_at(pc, bi).kind == 22 and tok_at(pc, bi + 1).kind == 1 { bi = bi + 2 }
  if bi >= nt or tok_at(pc, bi).kind != 14 { return false } ## '['
  mut i := bi                    ## the '['
  mut depth := 0
  while i < nt {
    k := tok_at(pc, i).kind
    if k == 14 { depth = depth + 1 }
    else if k == 15 {
      depth = depth - 1
      if depth == 0 { i = i + 1; break }
    }
    i += 1
  }
  ## i now points just past the closing ']'; need `. ident =`
  if i + 2 >= nt { return false }
  k0 := tok_at(pc, i).kind
  k1 := tok_at(pc, i + 1).kind
  k2 := tok_at(pc, i + 2).kind
  k0 == 22 and k1 == 1 and is_assign_tok(k2)
}

## NESTED PLACE — is the cursor a struct-field array-element write `v.field[i] = …` (vs a
## trailing `v.field[i]` READ expression with no top-level `=`)? Recognizes `ident . ident [`
## then scans the bracket expression to its matching `]` (bracket-balanced) and checks for an
## `=` (kind 21) just after. The parsed shape is `Index(Field(Var(v), field), idx)`, which the
## `index_parts` helper unwraps to a `Field`-based `IndexAssign` (lower handles the field base).
## Distinguished from a plain `arr[i] =` (no `.field` before the `[`) by the leading `ident .`.
field_index_assign_starts := fn(pc : PC) -> bool {
  nt := ntoks(pc)
  if pc.idx + 3 >= nt { return false }
  if tok_at(pc, pc.idx).kind != 1 { return false }      ## base var ident
  if tok_at(pc, pc.idx + 1).kind != 22 { return false } ## '.'
  if tok_at(pc, pc.idx + 2).kind != 1 { return false }  ## field ident
  if tok_at(pc, pc.idx + 3).kind != 14 { return false } ## '['
  mut i := pc.idx + 3            ## the '['
  mut depth := 0
  while i < nt {
    k := tok_at(pc, i).kind
    if k == 14 { depth = depth + 1 }
    else if k == 15 {
      depth = depth - 1
      if depth == 0 { i = i + 1; break }
    }
    i += 1
  }
  if i >= nt { return false }
  is_assign_tok(tok_at(pc, i).kind)   ## '=' / 'op=' just after the closing ']'
}

## Is the cursor a NESTED-field write `o.i.v = …` (≥2 `.field` levels, ending in `=`)? Recognizes a
## base ident then a run of `. ident` (≥2), then `=`, with NO `[` / `(` / operator in between (those
## are the index / call / other forms). A single-level `o.f = …` (exactly one field) is NOT matched —
## it stays the lighter `FieldAssign`. Distinguishes a nested field STORE from a nested field READ
## (`o.i.v + …`, no trailing `=`).
field_path_assign_starts := fn(pc : PC) -> bool {
  nt := ntoks(pc)
  if pc.idx + 4 >= nt { return false }
  if tok_at(pc, pc.idx).kind != 1 { return false }       ## base ident
  if tok_at(pc, pc.idx + 1).kind != 22 { return false }  ## '.'
  if tok_at(pc, pc.idx + 2).kind != 1 { return false }   ## first field ident
  if tok_at(pc, pc.idx + 3).kind != 22 { return false }  ## a SECOND '.' → nested (≥2 fields)
  mut i := pc.idx + 1
  mut nf := 0
  mut ok := true
  mut going := true
  while going and i < nt {
    k := tok_at(pc, i).kind
    if k == 22 {
      if i + 1 >= nt or tok_at(pc, i + 1).kind != 1 { ok = false; going = false }
      else { nf = nf + 1; i = i + 2 }
    } else if is_assign_tok(k) { going = false }   ## '=' / 'op=' — end of the field path
    else { ok = false; going = false }        ## '[' / '(' / operator → a different form
  }
  ok and nf >= 2 and i < nt and is_assign_tok(tok_at(pc, i).kind)
}

## Is the cursor a FIELD-THROUGH-POINTER write `deref(p).field = v` / `deref(node.next).field = v` (a
## `deref(…)` group, then one-or-more `.ident` levels, one `[ … ]`, and `=`. Distinguishes it from the
## scalar field writer below (which deliberately rejects `[` after the field), the whole-value
## `deref(p) = v` store, and a bare `deref(p).field` read. The balanced bracket scan is needed because
## the index expression itself may contain calls or nested indexing.
deref_field_index_assign_starts := fn(pc : PC) -> bool {
  if not is_mem_intrinsic(pc) { return false }
  nt := ntoks(pc)
  mut i := pc.idx + 1
  mut depth := 0
  while i < nt {
    k := tok_at(pc, i).kind
    if k == 10 { depth = depth + 1 }
    else if k == 11 { depth = depth - 1; if depth == 0 { i = i + 1; break } }
    i += 1
  }
  mut nf := 0
  while i + 1 < nt and tok_at(pc, i).kind == 22 and tok_at(pc, i + 1).kind == 1 {
    nf += 1
    i += 2
  }
  if nf == 0 or i >= nt or tok_at(pc, i).kind != 14 { return false }
  mut j := i
  mut d2 := 0
  while j < nt {
    k := tok_at(pc, j).kind
    if k == 14 { d2 = d2 + 1 }
    else if k == 15 {
      d2 = d2 - 1
      if d2 == 0 { j = j + 1; break }
    }
    j += 1
  }
  if j >= nt { return false }
  is_assign_tok(tok_at(pc, j).kind)
}

## Is the cursor a FIELD-THROUGH-POINTER write with an indexed array element followed by a scalar
## field, `deref(p).arr[i].field = …`? Keep this separate from the immediate array-element store
## above: the parsed place is `Field(Index(Field(Deref(p), arr), i), field)` and must remain a
## `FieldPathAssign` so lower can compose the pointer, array stride, and leaf offset.
deref_field_index_path_assign_starts := fn(pc : PC) -> bool {
  if not is_mem_intrinsic(pc) { return false }
  nt := ntoks(pc)
  mut i := pc.idx + 1
  mut depth := 0
  while i < nt {
    k := tok_at(pc, i).kind
    if k == 10 { depth = depth + 1 }
    else if k == 11 { depth = depth - 1; if depth == 0 { i = i + 1; break } }
    i += 1
  }
  mut nf := 0
  while i + 1 < nt and tok_at(pc, i).kind == 22 and tok_at(pc, i + 1).kind == 1 {
    nf += 1
    i += 2
  }
  if nf == 0 or i >= nt or tok_at(pc, i).kind != 14 { return false }
  mut j := i
  mut d2 := 0
  while j < nt {
    k := tok_at(pc, j).kind
    if k == 14 { d2 = d2 + 1 }
    else if k == 15 {
      d2 = d2 - 1
      if d2 == 0 { j = j + 1; break }
    }
    j += 1
  }
  if j >= nt { return false }
  mut nf2 := 0
  while j + 1 < nt and tok_at(pc, j).kind == 22 and tok_at(pc, j + 1).kind == 1 {
    nf2 += 1
    j += 2
  }
  nf2 > 0 and j < nt and is_assign_tok(tok_at(pc, j).kind)
}

deref_field_assign_starts := fn(pc : PC) -> bool {
  if not is_mem_intrinsic(pc) { return false }
  nt := ntoks(pc)
  ## skip the `deref`/`ptr` head ident, then walk the balanced `( … )` (the proven `is_generic_inst`
  ## paren-scan: advance to the matching `)` and stop just past it).
  mut i := pc.idx + 1                                      ## at '('
  mut depth := 0
  while i < nt {
    k := tok_at(pc, i).kind
    if k == 10 { depth = depth + 1 }
    else if k == 11 { depth = depth - 1; if depth == 0 { i = i + 1; break } }
    i += 1
  }
  ## `i` is just past the `)`. A field-through-pointer store has `.` here (not `=` / `[` / `(`).
  if i >= nt or tok_at(pc, i).kind != 22 { return false }  ## must be '.'
  mut nf := 0
  mut ok := true
  mut going := true
  while going and i < nt {
    k := tok_at(pc, i).kind
    if k == 22 {
      if i + 1 >= nt or tok_at(pc, i + 1).kind != 1 { ok = false; going = false }
      else { nf = nf + 1; i = i + 2 }
    } else if is_assign_tok(k) { going = false }           ## '=' / 'op=' — end of the field path
    else { ok = false; going = false }                     ## '[' / '(' / operator → a call / read
  }
  ok and nf >= 1 and i < nt and is_assign_tok(tok_at(pc, i).kind)
}

## Is the cursor a NESTED TUPLE-element write `t.N.M = …` (EXACTLY two numeric `.<int>` levels ending in
## `=`)? Recognizes `ident . <int> . <int> =` — a base ident (kind 1), `.` (22), an int literal (kind 3),
## `.` (22), another int literal (kind 3), then `=` (kind 21). Requires the `=` DIRECTLY after the second
## index (a THIRD `.` for a deeper `t.A.B.C =` fails this, staying on the generic path; a `.<int>.field =`
## also fails — the 5th token would be an ident, not an int). Bounds-guarded against the token end. This
## distinguishes a nested tuple STORE from a nested tuple READ in the trailing return (`t.N.M + …`, no `=`).
tuple_nested_index_assign_starts := fn(pc : PC) -> bool {
  nt := ntoks(pc)
  if pc.idx + 5 >= nt { return false }
  if tok_at(pc, pc.idx).kind != 1 { return false }       ## base ident
  if tok_at(pc, pc.idx + 1).kind != 22 { return false }  ## '.'
  if tok_at(pc, pc.idx + 2).kind != 3 { return false }   ## int index N
  if tok_at(pc, pc.idx + 3).kind != 22 { return false }  ## '.'
  if tok_at(pc, pc.idx + 4).kind != 3 { return false }   ## int index M
  is_assign_tok(tok_at(pc, pc.idx + 5).kind)              ## '=' / 'op=' directly after M (no deeper `.`)
}

## Is the cursor a ONE-level TUPLE-element write `t.N = …` (a single numeric `.<int>` level ending in
## `=`)? Recognizes `ident . <int> =` — a base ident (kind 1), `.` (22), an int literal (kind 3), then
## `=` (kind 21). A `.<ident> =` (a STRUCT field write) FAILS here — the 3rd token is an ident (kind 1),
## not an int — so this NEVER intercepts `s.name = v`. A NESTED `t.N.M =` also fails (the 4th token is a
## `.`, not `=`), staying on `tuple_nested_index_assign_starts`. Bounds-guarded against the token end.
## Distinguishes a tuple STORE from a tuple READ in the trailing return (`t.N + …`, no `=`).
tuple_index_assign_starts := fn(pc : PC) -> bool {
  nt := ntoks(pc)
  if pc.idx + 3 >= nt { return false }
  if tok_at(pc, pc.idx).kind != 1 { return false }       ## base ident
  if tok_at(pc, pc.idx + 1).kind != 22 { return false }  ## '.'
  if tok_at(pc, pc.idx + 2).kind != 3 { return false }   ## int index N
  is_assign_tok(tok_at(pc, pc.idx + 3).kind)              ## '=' / 'op=' directly after N (no deeper `.`)
}

## Set statement `h`'s `next` link to `nx` (reconstruct the variant with the new tail handle).
## Factored out so both `p_stmts` and the fn-body parser link statement nodes the same way.
## Set the `next` link of the Stmt at handle `h` to `nx`, preserving the other payloads. READS
## the Stmt via the `st := deref(node_ptr(Stmt, …))` COPY-then-`match st` shape (the one emit_stmts
## uses, recognized as a deref-of-call enum copy) — NOT `match deref(<local ptr>)`, which the
## self-host lower MIS-COMPILED (it bound the arm payloads to the fn's own locals `tp`/`h`, so a
## rebuilt `Stmt.Assign(ns,nl,v,nx)` got ns=h / v=&node — corrupting every linked body Stmt; found
## by gdb: snode stored the Assign correctly (ns=21585) but set_stmt_next overwrote it). The WRITE
## uses the snode shape `deref(node_ptr(Stmt,…)) = upd` (a local). Layout-agnostic (works under both
## Stage-0 up-growing + the self-host down-growing).
pub set_stmt_next := fn(a : ptr(mut rt::Arena), h : ptr(mut Stmt), nx : ptr(mut Stmt)) {
  st := deref(stmt_p(Stmt, h))
  match st {
    Stmt::Assign(ns, nl, v, o) => { upd := Stmt.Assign(ns, nl, v, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::While(c, b, o) => { upd := Stmt.While(c, b, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::FieldAssign(bns, bnl, fns, fnl, fv, o) => { upd := Stmt.FieldAssign(bns, bnl, fns, fnl, fv, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::Return(rv, o) => { upd := Stmt.Return(rv, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::If(c, th, el, o) => { upd := Stmt.If(c, th, el, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::Match(sc, ah, o) => { upd := Stmt.Match(sc, ah, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::For(fns, fnl, flo, fhi, fb, o) => { upd := Stmt.For(fns, fnl, flo, fhi, fb, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::DerefAssign(ptr, dv, o) => { upd := Stmt.DerefAssign(ptr, dv, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::IndexAssign(ib, ii, iv, o) => { upd := Stmt.IndexAssign(ib, ii, iv, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::IndexFieldAssign(fia, fii, ifs, ifl, fiv, o) => { upd := Stmt.IndexFieldAssign(fia, fii, ifs, ifl, fiv, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::FieldPathAssign(pl, v, o) => { upd := Stmt.FieldPathAssign(pl, v, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::Loop(b, o) => { upd := Stmt.Loop(b, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::Break(bv, bd, o) => { upd := Stmt.Break(bv, bd, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::Continue(cd, o) => { upd := Stmt.Continue(cd, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::ExprStmt(e, o) => { upd := Stmt.ExprStmt(e, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::CompIf(c, th, el, o) => { upd := Stmt.CompIf(c, th, el, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::CompFor(vs, vl, iv, b, o) => { upd := Stmt.CompFor(vs, vl, iv, b, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::CompForRange(vs, vl, lo, hi, b, o) => { upd := Stmt.CompForRange(vs, vl, lo, hi, b, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::CompMatch(sc, ah, o) => { upd := Stmt.CompMatch(sc, ah, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::Unchecked(b, o) => { upd := Stmt.Unchecked(b, nx); deref(stmt_p(Stmt, h)) = upd }
    Stmt::AllocWith(ae, b, o) => { upd := Stmt.AllocWith(ae, b, nx); deref(stmt_p(Stmt, h)) = upd }
  }
}

## A statement list for a braced body (while/loop/for/statement-if/match bodies). Consume to the
## body's closing `}` (kind 13) or EOF; returns the head handle (0 = empty), each statement's
## `next` linking to the one after. A statement is EITHER a `stmt_starts` form (binding /
## assignment / control flow) OR a bare EXPRESSION statement — a call/`?` evaluated for effect
## (`vec::push(toks, t)` inside a loop/if branch), which `stmt_starts` deliberately does not match
## (a bare call can't be told from a tail-value expression by lookahead). Mirrors `parse_decl`'s
## function-body peel loop, minus its trailing-return-expression case (a braced statement body has
## no tail value). This relies on the source being brace-BALANCED: the older `stmt_starts`-loop
## (stop at the first non-statement token, let the caller consume `}`) tolerated an off-by-one
## brace by mis-consuming a stray token, which masked malformed input — this loop does not, so a
## genuinely unbalanced body is a real parse error rather than silently "recovered".
## Block-nesting depth for `defer` scope detection. The function BODY is parsed by `parse_decl`'s own
## loop (NOT via `p_stmts`), so it runs at depth 0; every NESTED braced block (`while`/`loop`/`if`/`match`
## arm/`unchecked`/…) is parsed via `p_stmts`, which bumps this. (The lean x86 lower now models nested
## defers via per-block frames, so the old depth-based rejection is gone; the counter remains as harness.)
mut P_DEFER_DEPTH := 0
## Set to 1 while the `defer { … }` BLOCK form's statements are being parsed, and checked by the `defer`
## handler: a `defer` lexically INSIDE a `defer { }` registers a cleanup inside a cleanup — ill-formed in
## this slice (the lower does not allow a defer's block to contain another defer) — so it is rejected.
mut P_DEFER_BLK_NEST := 0
p_stmts := fn(in out pc : PC) -> usize {
  P_DEFER_DEPTH = P_DEFER_DEPTH + 1
  mut head := 0
  mut tail := 0
  while cur(pc).kind != 13 and cur(pc).kind != 0 {
    ## Skip an optional `;` statement SEPARATOR (kind 30). The lean lexer emits no newline tokens,
    ## so statements are normally newline-separated with nothing in the stream between them; but the
    ## source may also write two statements on one line with a `;` (`{ cp = i64(i); i = n }`). Without
    ## this, the `;` would be parsed as a (bogus) expression statement and drift the cursor.
    if cur(pc).kind == 30 {
      pc.idx = pc.idx + 1
    } else {
      mut s := 0
      if stmt_starts(pc) {
        s = p_stmt(pc)
      } else {
        e := p_or(pc)
        s = snode(pc.arena, Stmt.ExprStmt(e, 0))
      }
      if head == 0 { head = s } else { set_stmt_next(pc.arena, stmt_last(tail, pc.arena), s) }
      tail = s
    }
  }
  P_DEFER_DEPTH = P_DEFER_DEPTH - 1
  head
}

## Parse one top-level binding into a `Decl`; fallible with `?`. A value binding is
## `name := <expr>`; a **function binding** `name := fn(p0 : T, p1 : T) -> R { <expr> }`
## (0..2 typed params, expression body) is recognized when `fn` (keyword, `tok_kw`) follows
## `:=`. The param type annotations and the result type are parsed but skipped (types are
## sema's job); the body is the canonical `p_cmp` expression.
## GENERIC-STRUCT decl tier: detect + consume a single type-parameter list `( T )` between a
## decl's name and its `:=` (the `Name(T) := struct { … }` form). Returns true (and advances the
## cursor past `( T )`) if one was present, false otherwise. Distinguished from a plain decl
## `Name := …` (a `:=` directly after the name) by the leading `(` followed by an ident. Only the
## single-type-param form is recognized (multi-param deferred). Bounds-guarded with `vec::vlen`.
## Factored out of `parse_decl` so that fn's own register/scratch budget stays unchanged.
skip_type_param := fn(in out pc : PC) -> bool {
  nt := ntoks(pc)
  if cur(pc).kind == 10 and pc.idx + 1 < nt and tok_at(pc, pc.idx + 1).kind == 1 {
    pc.idx = pc.idx + 3   ## consume '(' , the type-param ident `T` , ')'
    return true
  }
  false
}

## Parse a `{ member, … }` body into an arena-linked `FieldDecl` list (the head, 0 = empty),
## consuming the opening `{` (cur must be on it) through the closing `}`. A struct field is
## `name : T` (arity 0; a `[T; N]` field sets `wsize = N`); an enum variant is `name` or
## `name(T, …)` (arity = payload count). Shared by the `Name := struct/enum {…}` decl form AND
## the type-FUNCTION form `Name := fn(T : type) -> type { struct {…} }`.
parse_struct_members := fn(in out pc : PC, packed : bool) -> usize {
  pc.idx = pc.idx + 1                       ## '{'
  mut fhead := fld_null()
  mut ftail := fld_null()
  while cur(pc).kind != 13 and cur(pc).kind != 0 {
    ## FIELD-LEVEL layout attributes (spec Types §8; `@` is kind 33). `@offset(N)` gives the field an
    ## explicit BYTE offset (MMIO / register maps) — a PREFIX surface marker (`@offset(N) x : T`)
    ## consumed here so the following `name : T` stays aligned; the VALUE is recovered by the lower via a
    ## SOURCE-SCAN (`lower_layout::field_offset_attr`, mirroring `is_packed`), so no `FieldDecl` field is
    ## added — AST-neutral, the fixpoint stays stable. `@offset` shapes a BYTE-precise layout, so it is
    ## meaningful on a `@packed`/attributed struct (the byte-layout path); on the default word layout the
    ## lower ignores it. `@align(N)` (raise a field's alignment above natural — round the running byte
    ## cursor up to a multiple of N; the struct size rounds up to the max field alignment) is ALSO lowered
    ## now (`lower_layout::field_align_attr`, a backward source-scan like `@offset`). `@endian(big|little)`
    ## is ALSO lowered now (`lower_layout::field_endian_attr`, a backward source-scan like `@offset`): a
    ## `@endian(big)` scalar field byte-REVERSES its bytes on store/load (a `bswap`/`rolw` sized to the field
    ## width) so wire-format bytes land MSB-first on the little-endian x86 native; `@endian(little)` is the
    ## native order (no swap, but still accepted, not fail-loud). Field-level `@offset`/`@align`/`@endian`
    ## shape a BYTE-precise layout, so they are meaningful ONLY inside a `@packed`/attributed struct; on the
    ## default WORD layout the lower has no byte-offset path and would silently ignore them (a wrong-layout
    ## miscompile), so a field-level layout attribute on a NON-packed struct also fails LOUD. A STRUCT/ENUM
    ## decl-level attribute is consumed before this call.
    while cur(pc).kind == 33 {
      an := tok_at(pc, pc.idx + 1)
      anm := str_at(pc.src + an.start, an.len)
      if not (str_eq(anm, "offset") or str_eq(anm, "align") or str_eq(anm, "endian")) {
        panic("selfhost: unknown field-level layout attribute — only @offset(N)/@align(N)/@endian(big|little) are (v1 byte-layout slice)")
      }
      if not packed {
        panic("selfhost: field-level @offset(N)/@align(N)/@endian(...) require a @packed struct (the word layout has no byte-offset path)")
      }
      pc.idx = pc.idx + 2                     ## '@' offset/align
      if cur(pc).kind == 10 {                 ## '(' N ')' — the balanced argument list
        mut ld := 1
        pc.idx = pc.idx + 1
        while ld != 0 and cur(pc).kind != 0 {
          if cur(pc).kind == 10 { ld = ld + 1 }
          else if cur(pc).kind == 11 { ld = ld - 1 }
          pc.idx = pc.idx + 1
        }
      }
    }
    ## A struct field may carry the front-end-only `mut` marker. The marker is intentionally not added
    ## to FieldDecl: the comptime descriptor lower recovers it from the field-name source span (the same
    ## source-scan discipline as local_is_mut), keeping the bootstrap AST layout stable.
    if tok_kw(pc, "mut") { pc.idx = pc.idx + 1 }
    mn := cur(pc); pc.idx = pc.idx + 1      ## member name
    mut marity := 0
    mut mts := 0
    mut mtl := 0
    mut mwsize := 1                   ## field size in words (1 scalar; N for [T; N])
    if cur(pc).kind == 8 {                  ## ': T'  — a struct field
      pc.idx = pc.idx + 1                   ## ':'
      ## §8 layout attributes are a PREFIX surface (`@offset(N) x : T`, consumed above before the field
      ## name); an attribute placed AFTER the `:` (`x : @offset(N) T`) is misplaced. The type-parse below
      ## would capture the `@` token as the type head and silently DROP the attribute — a wrong-layout
      ## miscompile. Fail LOUD instead (fixpoint-neutral: no `src`/`lib` field carries this shape).
      if cur(pc).kind == 33 {
        panic("selfhost: a layout attribute (@offset/@align/@endian) must PREFIX the field, not follow the ':' — write `@offset(N) name : T`, not `name : @offset(N) T`")
      }
      if cur(pc).kind == 14 {               ## '[ T ; N ]' — a fixed-array field (multi-word)
        obr := cur(pc)                      ## the '[' — the field type span STARTS here
        pc.idx = pc.idx + 1                 ## '['
        pc.idx = pc.idx + 1                 ## element type T
        pc.idx = pc.idx + 1                 ## ';'
        if cur(pc).kind == 3 {              ## an INT-LITERAL length N (the common case)
          nt := cur(pc)                     ## the length N (an int literal token)
          mwsize = lit_val_at(pc, nt.start, nt.len)
          pc.idx = pc.idx + 1               ## N
        } else {
          ## TYP-10 slice A — a COMPUTED length EXPRESSION (`[u64; N/64]`, referencing a comptime
          ## VALUE parameter of the enclosing type-function, Comptime §10/§1): the length is not
          ## knowable at parse time, so record the `wsize == 0` SENTINEL ("evaluate at layout")
          ## and skip the expression tokens up to the `]`. The whole `[T; <expr>]` span is
          ## captured below as usual; `lower_layout::ct_arr_len` folds the expression against the
          ## instance's comptime-value bindings. `src/`/`lib/` declare only literal lengths →
          ## fixpoint-neutral.
          mwsize = 0
          while cur(pc).kind != 15 and cur(pc).kind != 0 { pc.idx = pc.idx + 1 }
        }
        cbr := cur(pc)                      ## the ']'
        pc.idx = pc.idx + 1                 ## ']'
        ## capture the WHOLE `[T; N]` span (not just the element type T) so the lower resolves the
        ## field as an ARRAY — sizes it (`field_words` via `mwsize`), and `display` recurses into it.
        mts = obr.start
        mtl = cbr.start + cbr.len - obr.start
      } else if cur(pc).kind == 10 {          ## '( T0 , … , TN )' — a TUPLE field (multi-word)
        ## capture the balanced `(…)` span + the WORD COUNT (top-level commas + 1, scalar components)
        ## — the general type branch below mis-stops at the first `,` for a leading `(`. Sizing the
        ## field by its component count lets a following field land past it, and `display` recurse in.
        otk := cur(pc)
        mut tdp := 0
        mut cmn := 0
        mut go2 := true
        while go2 and cur(pc).kind != 0 {
          k := cur(pc).kind
          if k == 10 { tdp = tdp + 1 }
          else if k == 11 { tdp = tdp - 1 ; if tdp == 0 { go2 = false } }
          else if k == 9 and tdp == 1 { cmn = cmn + 1 }
          pc.idx = pc.idx + 1
        }
        ctk := tok_at(pc, pc.idx - 1)         ## the ')'
        mts = otk.start
        mtl = ctk.start + ctk.len - otk.start
        mwsize = cmn + 1
      } else {
        ## a field type span: capture the head token, then skip any remaining type tokens
        ## (`ptr(mut T)` / `Vec(T)` etc.) up to the `,` / `}` so the next member aligns. The span is
        ## extended to cover the WHOLE type (head .. last token), so the lower can resolve a
        ## `ptr(mut S)` field's POINTEE (e.g. `deref(x.f)` of a pointer-to-struct field as a by-ref arg).
        ft := cur(pc); mts = ft.start; mtl = ft.len
        pc.idx = pc.idx + 1                 ## type head
        mut td := 0
        ## STOP the type-span skip at a top-level `=` (kind 21) too, so a struct-field DEFAULT
        ## (`x : T = <expr>`, spec Types §9.4 / TYP-8) is NOT swallowed into the type span; the
        ## `= <expr>` is skipped just below. (Neutral: no src/lib field carries a default → no `=`.)
        while cur(pc).kind != 0 and (td != 0 or (cur(pc).kind != 9 and cur(pc).kind != 13 and cur(pc).kind != 21)) {
          if cur(pc).kind == 10 { td = td + 1 }
          else if cur(pc).kind == 11 { td = td - 1 }
          pc.idx = pc.idx + 1
        }
        lt := tok_at(pc, pc.idx - 1)        ## last type token — extend the span to cover the full type
        mtl = lt.start + lt.len - mts
      }
      ## struct-field DEFAULT `= <expr>` (spec Types §9.4 / TYP-8): the value is NOT stored in
      ## `FieldDecl` (the seed's 8-word node limit); it is recovered by SOURCE-SCAN in
      ## `driver::collect_struct_table` and RE-LEXED at each construction site. Here we only SKIP the
      ## `= <expr>` tokens (paren/bracket-balanced, up to the top-level `,`/`}`) so the next member
      ## aligns. Neutral: no `src/`/`lib/` struct field declares a default → no `=` here → byte-identical.
      if cur(pc).kind == 21 {
        pc.idx = pc.idx + 1                 ## '='
        mut dd := 0
        while cur(pc).kind != 0 and (dd != 0 or (cur(pc).kind != 9 and cur(pc).kind != 13)) {
          dk := cur(pc).kind
          if dk == 10 or dk == 14 { dd = dd + 1 }
          else if dk == 11 or dk == 15 { dd = dd - 1 }
          pc.idx = pc.idx + 1
        }
      }
    } else if cur(pc).kind == 10 {          ## '( T , … )' — an enum variant payload
      pc.idx = pc.idx + 1                   ## '('
      ## Count ONE arity per payload TYPE, skipping each type PAREN-BALANCED — a payload may be
      ## multi-token (`ptr(Expr)`, `Vec(T)`), and its inner `)` must NOT be mistaken for the end of
      ## the variant's payload list. (The earlier token-at-a-time count let `ptr(Expr)`'s inner `)`
      ## terminate the loop, so a 6-payload variant like `FieldAssign(…, ptr(Expr), usize)` was
      ## mis-counted → `enum_max_arity` came up short → the matched payload local was under-sized →
      ## the high-index binding (`nx`) read out of bounds. Mirrors the struct-field type skip.)
      while cur(pc).kind != 11 and cur(pc).kind != 0 {
        pt := cur(pc)                       ## the head token of this payload's type
        ## An enum variant payload is a list of POSITIONAL TYPE-exprs (`V(T, …)`, grammar §130 variant
        ## ::= ident [ "(" type-expr {sep type-expr} ")" ]) — NOT named fields. A `name : T` component
        ## (a `:` after the head) is a common mistake (struct syntax); left unchecked, the field NAME was
        ## read as the payload TYPE (garbage span "x"), and a named-arg construction then lowered as a
        ## `StructLit` for a non-existent struct → `emit_struct_assign`'s slot math UNDERFLOWED and the
        ## I11 checked-arith trap fired (`ud2`/SIGILL). Fail LOUD with a clear message instead. src uses
        ## only positional payloads, so this never fires for the self-host build → fixpoint-neutral.
        if pc.idx + 1 < ntoks(pc) and tok_at(pc, pc.idx + 1).kind == 8 {
          panic("selfhost: enum variant payload must be positional types `V(T, ...)`, not named fields `V(name : T, ...)`")
        }
        mut first_array := false
        if marity == 0 {
          mts = pt.start
          mtl = pt.len
          ## A fixed-array payload is a TYPE span, not merely the `[` head token. The struct-field
          ## parser already preserves `[T; N]`; do the same for enum payloads so lower/layout can
          ## classify `Some([Row; N])`. The endpoint is captured after the balanced payload scan
          ## below, when the preceding token is the matching `]` for this shape.
          first_array = pt.kind == 14
        }
        marity += 1
        mut td := 0
        while cur(pc).kind != 0 and (td != 0 or (cur(pc).kind != 9 and cur(pc).kind != 11)) {
          if cur(pc).kind == 10 { td = td + 1 }
          else if cur(pc).kind == 11 { td = td - 1 }
          pc.idx = pc.idx + 1
        }
        if first_array {
          last_pt := tok_at(pc, pc.idx - 1)
          mtl = last_pt.start + last_pt.len - mts
        }
        if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }   ## ',' between payload types
      }
      pc.idx = pc.idx + 1                   ## ')'
    }
    ## spec Types §6.2 — an enum variant MAY PIN its discriminant with `= N` (grammar §130
    ## `variant ::= ident [ "(" … ")" ] [ "=" int ]`; N a NON-NEGATIVE comptime integer LITERAL, decimal
    ## or `0x…` hex). CONSUME the `= N` here so a following `=` is not mis-read as the next member's name
    ## (the current bug: `A = 5` parsed `=` and `5` as bogus extra variants → the pin was silently
    ## dropped and `variant_index` handed back the POSITIONAL index — an FFI/serialization silent
    ## miscompile). The VALUE is recovered by the lower's `variant_index` SOURCE-SCAN (the
    ## `@repr`/`@offset` discipline), so no `FieldDecl` field grows → AST-neutral, the TOOL-1 fixpoint
    ## holds. `src/`+`lib/` pin nothing, so this branch is never taken for the self-host build
    ## (byte-identical). `=` is token kind 21 (distinct from `==` kind 20). A `=` NOT followed by an
    ## integer literal (a signed `= -1`, or a `= EXPR` — both spec-additive, unspecified in v1) is a
    ## malformed pin → fail LOUD (never a silent mis-parse).
    if cur(pc).kind == 21 {                 ## `=`
      pc.idx = pc.idx + 1                   ## `=`
      if cur(pc).kind != 3 {
        panic("selfhost: enum discriminant pin `= N` requires a non-negative integer literal (spec Types §6.2 / grammar §130 `\"=\" int`)")
      }
      pin := cur(pc)
      lit_val_at(pc, pin.start, pin.len)   ## shared validator; failures stay source-located
      pc.idx = pc.idx + 1                   ## the integer literal N
      ## The pin is EXACTLY one integer literal (grammar `"=" int`). A token OTHER than `,`/`}` here means
      ## a trailing EXPRESSION (`= 0 - 1`) — otherwise the `= 0` is silently taken and the `- 1` mis-parses
      ## into bogus extra variants (the same silent-mis-parse class the pin fix closes). Fail LOUD.
      if cur(pc).kind != 9 and cur(pc).kind != 13 {
        panic("selfhost: enum discriminant pin must be a SINGLE integer literal, not an expression (spec Types §6.2 / grammar §130 `\"=\" int`)")
      }
    }
    fnew := fnode(pc.arena, FieldDecl(ns = mn.start, nl = mn.len, arity = marity, next = 0, ts = mts, tl = mtl, wsize = mwsize))
    if unchecked bitcast(usize, fhead) == 0 { fhead = fnew } else {
      old := deref(ftail)
      upd := FieldDecl(ns = old.ns, nl = old.nl, arity = old.arity, next = fnew, ts = old.ts, tl = old.tl, wsize = old.wsize)
      deref(ftail) = upd
    }
    ftail = fnew
    if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }   ## ',' between members
  }
  pc.idx = pc.idx + 1                       ## '}'
  fhead
}

pub parse_decl := fn(in out pc : PC, in out da : rt::Arena) -> Result(usize, ParseErr) {
  ## `@limits(<limit>, …)` — the translation unit's orthogonal-limit contract (I5/I9, FND-10/11). Parsed
  ## as its OWN kind-0 marker decl (alias-shaped: `value = Num(0)`, `ret_ts/ret_tl` = the FIRST limit's
  ## name span), so the lower skips it exactly like a module alias and `check` reads the limit from
  ## `ret`. First slice records the first limit only (single-limit `@limits(no_comptime)`); a multi-limit
  ## contract is a follow-up. src/ declares no `@limits`, so this path is never taken there — the
  ## self-host build is byte-identical (the TOOL-1 fixpoint holds).
  if cur(pc).kind == 33 and tok_at(pc, pc.idx + 1).kind == 1
     and str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "limits") {
    pc.idx = pc.idx + 2                                    ## '@' 'limits'
    if cur(pc).kind == 10 { pc.idx = pc.idx + 1 }          ## '('
    mut lts := 0
    if cur(pc).kind == 1 { lts = cur(pc).start }           ## start of the FIRST limit name
    while cur(pc).kind != 11 and cur(pc).kind != 0 { pc.idx = pc.idx + 1 } ## consume the whole list
    mut ltl := 0
    if lts != 0 { lastt := tok_at(pc, pc.idx - 1); ltl = (lastt.start + lastt.len) - lts }  ## span the WHOLE list
    if cur(pc).kind == 11 { pc.idx = pc.idx + 1 }          ## ')'
    ph := newnode(pc.arena, Expr.Num(0, 0, 0))
    ## `arity = 99` is the LIMITS-MARKER sentinel — distinguishes this alias-shaped kind-0 decl (whose
    ## `ret` span covers the FULL limit list, e.g. "no_comptime, no_alloc") from a real value/alias/brand
    ## decl, so `check`'s per-limit substring scan (`span_has_limit`) can't false-match a normal decl.
    return Result(usize, ParseErr).Ok(dnode(da, Decl(
      name_start = lts, name_len = ltl, value = ph,
      is_fn = false, kind = 0, arity = 99, is_generic = false, params_head = 0,
      body_stmts = 0, fields_head = 0, ret_ts = lts, ret_tl = ltl,
      mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = 0, alias_ts = 0, alias_tl = 0)))
  }
  ## An optional `pub` visibility prefix (Modules §4.1): every module of the self-host
  ## tree exports its surface with `pub`, so the parser must accept it. The lean compiler does
  ## not yet gate on visibility (all flattened symbols are reachable), so the marker is consumed
  ## and the declaration parses as if bare; recording the exported flag is additive.
  ## Consume any leading decl-position prefixes in either order: `pub` (visibility, above) and
  ## `@inline` (an OPTIMIZATION hint; the lean lower does not inline, so the fn parses as an
  ## ordinary definition, semantically identical). `@inline` is `@` + the ident `inline` (guarded so
  ## `@test`/`@abi` are untouched). src uses only `pub` here, so this is byte-identical for the
  ## self-host build (the TOOL-1 fixpoint holds); it just also accepts `@inline`/`@inline pub`/`pub`.
  ## Whether a DECLARATION-PREFIX `@packed` (`@packed \n S := struct {…}`, Declarations §2.3) prefixes
  ## this declaration — the mirror of the value-position `sm_packed` below. The LAYOUT half of the
  ## prefix spelling is honoured by `lower_layout::_decl_prefix_attr`, but the parser's own gate on the
  ## FIELD-level byte-layout attributes read only the value-position flag, so a prefix-`@packed` struct
  ## carrying an `@offset(N)` field was REJECTED as "requires a @packed struct" — legal code turned away.
  mut pfx_packed := false
  mut pfx_mut := false
  mut pfx_comptime := false
  mut want_pfx := true
  while want_pfx {
    if tok_kw(pc, "pub") { pc.idx = pc.idx + 1 }
    ## `mut NAME := <value>` — a MUTABLE module-level global (`@static` data). Consume the `mut`
    ## marker; the value decl parses as usual (kind 0) and the lower recovers the mutability by
    ## source scan (`local_is_mut`) to give it .data storage + label-addressed reads/writes.
    else if tok_kw(pc, "mut") { pc.idx = pc.idx + 1; pfx_mut = true }
    else if tok_kw(pc, "comptime") { pc.idx = pc.idx + 1; pfx_comptime = true }
    else if cur(pc).kind == 33 and tok_at(pc, pc.idx + 1).kind == 1 {
      pfxnm := str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len)
      if str_eq(pfxnm, "test") { want_pfx = false }
      ## `@abi(value)` is a CALLING-CONVENTION attribute on a FUNCTION (Functions §6; Types §8 is
      ## explicit that it is "never a type's data layout"), and its grammar spells it in VALUE
      ## position, next to the `fn-sig` it applies to (Grammar §3.11 `extern-decl`, §3.6 `abi-attr`).
      ## In declaration-prefix position it prefixes the BINDING, and the lower's `@abi` recovery
      ## (`is_syscall` here, `fn_is_naked` in the lower) only ever reads the value position. This
      ## already failed — but as a bare `parse error` pointing nowhere, because the loop just stopped
      ## and the name parse hit the `@`. Say what is wrong and where.
      else if str_eq(pfxnm, "abi") {
        reject_at(pc, "selfhost: `@abi(...)` is a CALLING-CONVENTION attribute on a FUNCTION (Functions §6), written next to the `fn` it applies to - move it after the `:=`: `w := @abi(syscall) fn(...) -> i64`", cur(pc).start)
      }
      else if str_eq(pfxnm, "section") {
        ## `@section("name")` — a storage PLACEMENT attribute on a static binding (Memory §2.3/§2.4):
        ## consume `@ section ( "name" )`. The section NAME is recovered by the lower via a source scan
        ## (`global_section_name`, like `local_is_mut`/`@inline`), so no Decl field is needed here.
        pc.idx = pc.idx + 2                                   ## '@' 'section'
        if cur(pc).kind == 10 { pc.idx = pc.idx + 1 }         ## '('
        if cur(pc).kind == 4 { pc.idx = pc.idx + 1 }          ## the "name" string literal
        if cur(pc).kind == 11 { pc.idx = pc.idx + 1 }         ## ')'
      }
      else if str_eq(pfxnm, "export") {
        ## `@export("name")` — a linker-symbol directive (Modules §6.3): the declaration additionally
        ## emits the EXACT symbol `name` regardless of the `pub` chain (entry points, C interop).
        ## Consume `@ export ( "name" )`; the export NAME is recovered by the lower via a source scan
        ## (`export_name`, like `@section`), so no Decl field is needed. src uses no `@export` → the
        ## self-host build never takes this path (fixpoint-neutral).
        pc.idx = pc.idx + 2                                   ## '@' 'export'
        if cur(pc).kind == 10 { pc.idx = pc.idx + 1 }         ## '('
        if cur(pc).kind == 4 { pc.idx = pc.idx + 1 }          ## the "name" string literal
        if cur(pc).kind == 11 { pc.idx = pc.idx + 1 }         ## ')'
      }
      ## `@offset(N)` is the FIELD lever of Types §8 ("give a FIELD an explicit offset"): a byte
      ## position INSIDE an aggregate. A declaration — a binding or a type — has no offset to give,
      ## so the spelling has NO lowering, and it used to be consumed here and thrown away without a
      ## word (`@offset(8) S := struct {…}` laid out exactly like the un-attributed struct). Types §8
      ## calls the levers non-universal — "each targets a specific representational degree of freedom,
      ## applying only where that freedom exists" — so this is a target-kind reject, not a gap.
      else if str_eq(pfxnm, "offset") {
        reject_at(pc, "selfhost: `@offset(N)` is a FIELD layout attribute, not valid on a declaration - Types §8 gives a FIELD an explicit byte offset inside a `@packed` aggregate (`@packed S := struct { a : u32, @offset(0) b : u32 }`); a binding or a type has no offset to give", cur(pc).start)
      }
      ## `@endian(...)` shapes a type's byte order (Types §8). The lower has NO type-level endian swap
      ## (only the per-FIELD one, `field_endian_attr`), so consuming this as a no-op is a layout
      ## MISCOMPILE with no diagnostic — the value-position spelling (`S := @endian(big) struct {…}`)
      ## has failed loud all along, and this one silently laid the struct out native-order.
      else if str_eq(pfxnm, "endian") {
        reject_at(pc, "selfhost: a TYPE-level `@endian(...)` is not yet supported (v1 byte-layout slice) - there is no type-level endian swap in the lower; put it on the FIELDS of a `@packed` struct instead (`@endian(big) v : u32`, Types §8)", cur(pc).start)
      }
      ## `@niche(producer)` (Types §8/§6.2) declares an invalid bit-pattern an enclosing enum may fold
      ## into. The lower reads NO user niche: `is_niche_folded` recognizes exactly `Option(ptr(T))` by
      ## the pointer's own null pattern. So a user-written `@niche` never had an effect, and this
      ## position dropped it silently (the value position died in the LINKER instead — see below).
      else if str_eq(pfxnm, "niche") {
        reject_at(pc, "selfhost: `@niche(...)` is not yet supported (Types §8) - the only folded niche the lower knows is the pointer null of `Option(ptr(T))`, read from the type itself; a user-declared niche producer has no lowering", cur(pc).start)
      }
      else if str_eq(pfxnm, "repr") or str_eq(pfxnm, "packed") or str_eq(pfxnm, "align") {
        ## Layout attributes (TYP § layout levers) in DECLARATION-PREFIX position (Declarations §2.3 /
        ## Grammar §3.2 `modifier ::= … | attribute`). Consume the marker AND an optional balanced
        ## argument list (`@repr(u8)`, `@align(16)`, …) so the following declaration name stays
        ## aligned; the marker text stays in `src` and the lower recovers it by the BACKWARD scan
        ## `lower_layout::_decl_prefix_attr` (`is_packed` / `struct_align_attr` / `enum_repr_ty`).
        ## `@packed` additionally enables the FIELD-level byte-layout attributes inside the body, so
        ## record it for the `parse_struct_members` gate below — exactly as the value-position spelling
        ## does with `sm_packed`.
        if str_eq(pfxnm, "packed") { pfx_packed = true }
        pc.idx = pc.idx + 2                                   ## '@' attr
        if cur(pc).kind == 10 {
          mut ldepth := 1
          pc.idx = pc.idx + 1
          while ldepth != 0 and cur(pc).kind != 0 {
            if cur(pc).kind == 10 { ldepth = ldepth + 1 }
            else if cur(pc).kind == 11 { ldepth = ldepth - 1 }
            pc.idx = pc.idx + 1
          }
        }
      }
      else { pc.idx = pc.idx + 2 }
    }
    else { want_pfx = false }
  }
  if pfx_mut and pfx_comptime { reject_at(pc, "selfhost: `comptime mut` is invalid — a comptime binding is immutable (Comptime §2.2)", cur(pc).start) }
  if pfx_comptime and (tok_kw(pc, "if") or tok_kw(pc, "for") or tok_kw(pc, "match") or cur(pc).kind == 12) {
    reject_at(pc, "selfhost: standalone top-level `comptime if/for/match` is not a module item (Grammar §130)", cur(pc).start)
  }
  ## `@test("desc") fn() { … }` (TOOL-5) — a TEST function (kind 5). Anonymous: recorded as a
  ## kind-5 fn whose name span is the description (for reporting). The lower emits it under a
  ## synthetic `__test<i>` label and the `test` runner (driver) calls each in turn, checking its
  ## `Result(usize, str)` tag (Ok = pass). A `@test` takes NO parameters (TOOL-5), so the param
  ## list is consumed empty. ADDITIVE — a non-`@test` decl flows through the existing path below.
  ## (Recognized at decl START — distinct from a value-position `@abi(syscall)`, which follows a
  ## `name :=`; only `@test` appears where a decl name is expected.)
  if cur(pc).kind == 33 and tok_at(pc, pc.idx + 1).kind == 1
     and str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "test") {
    pc.idx = pc.idx + 1                       ## '@'
    pc.idx = pc.idx + 1                       ## 'test'
    mut ds := 0
    mut dl := 0
    if cur(pc).kind == 10 {                   ## '('
      pc.idx = pc.idx + 1
      if cur(pc).kind == 4 {                  ## the description string literal (span covers quotes)
        dt := cur(pc); ds = dt.start + 1; dl = dt.len - 2   ## inner span (strip the quotes)
        pc.idx = pc.idx + 1
      }
      if cur(pc).kind == 11 { pc.idx = pc.idx + 1 }   ## ')'
    }
    if tok_kw(pc, "fn") { pc.idx = pc.idx + 1 }       ## 'fn'
    if cur(pc).kind == 10 { pc.idx = pc.idx + 1 }     ## '('
    if cur(pc).kind == 11 { pc.idx = pc.idx + 1 }     ## ')' — a test takes no parameters
    ## Capture the `-> R` return type HEAD (like the normal fn path): the lower needs it to know
    ## the test returns a `Result` (a wide register return) — without it the `return Result(…).Err(…)`
    ## mis-lowers to a scalar 0, so the runner's `Ok`-tag check would pass every test. Then skip any
    ## remaining return-type tokens up to the body '{' (kind 12).
    mut trt := Token(kind = 0, start = 0, len = 0)
    if cur(pc).kind == 6 {                            ## '->'
      pc.idx = pc.idx + 1
      trt = cur(pc)                                   ## result type head (e.g. `Result`)
      pc.idx = pc.idx + 1
    }
    while cur(pc).kind != 12 and cur(pc).kind != 0 { pc.idx = pc.idx + 1 }
    pc.idx = pc.idx + 1                       ## '{'
    ## body: statements + an optional trailing return expr (the fn-body shape, kept local here).
    mut shead := 0
    mut stail := 0
    mut tbody := newnode(pc.arena, Expr.Num(0, 0, 0))
    while cur(pc).kind != 13 and cur(pc).kind != 0 {
      if stmt_starts(pc) {
        s := p_stmt(pc)
        if shead == 0 { shead = s } else { set_stmt_next(pc.arena, stmt_last(stail, pc.arena), s) }
        stail = s
      } else {
        e := p_or(pc)
        if cur(pc).kind == 13 or cur(pc).kind == 0 { tbody = e } else {
          es := snode(pc.arena, Stmt.ExprStmt(e, 0))
          if shead == 0 { shead = es } else { set_stmt_next(pc.arena, stmt_last(stail, pc.arena), es) }
          stail = es
        }
      }
    }
    tstmts := shead
    pc.idx = pc.idx + 1                       ## '}'
    return Result(usize, ParseErr).Ok(dnode(da, Decl(
      name_start = ds, name_len = dl, value = tbody,
      is_fn = true, kind = 5, arity = 0, is_generic = false, params_head = 0,
      body_stmts = tstmts, fields_head = 0, ret_ts = trt.start, ret_tl = trt.len,
      mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = 0, alias_ts = 0, alias_tl = 0)))
  }
  ## DESTRUCTURE import — `(A, B, …) := mod` (e.g. `(Arg, Arm, Expr) := ast`): brings each name
  ## into scope as an alias for `mod::Name`. The self-host compiler resolves type/fn references by
  ## NAME over the whole compiled decl set, so the imported names already resolve to their `mod`'s
  ## decls (fed alongside via compile_files) — the import itself is a parse-only no-op (kind 0,
  ## empty name, `Num(0)` placeholder; matches no lookup, emits no code). Recognized by a leading
  ## `(` (kind 10) where a decl name (ident) is expected.
  if cur(pc).kind == 10 {
    gopen := cur(pc)                          ## the '(' token — start of the verbatim import span
    pc.idx = pc.idx + 1                       ## '('
    while cur(pc).kind != 11 and cur(pc).kind != 0 { pc.idx = pc.idx + 1 }   ## names + ','
    pc.idx = pc.idx + 1                       ## ')'
    if cur(pc).kind == 5 { pc.idx = pc.idx + 1 }   ## ':='
    if cur(pc).kind == 1 { pc.idx = pc.idx + 1 }   ## head module ident
    while cur(pc).kind == 7 {
      pc.idx = pc.idx + 1                     ## '::'
      pc.idx = pc.idx + 1                     ## next path ident
    }
    php := newnode(pc.arena, Expr.Num(0, 0, 0))
    ## Retain the VERBATIM source span `(A, B, …) := mod` in `ret_ts`/`ret_tl` so `alatyr fmt` can
    ## reproduce the destructure import (its names/path are otherwise dropped — a parse-only no-op).
    ## `name_len` stays 0, so this decl still matches no name lookup and emits no code (fixpoint-neutral:
    ## the extra span is read ONLY by fmt); the last consumed token is `tok_at(pc, pc.idx - 1)`.
    lastt := tok_at(pc, pc.idx - 1)
    return Result(usize, ParseErr).Ok(dnode(da, Decl(
      name_start = 0, name_len = 0, value = php,
      is_fn = false, kind = 0, arity = 0, is_generic = false, params_head = 0,
      body_stmts = 0, fields_head = 0, ret_ts = gopen.start, ret_tl = lastt.start + lastt.len - gopen.start,
      mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = 0, alias_ts = 0, alias_tl = 0)))
  }
  name := cur(pc)
  ## Operator-fn NAMES: arithmetic 16/17/18/19/29, comparison 20/24..28, AND the bitwise glyphs 34
  ## `&` / 35 `|` / 36 `^` (OP-1 — the routing via `op_symbol`/`operator_decl_idx` already recognizes
  ## these three; the parser name-gate was the only barrier to declaring `& := fn(…)` over a user type).
  ## src/ declares no glyph-bitwise operator fn, so admitting these names is dormant → fixpoint-neutral.
  is_opnm := name.kind == 16 or name.kind == 17 or name.kind == 18 or name.kind == 19 or name.kind == 20 or name.kind == 24 or name.kind == 25 or name.kind == 26 or name.kind == 27 or name.kind == 28 or name.kind == 29 or name.kind == 34 or name.kind == 35 or name.kind == 36
  if name.kind != 1 and not is_opnm { return Result(usize, ParseErr).Err(ParseErr.Expected(1)) }
  pc.idx = pc.idx + 1
  ## GENERIC-STRUCT decl tier: a struct parameterized by a type `Name(T) := struct { … }`. After
  ## the `Name` ident a `(` (kind 10) introduces the single type parameter `T` (an ident, kind 1),
  ## closed by `)` (kind 11), then `:=`. `skip_type_param` detects + consumes the `(T)` (the helper
  ## keeps `parse_decl`'s own scratch budget unchanged) and returns whether one was present.
  is_gen_struct := skip_type_param(pc)
  ## `NAME : T = <value>` — a TYPE-ANNOTATED module-level binding (kind 0): the top-level dual of the
  ## annotated local `x : T = v`. Without this, `parse_decl` requires `:=` (kind 5) after the name, so
  ## an annotated global (incl. `mut STATE : S = …`, and a bare `K : u64 = …`) is a spurious parse
  ## error (`Expected(5)`). The type annotation is sema's concern; the lower sizes the slot from the
  ## VALUE (as for `:=`), so — mirroring the statement form — skip from `:` to the binding `=` (kind
  ## 21) and parse the value as a plain expression (fn/struct/enum decls use `:=`, never `: T =`). The
  ## annotation is dropped (ret_ts/tl = 0) to avoid the alias/brand paths' type-span interpretation.
  ## Only fires when the token after the name is `:` (kind 8) — the current error case — so `:=` decls
  ## are byte-identical and src/ (which uses only `:=` at top level) keeps the TOOL-1 fixpoint.
  if cur(pc).kind == 8 {
    pc.idx = pc.idx + 1                         ## ':'
    while cur(pc).kind != 21 and cur(pc).kind != 0 { pc.idx = pc.idx + 1 }   ## scan the type to '='
    if cur(pc).kind == 21 { pc.idx = pc.idx + 1 }   ## '='
    aroot := p_or(pc)
    ## optional trailing `when <comptime-predicate>` DECLARATION-GUARD on the type-annotated binding
    ## (Comptime §7.1/§9; CT-5): `K : u64 = 256 when target.arch == Arch.x86_64`. Same clause the fn /
    ## inferred-binding paths parse — `p_or` stops at the `when` keyword (never an operand). Dormant for
    ## the self-host build (`src/`+`lib/` carry no `when` on a typed binding) → fixpoint-neutral.
    mut awhen := unchecked bitcast(ptr(Expr), 0)
    if tok_kw(pc, "when") {
      pc.idx = pc.idx + 1                       ## 'when'
      awhen = p_or(pc)
    }
    return Result(usize, ParseErr).Ok(dnode(da, Decl(
      name_start = name.start, name_len = name.len, value = aroot,
      is_fn = false, kind = 0, arity = 0, is_generic = false, params_head = 0,
      body_stmts = 0, fields_head = 0, ret_ts = 0, ret_tl = 0,
      mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = awhen, alias_ts = 0, alias_tl = 0)))
  }
  if cur(pc).kind != 5 { return Result(usize, ParseErr).Err(ParseErr.Expected(5)) }
  pc.idx = pc.idx + 1                         ## ':='
  ## `Name := T.require(pred)` — the UFCS spelling of a validity-contract alias (Types §8.1).
  ## This path mirrors the existing `@require(pred) T` path for a bare type name; the predicate remains
  ## in source for `lower_layout::require_pred`, so no AST/Decl field changes. Named aggregate types are
  ## accepted here as well. Inline aggregate declarations and other multi-token type forms remain
  ## fail-loud until their own layout/ABI slices are implemented.
  if cur(pc).kind == 1 and tok_at(pc, pc.idx + 1).kind == 22
     and tok_at(pc, pc.idx + 2).kind == 1
     and str_eq(str_at(pc.src + tok_at(pc, pc.idx + 2).start, tok_at(pc, pc.idx + 2).len), "require")
     and tok_at(pc, pc.idx + 3).kind == 10 {
    ut := cur(pc)
    pc.idx = pc.idx + 4                         ## type, '.', 'require', '('
    mut rd := 1
    while rd != 0 and cur(pc).kind != 0 {
      if cur(pc).kind == 10 { rd = rd + 1 }
      else if cur(pc).kind == 11 { rd = rd - 1 }
      pc.idx = pc.idx + 1
    }
    ph := newnode(pc.arena, Expr.Num(0, 0, 0))
    return Result(usize, ParseErr).Ok(dnode(da, Decl(
      name_start = name.start, name_len = name.len, value = ph,
      is_fn = false, kind = 0, arity = 1, is_generic = false, params_head = 0,
      body_stmts = 0, fields_head = 0, ret_ts = ut.start, ret_tl = ut.len,
      mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = 0, alias_ts = 0, alias_tl = 0)))
  }
  ## MODULE-ALIAS import — `name := mod::sub` (e.g. `vec := alloc::vec`, `io := std::io`): the RHS
  ## is a qualified module path (`::`, kind 7), not a fn/struct/enum/value. Consume `ident (:: ident)+`
  ## and emit a no-op decl (kind 0, placeholder value) — the alias is a compile-time name binding the
  ## lower ignores. (Resolving a USE `vec::push` THROUGH the alias is a later nameres step; an UNUSED
  ## import — e.g. in `ast.al` — just needs to parse. The qualified-CALL form `mod::f(args)` is a
  ## value expression handled by `p_or`, so it is NOT matched here — this fires only on a bare path.)
  if cur(pc).kind == 1 and tok_at(pc, pc.idx + 1).kind == 7 {
    ## Look ahead over `ident (:: ident)*` WITHOUT consuming, to the token past the path.
    mut j := pc.idx + 1                ## at the first '::'
    ## Each step assumes a `:: ident` PAIR. A DANGLING `::` (a file truncated at `x := rt::`) made
    ## `j` step one PAST the EOF sentinel, `is_alias` fire, and the decl be recorded with an alias
    ## span running to the end of the buffer — a silent accept. Require the segment name.
    while tok_at(pc, j).kind == 7 {
      if tok_at(pc, j + 1).kind == 0 {
        zae := reject_eof(pc, "selfhost: a `::` must be followed by a path SEGMENT name - the input ends after it, so this qualified path is incomplete (a truncated file, a partial copy, or a bad merge)")
      }
      j = j + 2
    }
    ## A bare path (no trailing `(`) is a module alias. A trailing `(` would normally be a qualified
    ## CALL `mod::f(args)` (a value) left to `p_or` — EXCEPT the lexer emits no newline tokens, so the
    ## `(` of the NEXT decl (a destructure import `(A, B, …) := mod`) directly follows the path here.
    ## Disambiguate: if the `(`-group is followed by `:=` (kind 5), it is that next destructure decl,
    ## so the current `name := mod::path` is still a bare-path ALIAS (do not swallow the `(…)`).
    mut is_alias := false
    if tok_at(pc, j).kind != 10 { is_alias = true }
    else {
      nt := ntoks(pc)
      mut depth := 0
      mut k := j
      while k < nt {
        kk := tok_at(pc, k).kind
        if kk == 10 { depth = depth + 1 }
        else if kk == 11 {
          depth = depth - 1
          if depth == 0 {
            k += 1
            break
          }
        }
        k += 1
      }
      if k < nt and tok_at(pc, k).kind == 5 { is_alias = true }
    }
    if is_alias {
      ## Preserve the alias RHS path span (e.g. `strbuf::StrBuf`) in ret_ts/ret_tl so a TYPE alias
      ## (`String := strbuf::StrBuf`) can be resolved to its target struct by `struct_decl_of`. The
      ## decl stays kind 0 (the lower emits nothing for it); a MODULE alias (`vec := alloc::vec`)
      ## stores its path too but resolves to no struct (harmless). The span runs from the first path
      ## ident to the last (j-1); j is one past the path.
      firsttok := cur(pc)
      lasttok := tok_at(pc, j - 1)
      als_ts := firsttok.start
      als_tl := (lasttok.start + lasttok.len) - firsttok.start
      pc.idx = j                              ## consume the whole path (cursor left at the next decl)
      ph := newnode(pc.arena, Expr.Num(0, 0, 0))
      return Result(usize, ParseErr).Ok(dnode(da, Decl(
        name_start = name.start, name_len = name.len, value = ph,
        is_fn = false, kind = 0, arity = 0, is_generic = false, params_head = 0,
        body_stmts = 0, fields_head = 0, ret_ts = als_ts, ret_tl = als_tl,
        mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = 0, alias_ts = 0, alias_tl = 0)))
    }
  }
  ## `@abi(syscall) fn(...) -> R` — a SYSCALL-ABI fn (Stdlib §7 / ABI): a bodyless declaration
  ## whose ABI is the raw Linux syscall convention (param 0 = the syscall number in %rax, the
  ## remaining params in %rdi/%rsi/%rdx/%r10/%r8/%r9). Recognized by the `@` token (kind 33)
  ## before `fn`; skip `@ abi ( syscall )` and mark the decl (kind 4). lower emits a trampoline
  ## that maps the System V argument registers to the syscall registers + `syscall`/`ret`.
  ## Only consume `@abi(syscall)` when the effector really is `abi` — a bare `@` handler would also
  ## swallow a following `@owning struct`/`@inline fn` as if it were `@ abi ( syscall )` (5 tokens of
  ## garbage → parse error). Guarded on the ident after `@`, so other decl-position effectors fall
  ## through to their own handling (`@owning` → the struct/enum path below). src uses only `@abi` in
  ## decl position, so this stays byte-identical for the self-host build (the TOOL-1 fixpoint holds).
  ## skip any value-position `@ident` effector that is NOT `@abi` (e.g. `@convert`, `@inline`
  ## when it follows `:=`): the lean lower ignores these markers and parses the value bare.
  ## `name := @extern fn(…) -> R` / `@extern("sym") fn(…)` (Modules §7): a bodyless FFI import — the
  ## body lives in another object; calls resolve to the EXTERNAL symbol (the declared name by default,
  ## or the exact `@extern("sym")`, §7.2). Recognized here (value-position, like `@abi`); the fn parses
  ## bodyless (kind 1, `is_extern`) and the lower routes calls + skips its definition (source-scan
  ## `extern_symbol`). src declares no `@extern` → fixpoint-neutral.
  ## Whether a value-position `@packed` prefixes the type — enables field-level byte-layout attrs
  ## (`@offset`/`@align`) inside the struct body (they fail loud on the default word layout). Set below
  ## where the value-position `@ident` effector is consumed (`@packed struct`), and also at the stacked
  ## `@… struct` consumer further down.
  mut sm_packed := pfx_packed
  mut is_extern := false
  if cur(pc).kind == 33 and tok_at(pc, pc.idx + 1).kind == 1 and str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "extern") {
    is_extern = true
    pc.idx = pc.idx + 2                                     ## '@' 'extern'
    if cur(pc).kind == 10 {                                 ## optional `("sym")` exact name
      pc.idx = pc.idx + 1                                   ## '('
      if cur(pc).kind == 4 { pc.idx = pc.idx + 1 }          ## the "sym" string literal
      if cur(pc).kind == 11 { pc.idx = pc.idx + 1 }         ## ')'
    }
  }
  else if cur(pc).kind == 33 and tok_at(pc, pc.idx + 1).kind == 1 and str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "require") {
    ## `Name := @require(pred) T` — a VALIDITY CONTRACT (spec Types §8.1). Consume `@ require ( … )`
    ## (the predicate, a balanced group), then the SINGLE-token underlying type `T`. Record it as
    ## a BRAND-SHAPED decl (kind 0, arity 1, ret_ts/ret_tl = `T`) so `Name(v)` resolves/converts to `T`;
    ## a named struct/enum is accepted by the aggregate lowering slice below.
    ## and its value flows as `T`; the `@require(pred)` marker text stays in `src` for the lower's
    ## source-scan (`lower_layout::require_pred`) — AST-neutral, mirroring `is_packed`/`@repr`. At the
    ## `Name(v)` construction site the lower emits the checked predicate trap (§8.1 "exactly like
    ## narrowing"). src/lib declare no `@require`, so this path is never taken for the self-host build
    ## (the TOOL-1 fixpoint holds). Named-fn predicates remain source-only; inline `fn(v){…}` predicates
    ## are retained as Expr::Lambda values and lifted by the driver to synthetic predicate functions.
    pc.idx = pc.idx + 2                                    ## '@' 'require'
    ## Preserve an inline predicate as an Expr::Lambda so the driver can lift it to a synthetic
    ## function declaration. Named predicates remain source-only, as before.
    mut rph := newnode(pc.arena, Expr.Num(0, 0, 0))
    if cur(pc).kind == 10 {
      pc.idx = pc.idx + 1
      if tok_kw(pc, "fn") {
        rph = p_or(pc)
        if cur(pc).kind == 11 { pc.idx = pc.idx + 1 }
      } else {
        ## Named predicate: retain the old balanced skip and keep the AST placeholder.
        mut rd := 1
        while rd != 0 and cur(pc).kind != 0 {
          if cur(pc).kind == 10 { rd = rd + 1 }
          else if cur(pc).kind == 11 { rd = rd - 1 }
          pc.idx = pc.idx + 1
        }
      }
    }
    ## The underlying type starts with a named type head (`u32`, a brand, `ptr`, a named struct/enum, or
    ## a generic type constructor). Inline aggregate declarations (`struct`/`enum`/`union`) remain a
    ## later slice, but a parenthesized multi-token type such as `ptr(mut T)` is retained as one complete
    ## type span so the brand conversion and contract call see the actual pointer type rather than only
    ## the `ptr` head.
    if tok_kw(pc, "struct") or tok_kw(pc, "enum") or tok_kw(pc, "union") {
      panic("selfhost: an inline aggregate in `@require(pred) T` is not yet supported — name the aggregate type (Types §8.1)")
    }
    ut := cur(pc)                                          ## the underlying type head token `T`
    mut utl := ut.len
    pc.idx = pc.idx + 1
    if cur(pc).kind == 10 {
      mut td := 1
      pc.idx = pc.idx + 1                               ## consume the opening `(`
      while td != 0 and cur(pc).kind != 0 {
        if cur(pc).kind == 10 { td = td + 1 }
        else if cur(pc).kind == 11 { td = td - 1 }
        pc.idx = pc.idx + 1
      }
      if td != 0 { panic("selfhost: malformed multi-token underlying type in @require") }
      last := tok_at(pc, pc.idx - 1)
      utl = (last.start + last.len) - ut.start
    }
    return Result(usize, ParseErr).Ok(dnode(da, Decl(
      name_start = name.start, name_len = name.len, value = rph,
      is_fn = false, kind = 0, arity = 1, is_generic = false, params_head = 0,
      body_stmts = 0, fields_head = 0, ret_ts = ut.start, ret_tl = utl,
      mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = 0, alias_ts = 0, alias_tl = 0)))
  }
  else if cur(pc).kind == 33 and tok_at(pc, pc.idx + 1).kind == 1 and not str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "abi") {
    ## `@endian(...)` shapes a type's byte order; the lower has NO endian swap yet, so a type-level
    ## `@endian` (like a field-level one) fails LOUD — silently consuming it as a no-op would be a
    ## layout MISCOMPILE. src/lib declare no `@endian`, so this is fixpoint-neutral.
    if str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "endian") {
      reject_at(pc, "selfhost: a TYPE-level `@endian(...)` is not yet supported (v1 byte-layout slice) - there is no type-level endian swap in the lower; put it on the FIELDS of a `@packed` struct instead (`@endian(big) v : u32`, Types §8)", cur(pc).start)
    }
    ## `@offset(N)` is the FIELD lever of Types §8 — a byte position INSIDE an aggregate. In VALUE
    ## position it prefixes a type or a value, neither of which has an offset to give, and it used to
    ## be consumed and thrown away without a word (`S := @offset(8) struct {…}` laid out unchanged).
    ## Its declaration-prefix twin is rejected the same way.
    if str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "offset") {
      reject_at(pc, "selfhost: `@offset(N)` is a FIELD layout attribute, not valid on a type or a value - Types §8 gives a FIELD an explicit byte offset inside a `@packed` aggregate (`@packed S := struct { a : u32, @offset(0) b : u32 }`)", cur(pc).start)
    }
    ## `@niche(producer)` (Types §8/§6.2) has no lowering: `is_niche_folded` recognizes exactly
    ## `Option(ptr(T))` from the type itself and reads NO user-written niche. Consuming it left the
    ## underlying type as the declaration's VALUE expression, so `N := @niche(0) u64` compiled to a
    ## reference to an undefined symbol `N` and died in the LINKER — loud, but at the wrong layer and
    ## with nothing pointing at the attribute. Reject it here, located, like `@endian`.
    if str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "niche") {
      reject_at(pc, "selfhost: `@niche(...)` is not yet supported (Types §8) - the only folded niche the lower knows is the pointer null of `Option(ptr(T))`, read from the type itself; a user-declared niche producer has no lowering", cur(pc).start)
    }
    ## `@section("name")` is a STORAGE/PLACEMENT attribute on a BINDING — "it places a *static binding*
    ## in a named section" (Types §8, Memory §2.3/§2.4) — and Grammar §3.11/CG-6 has `@` decorate a
    ## CONSTRUCT and NEVER wrap an expression. So the only legal spelling is the declaration prefix
    ## `@section(".x") mut X := 42`; after the `:=` the attribute prefixes the VALUE, which has no
    ## placement to give. It used to be consumed and dropped without a word, so the binding silently
    ## landed in the derived `.data` and no `.section` directive was ever emitted.
    if str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "section") {
      reject_at(pc, "selfhost: `@section(\"...\")` places a static BINDING in a named section (Types §8, Memory §2.3), so it prefixes the DECLARATION, not the value - write `@section(\".mydata\") mut X := 42`", cur(pc).start)
    }
    if str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "packed") { sm_packed = true }
    pc.idx = pc.idx + 2
    ## a layout attribute carrying an argument list (`@repr(T)` before an enum, spec Types §8) leaves
    ## the balanced `( … )` after the `@ ident`: consume it so the following `struct`/`enum`/`fn` parses.
    ## The marker text stays in `src` for the lower's source-scan (`enum_repr_ty`) — no AST field added.
    ## src has no arg-bearing value-position `@ident` (non-abi) effector, so this is fixpoint-neutral.
    if cur(pc).kind == 10 {
      mut ld := 1
      pc.idx = pc.idx + 1
      while ld != 0 and cur(pc).kind != 0 {
        if cur(pc).kind == 10 { ld = ld + 1 }
        else if cur(pc).kind == 11 { ld = ld - 1 }
        pc.idx = pc.idx + 1
      }
    }
  }
  mut is_syscall := false
  if cur(pc).kind == 33 and tok_at(pc, pc.idx + 1).kind == 1 and str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "abi") {
    seltok := tok_at(pc, pc.idx + 3)          ## the ABI selector: `syscall` / `naked`
    pc.idx = pc.idx + 1                       ## '@'
    pc.idx = pc.idx + 1                       ## 'abi'
    pc.idx = pc.idx + 1                       ## '('
    pc.idx = pc.idx + 1                       ## selector
    pc.idx = pc.idx + 1                       ## ')'
    ## `@abi(syscall)` → the syscall-ABI trampoline (kind 4, bodyless). `@abi(naked)` → an ORDINARY
    ## fn parse (kind 1, WITH a body): `is_syscall` stays false, so the `fn` below parses the raw body;
    ## the lower recovers the naked marker by source-scan (`fn_is_naked`) and emits the body with NO
    ## prologue/epilogue (spec ch.80 — a raw-asm fn). src uses only `@abi(syscall)`, so this stays
    ## byte-identical for the self-host build (the selector is always `syscall` → the TOOL-1 fixpoint holds).
    if str_eq(str_at(pc.src + seltok.start, seltok.len), "syscall") { is_syscall = true }
  }
  if tok_kw(pc, "fn") {
    pc.idx = pc.idx + 1                       ## 'fn'
    ## `fn` is ALWAYS followed by its parameter list `(` (Grammar: `fn-type ::= "fn" "(" …`). This
    ## second skip used to be unconditional, so a file truncated at `f := fn` stepped over the EOF
    ## sentinel, the param loop exited immediately, and the residue scan below ran to the end of the
    ## buffer: the declaration was ACCEPTED (measured rc 0, the program ran to 42), and the MID-FILE
    ## spelling swallowed `main` while `check` still returned 0 — the build failed only at LINK time
    ## with `undefined reference to ...__main`. That silent `check` is what I11 forbids.
    if cur(pc).kind != 10 {
      zfp := reject_here(pc, "selfhost: `fn` must be followed by a PARAMETER LIST `(...)` - the input ends or continues with something else (a truncated file, a partial copy, or a bad merge)")
    }
    plparen := cur(pc).start                  ## the `(` that opens the list (for the unclosed reject)
    pc.idx = pc.idx + 1                       ## '('
    ## Parse the comma-separated `name : T` parameters into an arena-linked `Param` list
    ## (the `: T` annotation is skipped — types are sema's job). Up to 6 (the System V
    ## integer argument registers); a 7th+ param would need stack args (deferred).
    mut arity := 0
    mut phead := param_null()
    mut ptail := param_null()
    ## saw a `comptime` VALUE parameter (`comptime N : u64`, Comptime §10) anywhere in the list —
    ## recorded so a fn that is NOT a type-function carrying one can fail LOUD below (TYP-10
    ## slice A implements comptime value params on type-functions only).
    mut saw_ct := false
    while cur(pc).kind != 11 and cur(pc).kind != 0 {
      ## skip optional parameter modifiers `in` / `out` / `in out` (Functions §5). The self-host
      ## compiler passes aggregates BY REFERENCE and scalars by value regardless, so the modifier
      ## does not change a param's lowering — it is consumed. (The default `in` is usually
      ## omitted; `out`/`in out` mark a caller-visible write, which the by-ref aggregate handling
      ## already provides.) `in`/`out` are CONTEXTUAL keywords — usable as a param NAME too: a
      ## leading `in`/`out` is a MODIFIER only when the token after it is not `:` (a param name is
      ## always followed by `: <type>`), so `out : str` binds a param literally named `out`.
      ## record whether an `out` modifier was present (`out` / `in out`) — it marks a
      ## caller-visible write. For a SCALAR param this selects the by-reference out-scalar ABI
      ## (Param `pmode` 2); for an aggregate it is redundant (already by-ref) and `pmode` 2 is
      ## ignored by bind_param's type branches. `in`/`out` are CONTEXTUAL keywords (see below).
      mut p_out := false
      while (tok_kw(pc, "in") or tok_kw(pc, "out")) and tok_at(pc, pc.idx + 1).kind != 8 {
        if tok_kw(pc, "out") { p_out = true }
        pc.idx = pc.idx + 1
      }
      ## A COMPTIME VALUE parameter `comptime N : u64` (Comptime §10 `comptime-param`) — the
      ## keyword PREFIXES the parameter name; consume it so `pn` below captures the name (`N`),
      ## not the keyword. The parameter rides the ordinary `Param` list (its type span is the
      ## declared value type, `u64`), exactly like a `: type` parameter does; the type-function
      ## desugar marks the decl generic either way. `src/` declares no comptime param → dormant
      ## for the self-host build (fixpoint-neutral).
      if tok_kw(pc, "comptime") { saw_ct = true; pc.idx = pc.idx + 1 }
      pn := cur(pc); pc.idx = pc.idx + 1      ## param name
      pc.idx = pc.idx + 1                     ## ':'
      mut pts := 0
      mut ptl := 0
      mut p_is_arr := false
      mut p_arrlen := 0                        ## static length N of an `[T; N]` array param (0 if none)
      mut p_slicevar := false                  ## §7.2 SLICE-variadic `name : ...T` (a rest WITH element type T)
      mut pps := 0
      mut ppl := 0
      ## AGGREGATE-PARAM tier — an ARRAY parameter type `[T; N]` (kinds: 14 `[`, 30 `;`,
      ## 15 `]`). Capture the ELEMENT type span `T` (the token after `[`) — lower resolves the
      ## element layout/stride from it — and skip to the closing `]` (the length `N` is not
      ## needed: element access is by runtime index, no bounds check). `is_arr` marks the param
      ## so lower binds it as a by-reference array.
      if cur(pc).kind == 14 {
        pc.idx = pc.idx + 1                   ## '['
        et := cur(pc); pts = et.start; ptl = et.len  ## element type T
        p_is_arr = true
        pc.idx = pc.idx + 1                   ## past T
        ## capture the STATIC length N (the int after `;`) so the callee can bounds-check `a[i]` (I11) —
        ## N is stored in the param's free `pps` slot below. (Element access is still by runtime index.)
        if cur(pc).kind == 30 {               ## ';'
          pc.idx = pc.idx + 1
          if cur(pc).kind == 3 { p_arrlen = lit_val_at(pc, cur(pc).start, cur(pc).len) }
        }
        while cur(pc).kind != 15 and cur(pc).kind != 0 { pc.idx = pc.idx + 1 }  ## skip to ']'
        pc.idx = pc.idx + 1                   ## ']'
      } else if cur(pc).kind == 10 {
        ## AGGREGATE-PARAM tier — a TUPLE parameter type `(T0, T1, …)` (kind 10 `(`). Like an array param,
        ## it is a by-reference N-word aggregate: mark `p_is_arr` (so lower binds it `ek 5` by-ref) and
        ## capture the FIRST component type as the element span (scalar-component tuples use stride 1,
        ## matching how a tuple LOCAL is stored). Element access `a.N` reads element N by runtime index
        ## (the `Index` path), so N is not needed here. Without this the leading `(` was captured as the
        ## type name → the param bound as a scalar → `a.0` read frame garbage (a silent miscompile, §8).
        pc.idx = pc.idx + 1                   ## '('
        ct := cur(pc); pts = ct.start; ptl = ct.len  ## first component type T0
        p_is_arr = true
        mut pdepth := 1
        while pdepth > 0 and cur(pc).kind != 0 {
          if cur(pc).kind == 10 { pdepth = pdepth + 1 }
          else if cur(pc).kind == 11 { pdepth = pdepth - 1 }
          if pdepth > 0 { pc.idx = pc.idx + 1 }
        }
        pc.idx = pc.idx + 1                   ## ')'
      } else {
        pt := cur(pc); pts = pt.start; ptl = pt.len; pc.idx = pc.idx + 1  ## type (`ptr`/`u64`/`P`/…)
        ## A QUALIFIED parameter type `mod::Type` or N-seg `a::b::C` (e.g. `rt::Vec`,
        ## `alloc::strbuf::StrBuf`): walk ALL `::ident` segments, keeping the TAIL name.
        while cur(pc).kind == 7 {
          pc.idx = pc.idx + 1                   ## '::'
          tt := cur(pc); pts = tt.start; ptl = tt.len; pc.idx = pc.idx + 1   ## tail type name
        }
        ## A VARIADIC parameter `args : ...` — lexed as `..` (kind 31) + `.` (kind 22).
        ## The lean lower does not handle the COMPTIME variadic (`...` with NO element type — §7.1),
        ## so its tokens are just consumed; `pts`/`ptl` stay the `..` span (`type_is_variadic_rest`).
        ## §7.2 SLICE variadic `name : ...T`: when a TYPE ident (kind 1) FOLLOWS the three dots, it is
        ## the element type `T` of a homogeneous runtime `[T]` slice — capture its span as the param
        ## type (so `type_is_variadic_rest` does NOT fire and the fn is emitted as a REAL runtime fn)
        ## and mark `p_slicevar` (→ `pmode == 3`). The call site gathers the trailing args into a
        ## contiguous block + passes a `{ptr, len}` slice; `bind_param` binds the param as a by-ref `[T]`.
        if pt.kind == 31 {
          if cur(pc).kind == 22 { pc.idx = pc.idx + 1 }   ## third dot
          if cur(pc).kind == 1 {
            vt := cur(pc); pts = vt.start; ptl = vt.len; pc.idx = pc.idx + 1   ## element type T
            p_slicevar = true
          }
        }
        ## A POINTER parameter type `ptr(mut T)` / `ptr(T)`: the type token `ptr` followed by a
        ## paren-balanced pointee form `(…)`. Capture `ptr`'s span as the type lexeme (sema
        ## resolves it to a pointer, tag 5) and consume the `(…)`.
        if str_eq(str_at(pc.src + pt.start, pt.len), "fn") and cur(pc).kind == 10 {
          ## A FUNCTION-VALUE parameter type `f : fn(p : T, …) -> R` (higher-order — `sort_by`'s
          ## comparator, `map_in_place`'s mapper, …). A fn value is a CODE POINTER = one scalar
          ## word, so keep `pts`/`ptl` = "fn" (bind_param falls through to the scalar `bind_slot`).
          ## CONSUME the balanced `(…)` param-type list, then an optional `-> RetType` (a type head
          ## + any `::seg` + a balanced `(…)`). WITHOUT this the type parse fell to `skip_type_param`
          ## (which expects a single `(T)`), mis-consumed `( name :`, and left the rest of the fn
          ## type dangling — corrupting the enclosing param list and causing a downstream parse
          ## error. The inner param names are NOT registered as the enclosing fn's params. `src/`
          ## has no fn-type param, so this is fixpoint-neutral; `lib/`'s slice/vec need it.
          mut fdepth := 1
          pc.idx = pc.idx + 1                 ## '('
          while fdepth != 0 and cur(pc).kind != 0 {
            if cur(pc).kind == 10 { fdepth = fdepth + 1 }
            else if cur(pc).kind == 11 { fdepth = fdepth - 1 }
            pc.idx = pc.idx + 1
          }
          if cur(pc).kind == 6 {              ## '->' return type
            pc.idx = pc.idx + 1               ## '->'
            pc.idx = pc.idx + 1               ## the ret-type head token
            while cur(pc).kind == 7 { pc.idx = pc.idx + 2 }   ## `::seg` tail(s)
            if cur(pc).kind == 10 {           ## a `(…)` type-arg / pointee — balance it
              mut rdepth := 1
              pc.idx = pc.idx + 1
              while rdepth != 0 and cur(pc).kind != 0 {
                if cur(pc).kind == 10 { rdepth = rdepth + 1 }
                else if cur(pc).kind == 11 { rdepth = rdepth - 1 }
                pc.idx = pc.idx + 1
              }
            }
          }
        } else if str_eq(str_at(pc.src + pt.start, pt.len), "ptr") and cur(pc).kind == 10 {
          pc.idx = pc.idx + 1                 ## '('
          ## Capture the POINTEE type span (`pps`/`ppl`): the token after an optional `mut`
          ## (`ptr(mut T)`) — peeked without advancing, the balance loop below consumes it.
          ## Lower reads it so `match deref(p)` over a `ptr(Enum)` resolves the enum (the
          ## arena-AST shape). The common pointee is a bare type name (`Expr`); a nested
          ## `ptr(...)`/`G(...)` pointee just records its head token, unused by the match path.
          mut ppi := pc.idx
          if tok_kw(pc, "mut") { ppi = pc.idx + 1 }
          ppt := tok_at(pc, ppi)
          pps = ppt.start; ppl = ppt.len
          ## a QUALIFIED pointee `mod::Type` (e.g. `ptr(mut rt::Arena)`) — keep the TAIL type name
          ## (`Arena`), so the lower resolves the pointee struct/enum by tail name (matching the
          ## global-by-tail-name rule). Without this `pps`/`ppl` captured only `rt` (the module).
          if tok_at(pc, ppi + 1).kind == 7 {
            tt := tok_at(pc, ppi + 2); pps = tt.start; ppl = tt.len
          }
          mut depth := 1
          while depth != 0 and cur(pc).kind != 0 {
            if cur(pc).kind == 10 { depth = depth + 1 }
            else if cur(pc).kind == 11 { depth = depth - 1 }
            pc.idx = pc.idx + 1
          }
        } else if cur(pc).kind == 10 {
          ## A GENERIC-STRUCT instantiated parameter type `p : Vec(u64)` / `p : Result(usize,
          ## AllocError)` — the type token followed by a type-argument list `(…)` of ONE OR MORE
          ## comma-separated args. The type args are erased (word-sized → the same layout), so
          ## capture just the bare head span (already `pts`/`ptl`) and PAREN-BALANCE-skip the whole
          ## `(…)`. The old `skip_type_param` consumed a fixed `( ident )` (single arg), so a
          ## MULTI-arg list `(usize, AllocError)` left `, AllocError )` dangling — the stray `,` then
          ## read as a param separator, corrupting the enclosing param list and SWALLOWING following
          ## decls (e.g. `alloc::fmt::display` vanished entirely). Balancing consumes any arg count +
          ## nested parens. Single-arg `(T)` consumes the identical token span, so `src/` (whose
          ## generic param types are all single-arg) is byte-identical → fixpoint-neutral.
          mut gdepth := 1
          pc.idx = pc.idx + 1                 ## '('
          while gdepth != 0 and cur(pc).kind != 0 {
            if cur(pc).kind == 10 { gdepth = gdepth + 1 }
            else if cur(pc).kind == 11 { gdepth = gdepth - 1 }
            pc.idx = pc.idx + 1
          }
        }
      }
      ## §5.1 in-PARAMETER DEFAULT `in x : T = <expr>`: when the argument is omitted at the call, this
      ## expression is supplied at the call site (FN-5). The `=` (kind 21) after the type opens it.
      ## STORAGE without growing `Param` (which must stay 8 words): a non-pointer value
      ## param leaves `pps`/`ppl` at 0/0 and every reader of `pps` is guarded by `ts == "ptr"` (lower
      ## 1725/12149/12156), so `pps` is FREE — store the default's `Expr` pointer there (as a usize).
      ## The lower's `fill_program` recovers it (bitcast back) and appends the omitted trailing args.
      ## Only an `in` value param may default (§5.1: `out`/`in out` have no default — a result place is
      ## caller-supplied); an `out`/`in out`/array/pointer param default is rejected (pps is unavailable
      ## for a pointer; the others have no value to default). `src/` uses no defaults → fixpoint-neutral.
      mut p_defp := 0
      if cur(pc).kind == 21 {
        pc.idx = pc.idx + 1                    ## '='
        dexpr := p_or(pc)
        if p_out or p_is_arr or str_eq(str_at(pc.src + pts, ptl), "ptr") { panic("selfhost: parameter default only on an `in` value parameter") }
        p_defp = unchecked bitcast(usize, dexpr)
      }
      ## passing mode: a slice-variadic param is 3 (§7.2); else an array param is 1; else an
      ## `out`/`in out` param is 2; else 0 (value). (Array takes precedence over out — an `out [T;N]`
      ## is by-ref already, so it rides the array path. A slice-variadic is never array/out.)
      mut p_pmode : u8 = 0
      if p_slicevar { p_pmode = 3 } else if p_is_arr { p_pmode = 1 } else if p_out { p_pmode = 2 }
      ## a default (`p_defp`) is stored in `pps` — mutually exclusive with a pointer pointee span
      ## (rejected above), so no clash. `pps` is otherwise the pointer-pointee span (or 0).
      mut fpps := pps
      if p_defp != 0 { fpps = p_defp }
      ## an ARRAY param carries its static length N in `pps` (no pointee/default there) → the lower reads
      ## it for the `a[i]` bounds check.
      if p_is_arr { fpps = p_arrlen }
      pnew := pnode(pc.arena, Param(ns = pn.start, nl = pn.len, next = 0, ts = pts, tl = ptl, pmode = p_pmode, pps = fpps, ppl = ppl))
      if unchecked bitcast(usize, phead) == 0 { phead = pnew } else {
        old := deref(ptail)
        upd := Param(ns = old.ns, nl = old.nl, next = pnew, ts = old.ts, tl = old.tl, pmode = old.pmode, pps = old.pps, ppl = old.ppl)
        deref(ptail) = upd
      }
      ptail = pnew
      arity += 1
      if cur(pc).kind == 9 { pc.idx = pc.idx + 1 }   ## ',' between params
    }
    ## The list MUST be closed by `)`. The loop above also terminates on the EOF sentinel, and the
    ## unconditional skip below then stepped PAST it — so a file truncated inside a parameter list
    ## (`BROKEN := fn(`, `BROKEN := fn( -> u64 {`) left the cursor beyond the end of the stream and the
    ## body guard further down reported a MISSING BODY at a position one line past the file. That is a
    ## worse diagnosis than the truth: this is the UNBALANCED class, whose reject already exists at the
    ## tail of `parse_program`. Report it here with the SAME wording (one needle covers both) but a
    ## better position — the `(` that never closed, rather than the outermost open group.
    if cur(pc).kind != 11 {
      zpl := reject_at(pc, "selfhost: the input ends inside an unclosed `(`, `{` or `[` - the parser reached end-of-input while a group was still open, so this declaration and everything after it is NOT part of the program (a truncated file, a partial copy, or a bad merge); close the group", plparen)
    }
    pc.idx = pc.idx + 1                       ## ')'
    ## GENERICS tier: a comptime type parameter `x : type` at ANY position makes this a GENERIC fn
    ## (monomorphized per concrete type at the call). Detected by SCANNING the params for one whose
    ## type annotation is the literal `type` — `allocate := fn(in out self, T : type, …)` has it at
    ## index 1, not only the leading form. The type parameter stays in the `Param` list; the lower
    ## erases it (no register) at its position (`tparam_idx`) and mangles each instance `<fn>__<tag>`.
    ## `src/`'s own generics all have a single leading `T : type`, so this stays fixpoint-neutral.
    mut is_generic := false
    mut gp := phead
    while gp != 0 {
      gpm := deref(param_p(gp))
      if str_eq(str_at(pc.src + gpm.ts, gpm.tl), "type") { is_generic = true }
      gp = gpm.next
    }
    ## A COMPTIME VALUE parameter on a glyph-OPERATOR fn (`@inline + := fn(comptime N : u64,
    ## a : uint(N), b : uint(N)) -> uint(N)`, TYP-10 slice B) also makes the decl GENERIC: it is
    ## never emitted as a standalone runtime fn — the lower routes `a <op> b` to it by the operand
    ## type's base head and EXPANDS the body at the site with `N` bound from the operand's value
    ## argument. (A type-function carrying one — the slice-A `uint` — returned above already.)
    if saw_ct { is_generic = true }
    ## The return type is OPTIONAL — a VOID fn `fn(…) { … }` has no `-> R` (after the params `)`
    ## the cursor is already at the body `{`, kind 12). Consume `->` (kind 6) + capture the
    ## result-type head ONLY when present; a void fn gets an empty `rt` span (ret_tl 0), which
    ## `fn_returns_enum`/`fn_returns_struct` correctly read as "no aggregate return". Without this
    ## guard a void fn consumed the body `{` as `->`, mis-captured the first body token as the
    ## return type, then the multi-token-return skip scanned into the NEXT decl — corrupting it
    ## (the pervasive void fns in the passes: `lexer::lex_all`, statement-only helpers).
    mut rt := Token(kind = 0, start = 0, len = 0)
    if cur(pc).kind == 6 {
      pc.idx = pc.idx + 1                     ## '->'
      ## `->` must be followed by a RETURN TYPE. At EOF `rt` captured the zero-length EOF sentinel,
      ## the residue scans below found no `{` and stopped on the same sentinel, and the body loop
      ## exited at once: `f := fn() ->` as the last line of an otherwise complete program BUILT with
      ## rc 0, RAN to 42 and `check`ed clean — the headline silent accept of this class.
      if cur(pc).kind == 0 {
        zra := reject_eof(pc, "selfhost: a `->` must be followed by a RETURN TYPE - the input ends after it (a truncated file, a partial copy, or a bad merge)")
      }
      ## `-> scoped ptr(mut T)` — the `scoped` second-class-reference qualifier (§5.3.1) precedes
      ## the type; skip it so `rt` captures the actual return-type head (`ptr`), not `scoped` (which is
      ## not a type). Without this a `scoped`-returning `get` records `ret_ts = "scoped"`, so the
      ## pointer-return recognizers (`gen_ret_ptrstruct_span`) miss it and a `p := get(P,…)` binding
      ## can't resolve `deref(p).f` through the pointer. Dormant for `src/` (no `scoped` returns there).
      if str_eq(str_at(pc.src + cur(pc).start, cur(pc).len), "scoped") { pc.idx = pc.idx + 1 }
      rt = cur(pc)                            ## result type head (capture its span)
      pc.idx = pc.idx + 1
      ## A QUALIFIED return type `mod::…::Type` (an aliased / cross-module struct, e.g. the driver's
      ## `-> strbuf::StrBuf`): extend the captured span across EVERY `:: Type` pair so the FULL path
      ## is recorded. Otherwise only the head (or a partial path) is kept and `struct_decl_of` —
      ## which strips the module prefix via `name_tail` — cannot resolve the struct, so
      ## `fn_returns_struct` wrongly reports a SCALAR return: the GAS then delivers only %rax and the
      ## caller's `s := mod::f(…)` binding drops the struct's other words (the `compile_files`/
      ## `StrBuf`-return fixpoint miscompile).
      while cur(pc).kind == 7 and tok_at(pc, pc.idx + 1).kind == 1 {
        pc.idx = pc.idx + 1                   ## '::'
        tt := cur(pc)                         ## tail type ident
        ## Snapshot the old span before rebuilding the byte-layout Token. The self-host lower clears
        ## an aggregate assignment's destination before evaluating its fields; reading `rt.start`
        ## from the RHS after that clear turns it into zero and makes the length an absolute source
        ## offset. Keep the source values in scalars first (the same rule used for other aggregate
        ## copies in this parser).
        rts := rt.start
        rtk := rt.kind
        rt = Token(kind = rtk, start = rts, len = tt.start + tt.len - rts)
        pc.idx = pc.idx + 1
      }
      ## A TUPLE return type `(T0, T1, …)` — the head token is `(` (kind 10). Extend the captured
      ## span across the balanced parens (so `fn_returns_tuple` / `tuple_words` read the whole `(…)`)
      ## and advance past the matching `)`. The lean lower delivers a tuple return via the SAME
      ## register-return convention as a small struct (word k → %rax/%rdx/%rcx/…).
      if rt.kind == 10 {
        mut tdepth := 1
        mut tendpos := rt.start + 1
        while tdepth > 0 and cur(pc).kind != 0 {
          ck := cur(pc)
          if ck.kind == 10 { tdepth = tdepth + 1 }
          else if ck.kind == 11 { tdepth = tdepth - 1 }
          tendpos = ck.start + ck.len
          pc.idx = pc.idx + 1
        }
        rts := rt.start
        rt = Token(kind = 10, start = rts, len = tendpos - rts)
      }
    }
    ## A `comptime` VALUE parameter on a NON-type-function is in scope only for a glyph-named
    ## OPERATOR fn (TYP-10 slice B: `@inline + := fn(comptime N : u64, a : uint(N), b : uint(N))`,
    ## routed + expanded per instance by the lower); any other runtime/extern/syscall fn carrying
    ## one is out of this slice's scope (generic NAMED runtime fns over comptime values — the mono
    ## machinery for them — land with a later slice). Fail LOUD here rather than silently treating
    ## the comptime parameter as an ordinary runtime argument (a wrong-ABI miscompile).
    if saw_ct and str_eq(str_at(pc.src + rt.start, rt.len), "type") == false and is_opnm == false {
      panic("selfhost: a `comptime` value parameter is only supported on a type-function (`fn(comptime N : u64) -> type { … }`) or a glyph-named operator fn in this slice — generic named runtime fns over comptime values are a later slice")
    }
    ## An `@extern` fn has NO body — the `-> R` is the whole declaration (the definition is external).
    ## Emit an ORDINARY kind-1 Decl with an empty body: the lower routes calls to it to the external
    ## symbol (`extern_symbol`) and skips emitting a (non-existent) body. Kind 1 (not a new kind) so the
    ## existing callee-resolution sites resolve it with no change.
    if is_extern {
      eph := newnode(pc.arena, Expr.Num(0, 0, 0))
      return Result(usize, ParseErr).Ok(dnode(da, Decl(
        name_start = name.start, name_len = name.len, value = eph,
        is_fn = true, kind = 1, arity = arity, is_generic = false, params_head = phead,
        body_stmts = 0, fields_head = 0, ret_ts = rt.start, ret_tl = rt.len,
        mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = 0, alias_ts = 0, alias_tl = 0)))
    }
    ## A SYSCALL-ABI fn has NO body — the `-> R` is the whole declaration. Emit a kind-4 Decl
    ## (the params drive the trampoline's arg-register mapping; `arity` is the param count).
    if is_syscall {
      ph := newnode(pc.arena, Expr.Num(0, 0, 0))
      return Result(usize, ParseErr).Ok(dnode(da, Decl(
        name_start = name.start, name_len = name.len, value = ph,
        is_fn = true, kind = 4, arity = arity, is_generic = false, params_head = phead,
        body_stmts = 0, fields_head = 0, ret_ts = rt.start, ret_tl = rt.len,
        mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = 0, alias_ts = 0, alias_tl = 0)))
    }
    ## TYPE-FUNCTION generic form — `Name := fn(T : type) -> type { [@owning] struct {…} }` (the
    ## spec's generic-type mechanism, used by the real stdlib: `Vec`/`Slice`/`Handle`/`Buf`). A fn
    ## whose RESULT type is `type` and whose body is a `struct`/`enum` defines a GENERIC type:
    ## desugar it to a kind-2/3 type decl (is_generic), so `Name(U)(…)` constructs an instance and
    ## the layout resolves like `Name(T) := struct {…}`. Skip the fn body `{`, an optional
    ## `@owning` effector, then parse the struct/enum members; the closing `}` is the fn body's.
    if str_eq(str_at(pc.src + rt.start, rt.len), "type") {
      pc.idx = pc.idx + 1                     ## '{' (fn body)
      if tok_kw(pc, "return") { pc.idx = pc.idx + 1 }  ## skip an optional `return` (`{ return struct … }`)
      mut tf_packed := false
      if cur(pc).kind == 33 {                 ## skip '@owning'/'@packed' ('@' + ident)
        if str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "packed") { tf_packed = true }
        pc.idx = pc.idx + 2
      }
      tk : u8 = if tok_kw(pc, "struct") { 2 } else { 3 }
      pc.idx = pc.idx + 1                     ## 'struct' / 'enum'
      tfh := parse_struct_members(pc, tf_packed)         ## '{ member, … }' (the type body)
      pc.idx = pc.idx + 1                     ## '}' (fn body close)
      placeholder := newnode(pc.arena, Expr.Num(0, 0, 0))
      return Result(usize, ParseErr).Ok(dnode(da, Decl(
        name_start = name.start, name_len = name.len, value = placeholder,
        is_fn = false, kind = tk, arity = 0, is_generic = true, params_head = phead,
        body_stmts = 0, fields_head = tfh, ret_ts = 0, ret_tl = 0,
        mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = 0, alias_ts = 0, alias_tl = 0)))
    }
    ## A MULTI-TOKEN return type — `Result(Decl, ParseErr)` / `scoped ptr(mut T)` / `ptr(T)` — has
    ## more tokens after its head before the body `{`. `rt` already captured the head (used for the
    ## single-token enum/struct-return detection); skip the rest up to the body `{` (a return type
    ## holds no `{`, so a flat scan is unambiguous). A single-token return (`-> u64 {`) is already
    ## at `{`, so this skips nothing. STOP the skip at a `when` guard keyword (never inside a return
    ## type) so the guard clause below is not swallowed as return-type residue.
    mut when_e := unchecked bitcast(ptr(Expr), 0)
    ## STOP the residue skip at a `:=` (kind 5) as well as at `{` / EOF / `when`. A return type never
    ## contains a `:=` — but the NEXT DECLARATION starts with one, and that is what made a MID-FILE
    ## truncation silent: `f := fn() ->` or `f := fn() -> u64` followed by the rest of the file scanned
    ## forward over `main := fn() -> u64 { 42 }` and took MAIN'S `{` as this function's body, so `main`
    ## itself was never declared. Measured on the pre-fix compiler: `check` returned 0 and the build
    ## failed only in `ld` with `undefined reference to <mod>__main`. With the stop in place the scan
    ## halts at the next declaration and the `{` guard below rejects, located.
    while cur(pc).kind != 12 and cur(pc).kind != 0 and cur(pc).kind != 5 and not tok_kw(pc, "when") { pc.idx = pc.idx + 1 }
    ## optional `when <comptime-predicate>` DECLARATION-GUARD (Comptime §7.1/§9; CT-5) — sits between the
    ## fn signature and the body `{` (`fn(…) -> R when target.arch == Arch.x86_64 { … }`). Parse the
    ## predicate expression into `when_e`; `lower::emit_program` folds a CLOSED (target-gating) predicate
    ## and neuters the whole decl to an inert no-op when it folds FALSE (Comptime §9 two-phase). `when` is
    ## a reserved word (a lexer keyword), never used as an identifier in `src/`+`lib/`, so this path is
    ## dormant for the self-host build (the TOOL-1 fixpoint holds).
    if tok_kw(pc, "when") {
      pc.idx = pc.idx + 1                     ## 'when'
      when_e = p_or(pc)
    }
    while cur(pc).kind != 12 and cur(pc).kind != 0 and cur(pc).kind != 5 { pc.idx = pc.idx + 1 }  ## any residue up to '{'
    ## The body MUST open with `{`. Every BODYLESS declaration form has already returned above
    ## (`@extern`, `@abi(syscall)`, and the `-> type` type-function), so anything reaching here is an
    ## ordinary fn whose body is mandatory. Unchecked, the skip stopped on the EOF sentinel, the next
    ## `pc.idx + 1` walked past it, and the statement loop exited at once — the declaration was
    ## accepted with an empty body.
    if cur(pc).kind != 12 {
      zbb := reject_here(pc, "selfhost: a `fn` SIGNATURE must be followed by a braced BODY `{ ... }` - the input ends or continues with something else, so this function has no body (a truncated file, a partial copy, or a bad merge)")
    }
    pc.idx = pc.idx + 1                       ## '{'
    ## The fn body is a run of statements, then an OPTIONAL trailing return expression. Unlike a
    ## nested braced body (no value, so `p_stmts`), the fn body's LAST expression is the return
    ## value — but a statements-vs-trailing-expr boundary cannot be told by lookahead (statements
    ## are whitespace-separated). So: collect `stmt_starts` statements; on a bare expression, peek
    ## — if `}` follows it is the trailing return; otherwise it is a bare expression STATEMENT
    ## (a call/`?` for effect) and we record it + keep going. A body that ends in an early
    ## `return` (or any statement) leaves no tail expr → the internal sentinel `Num(-1)` (lower's
    ## `emit_fn` falls through to the epilogue, where the early `return` already delivered). Keep
    ## this distinct from a real tail literal `0`, which is a valid function result.
    mut shead := 0
    mut stail := 0
    mut body := newnode(pc.arena, Expr.Num(0 - 1, 0, 0))
    while cur(pc).kind != 13 and cur(pc).kind != 0 {
      ## Skip an optional `;` statement SEPARATOR (kind 30) — two statements on one line
      ## (`mut x = 0 ; if c { … }`). Without this the `;` falls to the bare-expression branch
      ## (`p_or` on a `;`), which drifts and mis-parses the FOLLOWING statement (a `;` before a
      ## statement-`if` made it an expression-if → the body's assignment was dropped). Mirrors
      ## `p_stmts`' separator handling — the fn-body loop is the value-bearing dual of it.
      if cur(pc).kind == 30 {
        pc.idx = pc.idx + 1
      } else if stmt_starts(pc) {
        s := p_stmt(pc)
        if shead == 0 { shead = s } else { set_stmt_next(pc.arena, stmt_last(stail, pc.arena), s) }
        stail = s
      } else {
        e := p_or(pc)
        if cur(pc).kind == 13 or cur(pc).kind == 0 {
          body = e                            ## trailing return expression (`}`/EOF follows)
        } else {
          es := snode(pc.arena, Stmt.ExprStmt(e, 0))
          if shead == 0 { shead = es } else { set_stmt_next(pc.arena, stmt_last(stail, pc.arena), es) }
          stail = es
        }
      }
    }
    stmts := shead
    pc.idx = pc.idx + 1                       ## '}'
    return Result(usize, ParseErr).Ok(dnode(da, Decl(
      name_start = name.start, name_len = name.len, value = body,
      is_fn = true, kind = 1, arity = arity, is_generic = is_generic, params_head = phead,
      body_stmts = stmts, fields_head = 0, ret_ts = rt.start, ret_tl = rt.len,
      mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = when_e, alias_ts = 0, alias_tl = 0)))
  }
  ## `Name := @owning struct {…}` / `@owning enum {…}` — the `@owning` effector (linearity) may
  ## prefix a DIRECT type declaration, not only the generic `fn(T : type) -> type { @owning struct }`
  ## form. Skip the `@owning` (`@` + ident) so the struct/enum body parses; the marker is a checker
  ## concern with NO codegen effect (the lowered struct is identical to a plain one). Guarded on a
  ## `struct`/`enum` following the effector, so a value-position `@abi(…)`/`@…` is left untouched.
  ## A STACKED value-position attribute (`@… @packed struct`) — the first was consumed above; capture a
  ## trailing `@packed` here too so field-level byte-layout attrs are enabled.
  if cur(pc).kind == 33 and tok_at(pc, pc.idx + 1).kind == 1 and (tok_kw_at(pc, pc.idx + 2, "struct") or tok_kw_at(pc, pc.idx + 2, "enum")) {
    if str_eq(str_at(pc.src + tok_at(pc, pc.idx + 1).start, tok_at(pc, pc.idx + 1).len), "packed") { sm_packed = true }
    pc.idx = pc.idx + 2
  }
  ## `Name := struct { f : T, … }` / `Name := enum { V, V(T), … }` — a type declaration.
  ## Capture each member's name + payload arity into an arena-linked `FieldDecl` list:
  ## a struct field is `name : T` (arity 0, skip `: T`); an enum variant is `name` or
  ## `name ( T , … )` (arity = payload count).
  ## `union { m(T), … }` (spec Types §6.3) is a VARIANT-list type (grammar §130 `union-type ::= "union"
  ## "{" [ variant … ] "}"`, the SAME `variant` production as `enum`), differing from an enum ONLY in
  ## LAYOUT (offset-0 overlap, size/align = maxima) and ACCESS (untagged — no discriminant). So it parses
  ## into the EXISTING enum-shaped decl (kind 3, `parse_struct_members` captures each `m(T)` variant); the
  ## lower distinguishes union-from-enum by a SOURCE-SCAN of the decl keyword (`lower_layout::is_union_decl`),
  ## exactly the `is_packed`/`@repr` discipline — no new AST node/kind/flag, so an enum stays byte-identical
  ## (the union branch is dormant for the self-host build → the TOOL-1 fixpoint holds). `src/`+`lib/` declare
  ## no `union`, so admitting the keyword here is fixpoint-neutral.
  if tok_kw(pc, "struct") or tok_kw(pc, "enum") or tok_kw(pc, "union") {
    k : u8 = if tok_kw(pc, "struct") { 2 } else { 3 }   ## enum AND union → kind 3 (variant-shaped)
    pc.idx = pc.idx + 1                       ## 'struct' / 'enum' / 'union'
    ## The body MUST open with `{` (kind 12). A PARAMETERIZED spelling `Name := struct(T : type) { … }`
    ## is not Alatyr — the generic forms are `Name(T) := struct { … }` and the type-function
    ## `Name := fn(T : type) -> type { return struct { … } }`. Without this guard
    ## `parse_struct_members` consumed the `(` as the body opener and walked off the token stream:
    ## the compiler died with SIGILL (rc 132, core dumped) and NO diagnostic. Reject it located.
    if cur(pc).kind != 12 {
      reject_at(pc, "selfhost: a `struct`/`enum`/`union` body must open with `{` - a parameterized `Name := struct(T : type) { ... }` is not valid Alatyr; write `Name(T) := struct { ... }` or `Name := fn(T : type) -> type { return struct { ... } }`", cur(pc).start)
    }
    fhead := parse_struct_members(pc, sm_packed)         ## '{ member, … }' (consumes the closing '}')
    ## optional trailing `when <comptime-predicate>` DECLARATION-GUARD on a `struct`/`enum` type decl
    ## (Comptime §7.1/§9; CT-5): `Pt := struct { … } when target.arch == Arch.x86_64`. `parse_struct_members`
    ## leaves the cursor past the body `}`, so a `when` keyword there unambiguously begins the guard (never
    ## a field/member — `when` is a reserved lexer keyword). Same clause the fn / binding paths parse.
    ## Dormant for the self-host build (`src/`+`lib/` carry no `when` on a type decl) → fixpoint-neutral.
    mut swhen := unchecked bitcast(ptr(Expr), 0)
    if tok_kw(pc, "when") {
      pc.idx = pc.idx + 1                       ## 'when'
      swhen = p_or(pc)
    }
    placeholder := newnode(pc.arena, Expr.Num(0, 0, 0))
    return Result(usize, ParseErr).Ok(dnode(da, Decl(
      name_start = name.start, name_len = name.len, value = placeholder,
      is_fn = false, kind = k, arity = 0, is_generic = is_gen_struct, params_head = 0,
      body_stmts = 0, fields_head = fhead, ret_ts = 0, ret_tl = 0,
      mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = swhen, alias_ts = 0, alias_tl = 0)))
  }
  ## `Name := brand(U)` — a NOMINAL BRAND over an underlying scalar type `U` (the
  ## prelude scalars `bool`/`char`/`fN` are brands over `bitsN`; a user brand is the same shape).
  ## Recorded as a kind-0 decl MARKED by `arity = 1` (a plain value/alias decl is arity 0), with the
  ## underlying type span in ret_ts/ret_tl — so `struct_decl_of` follows the brand to its underlying
  ## (a scalar → not a struct) and the lower peels `Id(v)` construction / `u64(id)` conversion to `U`.
  ## Only the single-token underlying form (`brand(u64)`/`brand(bits64)`) is recognized — all real
  ## brands. src/ declares no brand → the self-host build is fixpoint-neutral.
  if cur(pc).kind == 1 and str_eq(str_at(pc.src + cur(pc).start, cur(pc).len), "brand") and tok_at(pc, pc.idx + 1).kind == 10 {
    ut := tok_at(pc, pc.idx + 2)              ## the underlying type token
    pc.idx = pc.idx + 4                       ## consume 'brand' '(' U ')'
    ph := newnode(pc.arena, Expr.Num(0, 0, 0))
    return Result(usize, ParseErr).Ok(dnode(da, Decl(
      name_start = name.start, name_len = name.len, value = ph,
      is_fn = false, kind = 0, arity = 1, is_generic = false, params_head = 0,
      body_stmts = 0, fields_head = 0, ret_ts = ut.start, ret_tl = ut.len,
      mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = 0, alias_ts = 0, alias_tl = 0)))
  }
  rhs_idx := pc.idx                        ## first token of the RHS (for the alias-shape scan below)
  root := p_or(pc)
  ## TYPE-ALIAS-to-a-GENERIC-INSTANCE shape (TYP-10 slice C, Types §7): `u128 := uint(128)` — the
  ## RHS is EXACTLY ONE bare-ident call `ident ( … )` whose args carry NO top-level `=` (kind 21;
  ## that would be a struct literal's `field = value`, e.g. `mut S := Pt(x = 10, y = 0)`) and whose
  ## closing `)` is the expression's last token. Record the full `uint(128)` span in
  ## `alias_ts`/`alias_tl` — the decl stays an ordinary kind-0 value binding everywhere else (a
  ## plain `x := f(1)` records it too; `lower_layout::alias_rhs` consults the span ONLY when the
  ## callee head resolves to a GENERIC struct type-function, so a value call's span is inert). The
  ## `=`-gate is what keeps every struct-literal-initialized global byte-identical (fixpoint).
  mut als_ts := 0
  mut als_tl := 0
  mut als_ok := false
  if tok_at(pc, rhs_idx).kind == 1 and tok_at(pc, rhs_idx + 1).kind == 10 {
    nt := ntoks(pc)
    mut k := rhs_idx + 1
    mut depth := 0
    mut top_eq := false
    mut close := 0
    mut scanning := true
    while scanning and k < nt {
      kk := tok_at(pc, k).kind
      if kk == 10 { depth = depth + 1 }
      if kk == 11 {
        depth = depth - 1
        if depth == 0 { close = k; scanning = false }
      }
      if kk == 21 and depth == 1 { top_eq = true }
      k += 1
    }
    if close == pc.idx - 1 and top_eq == false { als_ok = true }
    if als_ok {
      ct0 := tok_at(pc, rhs_idx)
      ct1 := tok_at(pc, close)
      als_ts = ct0.start
      als_tl = (ct1.start + ct1.len) - ct0.start
    }
  }
  ## TYPE-ALIAS-to-a-PLAIN-TYPE shape (Types §1/§4.1): `C := Color`. A bare identifier
  ## otherwise has no source metadata, so later layout/sema passes could only see the
  ## placeholder value and silently treat `C.Green` as a value-field access. Record the
  ## one-token RHS in `alias_ts`/`alias_tl`, the field shared with the generic-instance alias path;
  ## keeping `ret_ts`/`ret_tl` empty preserves the distinction from mutable globals and function
  ## return annotations. The lower still verifies that the RHS resolves to a declared aggregate
  ## before following it; a plain value binding with the same syntax therefore cannot manufacture a
  ## type. This is deliberately limited to one bare token — alias chains and expression forms remain
  ## fail-loud until their identity rules are specified.
  mut plain_ts := 0
  mut plain_tl := 0
  if tok_at(pc, rhs_idx).kind == 1 and pc.idx == rhs_idx + 1 {
    ptok := tok_at(pc, rhs_idx)
    plain_ts = ptok.start
    plain_tl = ptok.len
  }
  ## optional trailing `when <comptime-predicate>` DECLARATION-GUARD on an inferred `name := <expr>`
  ## binding (Comptime §7.1/§9; grammar §3.2 — `when` at the end): `MAX := 256 when target.arch ==
  ## Arch.x86_64`. `p_or` stops at the `when` keyword (never an operand); parse the predicate into
  ## `vwhen`. Dormant for the self-host build (`src/`+`lib/` carry no `when`) → fixpoint-neutral.
  mut vwhen := unchecked bitcast(ptr(Expr), 0)
  if tok_kw(pc, "when") {
    pc.idx = pc.idx + 1                       ## 'when'
    vwhen = p_or(pc)
  }
  mut alias_out_ts := als_ts
  mut alias_out_tl := als_tl
  if alias_out_tl == 0 { alias_out_ts = plain_ts; alias_out_tl = plain_tl }
  Result(usize, ParseErr).Ok(dnode(da, Decl(
    name_start = name.start, name_len = name.len, value = root,
    is_fn = false, kind = 0, arity = 0, is_generic = false, params_head = 0,
    body_stmts = 0, fields_head = 0, ret_ts = 0, ret_tl = 0,
    mod_start = pc.mod_s, mod_len = pc.mod_l, when_cond = vwhen,
    alias_ts = alias_out_ts, alias_tl = alias_out_tl)))
}

## Parse a sequence of bindings until EOF (kind 0) into `out_decls`; returns the count.
pub parse_program := fn(in out pc : PC, in out out_decls : rt::Vec, in out da : rt::Arena) -> Result(usize, ParseErr) {
  ## RESERVE arena handle 0. Every AST handle uses 0 as the null/"none" sentinel (a `Stmt`/`Arm`/
  ## `FieldDecl` `next = 0` ends a list; a `Decl`'s `body_stmts`/`fields_head`/`params_head == 0`
  ## means "none"). So a real node must NEVER land at arena offset 0. Previously the lexer filled
  ## this arena first (tokens), so the parser's first node was always at a nonzero offset; now the
  ## lexer writes tokens to its own `rt` arena and the AST arena starts empty — the first node
  ## would land at offset 0 and be misread as "none" (e.g. a struct's first field vanishes). Burn
  ## the first word so the first real node has a nonzero handle. (For a multi-module parse this
  ## reserves once on the empty arena; later calls waste a few bytes, which is harmless.)
  g0 := node_alloc(deref(pc.arena), 16)
  while cur(pc).kind != 0 {
    ## A top-level `module <name>` directive (MODULE tier): the ident `module` (kind 1)
    ## followed by a name ident that is NOT itself a binding (`:=` would make `module` a
    ## value name). It sets the current module for the decls that follow (stamped onto each
    ## `Decl` via `pc.mod_s`/`pc.mod_l`). Not a keyword — recognized by lexeme here so the
    ## lexer's keyword table stays unchanged.
    t := cur(pc)
    if t.kind == 1 and str_eq(str_at(pc.src + t.start, t.len), "module") and tok_at(pc, pc.idx + 1).kind == 1 {
      pc.idx = pc.idx + 1                 ## 'module'
      mn := cur(pc); pc.idx = pc.idx + 1  ## module name
      pc.mod_s = mn.start
      pc.mod_l = mn.len
    } else {
      h := parse_decl(pc, da)?
      np := rt::vec_push(out_decls, h)
    }
  }
  ## END-OF-INPUT CONTAINMENT (I11 correct-or-trap; Grammar §2 — a program is a sequence of
  ## declarations, and the whole token stream belongs to one). EVERY recursive-descent loop in this
  ## module terminates on `kind == 0` as well as on its own closer (see `tok_at` — the synthetic EOF
  ## sentinel is what keeps a past-end peek from dereferencing an unwritten slot). That is what makes
  ## a truncated file PARSE: the loop that was waiting for `)` / `}` / `]` reaches EOF, stops as if
  ## the group had closed, and `parse_decl` hands back a well-formed-looking `Decl`. Measured on the
  ## pre-fix compiler: a file whose tail is `BROKEN := fn( -> u64 {` built with rc 0 and RAN, and the
  ## same held for an unclosed `fn` body, `struct {`, `enum {` and a bare `fn(` — the accepted program
  ## silently omitted the truncated declaration and everything after it. A silent acceptance of an
  ## unparsed remainder is the forbidden outcome: the program that runs is not the program that was
  ## written.
  ##
  ## The residual DELIMITER DEPTH over the whole token stream is what distinguishes the two. A file
  ## the compiler must accept is balanced — measured independently over all 1 419 tracked `test/*.al`
  ## plus `src/` (29) and `lib/` (36): residual 0 for every one, and the delimiter count is taken over
  ## TOKENS, so a `{` inside a string literal or a comment cannot perturb it (the lexer emits neither).
  ## A truncated file leaves a group open. So: after the declaration loop has consumed the stream to
  ## EOF, a POSITIVE residual means an open group was closed by end-of-input rather than by its own
  ## closer — reject, located at the OUTERMOST still-open opener (the last `0 -> 1` transition, i.e.
  ## the point the truncation begins).
  ##
  ## The diagnostic goes through `reject_at` — this module's own located-reject mechanism (23 call
  ## sites) — and NOT through the `Result(usize, ParseErr)` return, because that channel carries a
  ## POSITION on one path only: `driver::check_files` reads `parser::cur(pc)` after an `Err` and renders
  ## `alatyr: parse: unexpected token … at line N in M`, while all ten OTHER `parse_program` call sites
  ## in `driver.al` (every build/emit/run/fmt/test path, including the `-o out <file>` path this defect
  ## was reported on) turn any `Err` into a bare `panic("selfhost: parse error")` with no location at
  ## all. Measured: on the pre-fix compiler a trailing `}}}` printed the located message under `check`
  ## and the unlocated one under `-o`. `reject_at` gives the same `[module M, at line N, near `…`]` on
  ## all seven CLI paths (verified: check/run/fmt/emit/wat/aarch64/riscv64 all rc 1 + located), which is
  ## what "loud" has to mean for a file the author believes is intact.
  ##
  ## This sits at the TAIL of `parse_program`, not in the 61 `cur(pc).kind != 0` guards that
  ## actually absorb the EOF, for three reasons: it runs ONCE per module and never on a nested parse
  ## path, so it cannot alter the parse of any program that is accepted today; changing those loops
  ## would rewrite the parser's error recovery wholesale (and each of them is on the hot accepted
  ## path); and the diagnostics of the shapes that ALREADY fail would move — trailing `}}}`, a bare
  ## `42` and a bare identifier are each rejected by `parse_decl` before this point with a located
  ## `alatyr: parse: unexpected token …`, and a NEGATIVE residual is deliberately not reported here so
  ## those keep the message they have. An empty file and a comment-only file have no delimiters at all,
  ## so their present behaviour is untouched.
  mut eod := 0
  mut eod_off := 0
  mut eod_i := 0
  eod_n := ntoks(pc)
  while eod_i < eod_n {
    eod_k := tok_at(pc, eod_i).kind
    if eod_k == 10 or eod_k == 12 or eod_k == 14 {
      if eod == 0 { eod_off = tok_at(pc, eod_i).start }
      eod = eod + 1
    }
    else if eod_k == 11 or eod_k == 13 or eod_k == 15 {
      if eod > 0 { eod = eod - 1 }
    }
    eod_i = eod_i + 1
  }
  if eod > 0 {
    reject_at(pc, "selfhost: the input ends inside an unclosed `(`, `{` or `[` - the parser reached end-of-input while a group was still open, so this declaration and everything after it is NOT part of the program (a truncated file, a partial copy, or a bad merge); close the group", eod_off)
  }
  Result(usize, ParseErr).Ok(rt::vec_len(out_decls))
}
