## e2e (reject) — `@section("name")` places a static BINDING in a named section (Types §8: "not a
## layout lever … a storage/placement attribute on a binding"; Memory §2.3/§2.4), and Grammar §3.11 /
## CG-6 has `@` decorate a CONSTRUCT and NEVER wrap an expression. So the only legal spelling is the
## declaration prefix `@section(".mydata") mut X := 42` (test/section_global.al). After the `:=` the
## attribute prefixes the VALUE, which has no placement to give — and it used to be consumed and
## dropped without a word, so the binding silently landed in the derived `.data` and no `.section`
## directive was ever emitted. `readelf -S` showed no `.mydata`; nothing said why.
mut X := @section(".mydata") 42
main := fn() -> u64 { X }
