# AST list migration to `Option(ptr(T))`

This note is the hand-off for the remaining list migrations: **Param, Arm, Arg, Stmt**. It covers the
procedure, the rewrite rules, the tool, the measurements, the defects found so far, and the PR shape. It
was written after three lists were done (Bind, FInit, FieldDecl), and it is meant to be complete enough
to execute the Param migration from start to finish with no other context.

## Why

Strict forms §1 (`AGENTS.md`, `.agents/skills/alatyr-lane/strict_forms.md`, #529) says absence is
`Option`, not a sentinel. The compiler's AST lists end in a null pointer instead: `next : ptr(mut T)`
with a `0` end, tested by `p != 0` or `unchecked bitcast(usize, p) != 0`. Each such test is counted by
`scripts/strict_forms_check.sh`:

- **null-explicit** — the lexical count of explicit null forms;
- **typed null / implicit OP-CMP** — the #529 checker instrument on fd 98, which knows `p` in `p != 0`
  is a pointer.

The goal is to drive those counters down by expressing every list as `Option(ptr(mut T))`. The
counters must go **down**: rewriting `p != 0` as `unchecked bitcast(usize, p) != 0` only moves a count
from the implicit column to the explicit one. That move is not progress.

Owner rule: write the target form only — no explicit-null stopgaps and no `## null-ok` /
`## unchecked-ok` markers. If the target form does not work, that is a compiler defect: file it (see
"Defects") and fix it, or report it. Never route around it.

## What a finished list looks like

These are the forms used in the Bind / FInit / FieldDecl migrations. The FieldDecl versions are shown;
for another list, substitute its own names.

**Types (`src/ast.al`).**

```alatyr
## before
pub FieldDecl := struct { ns : usize, nl : usize, arity : usize, next : ptr(mut FieldDecl), … }
  fields_head : ptr(mut FieldDecl),          ## in Decl
pub fld_null := fn() -> ptr(mut FieldDecl) { unchecked bitcast(ptr(mut FieldDecl), 0) }

## after
pub FieldDecl := struct { ns : usize, nl : usize, arity : usize, next : Option(ptr(mut FieldDecl)), … }
  fields_head : Option(ptr(mut FieldDecl)),  ## in Decl — `None` = no fields
## `fld_null` is DELETED. `fld_p` (the identity accessor) stays and is applied to a `Some` payload.
pub fld_p := fn(p : ptr(mut FieldDecl)) -> ptr(mut FieldDecl) { p }
## Helpers the walks need. Add one only when ≥ 2 sites ask the same question (strict forms §4).
pub fld_any := fn(h : Option(ptr(mut FieldDecl))) -> bool { match h { Some(_q) => { true }; None => { false } } }
pub fld_at := fn(h : Option(ptr(mut FieldDecl)), msg : str) -> ptr(mut FieldDecl) {
  match h { Some(q) => { q }; None => { panic(msg) } }      ## "the list cannot end here": a located error
}
## Bind used `bnd_next(p) -> Option(...)`, `bind_count(h) -> usize` and `bind_same(x, y) -> bool`
## (list identity), the same way.
```

**Walk.**

```alatyr
## before
mut f := d.fields_head
while f != 0 {                         ## or: while unchecked bitcast(usize, f) != 0 {
  fd := deref(fld_p(f))
  …
  f = fd.next
}
## after
mut f := d.fields_head
loop {
  match f {
    Some(fq) => {
      fd := deref(fld_p(fq))
      …
      f = fd.next
    }
    None => { break }
  }
}
## A guarded walk `while f != 0 and C {` becomes `Some(fq) => { if not (C) { break } … }`.
```

**Head-only test.** `if d.fields_head != 0 {…}` becomes `if fld_any(d.fields_head) {…}`, or a `match`
when the body needs the node.

**Optional cursor that advances alongside another list** (for example a struct literal's values walked
together with the struct's fields):

```alatyr
## before
mut fld := 0
if di != 0 { fld = deref(decl…).fields_head }
while g != 0 { …; if fld != 0 { fd := deref(fld_p(fld)); …; fld = fd.next }; g = ga.next }
## after
mut fld : Option(ptr(mut FieldDecl)) = Option.None
if di != 0 { fld = deref(decl…).fields_head }
while g != 0 { …; match fld { Some(fldq) => { fd := deref(fld_p(fldq)); …; fld = fd.next }; None => {} }; g = ga.next }
```

**"Must have a node here" cursor.**

```alatyr
## before
if fd == 0 { panic("… more values than fields") }
fdn := deref(fld_p(fd))
## after
fdn := deref(fld_p(fld_at(fd, "… more values than fields")))
```

**Two lists in lockstep.** Nest the matches. "Both ended" agrees; "one ended first" disagrees. See
`agg_members_agree` in `src/lower.al`, which compares two structs' field names.

**Append-build (parser).**

```alatyr
## before
mut fhead := fld_null()
mut ftail := fld_null()
… fnew := fnode(pc.arena, FieldDecl(…, next = unchecked bitcast(ptr(mut FieldDecl), 0), …))
if unchecked bitcast(usize, fhead) == 0 { fhead = fnew } else {
  old := deref(ftail); deref(ftail) = FieldDecl(…, next = fnew, …)
}
ftail = fnew
## after
mut fhead : Option(ptr(mut FieldDecl)) = Option.None
mut ftail : Option(ptr(mut FieldDecl)) = Option.None
… fnew := fnode(pc.arena, FieldDecl(…, next = Option.None, …))
match ftail { Some(ft0) => { deref(ft0).next = Option.Some(fnew) }; None => { fhead = Option.Some(fnew) } }
ftail = Option.Some(fnew)
```

**Constructor fields.** `fields_head = unchecked bitcast(ptr(mut FieldDecl), 0)` becomes
`fields_head = Option.None`, and `fields_head = node` becomes `fields_head = Option.Some(node)`.

**Handle parameters and returns.** A `usize` or `ptr(mut T)` parameter, local or return value that
carries a list head becomes `Option(ptr(mut T))`. Callers that passed
`unchecked bitcast(ptr(mut T), 0)` now pass `Option.None`. An `Option` parameter is passed by reference
(one folded word) and costs nothing extra.

**Backend handle globals.** Two forms, both of which need #823/#824 in the compiler that builds the tree:

```alatyr
## before
mut A64_ARM_BINDS := 0                                   … A64_ARM_BINDS = unchecked bitcast(usize, am.binds_head)
mut A64_BIND_HEADS : [usize; 32] = [0; 32]               … bh := unchecked bitcast(ptr(mut Bind), A64_BIND_HEADS[bi]); if bh != 0 {…}
## after
mut A64_ARM_BINDS : Option(ptr(mut Bind)) = Option.None  … A64_ARM_BINDS = am.binds_head
mut A64_BIND_HEADS : [Option(ptr(mut Bind)); 32] = [Option.None; 32]
                                                         … bh := A64_BIND_HEADS[bi]   ## a consumer that maps None → "not found" needs no test
```

An identity compare between two handles (`HEADS[top] == unchecked bitcast(usize, head)`) becomes a
typed helper that compares the two `Some` payloads (`bind_same`).

## Procedure for one list

Work on a lane worktree stacked on the previous list's PR head. Keep one list per PR.

1. **Inventory.** Count every site that touches the list. For Param:
   ```sh
   for pat in params_head 'param_p(' 'param_null(' 'Param(ns' 'ptr(mut Param)' A64_PARAMS RV_PARAMS WAT_PARAMS; do
     printf '%-16s ' "$pat"; grep -rcF "$pat" src --include='*.al' | grep -v ':0$' | sed 's|src/||' | tr '\n' ' '; echo
   done
   grep -rn 'while [a-z_]* != 0\|while unchecked bitcast(usize, [a-z_]*) != 0' src | wc -l   # all list walks, every list
   ```
   For Param, at the time of writing: about 1200 `params_head` occurrences, most of them the backends'
   pass-through `params_head : ptr(mut Param), pcount : i64` parameters (aarch64 78, riscv64 74, wasm 74).
   There are about 230 `param_p(` sites, 23 `param_null()` / `ptr(mut Param), 0` sites in the parser and
   9 in the driver. Other sites to expect:
   - the globals `A64_PARAMS := 0` + `a64_params()`, and their riscv64 / wasm twins;
   - `param_find(params_head : ptr(mut Param), …)` in `lower_ctx.al` and in `wat.al`;
   - the `Expr::Lambda(usize, ptr(mut Param), …)` payload;
   - `set_param_next` and `if unchecked bitcast(usize, head) == 0 { head = np } else { set_param_next(a, tail, np) }` in the parser;
   - `ephead` ("effective params head") locals in the backends.
2. **Retype** the link field, the head field(s), any enum payload that carries a head, and the null
   accessor (`param_null` is deleted), all in `src/ast.al`. Then convert the parser's builders and
   constructors.
3. **Convert walks with the tool.** Review every rewritten hunk.
   ```sh
   python3 scripts/ast_option_walk.py walk '[^\n]*?params_head' src/*.al src/lower/*.al
   python3 scripts/ast_option_walk.py ifsome src/<file>.al <var> …    # `if v != 0 {…}` cursors
   ```
   The tool rewrites `while V != 0 [and C] {…}` and `while unchecked bitcast(usize, V) != 0 [and C] {…}`
   for every `V` bound from a head matching the regex. It reports what it skipped: a body that never
   advances `V`, or a `Vq` name that is already taken. It does not change declarations. Run it again
   with a broader head regex for walk variables bound from parameters, returns or `deref(...)`
   expressions.
4. **Convert the rest by hand**, using the "What a finished list looks like" forms:
   - head tests, cursors, lockstep walks;
   - parameter / return / local types;
   - constructor fields;
   - globals and global stacks;
   - identity compares.

   To find what is left, grep for the old forms. All of these should be gone except unrelated lists:
   ```sh
   grep -rn 'param_null\|ptr(mut Param), 0\|bitcast(usize, [a-z_.]*params_head\|params_head) != 0\|PARAMS != 0' src
   grep -rn 'param_p(' src | grep -v 'param_p([a-z_0-9]*q)'   # every remaining deref of a non-`Some` handle
   ```
5. **Build with a tree compiler, not the seed.** The frozen seed usually lags these forms; it accepts the
   tree only after the integrator's next promotion. Use an `alatyr` built (by the seed) from the BASE
   commit, which contains every compiler fix the migrated source needs:
   ```sh
   nix develop -c bash -c 'ulimit -c 0; bash scripts/ast_option_measure.sh <base-tree-compiler> <base-sha> --e2e'
   ```
   (see "Measurements").
6. **Fix what fails.** If the tree compiler refuses or miscompiles the target form, it is a defect: see
   "Defects". A "NARROWER binding" refusal is not a defect. Alatyr `:=` locals are function-scoped, so a
   new `Option` local that reuses the name of an earlier `usize` or `ptr` local in the same function must
   be renamed (FInit: `g` → `fig`).
7. **Commit** with a `refactor(ast): express the <List> list as Option(ptr(mut <T>))` subject. The body
   records the measurements from step 5 (see "PR shape").

## Measurements

`scripts/ast_option_measure.sh <tree-compiler> <base-ref> [--e2e]` prints all of these:

| what | must hold |
|---|---|
| `fixpoint: Stage1' GAS == Stage2' GAS`, `Stage2 == Stage3 binaries` | yes (the migrated tree reaches its own fixpoint) |
| `codegen unchanged` | yes for a pure list migration (a migration that bundles a compiler fix shows exactly that fix's sites instead: FieldDecl's #846 fix showed 2 hunks, `movq $1` → `movq $0`, and that IS the seed-vs-Stage1 delta the next promotion reviews). The base compiler and the tree's compiler emit the same GAS for the tree, so the frozen seed will satisfy `seed == Stage1 == Stage2` once it accepts the tree, and **no extra promotion** is owed for the list (only the one that carries the compiler fixes) |
| `strict forms: … null-explicit=A->B` / `strict forms typed: … null=…(explicit=… implicit-cmp=…)` | the counts go DOWN. Report null-explicit, typed null, **implicit OP-CMP** (the counter the goal tracks) and unchecked, per list |
| `own-GAS delta` | informational: hunks and functions of the compiler's own GAS against the base tree (labels normalized). It changes because the compiler's SOURCE changed, so it is **not** a promotion delta |
| `seed:` | whether the frozen seed accepts the tree. A refusal means the PR waits for a promotion. Report it; a lane never promotes |
| e2e | all green with the tree's compiler |

The census can also be run alone:
`ALATYR_STRICT_BASE=<base> bash scripts/strict_forms_check.sh` (lexical) and
`… --typed` (needs `target/debug/alatyr` built from the tree).

Results so far (each measured against its parent):

| list | PR | null-explicit | typed null | implicit OP-CMP | unchecked | functions touched |
|---|---|---|---|---|---|---|
| Bind | #834 | 903→830 | 1262→1189 | 359→359 | 1818→1802 | 54 |
| FInit | #847 | 830→828 | 1189→1187 | 359→359 | 1802→1795 | 3 (parser) |
| FieldDecl (+#826, #846) | #848 | 828→806 | 1187→1158 | 359→352 | 1795→1788 | 559 (most are frame-offset shifts: every function that copies a `Decl`) |

Bind and FInit were walked through explicit `unchecked bitcast` forms or uncounted shapes. FieldDecl was
the first list whose `while f != 0` walks were counted as implicit OP-CMP rows. Param, Arm, Arg and Stmt
are mostly `while p != 0` / `while s != 0` walks, so their implicit OP-CMP drop should be large.

## Defects: the ones hit so far, and how to recognize a new one

A migration that produces the target form, check-passes, and then fails at build or run time with the
**tree** compiler has found a compiler defect. Every one below was a real defect, not a migration
mistake:

| symptom | defect | status |
|---|---|---|
| SIGSEGV when matching an `Option(ptr)` parameter/local and dereferencing the payload; "NARROWER binding" on `p = Option.None` | bare `Option.Some/None` not folded at a parameter / re-assignment (#789) | fixed (#796) |
| `a.next = Option.Some(p)` stores None | field store pushed the literal as a scalar (#797) | fixed (#807) |
| an `[Option(ptr(T)); N]` local/param/field reads 0 | array element sized from the first literal (#808) | fixed (#819) |
| "cannot see the scrutinee's enum type" on `match G.f` / `match xs[i].f` / `match deref(p).f` | #809 | fixed (#820) |
| a `mut G : Option(ptr(T))` global reads 0 | #823 | fixed (#831) |
| a global `[Option(ptr(T)); N]` reads 0, or `check` refuses an element in value position | #824 | fixed (#832) |
| "aggregate-value call-arg temp pool overflow" on nested calls passing Option values | #828 | fixed by #815 (measured pool) |
| a global struct with an Option field before another field misreads the later field | #826 | fixed with the FieldDecl migration |
| the compiler SIGSEGVs on its own `deref(gdp) = Decl(…, fields_head = Option.None, …)` | `deref(p) = S(…)` pushed a folded field literal as a scalar (#846) | fixed with the FieldDecl migration |
| `ptr(mut G[i])` of a global struct element is wrong | #825 (not Option-specific) | open; avoid the form or fix it |
| a string such as `"field name="` turned into `"fieldq name="` after conversion | the first version of the walk tool renamed words inside string literals | fixed in `scripts/ast_option_walk.py` (it skips strings and `##` comments); still grep the diff for changed string literals |

How to recognize a new one:

- A **crash of the tree compiler on some e2e rows** after a migration most likely means a struct
  **literal** with a folded field is materialized by a path that pushes fields as scalars. `ast::Option`
  is `enum { Some(T), None }`, so a bare `Option.None` pushed as a scalar is variant index **1**, not 0.
  The tree's own `Decl(…)`, `Arm(…)`, `Param(…)` and `Stmt` constructions hit this first.
  1. `gdb -batch -ex run -ex bt --args ./target/debug/alatyr -o /tmp/x <failing test>` names the function.
  2. Find which constructor writes the list field there.
  3. Make that store path push through `emit_store_value(v, <field's declared type>)`; #807/#846 are the
     pattern.
- A **refusal** naming an Option form ("cannot see the scrutinee's enum type", "NARROWER binding" on a
  value of the same type, "temp pool overflow") is a missing case in the folded-Option decision point:
  `folded_value_span`, `folded_slot_span`, `folded_array_elem_of`, `field_place_type_span`,
  `try_folded_value_scrut`, `emit_store_value`, `emit_folded_option_value`. Extend that machinery
  rather than adding a parallel path (strict forms §4).
- Reproduce every defect as a 10–20-line user program, file it with the `wrong-value` or
  `fails-when-valid` label plus `area:lower`, fix it with its own fixture (`run_x86 <name> 42`), and
  stack the list migration on that fix.

## PR shape

- One list per PR, stacked: each PR is based on the previous list's head. The relation line is
  `Refs #529`, or `Closes #N` if the PR also fixes a filed defect; mention #529 in the body then.
  Exactly one line-initial relation marker.
- Body: what changed (types, walks by tool and by hand, helpers, handles, globals), plus every number
  from `ast_option_measure.sh`: fixpoint, codegen unchanged, census deltas including implicit OP-CMP,
  own-GAS delta, seed acceptance, e2e.
- If the frozen seed refuses the tree, say so: the PR waits for the integrator's promotion that carries
  the needed compiler fixes. Codegen-unchanged means no second promotion is owed for the list itself.
- No oracle files (`scripts/corpus.manifest`, `scripts/idiom.baseline`, `scripts/needle.baseline`). A
  pure list migration adds no fixture and should show `0 CHANGED, 0 ADDED`. A bundled defect fix adds
  its fixture's rows.
- The authoritative gate (`gate/<name>` → GitHub Actions, or the native x86_64 gate box) needs a seed
  that accepts the tree, so for a list migration it runs after the promotion. Until then the evidence is
  the tree-compiler measurement above.

## Suggested order inside Param

1. `ast.al` (types, `param_null` removed) → `parser.al` (builders, `set_param_next`) → `driver.al`.
2. `lower_ctx.al::param_find` and `wat.al::param_find` (they walk the list), then `lower_layout.al`.
3. `sema.al`.
4. `lower.al` and `src/lower/*`.
5. The backends: the `params_head` parameters become `Option(ptr(mut Param))`, the `A64_PARAMS`-style
   globals become `Option(ptr(mut Param))` globals (their `a64_params()` accessor returns the Option),
   and `ephead` becomes typed.
6. The `Expr::Lambda` payload.

Expect the backend parameter plumbing to be most of the diff, and most of the frame-offset shifts in
the own-GAS delta.
