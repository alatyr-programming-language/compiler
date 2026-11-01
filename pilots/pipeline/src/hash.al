## Hashing one chunk, generating the input, and folding the per-chunk hashes into one number.

## FNV-1a, 64-bit (offset basis and prime from the FNV reference).
FNV_OFFSET : u64 = 0xcbf29ce484222325
FNV_PRIME : u64 = 0x100000001b3

## The FNV-1a hash of `data`, started from the offset basis mixed with `seed`, so that two equal
## chunks at different positions hash differently.
pub fnv1a := fn(seed : u64, data : Slice(u8)) -> u64 {
  mut h : u64 = FNV_OFFSET ^ seed
  for b in data {
    ## blocked-by: #1208 — `(h ^ u64(b)).wrapping_mul(FNV_PRIME)` fails to link, so the operand
    ## is bound to a typed local first.
    x : u64 = h ^ u64(b)
    h = x.wrapping_mul(FNV_PRIME)
  }
  h
}

## One step of xorshift64 (Marsaglia), the input generator. `x` must not be zero.
pub xorshift := fn(x : u64) -> u64 {
  mut s := x
  s = s ^ s.shl(13)
  s = s ^ s.shr(7)
  s = s ^ s.shl(17)
  s
}

## Fold one chunk's hash into the running total. Addition commutes, so the total is the same
## whatever order the workers finish in.
pub fold := fn(total : u64, h : u64) -> u64 {
  total.wrapping_add(h)
}
