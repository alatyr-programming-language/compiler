## e2e (for-over-iterable over a BYTE slice — `for c in bytes(s)`). `bytes(s)` is a non-var str-view
## yielding a `Slice(u8)` (byte elements, stride 1). The iterable loop read every element at word
## stride 8 (garbage for bytes); combined with the non-var gap it did not iterate at all. Now the
## non-var iterable is materialized into the {ptr,len} temp and, when the iterable is a `bytes(…)`
## call, each element is read with `movzbq` at stride 1. Sum the bytes of "hello" (104+101+108+108+
## 111 = 532) → 532 - 490 = 42.
main := fn() -> u64 {
  mut s : u64 = 0
  for c in bytes("hello") { s = s + u64(c) }
  s - 490
}
