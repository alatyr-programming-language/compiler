## `bool` — a truth value, a prelude **brand** over `bits8` (D24/D25: the kernel
## keeps no built-in boolean type; `bool` is a prelude type over a raw byte).
## `true`/`false` are its values; `==`/`<`/`and`/`or`/`not` and every comparison
## yield it.
bool := brand(bits8)
