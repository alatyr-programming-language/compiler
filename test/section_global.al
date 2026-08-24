## e2e — §4 @section: a mutable global with an explicit @section("name") placement attribute is
## emitted under `.section .mydata` instead of the derived `.data` (Memory §2.3), but reads/writes
## exactly as a normal global (the section directive only changes placement). Returns X = 42.
@section(".mydata") mut X := 42
main := fn() -> u64 { X }
