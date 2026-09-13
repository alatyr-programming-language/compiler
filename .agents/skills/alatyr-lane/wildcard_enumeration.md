# Enumerating a file's wildcard `match` arms (#544 stage 1)

This is the written procedure the #544 stage-1 pilot owed. It applies to one file at a time and it is
not a sweep: a mechanical pass over the tree produces silent wrong values, which is the one forbidden
outcome. Read `AGENTS.md` and `SKILL.md` first — this file only adds what is specific to replacing
`_ =>` arms with spelled-out ones.

Measured on the pilot, `src/lower_ctx.al` (24 arms, 666 lines, PR for #544 `Refs #544`). Every number
below is from that file unless it says otherwise.

## The rule in the other direction, and why it is not symmetric

**A change may not add an unacknowledged `_ =>` arm over an enumerable scrutinee.**
`scripts/wildcard_arm_check.sh` is a stage of `scripts/full.sh` and refuses one by file and line.

The two directions look like the same rule and are not, because the two costs were measured. Adding
an arm costs the author nothing to avoid: they are present, they know which forms the arm absorbs,
and they can either enumerate them or write down why the wildcard is required. **Deleting** one is
expensive, and in **249 of the 727** arms the census walked it is worse than expensive — it is
invisible. A `match` with no arm taken returns −1 at run time (`run rc=255`) on a clean compile with
rc 0 from both `check` and `build`, no diagnostic anywhere; that is why §2's per-arm deletion census
exists, and why the existing arms come out one file at a time instead of in a sweep.

What forced the check rather than a written convention was the metric standing still. Between
`6759a95` and `6fe1e1d` the `src/` total went **727 → 731** — lane #651 added one arm each to
`src/aarch64.al`, `src/riscv64.al`, `src/wat.al` and `src/lower_layout.al`, and nothing was removed.
Stage 1 then landed two entire files, `src/lower_ctx.al` 24 → 2 (#661) and `src/aarch64.al` 69 → 33
(#678) — about 58 arms — and the tree-wide count did not move. Removal and addition were running at
the same rate, so this stage could have spent its remaining eight files, `src/lower.al`'s 227
included, and finished where it started. Refusing unacknowledged additions while letting removals
through turns that stalemate into a monotone decrease.

**The exceptions, written down.**

- **A non-enumerable scrutinee.** Over an integer or a byte the domain is not a list anybody can
  spell, and `_` is the only way to write "everything else". The census found **four** such arms in
  the whole tree — `src/comptime.al`'s binary-op dispatch and `src/lower.al`'s three register-name
  tables — so the rule almost never fires on a correct use. The check decides this from the
  scrutinee's **resolved type**, never from the arm's text: it resolves the type through the sibling
  arms' patterns against the `enum` declarations it parsed out of the tree, so `E::V`, `E.V` and the
  bare `V` spelling all resolve alike and none of them is a way out.
- **A `comptime match typeinfo(T)` kind dispatch**, and the generic `T.(v)` comptime-variant pattern
  `lib/base/derive.al` uses. The kind set is closed, but it is not a project `enum` declaration the
  scanner can name, so those ten arms are exempt — and reported by count in the verdict line rather
  than silently dropped, so the exemption stays reviewable.
- **No exemption for the single-case accessor.** §3 records the measurement: it would have skipped 22
  of the pilot's 23 arms including `num_lit_value`, which is where the pilot's only wrong value
  (#659) came from.

**Acknowledging one.** Put `wildcard-ok: <reason>` in a comment on the arm's own line or the line
immediately above it, with a non-empty reason. It lives where the arm lives on purpose: #649 had to
turn the `git add` convention into a gate stage after a lane lost a whole gate run to it, and a
reason kept in a commit message is a reason the next reader of the arm will never see.

**Counted with a parser, not a grep.** `scripts/wildcard_arm_scan.awk` tokenizes with `src/lexrt.al`'s
lexical rules. §1 below is the measurement that makes that mandatory, and the check reproduces this
file's own census: over `src/` it answers **727** at `6759a95` and **731** at `6fe1e1d`, with four
non-enumerable arms at both.

## 0 · Before you take a file

Three blind classes have been measured; TWO of them have since been fixed and are kept here as worked
examples, because a fixed class still tells you what to re-measure and how. In a blind class,
enumerating buys nothing while *deleting* writes a wrong value. Check your file against all three
before claiming it:

- **#655 — FIXED on `main`; like #656 below, a worked example now, not a warning.**
  `sema::check_program` decided which modules to TRUST by the substring `__` in the mangled module
  name, and `__` is how the parser spells a path separator, so every nested submodule of every
  package was skipped wholesale — all twelve files and 12 007 lines of `src/lower/`, in which a name
  bound nowhere passed `check` AND `build`. PR #677 made the question a provenance one, answered
  from the driver's published table. Re-measured on `a54ae6c`, with a compiler **built from that
  tree** for the same reason #656 gives — the frozen seed predates the fix and still accepts every
  deletion — the deletion census over all **57** line-initial `_ =>` arms under `src/lower/` answers
  **44 caught**, where the same census on #677's parent answers **0 of 57**. The class is gone; the
  twelve files are not finished by fixing it. The remaining **13** are blind per ARM, not per file,
  and eight of them are the #660 shape below — `match st` over `st := deref(stmt_p(Stmt, …))`, the
  same spelling as `src/aarch64.al`'s 24. The other five are `match deref(<expr>)` forms over a call
  result, an argument node and an array place, and this unit did not classify them; classify before
  enumerating. Per file, caught/total: `abi_c` 1/1, `assign` 1/1, `collect_slots` 0/2, `ctfold`
  10/10, `enum_match` 5/5, `fnval` 2/3, `ir` 11/19, `mono` 1/2, `place` 10/11, `scratch` 3/3,
  `decl_index` and `rodata` none to measure.
- **#656 — FIXED on `main`; this entry is now a worked example, not a warning.** A module sorting
  before `src/ast.al` could not resolve `ptr(T)` identity, so every arm in it was invisible, and
  `src/aarch64.al` was the whole of that class. PR #662 (`4873d30`) fixed `resolve_ty`'s `is_ptr`
  branch. (The defect is gone; issue #656 itself was still open and carrying `in-progress` when this
  was written, so read the tree, not the label.) Re-measured independently on `cff2b72`, with a
  compiler **built from that tree** because the frozen seed predates the fix and still accepts all
  63, the file's deletion census answers
  **39 caught of 63**, where #662's parent answered **0 of 63**. The class is gone; the file was not
  finished by fixing it. Its remaining **24** are blind for the third reason below, and that reason
  is per ARM, not per file: all 24 are `match st` over `st := deref(stmt_p(Stmt, <h>))`.
- **#660** — a single *site* is blind when its scrutinee's enum type arrives through a generic
  function's return type. This one is per-arm, not per-file, and it has a workaround: annotating the
  local (`stmt : Stmt = …`) or the pointer (`sp : ptr(mut Stmt) = …`) restores the check.

Re-measured a third time on `src/parser.al` (`60338f4`, compiler built from that tree): **21 caught
of 24**, and all three blind arms are the per-arm class — two are `#660`'s `match x` over
`x := deref(stmt_p(Stmt, st))`, and the third, `parser.al:3418`, binds `init_e := p_or(pc)` where
`p_or` is **not generic** and returns a concrete `ptr(mut Expr)`. So the boundary is the binding
through an unannotated local, not the genericity of the callee; #680 carries the five-row table for
both spellings. Check a candidate file for BOTH shapes, not only for `stmt_p`.

`comptime.al` is blocked, not merely deprioritised. `aarch64.al` is not, any
more: it was taken as the second file of this stage (`Refs #544`, 38 of its 39 caught arms enumerated)
once #662 landed, and the first thing that unit owed was re-measuring the census rather than carrying
#662's numbers over. A control is worth keeping beside a fixed class: the byte-identical twin of one
of the 24 in `src/wat.al` — a module sorting AFTER `src/ast.al` — is equally blind (`wat.al:298`
deleted -> rc 0 silent, while `wat.al:286`'s `match deref(e)` -> rc 1 `at line 266 in wat`), which is
what tells a per-arm blindness apart from a per-file one. `src/lower/*.al` is not blocked either,
since #677 (above); it is the next candidate for this stage. §3's #673 constraint on a non-empty
group-arm body is gone (PR #685), so a body holding a string literal no longer excludes an arm;
what a non-empty body still costs is `src/` text, which §3 now quantifies.

## 1 · Count the arms with a parser, not a grep

`grep -cE '^\s+_ =>'` answered **4** for a file with **24** arms: twenty of them are one-line
`match … { A => …; _ => {} }` accessors where the arm is not line-initial. The error runs the other
way too — after the change, `grep -c '_ =>'` answers **2** for the **1** arm that is left, because
the new band comment quotes the token in prose. Every tree-wide wildcard figure derived from a grep
is an estimate with an unknown, non-uniform error, and #544's own census had to parse the AST to get
727.

Enumerate the arms by matching `match <scrutinee> {` and walking to its closing brace, or reuse
#544's census listing for your file.

## 2 · The deletion census: one arm at a time, and it is the whole safety argument

For each arm, restore the file, delete **only** that `_ => {}`, and run `./seed/alatyr check
package.al` with the rc read outside a pipeline. Record rc and the exact diagnostic.

- **rc 1 naming your file and the arm's line** → the arm is *caught*. Enumerating it is safe and buys
  a compile error when a variant is added.
- **rc 0, silent** → the arm is *blind*. **Leave it exactly as it is.** #544's census measured that a
  `match` with no arm taken returns −1 (`run rc=255`) on a clean compile with no diagnostic, so the
  blind arms are precisely where a sweep manufactures the forbidden class.

`check` reports the **first** error only, so the arms cannot be batched: deleting two arms reports one
line and tells you nothing about the other. On the pilot each run cost ~35 s, so 24 arms is ~14 min
serially; six copies of the worktree running four arms each brought it to ~2.5 min, and `check`
produces no target artifacts, so the copies do not collide the way two gates in one checkout would.

Pilot result: **23 caught, 1 blind** — 23 for 23 naming `lower_ctx` and the exact line. Note that a
whole-line deletion reports the `match` head's line, not the deleted line; an inline deletion reports
the accessor's line.

For a blind arm, run the four-variant follow-up before you conclude anything about *why*: inline the
scrutinee, annotate the value local, bind the pointer, annotate the pointer. On the pilot that table
is what separated #660 from "`deref(<call>)` is not supported" — the inlined form is still blind and
the annotated form is caught, so the generic return type is the variable, not the call.

## 3 · Write the group arm, not 23 arms

A spelled-out empty arm is written as **one OR-pattern group arm listing every absorbed variant**, in
`src/ast.al` declaration order, wrapped at ~100 columns with the `|` line-initial on continuations:

```alatyr
match deref(v) {
  Expr::StructLit(ss, sn, nf, ah) => { r = true }
  Expr::Num | Expr::BoolLit | Expr::Var | Expr::Bin | Expr::If | Expr::Match | Expr::Call
    | Expr::Field | Expr::EnumLit | Expr::AddrOf | Expr::Deref | Expr::StrLit | Expr::ArrayLit
    | Expr::Index | Expr::Try | Expr::FloatLit | Expr::Slice | Expr::CompField | Expr::Unchecked
    | Expr::Lambda | Expr::FnRef | Expr::Bitcast | Expr::Loop => {}
}
```

Bare variant names, no payload patterns — the form `src/lower/assign.al`'s `const_scalar_lit` (#601)
already uses. Declaration order so a reader can diff the list against the enum by eye. Generate the
list with a script rather than by hand; a hand-typed 23-name list is where a transposition hides.

**A non-empty group-arm body is duplicated once per alternative. A string literal in one WAS a hard
stop; it is not any more (#673, PR #685).** The pilot never met this because all 23 of its bodies
were `{}`. `src/aarch64.al` did: `emit_a64_expr`'s wildcard body is
`push_str(sb, "  brk #0 // unsupported expr\n")` and its group arm absorbs eight variants, so the
data walk reached that one body eight times and defined one `.Lstr<m>_<k>` eight times — `as` refused
the self-build at `Error: symbol '.Lstr1_617' is already defined`, while `check` still said rc 0.
That is why the file landed at 38 of 39 arms.

The fix is in the walk, not in the label allocator: an OR-pattern's alternatives share ONE body node,
a `.rodata` cell belongs to the literal NODE rather than to the control-flow path that reaches it, so
the data walks now visit a shared body once (`ast::arm_body_first_use`). **A group-arm body may hold
a string literal.** Nothing else about this section changes: enumerate every arm whose body is `{}`,
and a non-empty body still enumerates fine and still costs N copies of its TEXT, which is `src/`
growth rather than an emission change — measured at ~39 GAS bytes per extra alternative for a
one-assignment body and ~415 for a ten-argument call, against ~61 bytes of per-alternative dispatch
that a group arm costs whether its body is empty or not. The 69 empty group-arm bodies now in
`src/`+`lib/` cost none of it.

**But not until the seed can compile it, and that is measured.** `src/` is built by
`seed/alatyr`, and the frozen seed is the compiler that has the defect. Converted on a throwaway
worktree over the fixed tree, `emit_a64_expr`'s group arm still stops the seed build at
`Error: symbol '.Lstr1_617' is already defined`; the same tree built by the Stage1 compiler compiled
FROM the fixed tree builds clean, and its aarch64 emission is byte-identical to the unconverted
compiler's over all 1 723 `test/*.al`. So the arm is correct, neutral and ready — and it can only be
written into `src/` after the integrator promotes a seed that carries the fix. Until then this one
arm stays a `_` with a note pointing here, and the constraint applies to the same emitters in
`riscv64.al` and `wat.al`. In a user program there is no such wait: an OR-pattern arm body may hold
a string literal on all four backends as soon as this lands.

Enumerate it with a non-vacuity check that names its line, as every other arm in this stage owes.

**So the pre-census grep changed its question, not its value.** It used to ask "does this file hold
a hard stop?"; it now asks "does this file need a seed promotion before its arm is writable?" — and
it is still one grep over the group-arm bodies, still worth running before an hour of census.
`src/parser.al` (24 arms, `Refs #544`) answers no at all 21 of its enumerated arms: every body is
`{}`, a bare value (`{ false }`, `{ NSpan(s = 0, n = 0) }`, `{ unchecked bitcast(ptr(Expr), 0) }`,
`{ r = false }`, `{ deref(ok) = false }`) or a two-line constructor, and not one holds a string
literal — so that file was writable in full against the frozen seed, and its census was paid for
knowing so. Expect that answer from a non-backend file: the `push_str(sb, "…")` shape that owns the
wait lives in the three backend emitters, so the seed-promotion constraint is a property of
`aarch64.al`, `riscv64.al` and `wat.al`, not of the stage.

**Why a group arm and not one arm per variant, with numbers.** #544's plan says "a genuinely empty
arm is written as its variant with an explicit comment saying why nothing is emitted, never as `_`".
Read literally on one accessor that is 23 arms and 23 comments. Measured on the pilot's 23 enumerated
arms, which absorb 528 variants between them:

| form | lines added to a 666-line file | file grows to |
|---|---:|---:|
| one arm per variant + a comment each | ~1 100 | ~1 770 (2.7×) |
| one arm per variant, no comments | ~570 | ~1 240 (1.9×) |
| **group arm + one band comment** | **171** | **837 (1.26×)** |

Across the 376 single-case `Expr` accessors the census counted tree-wide, the literal reading is
**8 648** arm lines (the plan's "~8 600") before any comment; the group arm is ~1 500 arm lines plus
~750 structural lines plus ~1 250 band-comment lines, so about **3 500** against **9 400–17 300**.

**Why no exemption for single-case accessors.** The other candidate was to leave `_ => {}` in place
wherever a `match` has exactly one real arm. That is 0 lines and 0 enforcement at 376 of 569 `Expr`
sites — and those are the sites that need it most, because an accessor that silently answers `false`
or `0` for a variant it has never heard of is exactly the #558/#659 shape. The decisive measurement
is from the pilot itself: **the exemption would have skipped 22 of its 23 arms, including
`num_lit_value`, and `num_lit_value` is where the pilot's only wrong value (#659) came from.** An
exemption that suppresses the finding the stage exists to produce is not a cost saving.

## 4 · The comment moves from the arm to the band

Keep the plan's requirement — the reason nothing is emitted is written down — and move it up one
level. On the pilot, twenty accessors had **one** reason between them ("this is a predicate or a
projection; for every other form the default *is* the answer"), spread over seven bands that the file
already had band comments for. Twenty copies of one sentence is noise that hides the one place the
reason differs.

So: one **band note** stating the reason, what a new variant means for the whole band, and the
measured non-vacuity result; a one-line back-reference in each sibling band comment; and a **per-arm**
comment only where that arm's reason is genuinely its own. On the pilot exactly two arms earned their
own note — `num_lit_value` (its default is indistinguishable from a real answer; #659) and the blind
one (why it keeps its `_`).

Classify each arm as **predicate / projection / normalizer / emitter** and say which in the note. Only
an emitter is dangerous: a predicate's "no" and a projection's empty span are answers, a normalizer
correctly leaves its input alone, and an emitter that emits nothing is a missing lowering.

## 5 · Where there is no correct lowering, leave a located refusal

Not silence, not a trap. `AGENTS.md`: a trap is acceptable, a wrong value is not, and a located
refusal beats a trap. But do not change behaviour inside the enumeration unit — see §6. If an arm
needs a refusal, the enumeration unit records it and the refusal is its own unit with its own fixture.

## 6 · A reached-and-wrong form is a separate issue, always

The enumeration is a byte-identity refactor. The moment you fix something inside it, the byte-identity
evidence stops being available and the unit stops being reviewable. Every form that turns out to be
reached and wrong gets its own issue with a reproducer, a measured table, and acceptance criteria.

The pilot found one this way. Enumerating `num_lit_value`'s group arm made its absorbed forms a list
rather than a `_`, and reading that list against its callers gave #659: a raw-asm source operand that
is not a bare `Num`/`BoolLit` emits `$0`, so `movq(rbx, 0 - 1)` assembles `movq $0, %rbx` with rc 0
from both `check` and `build`. Note the shape — the accessor is correct and the **caller** is wrong,
because it commits to the immediate path before asking a question that cannot answer "not a literal".
Look for that pattern in every accessor whose default is a representable value.

## 7 · Evidence the unit owes

1. **Byte-identical emission, input tree held fixed, in both directions.** Build the parent compiler
   from the parent tree and the branch compiler from the branch tree, each in its own repository
   layout (never move a built compiler away from its adjacent `lib/`). Then emit GAS with
   `<compiler> <path>/package.al > out.s` for **both** compilers over the **parent** tree and again
   for both over the **branch** tree, and `cmp` each pair. Comparing your tree against the old one
   compares a longer source with a shorter one and proves nothing. Watch #534's `__lam<N>` hazard.
2. **The corpus oracle at `match`.** Predict it before the gate: an enumeration that changes no
   behaviour predicts zeros in every class.
3. **Per-unit non-vacuity.** Plant a 25th `Expr` variant in `src/ast.al`, change nothing else, and
   show `check` refuses **naming your file**; revert and show the same sha256 comes back. This is the
   experiment #464's pilot failed, and it is the difference between a claim about the diff and a
   claim about the compiler.

   Expect it to be masked, and run it with a control. `check` reports one error, and `src/lower.al`
   carries two `Expr` matches with no wildcard at all (`emit_gas` among them), so on the pilot both
   the parent tree and the branch tree answered `type mismatch at line 16038 in lower` and neither
   named `lower_ctx`. Run the SAME sequence on both trees, silencing each reported match in both
   identically (insert a `_ => {}` before that match's closing brace) until they diverge. On the
   pilot they diverged at the third step: the branch stopped at `line 212 in lower_ctx` and the
   parent walked past it to `line 3569 in lower_layout` — and since modules are checked in name
   order, `lower_layout` being reached proves the parent's check had already crossed `lower_ctx`
   in silence. Script the silencing; do it by hand and you will silence the two trees differently.
   The §2 deletion census remains the stronger per-arm form of the same proof, because it names
   every one of your arms rather than the first.

   **Once the earlier files are enumerated, `_ => {}` is the wrong silencer and one-at-a-time is
   the wrong loop.** Both were measured on `src/parser.al`, whose module name sorts late. Inserting
   `_ => {}` into `aarch64.al`'s `a64_cf_offset_value`, every arm of which ends in `return`, left
   the function with a value-less path and turned the sequence into `check: invalid at line 1857 in
   aarch64` — an error about the silencer, not about the plant, and the loop cannot step past it.
   Silence a match that ALREADY has a spelled-out group arm by appending `| Expr::<planted>` to that
   arm instead: it is the same textual operation the enumeration itself performs, it cannot change
   the arm's type, and it works for a value-position match. Keep `_ => {}` only for a match with no
   group arm. And do the whole pre-your-file set in ONE scripted pass rather than one `check` per
   step: `aarch64.al` alone masks for a dozen steps at ~40 s each. On `src/parser.al` a single
   blanket pass over all 68 non-parser modules — 66 group-arm appends, 10 wildcard inserts, applied
   identically to both trees, verified by `sha256sum` over every `src/**/*.al` showing exactly ONE
   differing file — reduced the loop to **four** steps. It diverged at step 4: the branch stopped at
   `type mismatch at line 674 in parser` (its first group arm, `clone_expr`'s) while the parent
   walked past `parser` to `invalid at line 6674 in sema`. Check the name order you actually get
   rather than the one you expect: `ast.al` sorts BEFORE `parser.al` and holds eight `Expr::`
   patterns, but `aarch64` sorts before `ast`, and the first module to name the plant was
   `aarch64`, then `lower`, `lower__assign`, `lower_layout`.
4. **`git add` the file set before the gate.** `scripts/corpus_enum_check.sh` refuses in ~15 s when
   the index and the worktree name different `.al` sets.

## 8 · Order for the remaining files

The census's order, and it is not by size — size correlates with neither the caught fraction nor the
reading effort. `parser.al` (24) **is done** (`Refs #544`, 21 of its 24 caught arms enumerated), and
so is `riscv64.al` (52 by the parser-based count, all 27 of its caught arms enumerated); then
`fmt.al` (29, and it holds the one `gap=0` arm that is removable for free), `wat.al` (63–64),
`lower_layout.al` (38), `sema.al` (108), `driver.al` (46 arms but 21 M entries), and `lower.al` (210)
last, in reviewed slices.

Budget, measured on the pilot rather than estimated: **about 1 h of wall clock** end to end with the
`check` runs overlapped against the writing — ~12 min reading #544's comments and the file, ~2.5 min
for the 24-run deletion census (six worktree copies; ~14 min serial), ~4 min for the blind arm's
five-row follow-up, ~4 min probing the wrong value it exposed, ~10 min writing the two issues, ~9 min
for the two compiler builds and the four GAS emissions, ~12 min writing the enumeration and the
notes, ~5 min for the non-vacuity sequence, and ~12 min of gate. Serially that is about 1 h 15.

Third data point, `src/parser.al` (24 arms, 6 467 lines): about **2 h** end to end, and the shape of
the cost is different from both files above. The 24-run census was **3 min 12 s** at six-way
parallelism (~45 s per `check`, competing with three other lanes) and the five-row blind-arm
follow-up another **2 min 14 s** — the measuring was under six minutes for the whole file. What cost
the two hours was the **reading**: 24 arms over one enum, but five distinct bands with five distinct
reasons, and one arm (`index_parts`) whose absorbed list had to be read against nine call sites
before it could be written down. That reading is what produced #681, and it does not parallelise and
does not shrink with practice. Budget by BANDS, not by arms. Two more numbers worth carrying: the
two compiler builds plus the four GAS emissions were ~6 min, and the non-vacuity sequence was ~8 min
once the blanket silencer above replaced the one-at-a-time loop (it was heading for 40+ `check` runs
before that).

Second data point, `src/aarch64.al` (63 arms, 8 879 lines): about **2 h** end to end, of which the
63-run census was ~45 min at six-way parallelism on a loaded machine (~40 s per `check`, and it was
competing with three other lanes' gates) — the census is the floor, and it does not shrink with
familiarity. The two compiler builds and four GAS emissions were ~10 min; the two issues the file
produced, ~25 min. The `check` runs scale linearly with the arm count and parallelise; the reading and
the writing do neither. `lower.al`'s 205 caught arms are ~2 h of `check` serially and ~20 min at six-way
parallelism, so what has to be sliced there is the reading, not the measuring.

Fourth data point, `src/riscv64.al` (52 arms, 7 971 lines): about **2 h** end to end, and it is the
first file whose census split on a PERFECTLY clean line — **27 caught / 25 blind, 27 for 27 of the
`match deref(<expr>)` arms over `Expr` and 25 for 25 of the `match st` arms over
`st := deref(stmt_p(Stmt, <h>))`**, with no third case anywhere in the file. That is worth carrying
as a prediction for the remaining backends and NOT as a licence to skip the measurement: the split is
what makes the file's reading cheap, and only the per-arm census can tell you the file has it.
The 52-run census was **10 min 0 s** wall clock at eight-way parallelism (11:23:35 to 11:33:35;
~40 s per `check` unloaded, ~90 s under its own eight-way load) against ~35 min serial; the two
compiler builds and the four GAS emissions were ~8 min; the non-vacuity sequence diverged at
**step 3** and took ~6 min.

Three things this file adds to the procedure rather than repeating:

- **Take the census with the compiler this tree builds, and take the GAS evidence with it too.** The
  seed is 0.2.3 here and would have agreed, but that is luck, not method — §0's first two entries are
  both cases where the seed disagreed with the tree it was being used to check.
- **§3's seed-promotion wait is over, and this file is where it was spent.** `emit_rv_expr`'s group
  arm absorbs eight variants over a body holding `push_str(sb, "  ebreak\n")` — the exact shape that
  stopped `src/aarch64.al` at 38 of 39 with `Error: symbol '.Lstr1_617' is already defined`. Written
  out against seed 0.2.3 (`a46be2c`, carrying PR #685) the seed builds it clean, and the emission is
  byte-identical in both directions. `src/aarch64.al`'s one deferred arm is now writable too, and it
  is the cheapest remaining unit of this stage: one arm, one already-measured census row.
- **Name the blanket silencer's group arms by SHAPE, not by line.** §7's blanket pass appends
  `| Expr::<planted>` to every existing group arm, and the first attempt here matched only arms whose
  `|` and `=>` sit on the SAME line. `src/parser.al`'s enumerated arms wrap with a bare
  `      => { … }` continuation line, so 2 of 93 were missed, `_ => {}` went into a value-position
  match instead, and the loop spent three steps producing `check: invalid` errors about the silencer
  before the file stopped parsing at all. Match a group-arm tail as "a line of `|`-joined bare
  `Expr::X` tokens whose next non-empty line starts with `=>`" as well, and the pass is 93/93.
