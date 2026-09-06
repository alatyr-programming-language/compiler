## Issue #429 (Memory §3.1/§3.3 · Types §7) — the same write with the binding declared `mut`.
## Mutability is a write permission on the PATH, and the AND rule takes a dereference step's
## permission from the POINTEE, not from the name: `mut` moves the binding (a whole-view
## reassignment stays legal), never the bytes it points at. The bytes of a `"..."` literal are
## initialized immutable static data (`.rodata`, Memory §2.3), so this is a reject too, and for
## a reason the `immutable binding` wording would state wrongly — the binding here IS mutable.
##
## Measured on the parent (d18fb3f): built clean, x86_64 exit 139 (SIGSEGV).
main := fn() -> u64 {
  mut s := "abc"
  s[0] = 65
  7
}
