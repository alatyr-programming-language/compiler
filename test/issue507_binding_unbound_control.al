## Issue #507 CONTROL — binding position, `y := vv.ek`. Already refused by the parent with the
## located name-resolution diagnostic; it must keep exactly that message class after the fix.
## Green on BOTH sides of the change.
Rec := struct { ek : u64 }
user := fn(x : u64) -> u64 { y := vv.ek  40 + y }
main := fn() -> u64 { user(2) }
