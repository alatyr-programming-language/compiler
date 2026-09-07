## Issue #507 CONTROL — a bare undeclared name as the WHOLE `if` condition. This one the parent
## ALREADY refused, with the located name-resolution diagnostic; it is here so the fix is measured
## against a position that must keep exactly that message class rather than drift to the compound
## one. Green on BOTH sides of the change.
main := fn() -> u64 { if vv { return 1 }  7 }
