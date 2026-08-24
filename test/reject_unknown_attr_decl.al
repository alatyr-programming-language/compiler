## e2e — Declarations §2.3: "An unknown `@name` … is a Semantic diagnostic that names the family."
##
## Before this, the parser's declaration-prefix loop fell through to a bare `pc.idx = pc.idx + 2` for
## every attribute it did not act on: `@bogusattr X := 42` compiled clean and the attribute was
## consumed and DROPPED. A typo'd `@pcked`/`@inlien` therefore declared a property that was silently
## replaced by no property at all. Sema now rejects it, LOCATED at the attribute (line 11).
##
## The judgement lives in sema, not the parser, because the library attribute set is OPEN (CT-10 —
## only the layout machine levers are closed); see `accept_userdef_attr.al` for the neighbouring
## legal shape that must keep passing.
@bogusattr
X : i64 = 42

main := fn() -> i64 {
  return X
}
