## Issue #1065: a comparison over two of the author's own types resolves to the author's `eq`.
##
## Stdlib appendix §2.6 and Memory §4.5 (MEM-10): a comparison site resolves over its operand pair, and a
## heterogeneous pair `A × B` is declared by a concrete `eq(in a : A, in b : B) -> bool`. So `a == b`
## below calls `eq`, which answers true for v = w + 1, and the program returns 42.
##
## Measured on x86_64 at 2cf60b45: it returns 1. The comparison arm in sema decides by `ty_eq` over the
## operand kinds (both are structs), never looks the declared `eq` up, and lowers a structural compare of
## 42 against 41. A silent wrong value, not a refusal.
##
## The deviation on each backend is a row of scripts/known-deviations.tsv naming #1065.
A := struct { v : u64 }
B := struct { w : u64 }
eq := fn(in a : A, in b : B) -> bool { return a.v == b.w + 1 }
main := fn() -> u64 {
  a := A(v = 42)
  b := B(w = 41)
  if a == b { return 42 }
  return 1
}
## expect: run 42
