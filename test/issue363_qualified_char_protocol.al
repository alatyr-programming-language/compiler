## e2e — Issue #363 / Stdlib appendix §3.6 + §2.4 + Modules §3: the code-point iterator §3.6 names
## must be reachable through the QUALIFIED path from a module that is not a descendant of
## `base::str`. §3.6 lists `chars(in self) -> CharIter   # iterate code points (Iterator, §2.4)`,
## §2.4 makes the returned type an iterator through `next(in out self) -> Opt` (and iterable through
## `iter(in self) -> I`), and Modules §3 fixes the external surface as exactly the
## pub-chain-to-root-reachable one.
##
## Failure-first on parent 61ca2c2 (x86_64, default build path): `base::str::chars` is `pub`, but
## the qualified `base::str::iter` at line 26 is rejected with `alatyr: check: invalid at line 26 in
## issue363_qualified_char_protocol`.
## The CharIter overloads of `iter`/`next` were already `pub` there — the private `SplitIter`
## overloads of the SAME two names in the SAME module were what failed the visibility test, because
## `sema_vis_pair` (`src/sema.al`) reports a violation when ANY same-name, same-module declaration is
## invisible, not when every candidate is. Measured in three lib variants on that same parent
## compiler binary: neither `SplitIter` marker → rejected at the `iter` line; `iter` published only
## → the rejection MOVES to the `next` line (30); both published → this program builds and answers 42.
##
## Not a duplicate of `test/package/issue363_chariter_public`: that consumer qualifies only `chars`
## and takes `iter`/`next` unqualified, which is the spelling #403 shows never applies a `pub` test
## at all, so it could not see this. Each rejection code below is distinct and < 126.

main := fn() -> u64 {
  s := "Aé€😀"                       ## 1-, 2-, 3- and 4-byte encodings; 4 code points in 10 bytes
  mut cursor : CharIter = base::str::chars(s)

  copy := base::str::iter(cursor)     ## §2.4 iterable — the identity, qualified
  if copy.pos != 0 { return 1 }
  if copy.len != 10 { return 2 }

  c0 := unwrap(char, base::str::next(cursor))    ## §2.4 iterator — qualified
  if u32(c0) != 65 { return 3 }
  if cursor.pos != 1 { return 4 }
  c1 := unwrap(char, base::str::next(cursor))
  if u32(c1) != 233 { return 5 }
  if cursor.pos != 3 { return 6 }
  c2 := unwrap(char, base::str::next(cursor))
  if u32(c2) != 8364 { return 7 }
  if cursor.pos != 6 { return 8 }
  c3 := unwrap(char, base::str::next(cursor))
  if u32(c3) != 128512 { return 9 }
  if cursor.pos != 10 { return 10 }

  match base::str::next(cursor) {                ## exhausted — absent, not a fifth code point
    Option::Some(x) => { return 11 }
    Option::None => { }
  }
  42
}
