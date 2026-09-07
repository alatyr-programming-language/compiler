## Issue #507 CONTROL — tail-expression position, a bare `vv.ek` as the function result. Already
## refused by the parent with the located name-resolution diagnostic; it must keep exactly that
## message class after the fix. Green on BOTH sides of the change.
Rec := struct { ek : u64 }
user := fn(x : u64) -> u64 { vv.ek }
main := fn() -> u64 { 40 + user(2) }
