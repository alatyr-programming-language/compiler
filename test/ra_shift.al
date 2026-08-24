## e2e — REGALLOC: bit shifts `shl`/`shr` (logical) + `sar` (arithmetic) on the register-allocated
## scalar-leaf IR path. `sh` and `sa` are scalar-leaf (native scalar params + return, only shift
## operation-fns) → the IR path (new opcodes 19=shl, 20=shr, 21=sar rendered `shlq`/`shrq`/`sarq %cl,
## <reg>`, the count pinned to %rcx so %cl is the implicit shift count; a CHECKED shift keeps the
## over-width `cmpq $64,%rcx; jb; ud2` guard). `sh` covers shl(19) + logical shr(20) on u64; `sa`
## covers arithmetic sar(21) on a signed i64. Same exit whether built default (regalloc) or ALATYR_RA=0
## (text). 17<<1 = 34, 17>>1 = 8, 34 + 8 = 42; 84 sar 1 = 42.
sh := fn(a : u64, b : u64) -> u64 { (a.shl(b)) + (a.shr(b)) }
sa := fn(x : i64, n : u64) -> i64 { x.shr(n) }
main := fn() -> u64 {
  q := sa(84, 1)          ## arithmetic sar (op 21): 84 >> 1 = 42
  r := sh(17, 1)          ## shl (op 19) + logical shr (op 20): 34 + 8 = 42
  if u64(q) == r { r } else { 0 }
}
