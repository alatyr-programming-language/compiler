# Strict forms — how to write compiler code the checker can hold you to

Read this before you write compiler or library code, not after the gate refuses it. `AGENTS.md`
"Strict forms" is the one-screen summary; this file gives each form's reason, the issue where the
defect shipped, and a short "write this / not this" example.

Prose and checks do different jobs. A rule you have read makes the code better on the **first**
pass: you write the strict form because you know why it matters. A check is the barrier for what gets
past that. The project has measured what happens to a rule kept only in prose: #649 found the
"`git add` a new fixture" rule was written down and still cost a whole gate run, and people route
around rules like that. So every form below states whether a check holds it, and "not checked, held
by review" is an honest answer too. A form with no check yet is still a rule. The missing check is a
gap to close, not permission.

Every form turns a defect class this compiler has **shipped** into something that cannot be written,
or cannot be written without a visible, justified marker. The type does most of that work. The check
is there for the places the type does not yet reach.

**Write the strict form in the first draft.** Use idiomatic code with strict types from the start;
do not write loose code and tighten it after a check complains. Never satisfy a check by switching
to an explicit sentinel, or by adding a marker, when the typed form is possible. A marker
acknowledges a form that cannot be avoided *yet*. It is not a way around a rule. If the typed form
does not compile, or the compiler gets it wrong, that is a compiler defect. File it, and name the
issue in the marker's reason. Do not quietly route around it.

| § | form | defect class it retires | held by |
|---|---|---|---|
| 1 | absence is `Option(ptr(T))` walked with `match`, not a sentinel | 0 as null, −1 as "not found", 255 as "poisoned" | `strict_forms_check.sh` `null` (typed + lexical); the transitional marker names its blocker (#809, #792) |
| 2 | a kind is an enum, not an integer; flags are not packed into it | #583 (134 literal `.tag` sites), #626, `+128` mut flag | `strict_forms_check.sh` `kind-literal` |
| 3 | decide with an exhaustive `match` on the value | #544 (249 blind wildcard arms), #716, #464 | `wildcard_arm_check.sh`; the rest by review |
| 4 | one decision, one place | the #540 family, #539 | `idiom_gate.sh` (for the shapes it knows) |
| 5 | width and signedness are spelled, never inferred from a form | #546, #608, #707, #764–#766 | review |
| 6 | `unchecked` is explicit and justified; no implicit `usize` ↔ `ptr` | #529, #610 | `strict_forms_check.sh` `unchecked`, `ptrint` |
| 7 | bind a `?` before using its value | #752 | `strict_forms_check.sh` `try-inline` |
| 8 | do not write the forms the frozen seed miscompiles | no live rows; seven retired by 0.2.5, two (#790, #791) by 0.2.7 | `seed_forms_check.sh` (the registry, `scripts/seed_forms.tsv`); a comment at every workaround |
| 9 | an AST handle has its node's own type | #760 (12 walkers), the `usize` pass-plumbing | the checker (since #760), review; §9 has the proposal |
| 10 | a quantity with an identity is a `brand`, not a bare number | #167 (word offset used as a byte offset), #760, #299 | the checker refuses a sibling or raw mix (since #299); *choosing* a brand is held by review |

## 1 · Absence is `Option(ptr(T))` walked with `match`, not a sentinel

**Defect class.** A value that means "there is nothing here" but has the same type as a real value.
The compiler cannot tell the two apart, so nothing makes you check before you use it. That has
shipped in every form:

- a null pointer read without a test: #681, where `index_parts` returns a null base the store dispatch
  never checks, and the compiler segfaults;
- an accessor whose "not that form" answer is also a real answer: #659, where `num_lit_value` answers
  `0` both for "not a literal" and for the literal zero (#691 lists the #558 / #590 / #602 / #633
  family);
- `-1` as "not found" (`conv_kind(...) >= 0`), and `255` as a poisoned binding (`tag_is_poison`).

An *explicit* null (`unchecked bitcast(usize, p) != 0`) does not retire this class. It only makes the
null visible. The value still has a pointer's type, nothing makes the reader test it, and the `null`
sum stays flat. So the explicit spelling is never the target form. At most it is a transitional
form (below).

**Write this, in the first draft.** The absence is part of the type. `Option(ptr(T))` is
niche-folded, so it is still one word (Types §8, `test/niche_option_ptr.al`). A `match` on it forces
the absent case to be handled, and a linked structure is walked with that `match`:

```alatyr
## not this — the absence is the integer 0, and nothing makes the caller test it
find_decl := fn(decls : ptr(Decl), n : usize, s : usize) -> ptr(Decl) {
  ...
  unchecked bitcast(ptr(Decl), 0)
}
d := find_decl(ds, n, s)
v := deref(d).value                         ## reads address 0 when the test is forgotten

## not this either — the same sentinel, only spelled out
while unchecked bitcast(usize, s) != 0 { ... ; s = deref(s).next }

## this — the absence is a variant, and the match cannot leave it out
find_decl := fn(decls : ptr(Decl), n : usize, s : usize) -> Option(ptr(Decl)) {
  ...
  Option(ptr(Decl)).None
}
r : Option(ptr(Decl)) = find_decl(ds, n, s)
match r {
  Some(d) => { dv : Decl = deref(d) ; use(dv.value) }
  None => { return located_reject(s) }
}

## this — a list walk (N := struct { v : u64, next : Option(ptr(mut N)) })
mut p : Option(ptr(mut N)) = head
loop {
  match p {
    Option::Some(q) => { nd : N = deref(q) ; s = s + nd.v ; p = nd.next }
    Option::None => { break }
  }
}
```

For an integer, use `Option(u64)`, `Option(usize)` and so on, not a reserved value.

**The seed handles these forms since 0.2.5.** The tree fixed #768, #770 and #775 (#787), #789
(#796) and #797 (#807), and the 0.2.5 promotion carried every fix into the seed. The §8 registry
proved it: every `option_ptr_*` row planted against seed 0.2.4 answered 42 under 0.2.5 and retired.
So compiler and library code writes the walk above, and builds lists the same way
(`a.next = Option.Some(ptr(mut b))`). Bare `Option.Some(x)` / `Option.None` fold to their
position's type.

**Transitional form, only for the shapes that are still broken.** Two defects remain, and the
typed form cannot be written in these shapes yet:

- #809: a direct `match` over an `Option(ptr(T))` field reached through a mutable global, an array
  element or `deref(p)` (`match deref(p).next {…}`) is refused by the lowering. Copy the field into
  an annotated local first (`o : Option(ptr(mut N)) = deref(p).next ; match o {…}`). That works, so
  it is the form to write, not a sentinel.
- #792: an enum-typed or `Option(u64)` field read through a pointer (`deref(p).f`) is a wrong value
  or a SIGSEGV. Bind the record first (`rv : Rec = deref(p) ; rv.f`).

Where neither workaround reaches (the AST's own lists still end in a raw null `next`, and converting
them is §9 step 2), spell the null explicitly (§6). The marker's reason must name the **blocking
issue**, not only the structure:

```alatyr
## null-ok: #809 — Stmt.next ends in a null link; the AST's lists are not Option(ptr(Stmt)) yet (§9)
while unchecked bitcast(usize, s) != 0 { ... }
```

A `null-ok` whose reason names no issue is a sentinel chosen, not a sentinel forced. Review refuses
it. When the named issue closes, its markers are the sites to convert.

**Check.** The `null` rule of `scripts/strict_forms_check.sh`. It counts the explicit spellings
(`bitcast(ptr(T), 0)`, and `bitcast(usize, p) ==/!=/> 0` in either operand order) and the implicit
comparison `p == 0` with `p : ptr(T)`. The compiler reports the implicit one, because only the checker
knows `p` is a pointer. The check refuses a change that increases the sum. Marker: `## null-ok: #<the
blocking issue> — <which null-terminated structure>`. The sum is flat while #529 converts implicit
tests into explicit ones, so that work is never refused. The rule checks that a reason exists. That
the reason names a real blocker is held by review. The 10 `null-ok` markers already in `src/` predate
this rule and name only the structure. Each gets its blocker named the next time its file is edited.

## 2 · A kind is an enum, not an integer, and flags are not packed into it

**Defect class.** A kind stored as a number and tested against literals whose meaning lives only in a
comment. #583 measured **134** such `.tag` sites in `src/sema.al` and traced three defects to them:

- #519: a wiring gap that an exhaustive match would have shown;
- #529: the implicit `usize` ↔ `ptr` seam, which exists only because `1` and `5` are comparable;
- #562: two constructs that share tag 8.

The byte then took on more meanings: `+128` marks a `mut` binding and `255` poisons one (`src/sema.al`,
the `tag_with_mut` / `tag_is_poison` band). #626 records `Local.prov`, one `u8` that carries eleven
meanings in two encodings.

**Write this.** A kind is an `enum`, flags are separate fields, and the question is a `match`.
`src/sema.al`'s `TyKind` is the model (#583, `503d602`):

```alatyr
## not this
if t.tag == 5 { ... }                        ## 5 means "pointer", per a comment 4000 lines away
mut_tag := tag + 128                         ## a flag packed into the kind byte
if tag == 255 { return poisoned }

## this
TyKind := enum { TyUnknown, TyInt, TyBool, TyStruct, TyEnum, TyPtr, ... }
Local := struct { kind : TyKind, is_mut : bool, state : BindState }
match ty_kind(t) { TyPtr => { ... } ; TyInt | TyBool | ... => { ... } }
```

If a kind is still an integer (the lexer's `Token.kind` is compared with a literal 384 times in
`src/parser.al`), do not add another literal comparison. Name the value once, or convert that kind.
The replay below shows #583's slices #723, #724 and #734 removed 306 of these comparisons in three
merges. That is the direction the tree is moving.

**Check.** The `kind-literal` rule. It fires on a name or field `kind`, `tag`, `prov`, `flags`, `*_kind`
or `*_tag`, or a call `*_kind(…)`, that is compared with an integer literal (`== != < > <= >=`) or
combined with one (`+ - & |`). It also fires on a `match` over such a name that has a literal arm.
Marker: `## kind-literal-ok: <why this kind has no named form yet>`.

## 3 · Decide with an exhaustive `match` on the value

**Defect class.** A decision that absorbs a case nobody wrote. #544's census found **249 of 727**
`_ =>` arms where deleting the wildcard is silent: `check` 0, `build` 0, and at run time no arm is taken
and the program exits `rc=255`. #464 is the emitter family, where `_ => {}` silently succeeds. #716 is
the other half: a `match deref(ptr(mut x))` on a local of the same function compared every arm against
tag 0, because the lowering could not resolve that scrutinee's enum type and answered 0 instead of
refusing.

**Write this.**

- Spell the absorbed variants as one OR-pattern arm (`wildcard_enumeration.md` §3). Never use `_` over
  a project enum.
- Match the enum *value* instead of re-deriving the variant from numbers or names. The scrutinee shapes
  the lowering is proved on are a parameter's `deref`, a bound local, or a direct call whose declared
  result is the enum. `ty_kind(t)` exists so a `match` can use it as its scrutinee.

```alatyr
## not this
match deref(e) { Expr::Num(v) => { ... } ; _ => {} }              ## absorbs every later variant
if expr_kind(e) == 7 { ... }                                       ## the variant as a number

## this
match deref(e) {
  Expr::Num(v) => { ... }
  Expr::Var | Expr::Call | Expr::Field => {}                      ## a new variant is a check error
}
```

**Check.** `scripts/wildcard_arm_check.sh` refuses a new `_ =>` over an enumerable scrutinee (marker
`## wildcard-ok: <reason>`). Scrutinee choice is held by review.

## 4 · One decision, one place

**Defect class.** The same fact recovered by scanning the source in several places, with the copies
drifting apart. The #540 umbrella counts this as the reason the defect count grows. #539 is a third copy
of one layout decision with a narrower scalar set. #501 / #505 → #528 shows two correct copies whose
merge produced a new wrong value.

**Write this.** Before you write a predicate, `grep` for the question it answers. If an answer exists,
call it. If two exist, reducing them to one is part of your fix (`SKILL.md` §4). A new answer lives next
to the type it is about (`TyKind`'s predicates are one exhaustive `match` each, so a new kind has to be
answered in all of them).

**Check.** `scripts/idiom_gate.sh` (the TABLE and SCAN rules) refuses a new duplicated decision of the
shapes it knows. Anything it cannot see is held by review.

## 5 · Width and signedness are spelled, never inferred from a form

**Defect class.** The emitted operation chosen from the *spelling* of an operand instead of its type:

- #546: `bitcast(i64, x) < 0` is constant-false, because the bitcast does not re-sign the comparison;
- #608: four unsignedness predicates disagree;
- #707: an indexed unsigned element compares signed;
- #764 / #765 / #766: a signed `/`, `%` or ordering whose operand is `unchecked`, an `if`, or
  literal-only divides or compares the wrong way.

**Write this.** Give the value a declared type before you compute with it: annotate the local, then
use it (`d : i64 = unchecked bitcast(i64, x)` ; `if d < 0`). Do not rely on a literal-only expression or
an `if` / `match` expression to carry signedness into `/`, `%` or an ordering. Choose the narrowest
width that holds the value, and write that width.

**Check.** None. Held by review. A typed rule is possible over a census channel, as for §6.

## 6 · `unchecked` is explicit and justified, and there is no implicit `usize` ↔ `ptr`

**Defect class.** A reinterpret that the reader cannot see, or cannot tell from a silenced mismatch.
Types §4.3 makes a reinterpret explicit, and Memory §4.5 makes fabricating a pointer from an integer
ill-formed outside an `unchecked` grant. #529 is the checker accepting the implicit form anyway (361
comparisons remain, all `p == 0` / `p != 0` shapes). #610 is pointer arithmetic that never reaches the
seam at all. The tree holds 1818 `unchecked` escapes, not counting null forms, and none of them carries
a reason.

**Write this.** Cross between integer and pointer only with `unchecked bitcast`, and write down why it
is sound, on that line or the line above:

```alatyr
## not this
h : usize = p                                   ## implicit crossing (#529)
q := unchecked bitcast(ptr(mut Stmt), h)        ## why is this sound?

## this
## unchecked-ok: rt::Vec stores usize words; every slot of `stmts` was pushed from a ptr(mut Stmt).
q := unchecked bitcast(ptr(mut Stmt), rt::vec_get(stmts, i))
```

Before you write the marker, check whether the operand already has the right type. The cheapest
`unchecked` is the one you delete.

**Check.** The `unchecked` rule (marker `## unchecked-ok: <reason>`). An `unchecked` that only spells a
§1 null form is counted under `null` instead, so one line never needs two markers. The typed `ptrint`
rule refuses any new implicit crossing and has no marker: write the crossing explicitly instead.

## 7 · Bind a `?` before using its value

**Defect class.** #752: `x := f()?` over a multi-word `Ok` payload delivered only word 0. The fix
(#754, `4d4911c`) made the binding correct, and the frozen seed 0.2.4 has that fix. The inline uses
(`f()?.a`, `use(f()?)`, `S(a = f()?)`) stayed wrong until `1b5cd53`, which now takes every word or
refuses. Seed 0.2.4 predated `1b5cd53` and answered 0 on `f()?.b`. Seed 0.2.5 answers 42, and
the §8 registry row that planted it retired with that promotion. So the seed reason for this form is
gone. The rule still holds for its own sake, because a bound `?` is easier to read and to check. Its
removal is the owner's decision.

**Write this.**

```alatyr
## not this
n := allocate(deref(d.arena), T, sz, al)?.idx
return S(a = f()?)

## this
blk := allocate(deref(d.arena), T, sz, al)?
n := blk.idx
fv := f()?
return S(a = fv)
```

The statement form `f()?` is fine, because there is no value to read.

**Check.** The `try-inline` rule refuses a `?` followed on its own line by anything but `}` or `;`
(marker `## try-inline-ok: <why the payload is one word>`).

## 8 · Do not write the forms the frozen seed miscompiles

**Defect class.** `seed/alatyr` builds Stage1, so a form it miscompiles breaks the compiler even when
the tree's own compiler handles it correctly. For a long time these forms were recorded **only** as
comments at the workaround sites. A comment cannot tell anyone whether it is still true, and nothing
noticed when a promotion made one obsolete. The owner's decision on #785 made them a registry.

**The registry.** `scripts/seed_forms.tsv` has one row per form. Each row points to a planted
program, `scripts/seed_forms/<name>.al`, and gives its correct exit value, its issue and its
workaround sites. The programs live outside `test/`, because the corpus pathspec `test/*.al` crosses
`/`, and a seed limitation that retires on a promotion must not move the corpus manifest. A row has
one of two states:

- **`seed`**: the frozen seed miscompiles the form and the tree compiler runs it correctly. This is a
  limitation of the seed alone.
- **`tree`**: the tree compiler gets it wrong too. A workaround comment blamed the seed, but it is a
  tree defect with its own issue. The row records it until the fix lands. Then the check makes the
  fixing change move the row to `seed`.

The registry has no live row at 0.2.7. A new row is added with the next form the frozen seed is
found to miscompile.

**Retired by the 0.2.7 promotion.** Both rows that were `tree` at `db74009` moved to `seed` when the tree
fixes landed (#842 for #790, #843 for #791), and under seed 0.2.7 (`1ec875d9…`) both answer 42, so the
check refused them with "the seed now handles …" and they were removed:

| retired row | issue | seed 0.2.6 | seed 0.2.7 | workaround it retires |
|---|---|---:|---:|---|
| `enum_copy_two_derefs`: `deref(dst) = deref(src)` over a multi-word enum | #790 | 1 | 42 | `src/ast.al` `bitcast_identity_erase` (word-by-word copy) |
| `call_result_enum_field_arg`: `is_c(mk().kind)` with an enum field | #791 | 139 | 42 | `src/sema.al` `resolve_kind` (result bound first) |

The two workarounds are still in the source. Removing one changes the compiler's own emission, so it
is a separate change with its own fixpoint, not part of a promotion; their comments say so.

**Retired by the 0.2.5 promotion.** This is the registry's first retirement, and it worked the way it
is designed to. Seven `seed` rows were planted against 0.2.4, where the tree answered 42 and the seed
answered as shown. Under 0.2.5 each one answered 42, and the check refused them with "the seed now
handles …", so they were removed:

| retired row | issue | seed 0.2.4 | seed 0.2.5 | workaround it retires |
|---|---|---:|---:|---|
| `try_inline_multiword` (`f()?.b`) | #752 | 0 | 42 | §7's seed reason |
| `option_ptr_payload_field` | #768 | 0 | 42 | §1: bind the deref first (dropped) |
| `option_ptr_mut_generic` | #770 | 13 | 42 | §1: no generic over `ptr(mut T)` (dropped) |
| `option_ptr_local_forms` | #775 | 1 | 42 | §1: annotate the local (dropped) |
| `option_ptr_param_match` | #789 | 139 | 42 | §1 transitional null for walks (dropped) |
| `option_ptr_list_walk` | #789 | 139 | 42 | same |
| `option_ptr_bare_some_arg` | #789 | 139 | 42 | §1: spell the constructor out (dropped) |

The tree also handled #797's field store (`a.next = Option.Some(…)`) before this, via #807, and seed
0.2.5 answers 42 on it, so it never needed a row. None of the retired rows had a workaround comment
in `src/` or `lib/`. Their workarounds were the §1 and §7 advice above, which this revision removes.

**Recorded as seed limitations and not reproduced (measured on 0.2.4).** Each of these comments was
probed with a minimal program. The seed answered correctly, so no row plants it, and inventing one that
does not fail would be a fake. Each is a **candidate for retiring its workaround**. Several comments
tie the fault to one very large function or emit path, which a minimal program does not recreate. So
the proof is to revert the workaround at its site and run the fixpoint, not to delete the comment on
the strength of this list:

- a function returning a new struct type (`src/wat.al` `wat_defer_action` and its neighbour,
  `src/aarch64.al` head, `src/lower_layout.al` `ptr_target_pointee_s`): a 3-word struct return
  answered 42;
- a helper taking `in out` of a struct plus a large by-value struct (`src/wat.al`, the overload
  suffix, #611): 10-word by-value plus `in out` answered 42;
- a span passed to a helper through params (`src/aarch64.al` and `src/riscv64.al`, the generic
  instance tag): a 9-parameter call reading params 7–9 answered 42;
- the second word of a tuple returned off an inferred `unchecked` binding (`lib/base/num.al`
  `overflowing_*`): 42;
- an early `return` inside a `match` arm (`src/sema.al` `check_expr_arms` `Var` arm, `src/wat.al`,
  `src/cli.al`), including one returning a 3-word `Result`: 42;
- a nested `match … return` (`src/sema.al` `field_variant_name`): 42;
- a comparison `and`-ed with a call (`src/parser.al`, the lambda-call reject): 42;
- an inline str-returning call as a `str` argument (`src/fmt.al`, `src/lower_asm.al`, `src/wat.al`),
  including into an `in out` helper: 42;
- a recursive `in out` call (`src/parser.al`, `@label`): 42;
- a 9-word struct written through `in out` (`src/parser.al`, the struct field-order table): 42;
- an `in out` scalar as a 7th parameter (`src/lower_ctx.al` `call_cidx`): 42;
- a `[0; 2048]` global initializer (`src/regalloc.al`): 42;
- an `else if` chain as a function body (`src/fmt.al`): 42;
- a struct constructor stored through `deref(p) = S(…)` (`src/parser.al`, lambda params): 42;
- a module constant as a call argument (`src/sema.al`, the brand census descriptor): 42;
- a 2-word accessor on the second match-bound child (`src/wat.al` `CompField`): 42.

**Not seed limitations: the tree refuses them too.** A payload-heavy arm of a big `match` over a
bound `deref` ("scar #2", `src/sema.al`, the `check_expr` pre-match band), and a variant `match`
nested in another arm on a bound child (`src/lower.al`, `src/sema.al`, `src/fmt.al`, `src/wat.al`).
The tree compiler refuses both with #716's located diagnostic ("the lowering cannot see the
scrutinee's enum type"), even on an annotated local. That is a lowering limit of the tree, and the
compiler itself holds it. §3 names the scrutinee shapes that lower.

**Write this.** Follow the existing idioms at the workaround sites (AGENTS.md "Workspace
invariants"). When you work around a seed limitation, **add a registry row** with a planted program
that the seed miscompiles and the tree runs correctly. Put a comment at the workaround that names the
limitation and the issue, and list that site in the row. Then the row can be retired after a
promotion, the way `29d134c` dropped #751's and #753's workarounds. If the tree gets the form wrong
too, it is a tree defect: file it and add the row as `tree`.

**Check.** `scripts/seed_forms_check.sh`, a full-gate stage after the build. A `seed` row fails if
the tree compiler does not answer the due value, because the form regressed in the tree. It also
fails if the seed does, with "the seed now handles <form>: retire this entry and remove its
workaround comments at <sites>". So a promotion that fixes a form turns the gate red until the row
and its workarounds are gone. A `tree` row fails once the tree answers the due value, with "change
its state to 'seed'". The registry and `scripts/seed_forms/` must match both ways. Its
`--self-test`, in `full.sh --self-test`, drives the decider through thirteen planted registries with
a fake compiler: three controls stay green and ten plants are refused by name. Writing a *new* seed
workaround without a row is held by review.

## 9 · An AST handle has its node's own type

**Defect class.** A handle to one kind of node that is declared as another kind, or as a bare integer.
#760's `Deref` arm, once it checked its operand, refused **twelve** walkers that declared an `Arm` or
`Arg` list head as `ptr(mut Stmt)` and passed it to `arm_p` / `arg_p`. `src/ast.al` still documents
the plumbing that makes this possible: "the pass-plumbing params that thread an arm-head (`head_in` /
`ah` / `head`, several of which also name Arg/Stmt heads) stay `usize` handles".

**Write this.** Declare every handle with its node's own pointer type: `ptr(mut Arm)`, `ptr(mut Arg)`,
`ptr(mut Stmt)`, `ptr(Expr)`. Do not use `usize`, and do not use a sibling node's type. Where a handle
passes through an untyped container (`rt::Vec` stores `usize`), convert it back at exactly one
accessor, with its `unchecked-ok` reason (§6).

**Check.** Since #760, the checker refuses a sibling-pointer mix at a `deref`. The `usize` plumbing is
held by review. The next step is proposed below.

### Proposal (not implemented): nominal AST handles

What the tree has today, measured at `a46b5bc`:

- **148** `bitcast(ptr(<AST node>), <non-literal>)` re-typings in `src/`. Each one is a place where a
  `usize` handle becomes a node pointer.
- **44** parameters or locals with a handle-like name (`head`, `h`, `nx`, `st`, `list_head`, …)
  declared `usize`.
- The identity accessors: `arg_p` 482 uses, `param_p` 234, `stmt_p` 220, `arm_p` 212, `fld_p` 122.

The steps:

1. **Pointer handles take their node's type** (§9 above, and possible today). This is the same shape
   of work as #529 step 3: one module per slice, byte-identical GAS as the refactor evidence, and
   `0 CHANGED` on the corpus manifest. After #529 closes the implicit seam, every remaining
   `usize` → node conversion is an explicit `unchecked bitcast` that the `unchecked` rule already makes
   justify itself. A cheap lexical rule, `handle-usize`, could then refuse a *new*
   `bitcast(ptr(<AST node>), <non-literal>)` outright.
2. **A handle that can be absent becomes `Option(ptr(mut Stmt))`.** It is niche-folded, so node layout
   is unchanged. The tree and seed 0.2.5 compile the walk and the build (§1). What still blocks the
   AST conversion is #809 (a direct `match` over such a field through `deref(p)` or an array
   element) and #792 (an enum or `Option` field read through `deref(p)`), the two shapes a
   pointer-linked AST uses everywhere.
3. **Handles that are not pointers become brands.** Arena offsets and `rt::Vec` slots would be
   `StmtId := brand(usize)`, `ExprId := brand(usize)`. #299 made brands nominal (siblings and the base
   type do not convert implicitly), so `StmtId` vs `ArmId` becomes a checker error instead of a review
   item. This needs a census of which handle containers carry which node, which the compiler can emit
   the way `brand_census.sh` does, and a decision on whether `rt::Vec` becomes generic in the
   compiler's own code. The seed's generic support decides that.

## 10 · A quantity with an identity is a `brand`, not a bare number

**Defect class.** Two quantities of different units or domains share one integer type, so the
compiler accepts one where the other is due:

- #167: a sub-word field store through `deref(p)` used the field's **word** offset as a **byte**
  offset, at word width. For `P2 := struct { a : u8, b : u8 }`, `deref(p).b = 5` emitted
  `movq %rcx, 8(%rax)` where `movb %cl, 1(%rax)` was due. `b` was never written, which is a silent
  wrong value (72 where 75 was due), and eight bytes were written past a two-byte object. Both
  offsets were a `usize`, so nothing could tell them apart.
- #760: twelve walkers declared an `Arm` or `Arg` list head as `ptr(mut Stmt)`, a handle of the
  wrong kind. For node *pointers* that is §9. The handles that are not pointers (arena offsets,
  `rt::Vec` slots, span starts) are bare `usize` today, and a slot index passes for a byte offset
  with no complaint.
- #299: until it closed, a `brand` carried no identity. A sibling brand, the raw type and even a
  brand over another numeric domain all converted implicitly, so `Meters` and `Seconds` were
  interchangeable. Since #299 a brand is nominal (Types §4.2): siblings do not convert, and brand ↔
  base is always explicit.

**Write this.** Give each unit or domain its own brand: a byte offset, a word count, a slot index, a
node handle. Convert between them only in a **named function**, one place per conversion (§4).
Unwrap with `usize(x)` only at the boundary that really needs the raw number, such as the address
arithmetic itself.

```alatyr
## not this — three units, one type
field_off := fn(s : usize, f : usize) -> usize { ... }      ## a word index? a byte offset?
store_at(base, field_off(s, f), v)                          ## #167: a word offset used as bytes

## this
ByteOff := brand(usize)
WordCount := brand(usize)
SlotIdx := brand(usize)
words_to_bytes := fn(w : WordCount) -> ByteOff { ByteOff(usize(w) * 8) }
field_byte_off := fn(s : usize, f : usize) -> ByteOff { ... }
store_at := fn(base : ptr(mut u8), off : ByteOff, v : u64) { ... }

store_at(base, field_byte_off(s, f), v)
store_at(base, words_to_bytes(n), v)       ## the conversion has a name
store_at(base, n, v)                       ## refused: WordCount where ByteOff is due
store_at(base, ByteOff(16), v)             ## a constant says its unit too
```

**Check.** The checker enforces a brand once it is chosen. Measured at `3e5d7b4` on the tree
compiler and on seed 0.2.4, so `src/` can use brands today. With `ByteOff` and `WordCount` both
`brand(usize)`:

- a `WordCount` passed where `ByteOff` is due is refused;
- a raw `usize` local passed where `ByteOff` is due is refused;
- `b + w` across the two brands is refused.

Each refusal is `check: implicit brand conversion … (Types §4.2/§4.3)`. The explicit constructor and
the named conversion above run to their value (42). A bare literal argument
(`store_at(base, 16, v)`) is refused as a type mismatch today, so constants are written
`ByteOff(16)`. The sinks the refusal reaches are listed in `test/accept_brand_unrefused_sinks.al`,
with their `reject_brand_*` twins. One known gap: an argument
to an overloaded, generic or qualified callee is not reached (`src/sema.al`, the brand census note).
`scripts/brand_census.sh planted`, a full-gate stage, proves that the census instrument still sees
crossings. **Choosing a brand for a new quantity is held by review.** No check can know that a
`usize` means a byte offset, and there is no gate rule for it. `src/` declares no brand yet. A new
quantity is the place to start, and the non-pointer handles of §9 step 3 are the planned campaign.

## How the checks count, and what they measured

`scripts/strict_forms_check.sh` follows `scripts/wildcard_arm_check.sh` point for point:

- It is an **addition rule**: the MERGE BASE and the head are counted, and the check refuses an
  increase per rule. There is no committed baseline and no fourth oracle.
- A marker on the line or the line above acknowledges a form, and an empty reason acknowledges
  nothing.
- A planted self-test runs in `scripts/full.sh --self-test`: 13 planted additions are refused by name,
  7 controls stay green, and an empty corpus is refused.
- The lexical half is a tokenizer (`scripts/strict_forms_scan.awk`, `src/lexrt.al`'s lexical rules),
  so a form quoted in a comment or a string is not counted.
- The typed half reads the #529 instrument on fd 98, with the head compiler checking both trees.
- `--typed-self-test` proves the channel sees a new `p != 0` and does not see its explicit twin.

Current tree (`a46b5bc`, identical under macOS awk and gawk):

| rule | count | acked | notes |
|---|---:|---:|---|
| `unchecked` | 1818 | 0 | plus 904 null-form escapes counted under `null` |
| `kind-literal` | 1017 | 0 | 384 in `src/parser.al` (lexer `Token.kind`); every sampled row a real kind or tag |
| `try-inline` | 10 | 0 | all `?.field` in `lib/alloc/` (`deque`, `hashmap`, `omap`, `oset`, `strbuf`, `vec`) |
| `null` explicit | 904 | 0 | 343 fabrications, 561 tests |
| `null` implicit / `ptrint` | 361 / 361 | — | every implicit row is an `OP-CMP` comparison |

**False positives.** A false positive here means a row whose form is not the one the rule names. It
does not mean a form that happens to be harmless. Sampling found none:

- `kind-literal`: 17 sampled rows were all a kind or tag byte compared with its literal.
- `null`: 7 sampled operands were all declared `ptr(T)`, or a call returning one.
- `unchecked`: exact by construction (the token).
- `ptrint`: exact by construction (the checker's own verdict).

The rules have **blind spots**, and they are known:

- `ptrint` sees only the spellings the #529 instrument sees (`scripts/ptrint_census.sh` documents the
  asymmetry).
- `null` does not see a parenthesized `(unchecked bitcast(usize, p)) == 0`.
- `kind-literal` does not see a kind held under another name.
- The counts are tree-wide, so an addition paid for by a removal elsewhere in the same change passes.
  The verdict line prints both totals.

**Replay over the last 39 first-parent commits on `main`** (the lexical rules, computed per commit):

- `try-inline` never moved.
- `kind-literal` would have refused 3 merges (#737, `1b5cd53`, #760), each adding one literal kind
  comparison. The #583 slices removed 328 in the same window.
- `unchecked` would have refused 9. Six were #529 step-3 conversions that turned implicit crossings
  into explicit `unchecked bitcast`s (#755 +152, then +33, +17, +12, +5, +2 in the per-module slices).
  That work is finished for every class except the null comparisons, and those are counted under
  `null`, where a conversion is sum-neutral. The other three are features adding 14, 3 and 1 escapes
  (#759, #739, #760).
