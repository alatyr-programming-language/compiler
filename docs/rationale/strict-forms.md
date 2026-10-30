# Strict forms — rationale

The measurements and coverage notes behind each strict form. The forms with their examples are in `.agents/skills/alatyr-lane/strict_forms.md`.

Moved verbatim from `AGENTS.md` (#1130). `AGENTS.md` states each rule briefly; this file is the full
text, with the reasons, measurements and history. Line citations are as of the move.

## Strict forms

Write compiler and library code in the forms below. Each one turns a defect class this compiler has
shipped into something that cannot be written, or cannot be written without a visible reason. The
reasons, the issues and a "this / not this" example for each form are in
`.agents/skills/alatyr-lane/strict_forms.md`. Read it before writing code, not after the gate refuses
some. Where a check holds a form, it is an **addition rule** against the merge base (no oracle file).
Only a new occurrence is refused, and a `## <rule>-ok: <reason>` comment on the line or the line above
acknowledges it.

Write idiomatic code with strict types in the **first draft**. Never satisfy a check by switching to
an explicit sentinel, or by adding a marker, when the typed form is possible. If the typed form does
not compile, or compiles wrong, that is a defect: file it and name it in the marker. Do not route
around it.

1. **Absence is `Option`, not a sentinel.** Do not use 0 as null, −1 as "not found", or 255 as
   "poisoned" (#659, #681). The target form is `Option(ptr(T))` (one word, niche-folded) walked with
   `match`, or `Option(u64)`. An explicit `unchecked bitcast(usize, p) != 0` only makes the null
   visible. It is a transitional form, allowed only where the typed form cannot be compiled yet, and
   its `null-ok` reason names an OPEN blocking issue. The two historical blockers, #809 (a direct
   `match` over such a field through `deref(p)` or an array element) and #792 (an enum or `Option`
   field read through `deref(p)`), are closed, so a new sentinel needs a newly filed blocker. Held by
   the `null` rule of `scripts/strict_forms_check.sh`, which counts explicit and implicit (`p == 0`)
   forms together. Decided, do not reopen: a pointer meeting an integer is **grant-only** (MEM-9, with
   MEM-10 refining it; spec/spec#19 merged, and both are inside the pinned revision, so the rule binds
   this tree now — which is what unblocks #1034, the compiler half that enforces it). On the axis each instrument measures, the **implicit** half is empty: `op-cmp=0` in
   `scripts/ptrint_census.baseline`. Only the gate's **typed** path can see an implicit row at all — it
   runs the compiler (`--typed-self-test`, `strict_forms_check.sh:55`, whose proof prints
   `implicit-cmp base=… +implicit=…` at `:478`); the count-driven decider at `:432` only *simulates*
   those counts, and the lexical scanner cannot see one at all — it needs the operand's type. The explicit
   half is where every real site lives: 595 `null` rows over the gate's paths (`src/` + `lib/`; `lib/`
   contributes none), 573 of them unacknowledged, in three shapes — blocked on #1069, the AST still
   spelling an absent `Decl.value`/`Arm.body` as null. #1034 carries the refusal and
   waits on the pin, not on review. The `null` gate refuses a new implicit `p == 0` today; the
   compiler's `check` does not, until the pin moves.
2. **A kind is an enum, and flags are separate fields.** Do not compare a `kind`/`tag` with a literal,
   and do not pack a flag into a tag byte (`+128`) (#583, #626). Held by `kind-literal`.
3. **Decide with an exhaustive `match` on the value.** Never use `_` over an enum (#544, #464). Do not
   recover a variant from numbers (#716). Held by `scripts/wildcard_arm_check.sh`.
4. **One decision, one place.** `grep` for the question before you answer it again (#540, #539). Held,
   for the shapes it knows, by `scripts/idiom_gate.sh`. The **private-copy** half is held by
   `scripts/copy_lift.py --gate` (#1077): it matches brace-balanced bodies, so it reports a copy even
   when its name differs from its home, and holds the exact set to a reviewed baseline, addition-only,
   by name. A new copy needs `## copy-ok: #<issue> — <reason>` naming what forces it; a marker citing no
   issue fails on its own. Deleting a copy passes and must lower the baseline. Textual identity is
   *necessary, not sufficient*: only a build decides deletability — census the emitter **and its child
   modules**, which resolve a bare name to the parent, and delete by span, never by line.
5. **Width and signedness are spelled.** Annotate a local before `/`, `%` or an ordering. Never infer
   them from the form of an operand (#546, #608, #764–#766). The **signedness** half is held by
   `scripts/sign_census.sh --gate`: it compares every signedness decision each backend takes against the
   type sema recorded for the same operand, and the ratchet (`scripts/sign_census.baseline`, measured on
   a clean checkout of the pinned revision) holds `x86_64=4 aarch64=0 riscv64=0 wasm=0` — a backend that
   answers nothing fails rather than reading as a zero, and a new shape-derived choice fails. The
   **width** half stays **review-only** until the aggregates and instance slices (docs/ir.md §7.2
   slices 3 and 6) take it from sema's side table too; `scripts/ir_census.sh --targets` measures how much
   each backend lowers from the shared IR, but it does not judge width, so it is coverage and not a pin.
6. **`unchecked` is explicit and justified.** No implicit `usize` ↔ `ptr(T)` (#529, Types §4.3). Held by
   `unchecked` (marker `unchecked-ok`) and the typed `ptrint` rule (no marker: write it explicitly).
7. **Bind a `?` before using its value** (`x := f()?`), never `f()?.a` or `g(f()?)` (#752). Seed
   0.2.5 compiles the inline form correctly, so the rule now stands for readability alone. Held by
   `try-inline`.
8. **Do not write the forms the frozen seed miscompiles.** Each one is a row of `scripts/seed_forms.tsv`
   with a planted program the seed must still miscompile and the tree must run correctly, and a
   comment at its workaround site. A new workaround adds a row. Held by `scripts/seed_forms_check.sh`,
   which fails when a promotion fixes a form so its row and workarounds retire.
9. **An AST handle has its node's own type**, never `usize` or a sibling node's pointer (#760 fixed 12
   walkers). **Partly held by the checker, review-only for the rest — and the two halves must not be
   conflated.** Where both operand types are known, the checker does discriminate pointee names:
   `ty_compat` compares `a.ns`/`b.ns` when both sides are pointers (`src/sema.al:502-511`), so a
   sibling-node pointer mix is refused at the sinks that route through it — call-result to pointer param
   (`:11006`), struct-literal field (`:11285`), place writes (`:11546`), tail result (`:16808`). It does
   **not** hold at a `deref`, where the type is deliberately `TyUnknown` under deferred pointee tracking
   (`:11360-11363`), nor at an argument position, where the pointee name is erased on purpose so a
   written `unchecked bitcast` cannot spuriously fail (`:11231-11237`, kind only). So the earlier wording
   here — "held by the checker at a `deref`" — named the one place the checker is blind, and a later
   correction that said there was no check at all was wrong in the other direction; both were coverage
   claims nobody had read the tree for. What stays **review-only** is exactly the gap: a bare `usize`
   handle, and a sibling-pointer mix at a deref or an argument. A gate rule would need a new hook, not
   reuse — the #529 instrument's classes are `ARG/BIND/REASSIGN/FIELD-LIT/FIELD-STORE/ELEM-STORE/
   PLACE-NESTED/PLACE-ARRNESTED/RESULT-RET/RESULT-TAIL/OP-CMP/OP-IF/OP-MATCH` (`src/sema.al:539-553`)
   and there is no `DEREF` among them. The proposal, with its measured blast radius, is in
   `.agents/skills/alatyr-lane/strict_forms.md` §9; until a rule lands, a reviewer answers the question
   and the answer is recorded in the PR, not assumed.
10. **A quantity with an identity is a `brand`**, not a bare number: a byte offset, a word count and a
    slot index get distinct brands, converted by named functions (#167, #760, #299). The checker
    refuses a sibling or raw mix since #299. Choosing a brand for a new quantity is **review-only**.
11. **A field a reader turns into a value type is not a place to put metadata.** A field that has
    always answered zero is not free to fill in: its meaning is whatever reads it does. Carrying the
    pointee span into `Ty.ns/nl` at `Expr::AddrOf` trapped six rows on three backends (#1097), because
    `sema_vty_record` (`src/sema.al:8740`) tries the **name** before the `TyPtr` kind — so
    `ptr(mut n)` where `n : i64` records the address node as `VcInt`, 8 bytes, signed (`ir.al:2527`),
    and `ir/build.al:230` builds an integer where a pointer belongs. "Zero staying zero" is the only
    case that cannot change behaviour, and non-zero was the point; "strictly additive" is therefore never
    a safety argument for filling a field in. Decided in #1099: the pointee goes in
    a fourth field on `Ty`, which `sema_vty_record` does not read. Held by review
    until a registry exists — the audit cannot be derived lexically, but once made it is holdable the
    way form 8's `seed_forms.tsv` is; read the **sema-side** hits first, that is where this one was.
