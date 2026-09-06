# Changelog

What a *user of the toolchain* would notice. The full record of how the compiler got here is its git
history and `seed/VERSION`; this file is the short version, aimed at someone deciding whether a new
build changes anything for them.

## Versioning policy

The compiler is versioned independently of the specification, and it **cites** the spec revision it
conforms to. Those two numbers move for different reasons and must not be conflated: a spec revision
can land without any compiler change, and the compiler changes constantly without the language
moving at all.

- **MAJOR** — a program **the specification calls valid** no longer compiles, or produces a different
  result. Also: the spec revision this build conforms to moves by a major. The qualifier is doing real
  work: this compiler has accepted many programs the specification declares invalid, and refusing one
  of those is a defect fixed, not a break — see PATCH.
- **MINOR** — new surface: a construct that used to be rejected now works, a backend gains a shape,
  a CLI verb or flag appears.
- **PATCH** — a defect fixed with no new surface, or a diagnostic improved. A **silent wrong value**
  turned into a correct one, or into a loud failure, is a PATCH even though its effect on a program
  can be dramatic; that is the class this project treats as most urgent. **Newly rejecting a program
  the specification declares invalid** is also a PATCH: the defect was accepting it, and someone whose
  code stops compiling for that reason was relying on a bug. Say so in the entry, so the reader can
  tell this case from a break.

Two things that deliberately do **not** move the version: making an existing rejection *louder* or
better-located (the program was already refused), and any change under `scripts/` — the gates are
how this repository proves itself, not part of what it ships.

## When the version moves, and the tag that records it

**The version moves on a seed promotion, and only on one.** `package.al`'s `version` field is the
compiler's identity; a promotion replaces `seed/alatyr` with a materially different compiler, and two
promoted builds reporting the same number is exactly what a version exists to prevent. Between
promotions the number stands still and `## Unreleased` accumulates, so the number identifies a seed
generation together with the tree that seed reproduces — not an individual commit.

`scripts/fixpoint.sh` enforces the pairing: `package.al`'s `version` must equal
`current-seed-version` in `seed/VERSION`'s CURRENT SEED block. It fires on both ways of breaking it — a
promotion that forgets the bump, and a bump made without a promotion. The fixpoint itself would not
catch either: the version IS part of the emission (a compile-time constant, TOOL-21), but changing it
moves the seed's output and Stage1's identically, so they stay byte-equal.

A promotion commit therefore carries all of these, and the gate is red if any is missing:

1. `seed/alatyr` — the promoted Stage2 binary.
2. `seed/VERSION` — the appended entry with the three stage hashes and the **read** delta, plus the
   CURRENT SEED block updated to the new hash and version. The entry is the reviewable part: it lands
   in the promotion PR, where a human can read the delta before it becomes history.
3. `package.al` — the new `version`.
4. `scripts/package_cli_test.sh` — its expected `alatyr <version>` line. Easy to forget, and forgetting
   it fails the gate with a diagnostic that never mentions the version.
5. This file — `## Unreleased` becomes `## <version> — <date>`, and a fresh empty `## Unreleased`
   opens above it.

**The tag.** After the promotion lands, an **annotated** tag `v<version>` goes on the promotion commit.
It is created after the merge, so nothing reviews its message — which is why the tag carries the digest
and never the primary record:

```
git tag -a v0.2.0 <promotion commit> -F - <<'EOF'
alatyr 0.2.0

<one paragraph: what this generation of the compiler does that the previous one did not>

Stage1 == Stage2 == Stage3, GAS <n> lines
GAS SHA-256:    <hash>
binary SHA-256: <hash>
Promoted stage: Stage2
Gate: e2e <n>/<n>, corpus <n>/<n>, formatter clean, idiom new=0, sweeps clean
Spec revision: <revision this build conforms to>
EOF
```

The full delta audit stays in `seed/VERSION`. A tag is not in the input tree — a source tarball loses
it, and a tag can be moved with a force-push — so it is navigation, not the record.

Two numbers that are **not** the compiler's version: the specification revision (this build cites it,
`README.md` carries the badge) and the seed lineage in `seed/VERSION`. The specification's own `v1.0.0`
tag lives in the sibling repository; a `v1.0.0` here would mean something else entirely.

## Unreleased

- A `{}` **template hole holding a negative signed integer** now prints the same text on all four
  backends. Functions §7.1 routes a hole through the scalar rendering layer and Stdlib appendix §2
  fixes that layer's integer form as base-10 with "a leading `-` for a negative two's-complement
  value"; **aarch64**, **riscv64** and **wasm** each had exactly one integer renderer and it was
  unsigned, so `a : i64 = 0 - 128` printed **18446744073709551488** on those three while x86_64
  printed **-128**. The program compiled cleanly and exited 42 on every backend — only the text was
  wrong, which is why the exit-code cross-target sweeps never contradicted it, and why no fixture had:
  every cross-backend stdout row in the suite printed a non-negative number (#444). Each of the three
  template emitters now picks a signed renderer when the hole's static type is signed, using the same
  signedness oracle `/`, `%` and `shr` already route on; a hole that oracle does not prove signed keeps
  the unsigned renderer and its exact previous bytes. The new signed helper is written last and only
  when a signed hole actually reached it, so a program without one emits byte-identical output to
  before — measured over all 1532 of `test/*.al` on all four backends, 0 differing. A hole whose signedness
  that oracle cannot see — an un-annotated local, an array element, a call result — still renders
  unsigned on the three backends; that residual is tracked separately.
- The **code-point iterator** of `str` is now reachable through its **qualified** path from outside
  the standard library. Stdlib appendix §3.6 lists `chars(in self) -> CharIter` as an Iterator (§2.4),
  and §2.4 makes the returned type usable through `iter`/`next`; those two `CharIter` overloads were
  already `pub`, but `base::str::iter(cursor)` and `base::str::next(cursor)` were still rejected with
  `check: invalid`. The cause was the **other** pair of overloads of the same two names in the same
  module: `SplitIter`'s `iter`/`next` were private, and the visibility test reports a violation when
  any same-name, same-module declaration is invisible rather than when every candidate is. Publishing
  the `SplitIter` protocol pair — the only two markers in this change — makes the §3.6 surface
  reachable as Modules §3 requires. Nothing changes about representation, decoding or iteration
  semantics, and no call site resolves differently: a program that declares its own `iter`, `next` or
  `split` still gets its own, including through `for`. The compiler's own emitted assembly is
  byte-identical.
- `alatyr fmt` no longer **deletes the target type** of a `bitcast` it cannot see in the tree.
  `bitcast(T, v)` is the identity on the block whenever `T` is a word-sized scalar, `str`, `type`, or
  a pointer over one of those, so the parser drops the node and every back end stays on the identity
  path — but the formatter reads the same tree, and with no node to read it wrote
  `unchecked bitcast(usize, n)` back to your file as `unchecked (n)`, at exit 0. Tooling §4.3 makes
  `fmt` semantics-preserving and the written target is what types a bare binding, so this quietly
  replaced a conversion with whatever type the operand happened to have; formatting this compiler's
  own sources rewrote about 1 100 such casts. The target span now survives beside the AST and comes
  back verbatim in every position — argument, operand, initializer, postfix base — including two
  erased levels on one expression, and the `unchecked` marker is recovered from the source rather
  than invented. What the compiler emits is unchanged: recording is on only for `fmt`.
- An **expression-form `match` in tail position** over an enum **place** now selects the right arm.
  Control Flow §5.3 makes `match` one expression with one meaning, but the tail-value route resolved
  only two kinds of scrutinee — a plain enum local and a mutable enum global — and sent every other
  enum place to the *integer* compare path, where an enum pattern arm carries no scalar literal at all.
  Every arm therefore compared the scrutinee against **0**, so only a variant whose discriminant is 0
  could ever match: `dotted := fn(h : Holder) -> u64 { match h.t { Red => 32, Green => 64, Blue => 128 } }`
  built cleanly and answered **0** for `Green` and `Blue`, and with a wildcard present it answered the
  wildcard instead. Reordering the arms exposes the other half of the same mechanism — write `Green`
  first and the **first arm** wins for every input. A struct field (`h.t`), an enum-array element
  (`cs[i]`), a struct-field array element (`h.items[i]`), an array-of-struct element's field (`xs[i].t`)
  and a mutable global struct's field (`G.t`) were all affected, and payload bindings through those
  places were lost with them. All five now materialize their enum words exactly as the value-expression
  and braced statement forms already did, which is why binding the field to a local first, or writing
  braced arms, was the workaround. x86_64 only: aarch64, riscv64 and wasm have no enum-match lowering
  and refuse an enum scrutinee fail-loud. A **nested** place (`o.inner.t`) is a separate, still-open
  defect — it answers the same wrong value in *every* match form, including the bound-local one.

- A single-file program that reaches the ambient allocator by its **bare names** now gets the base
  prelude. The shipped stdlib is injected by scanning the source text, and the only text that pulled
  the allocator surface was the bare name of the fallible-result type. Control Flow §5.2 makes a bare
  variant pattern (`Ok(h)`, `OutOfMemory`) exactly as legal as `Result::Ok(h)`, so a program that
  spells its patterns bare could contain no occurrence of that word at all — and then `Arena`,
  `arena_over`, `allocate` and the allocator error enum were all rejected as unbound names on a
  program the specification calls valid. The arena type, its constructor and the error enum are now
  triggers of their own, word-boundary matched, so `ArenaPool` or `AllocErrorKind` does not pull
  anything. A file that declares those names itself keeps its own meanings. This is the residual half
  of the defect first seen as `alatyr fmt` writing source that no longer compiled: the formatter stopped
  respelling patterns earlier, but any tool that rewrites source could still change which prelude a file
  gets, and a program that never needed rewriting was refused outright. Manifest/package builds keep the
  narrower result-name trigger they had.
- The **wasm** backend now answers correctly when a nested block shadows a **parameter**, as
  Declarations §6.1 allows ("an inner scope may shadow an outer name"). Its frame gives one *name* one
  slot for a whole function and its read path resolved a parameter before a local, so the shadow's
  `:=` wrote a slot nobody read: `if p == 1 { p := 8 ; acc = p }` left `acc` holding the argument, and
  the same shadow in a `while` body silently answered **6** where x86_64, aarch64 and riscv64 all
  answered **10** — a wrong value on a clean compile. Entering a block that binds a parameter's name
  now seeds that binding from the parameter and makes the block's reads resolve to it; leaving the
  block puts the parameter back in scope. Reading a bare **scalar parameter** on the right of an `=`
  or a `:=` was a second face of the same defect: a parameter's `: T` annotation was taken for a
  struct name without confirming it named one, so `acc = p` over `p : u64` went to the whole-aggregate
  copy path and **trapped** (134) instead of copying a word. Seven programs that used to trap on wasm
  — `std_math`, `math_ln`, `math_sin`, `math_cos`, `math_sqrt`, `inline_stmt_body` and
  `lambda_capture_comptime_if` — now run and answer what x86_64 answers. x86_64, aarch64 and riscv64
  emit byte-identical assembly before and after. What the outer name means *after* the shadowing block
  ends still differs between wasm (which restores it, per §6.1) and the three native backends (which
  do not); that divergence is tracked separately.
- Indexing an **array field of a mutable module-level struct** — `gg.xs[i]`, read **and** write — is
  now bounds-checked, as Types §6.4 requires by default. The check was missing on exactly this shape,
  on both sides. With `mut gg := G(xs = [10, 20, 30], guard = 99)`, the out-of-range read `gg.xs[3]`
  compiled cleanly and exited **99**: the address math ran past the field and returned the struct's
  *next field* as an ordinary value. The store `gg.xs[3] = 77` was worse in the same way — it
  **overwrote** `guard`, so a later read of `guard` returned the value the program believed it had put
  in the array. Both are silent wrong values, and both are hard to spot precisely because a
  neighbouring field is a plausible-looking number rather than obvious garbage. Every adjacent shape
  was already checked and is unchanged: the same array as a **local** struct's field, a direct mutable
  **global** array (`TABLE[i]`), a by-reference array parameter, a slice and a str. An **immutable**
  module-level struct's array field is a separate, already-loud case: it is refused with a "not yet
  supported" diagnostic and stays refused. `unchecked` still drops the check on exactly these two
  accesses (CT-11 / CG-7), including the address, which is unchanged. x86_64 only, because that is the
  only backend that lowers the shape at all: aarch64, riscv64 and wasm emit a fail-loud `unsupported
  index` trap for `gg.xs[i]` whether the index is in range or not, so they were never affected and are
  untouched here.

- Re-declaring a name **already bound in the same scope** is now a compile error, as Declarations §6.2
  requires ("a name means one thing within its scope"). No surface enforced that for function-body
  locals: `check` accepted the program and the four backends then disagreed. Written with two
  different types (`r := Result(usize, u32).Ok(7)` then `r := Option(usize).Some(9)`), the `match`
  below resolved its arms in the wrong enum and took **no** arm, so x86_64 fell through to the
  fallback and answered `77` on a clean compile — until a lowering-side fence started refusing that
  one spelling; aarch64, riscv64 and wasm trapped at run time instead. Written with the **same** type, all four backends accepted it
  in silence. The refusal is now a located `check` diagnostic naming the second declaration's line, so
  `check`, the `-o` build and the three emit-to-stdout backends refuse it identically and emit
  nothing. Cross-scope shadowing (§6.1) is untouched and stays legal: an inner block may shadow an
  enclosing name or a parameter, two sequential non-overlapping blocks may each bind the same name,
  two sibling `for` bodies may each bind the same loop-local, a `match` arm's payload binding may
  reuse one name across arms, and `x = v` after `x := v` is a write, not a second binding. `_` is a
  discard, not a name, so repeated `_ :=` is unaffected. The one specification exception — function
  overloading by signature (Functions §1.4 / FN-7) — is not reachable today: the lower has no local
  overload set, and no fixture spells one.
- Assigning to an element of a **string literal** is refused where it is written, instead of quietly
  becoming the function's result. `"abc"[0] = 65` followed by a `7` used to build with no diagnostic
  and exit **65**: the line was not recognized as a statement at all, so it fell to the
  trailing-expression path, where the `=` was taken for an opening parenthesis, the `65` for the
  parenthesized expression and the `7` for its closing token. The declared result was never reached
  and nothing said so — a silent wrong value. A literal is a value, not a storage location: its bytes
  are emitted once into read-only data, so a store has nothing to write into (Memory §1.6; Types §7),
  and Grammar §3.3 roots every assignable place at a name, a path or a `deref(…)`. The runtime-index
  spelling `"abc"[i] = v` and the compound `"abc"[0] += 1` were accepted the same way and are refused
  the same way. The refusal is in the parser, so `alatyr check` and all four emission surfaces
  (x86_64, aarch64, riscv64, wasm) agree and none leaves an artifact behind. Reading a literal
  element (`u64("abc"[0])`), writing an array element (`a[i] = v`) and every other place form are
  untouched. Newly rejecting a program the specification declares invalid: the defect was accepting
  it.
- Storing into an element of a **`str`** is refused in `check`, instead of killing the process. This is
  the neighbour of the entry above, and it reached the fault by a different route: here the target
  really is a place — `s` is a name, `s[i]` a legal `place` by Grammar §3.3 — so the parse is correct
  and the parser fence never sees it. `s := "abc"` followed by `s[0] = 65` built with no diagnostic and
  died with **SIGSEGV** (x86_64 exit 139) writing into `.rodata`; aarch64 and riscv64 reached a
  fail-loud trap (133) and wasm aborted (134), so all four backends accepted the program and then gave
  four different answers, none of them a message. `mut` did not help and was not supposed to: `str`
  **is** the slice `[u8]` (Types §7, Stdlib appendix §3.6), a slice's element permission comes from its
  pointer, and the writable spelling is `[mut T]` — so under Memory §3.3's AND rule the `mut` step
  passes and the pointee step fails. `mut s := "abc"` and `mut s : str = "abc"` segfaulted the same way
  and are refused the same way, as is the compound `s[0] += 1`. The refusal is in the shared semantic
  pass, so `alatyr check`, the `-o` build and the three emit-to-stdout backends agree and none leaves
  an artifact. What `mut` does buy is untouched: a whole-view reassignment `mut s := "abc"; s = "de"`
  is still legal. Reading a `str` element, sub-slicing one, `mut` array element writes, `mut` struct
  field writes and `deref(p) = v` are all untouched. An alias is covered too, and had to be: `t := s`
  copies the two-word view and not the bytes, so it inherited the same read-only run, and on the
  parent it re-opened the fault for every spelling of `s` — including a `str` parameter, whose own
  direct `s[i] = v` was already refused, so a one-word edit walked around that refusal. Where the
  FIRST failing step of the path is the binding itself — an immutable `s : str`, a `str` parameter, a module-level `G := "abc"` — the
  established `immutable binding` diagnostic still owns the message, unchanged. Newly rejecting a
  program the specification declares invalid: the defect was accepting it.
- Assigning to **any** value-expression is refused where it is written, closing the rest of the class
  the string-literal entry above fenced one spelling of. `5 = 3`, `f() = 65`, `[1, 2, 3][0] = 65` and
  `bytes(s)[0] = 65` all used to build with no diagnostic; the first exited **3** and the other three
  **65**, in each case the assignment's right-hand side standing in for the declared result. The cause
  is the same one: none of these was recognized as a statement, so the line fell to the
  trailing-expression path, where the `=` was taken for an opening parenthesis, the right-hand side
  for the parenthesized expression — and the **next statement** for its closing token. That last part
  is what makes this worse than an accepted bad program: a line of real work in between simply
  vanished. A program that declares 42 and stores through a live local between the bad assignment and
  the result exited **12**, cleanly, silently. Memory §1.6 is normative — a store's left operand must
  be a place-expression, and assigning to a value-expression is ill-formed — and Grammar §3.3 roots
  every place at a name, a path or a `deref(…)`, which a literal, an array constructor and a call
  result are not. The refusal is in the parser, so `alatyr check` and all four emission surfaces
  (x86_64, aarch64, riscv64, wasm) agree and none leaves an artifact behind. Every legal place form is
  untouched, in both the plain and the compound spelling: an array element, a struct field, an array
  element of a field, a tuple component, a `deref(p)` store and a qualified `mod::G` target. Newly
  rejecting a program the specification declares invalid: the defect was accepting it.

- The unary prefixes `-` and `~` now apply to the element, field or component the source names. Both
  took their operand at the **primary** level, so a postfix step that followed applied to the prefix's
  RESULT: `-a[i]` parsed as `(-a)[i]`, `~a[i]` as `(~a)[i]` and `-p.b` as `(-p).b`, and the read went
  to a frame slot instead of the array or struct. With `xs : [u64; 4] = [71, 42, 93, 55]`,
  `-xs[1]` negated `0` where `42` was due, `~~xs[2]` answered `5` where `93` was due, and nothing said
  so — the frame slot holds whatever that frame keeps, so the wrong answer is not reliably `0` and can
  look entirely plausible. Grammar §3.4 gives the unary level a `postfix-expr` operand and §4 puts the
  whole postfix family (call, index, field, UFCS, `?`) one level TIGHTER than the prefixes, so the
  postfix chain is part of the operand. Every base was affected the same way: a fixed array, a typed
  slice, a struct field, a tuple component and a UFCS chain. Parenthesizing the operand
  (`-(a[i])`) was already correct and is unchanged; parenthesizing the whole expression (`(-a[i])`)
  was **not** a rescue and now needs none. Binary operators are untouched — `~a & b` is still
  `(~a) & b` and `-c % d` is still `(0 - c) % d` — and `not`, which the parser takes at the comparison
  level, already reached past its postfix chain. On aarch64, riscv64 and wasm these shapes used to
  stop loudly rather than answer wrongly; they now run correctly there too. `alatyr fmt` needed no
  change: it already renders the prefix operand bare, and that text now re-parses to the same tree.

- The one-access verification mode `unchecked a[i]` now reads the element it names. The modifier
  bound to the **base** rather than the access, so `unchecked a[i]` parsed as `(unchecked a)[i]` and
  the read went to a frame slot instead of the array: `xs : [u64; 3] = [71, 42, 93]` answered `0`
  where `42` was due, and nothing said so. Every base was affected — a fixed array, a `str` local, a
  typed slice and a `str` literal alike — and `unchecked p.f` was silently taken out of its own scope
  the same way. The braced region form `unchecked { … }` was always correct and is unchanged, which
  is why this survived: the fixtures that exercise unchecked indexing all use it. The emitted code
  for `unchecked a[i]` now differs from the checked `a[i]` by exactly the omitted bounds trap, which
  is all the specification permits it to drop (Types §6.4). `unchecked` still binds looser than every
  binary operator, so `unchecked a[i] - 1` is unchanged. On aarch64, riscv64 and wasm these shapes
  used to stop loudly rather than answer wrongly; the array and slice bases now run there too, and a
  `str` index still stops loudly on all three. `alatyr fmt` follows the new binding: an `unchecked`
  operand used as a postfix base keeps its grouping parens.
- `deref` through a pointer bound from a view's data pointer (`q := s.ptr`, `q := bytes(s).ptr`, or
  the same off a `str`-returning call) now reads **one byte** however much whitespace separates the
  binding's name from its `:=`. The compiler recovered "this local is a `ptr(u8)`" by scanning at
  most 512 bytes forward from the name, so a declaration spelled with more spacing than that still
  compiled cleanly and loaded a full WORD instead: `if deref(q) == 65` took the wrong branch and the
  read ran seven bytes past a short `str`, with no diagnostic and a green `check`. An annotated
  pointer (`q : ptr(u8) = s.ptr`) was already correct. The shape the recovery fires on is otherwise
  unchanged — a struct field holding a `ptr(u8)`, and longer chains such as `a.ptr + k`, keep the
  word-sized load they had.

- Two same-named locals of **different aggregate types** in one function are now **refused with a
  located diagnostic** on x86_64 instead of silently answering the wrong value. A local declared in a
  nested block and then declared again in the enclosing scope under the same name but another enum
  type made the later `match` select **no arm at all** — no trap, no diagnostic, the assigned variable
  kept its pre-`match` value — and the same collision over two struct types made a field read answer
  the wrong word. The backend keys a frame slot by name alone for the whole function and recorded the
  first binding's type, so every later member resolution used it. The program is valid
  (Declarations §6.1) and aarch64, riscv64 and WAT already compile it correctly, so this is a
  backend limitation made loud rather than a rule: rename one of the two locals and the program
  compiles everywhere. One name bound to two instances of one generic enum, to two struct types that
  declare the same members, or to its own type again is unaffected, and a `match` arm's payload
  binding is not touched.

- Raw x86_64/Linux/ELF package entries that name ordinary no-parameter `fn() -> i32` functions now
  receive a generated call/exit wrapper, so the result becomes the process status code and procedures
  exit zero; `@abi(naked)` entries remain programmer-owned. The wrapper is emitted **under the entry
  declaration's own linker symbol** — its exact `@export` when it has one, else its module-derived
  spelling — so the executable's ELF entry address still resolves to the symbol the manifest's `entry`
  names, which is what a linker script or external harness keys on. An entry with no exact `@export`
  gives that spelling up to the wrapper and its body moves to the reserved `__alatyr_raw_entry_body`,
  so calling such an entry from inside the program now runs it as the process entry and exits.
- Indexing a string literal directly (`"abc"[2]`) now reads the byte at that offset. The form
  compiled cleanly and returned the contents of a frame slot instead — `u64("abc"[2])` answered `5`
  where `99` was due, and nothing said so; indexing through a local (`s := "abc"; s[2]`) or through
  `bytes("abc")` was always correct. An out-of-range literal index now traps like every other
  checked index, and taking the **address** of a literal element — which used to hand back a pointer
  into the caller's own frame — is refused with a located diagnostic instead of reading a live
  local. `str` is `[u8]`, so the value is a BYTE and not a code point: `"\xc3\xa9"[0]` is `195`.
  x86_64 only; the aarch64, riscv64 and wasm backends do not lower any `str` index yet and continue
  to stop loudly on all of them.
- `for x in <iterator>` now drives `next` instead of counting the iterable's first two words, so
  `for c in chars(s)` / `for c in s.chars()` walk a string's **code points** and `for part in`
  a `SplitIter` walks its pieces. Every spelling used to compile and run the backing view's BYTE
  length while yielding neither the code points nor the raw bytes — `"Aé€😀"` (4 code points,
  10 bytes) iterated 10 times and answered `65, 152, 0, 78, 0, 0, 0, 0, 0, 0` — and `next` was never
  called. The loop drives a copy, so a named iterator variable is not advanced behind your back, and
  the loop variable carries the payload type. A range, array, slice, `str` view, array global or
  `Vec` keeps the counted loop unchanged. An iterator whose `next` this form cannot yet call — a
  generic `next(K : type, …)`, as `alloc::hashmap::HashMapIter` declares, or a `next` that does not
  return `Option(T)` — is now **refused with a located diagnostic** instead of walked as a slice;
  drive it explicitly. One spelling is still wrong for an unrelated reason: `for c in iter(cur)`
  binds its iterator from an overloaded call, and such a binding is typed from the wrong overload
  (see the open follow-up), so it decodes with the wrong `next`.
- `std::os::env` now reads the complete process environment through the same growable
  `alloc::strbuf` image `std::os::args` uses, so a present variable whose value crosses the staging
  boundary is returned in full instead of appearing absent, and an exhausted allocator or failed read
  traps rather than being folded into `None`.
- `base::str` now publishes the `chars`, `iter`, and `next` functions required to consume the
  specification's `CharIter` protocol from an external package, in the qualified, bare and UFCS
  spellings; its representation and decoding behavior are unchanged, and `char_byte` stays private.
- Packed `[u8; N]` returns now extend to two machine words: a return of `N = 9..16` bytes is carried
  in two registers, indexed both after binding and directly on x86_64 and read directly on AArch64,
  and composes with fixed-array forwarding and fixed-array arguments on x86_64. `N = 1..8` keeps its
  existing one-word ABI, and a fixed-array return shape the compiler does not support is now refused
  with a located shape-specific diagnostic instead of falling through to scalar lowering.
- An equal-width aggregate `bitcast` used directly as a by-value struct ARGUMENT
  (`consume(bitcast(B, a))`) now passes the source aggregate's own block on x86_64 instead of passing
  its first word as a scalar, which the callee dereferenced as the block address — the reproducer
  died with a segmentation fault. An unequal bit width or a non-variable source in that position is
  rejected with a located diagnostic, and unsupported non-x86 aggregate bitcasts stay fail-loud.
- `alatyr fmt` now keeps the qualifier an enum-variant pattern was written with: `Result::Ok(h)` and
  `AllocError.OutOfMemory` come back qualified in both the expression- and statement-form arm
  renderers, instead of as a bare `Ok(h)` / `OutOfMemory`; a pattern written bare stays bare. The
  de-qualified text could stop compiling outright — the ambient standard-library prelude is injected
  by scanning the source for a bare `Result`, so deleting a file's last qualified spelling took
  `Arena`, `allocate` and `AllocError` out of scope while `fmt` still exited 0.
- `alloc::string::push` and `alloc::string::push_str` now report the **new byte length** of the
  string in their `Ok` arm, as the Stdlib appendix requires, instead of the number of bytes they
  appended: appending a 1-byte `char` to a 2-byte string answers `Ok(3)`, not `Ok(1)`, and
  `push_str("")` answers the unchanged length rather than `Ok(0)`. `AllocError` propagation and
  `alloc::strbuf`'s own appended-count convention are unchanged.
- A parenthesized generic type instance now works as a `bitcast` target: `unchecked bitcast(Box(P), p)`
  keeps the instantiated layout of `Box(P)` and moves the whole equal-width image on x86_64, instead of
  erasing the target so that every field of the bound local read zero. `alatyr fmt` keeps the type-arg
  group of such a target. Unsupported non-x86 aggregate bitcasts stay fail-loud.
- `alloc::vec::reserve` now returns `Err(AllocError.SizeTooLarge)` for a request it cannot represent
  in `usize` instead of aborting the process: the requested count `len + additional`, the capacity
  doubling, and the byte size handed to `allocate` are each computed with an explicit wraparound
  test. A wrapped count previously would have reported success for a request larger than the address
  space; a successful reserve, a no-op reserve, and a representable `OutOfMemory` are unchanged.
- `Arena.allocate` now returns `Err(AllocError.BadAlignment)` for an invalid alignment instead of
  accepting it: a non-power-of-two `align` used to produce a misaligned `Ok(Handle)` and `align = 0`
  trapped on a modulo by zero before any `Result` existed. A rejection leaves the bump cursor
  untouched; valid powers of two and the `OutOfMemory` path are unchanged.
- AArch64, RISC-V64 and WebAssembly no longer destroy the neighbouring narrow field when a field of a
  fixed-array element held in a struct field is written: the array literal is materialized at the
  element's byte-precise layout instead of one machine word per field. x86_64 was already correct.
- `HashMap(str, V)` now compiles and keys by string CONTENT: the structural `hash` derive gained the
  `Str` case it was missing (it fell through to a scalar conversion and refused the two-word view), and
  a `str` key parameter inside a monomorphized container instance now resolves its comptime type
  argument instead of being rejected. Equal-content views in distinct allocations are one key, through
  `insert`/`get`/`contains`/`remove` and across a rehash.
- AArch64 now emits module-qualified labels for named non-generic functions and direct qualified calls while preserving exact `@extern`/`@export` symbols.
- Aggregate bitcasts now reject packed records with unequal exact byte widths instead of accepting representations that only share a rounded machine-word count.
- Equal-width enum-to-enum `bitcast` bound to a local now preserves the discriminant and every
  payload word on x86_64 instead of copying the discriminant alone over a zeroed payload; unequal
  bit widths and non-variable sources are rejected with a located diagnostic.
- Aggregate `Slice(T)` parameter recovery now uses the complete source buffer instead of a fixed
  512-byte lookahead, so valid aggregate Slice field access beyond that boundary is recovered on
  x86_64 while unsupported non-x86 aggregate lowering remains fail-loud.
- `Result`/`Option` values can no longer be implicitly treated as their payload in explicitly
  annotated local bindings; invalid direct and inferred-local assignments now fail with located diagnostics.
- Semantic checking now rejects a wrong-typed value assigned through a fixed array of structs held in a struct field; deeper and pointer/slice-derived place paths remain separate work.
- Fixed runtime comparison conditions for materialized typed `comptime` `u64` locals so high-bit values
  use unsigned ordering while signed `i64` and ordinary runtime `u64` comparisons retain their paths.
- Fixed closed `comptime if` comparisons over typed high-bit `u64` values so branch selection uses
  unsigned ordering while signed `i64` controls retain signed ordering.
- Duplicate enum discriminants are now rejected by `check` on every target, instead of only by the
  x86_64 lower — the three non-x86 backends previously accepted and ran such a program.
- `CharIter` now bounds-checks its backing view in checked mode and rejects malformed UTF-8 instead of reading past the view or producing an out-of-range code point.
- Direct nested fixed-array parameters are now rejected with one located diagnostic before their malformed parameter ABI can reach lowering; full nested-array parameter support remains a follow-up.
- Fixed x86_64 silent wrong values when an inferred pointer's pointee type lies beyond the old
  512-byte source-recovery window; the scan is now bounded by the actual source-buffer length.
- Direct equal-width aggregate bitcasts used as small struct return values now preserve the source
  words instead of silently returning zero values on x86_64.
- `std::os::args` now reads the complete NUL-separated process command line, growing its arena-backed
  buffer instead of silently dropping arguments beyond the initial 64 KiB chunk.
- Unsupported `comptime if` codegen rejections now retain their source location through transparent `unchecked` conditions in multi-file builds without changing rejection semantics.
- Direct struct-field and explicitly typed local fixed-array-element assignments now enforce the
  declared destination type, rejecting silent `str`/`bool`-to-integer stores with located diagnostics.
- Direct user-defined brands now retain their nominal identity during semantic type resolution, so
  distinct brands with the same underlying layout are not treated as the same semantic type.
- `alatyr build --verbose` / `-v` now reports the selected manifest, profile, target, modules, and
  assemble/link outputs on stderr without changing the build artifact or machine-readable stdout.
- x86_64/Linux/ELF package targets with `Kind.shared_lib` now build a `lib<base>.so` artifact with
  the package's `pub`/`@export` surface and no executable entry point.
- Multi-target `plan` and `build --plan --target all` now emit one deterministic, target-qualified
  `plan.tsv` beside each selected target's artifacts.
- Direct builtin scalar conversions of named user aggregates without an in-scope `@convert` now
  fail at compile time with a located diagnostic on every backend instead of emitting an invalid
  aggregate-as-scalar conversion.
- Direct builtin scalar conversions of exact two-word tuple locals without an in-scope `@convert` now
  fail at compile time with the same located diagnostic instead of silently reading tuple word zero.
- The shared `ast` source recovery (assignment form, compound operator, declared type, no-initializer
  form) and the parser's no-initializer twin now scan to the published source extent instead of a
  fixed 512-byte window past the name. An assignment separated from its operator by a longer
  whitespace run stays an assignment for `sema`, `lower` and `fmt` alike and formatting preserves all
  eight compound spellings; a typed no-initializer local keeps its declared type, so a fixed-array
  local no longer collapses to one scalar word and read the wrong element; and a long declaration no
  longer absorbs the following statement or refuses the file. Every read in that recovery is
  bounds-checked against the source buffer instead of relying on allocator zero-fill.
- `alatyr build --quiet` / `-q` now suppresses the optional success summary while preserving the
  artifact, stdout, and exit status.
- Successful manifest-driven builds now print a deterministic profile, target and artifact summary to
  stderr while leaving stdout available for machine-readable output.
- The bounded scalar `comptime` binding slice now supports closed integer, boolean, and nullary
  user-enum values, while runtime-dependent initializers and unsafe rebinding cases fail loudly.
- WAT now materializes the bounded local scalar `comptime` slice, including literal values and
  `comptime if` conditions, instead of trapping on those programs.
- Unrecognised CLI commands and flags now produce invocation-level Config diagnostics naming the
  offending argument instead of a missing-source-file failure.
- Package setup failures now produce located Config diagnostics: `new` reports an occupied destination
  or missing name, and an explicitly empty `Package.source_dir` is rejected before codegen or linking.
- x86_64/Linux now supports direct code-point `jmp(label)` transfers to named `@label(name)` instructions inside `unchecked` scopes.
- The compiler now reports a controlled arena-initialization failure when an internal `mmap` fails,
  instead of dereferencing the kernel's negative errno result.
- `std::os::arena` now returns `Result(OsArena, IoError)` and maps zero-length and failed
  `mmap` requests before constructing an owning pointer.
- `alatyr fmt` now preserves bare `comptime match` expression arms and keeps the formatted source
  idempotent.
- `alatyr fmt` now preserves multi-segment qualified function return types and their following bodies.
- Ordinary source can no longer construct manifest-only `Package` or `Target` values; `check` and
  `build` now reject them with a located diagnostic.
- Fully comptime-known checked overflow in a direct scalar call argument now produces a located
  compile-time diagnostic before emission instead of compiling and trapping at runtime.
- Fully comptime-known checked overflow in an explicitly typed fixed-array element now produces a
  located compile-time diagnostic before emission instead of compiling and trapping at runtime.
- Declaration-level `when` guards now fold the selected package's `target.kind` and `target.code_size`
  consistently in `check` and `build`, excluding inactive duplicate declarations before name resolution.
- `alatyr fmt` now preserves and canonically emits valid `embed("path")` expressions without
  changing the embedded file bytes.
- Direct multidimensional fixed-array fields now fail loudly with a located diagnostic instead of
  compiling to a wrong value on nested indexing.
- Qualified reads of private module constants now report a located visibility diagnostic instead of
  the generic `invalid` message.
- `check` now agrees with `build` when rejecting direct multidimensional fixed-array fields.
- Unified sub-word scalar-width classification across parsing, formatting, lower layout, and WAT so
  `bits8`/`bits16`/`bits32` pointer casts preserve their intended width and format safely.
- Fixed silent wrong values when equal-width bitcasts target narrow signed, unsigned, or raw scalar
  types by preserving their low-width representation and canonicalizing the machine word on every
  backend.
- The pointee of a `ptr( [mut] T )` bitcast target is now recovered by one bounded, spacing-tolerant
  parse shared by every backend, so the permitted token spacing inside `ptr( … )` no longer widens a
  sub-word `deref` to a full machine word; the generic type-argument scan that feeds it is bounded by
  the published source extent instead of running past the buffer.
- Fixed ordinary scalar-field structs to use natural byte alignment, padding, and field offsets instead of one machine word per field.
- Fixed x86_64 silent wrong values when indexing arrays of narrow scalar structs by sharing the byte stride between literal initialization and indexed places.
- Fixed x86_64 wrong values when indexing a byte slice stored in a struct field by preserving its byte stride and data pointer.
- Fixed x86_64 silent wrong values when reading narrow fields through `Slice(struct)` elements.
- Fixed public `Option` helpers for niche-folded `Option(ptr(T))` values so they inspect the
  pointer-width representation instead of a two-word discriminant/payload layout.
- Fixed niche-folded `Option(ptr(str))` matches so payload bindings retain the pointee's two-word
  `str` view metadata.
- Fixed `run` so profile-looking program arguments after `--` cannot change the selected build profile.
- Fixed silent wrong values when indexing an ordinary byte array through a pointer-derived struct
  field on x86_64.
- Fixed x86_64 wrong matches and aggregate-call crashes for enum elements selected from struct array
  fields; unsupported pointer-derived and packed/byte-layout roots remain fail-loud.
- Statically known out-of-range indexes into fixed arrays now reject at compile time, including every
  index into `[T; 0]`, before any backend emits code.
- Made unsupported live `str`/view operands fail loudly instead of silently becoming an empty pair.
- Package targets with a non-default entry now reject unresolved declaration paths before invoking the linker.
- Made non-x86 entry exclusion explicit so backend wrappers cannot collide with a source `_start`.
- Fixed path dependencies whose source tree contains `lib/`: their modules now retain the dependency
  alias instead of being mistaken for ambient standard-library modules.
- Fixed qualified function-value aliases through nested module paths so direct calls resolve to the
  defining function instead of an undefined importing-module symbol.
- One-element listed projections after a bare module alias now parse as module imports.
- AArch64 now supports scalar nested field access through inferred homogeneous struct-array locals
  with runtime indices.
- RV64 now passes monomorphized `Slice(u64)` views to generic indexed writes without trapping.
- AArch64 now supports whole aggregate-element writes through inferred homogeneous struct-array locals
  with runtime indices.
- AArch64 and RV64 now compare concrete payload-less enum locals with `==` and `!=`.
- WAT now supports labeled `continue name` across statement-only `loop`, `while`, and `for` targets,
  including deferred cleanup for loops crossed by the transfer.
- WAT now supports `continue name` to a scalar-integer value-bearing `@label(name) loop`, including
  LIFO deferred cleanup across nested statement-only loops; unsupported value-loop result shapes remain
  fail-loud.
- WAT now rejects aggregate comptime-field projections loudly instead of loading an aggregate address
  as a scalar value.
- Explicit standard-byte tuple globals now reject before backend emission with a located diagnostic
  instead of reaching the unsupported word-based global representation.
- Immutable module-level aggregate initializers that call at runtime now reject before backend emission
  with a located diagnostic instead of silently becoming zero-initialized static storage.
- Undeclared bare type names used by package nested-module type builtins now reject with a located
  diagnostic before backend emission instead of silently producing a wrong layout-dependent value.
- Unknown bare nominal types in function signatures now reject with a located diagnostic before
  body checking or backend emission instead of silently taking scalar layout and ABI.
- Sema diagnostics for unbound names in compound expressions now report the offending expression's
  line instead of the enclosing declaration's line.
- Indexing a `str` element of a fixed `[str; N]` array (`arr[k][j]`) now reads the byte at offset `j`
  of the selected element. The form compiled cleanly and returned a word of the frame prologue
  instead: the result depended on neither the array, the outer index, nor the string bytes, so
  `arr[0][j]` and `arr[1][j]` were byte-identical and `["abc", "XYZ"]` answered `5` for both
  `arr[0][2]` and `arr[1][2]` where `99` and `90` were due. The same read through a typed
  `Slice(str)` view (`s[k][j]`) is fixed with it, a non-constant outer or inner index works, and an
  out-of-range byte index now traps against that element's runtime length like every other checked
  index. `str` is `[u8]`, so the value is a BYTE, not a code point. x86_64 only; aarch64, riscv64 and
  wasm do not lower this shape and continue to stop loudly on it. Indexing a string LITERAL directly
  is a separate defect and is unchanged here.

First public release in preparation. Nothing is tagged yet; the entries below start once it is.

Entries are added by the change that causes them, in its own commit — not gathered from the log at
release time, which is archaeology and gets the "would a user notice this" judgement wrong once the
measurement is a month old. `CONTRIBUTING.md` states it as a rule and the pull-request template
carries the box.

Where the current state actually stands is the open
[issues](https://github.com/alatyr-programming-language/compiler/issues), honestly and in detail —
including the open silent-wrong-value classes, the cross-backend coverage numbers, and what "ready"
would still require. Read those rather than inferring status from this file's emptiness.
