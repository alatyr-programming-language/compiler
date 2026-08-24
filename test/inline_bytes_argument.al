## Proposal #3 / Codegen §3.5: inlining must preserve builtin bytes(...) dispatch
## when the builtin result is passed as the concrete Slice(u8) aggregate argument.
## This is the exact codec seam: the body indexes the bytes view, so a module-call
## fallback would either fail to link or lose the byte value. 42.
@inline
head := fn(s : Slice(u8)) -> u8 { s[0] }

main := fn() -> u64 { u64(head(bytes("*"))) }
