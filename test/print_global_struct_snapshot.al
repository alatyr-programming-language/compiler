## e2e — printing a mutable struct GLOBAL via a local snapshot (`p := S; print("{}", p)`). Passing the
## global itself by-ref would misread fields (its `.data` is ascending; the by-ref ABI is down-growing),
## so the supported path copies it into a down-growing local first. block_decl_type resolves p's type
## from the global's struct name. Prints "S { x = 40, y = 2 }" (verified) and returns 42.
Pt := struct { x : u64, y : u64 }
mut S := Pt(x = 40, y = 2)
main := fn() -> u64 {
  p := S
  std::fmt::print("S {}\n", p)
  42
}
