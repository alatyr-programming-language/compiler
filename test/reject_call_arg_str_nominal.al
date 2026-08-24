## TYP-6 / Types §4.6 — a `str` argument against a NOMINAL struct parameter. §4.6 settles the case a
## user conversion-constructor might otherwise seem to rescue: "a `@convert` fires **only** through an
## explicit `T(v)`; it is never an implicit conversion (only **widen** is implicit, §4.3)". So no
## in-scope `@convert` makes `f("nope")` conforming — `f(S("nope"))` is the spelling that does.
S := struct { a : u64 }

f := fn(s : S) -> u64 { return s.a }

main := fn() -> u64 { return f("nope") }
