## std::strmap — a hash map with **byte-slice keys** over OS memory (open
## addressing, linear probing).
##
## Concrete `[u8] -> u64`, fixed-capacity (traps if full — resize is a follow-up).
## Keys are compared by **content** (`bytes_eq`) and placed by **content hash**
## (`hash_bytes`), so this is the string/symbol-table capability now — ahead of
## the generic `HashMap(K, V)` (which needs the `Hash`/`Eq` protocols over
## `typeinfo`). A bucket is 4 `u64` slots: `[used, key_ptr, key_len, value]`.
## **Allocator-borne**: the buckets come from a pluggable `Arena`
## (region protocol), not a direct `mmap`; the arena's region pages are
## zero-filled, so every bucket starts `used = 0` (empty).
##
## **Key lifetime:** a bucket stores the key's pointer + length (no copy), so the
## caller must keep each inserted key's bytes alive for the map's lifetime.

StrMap := struct { ptr : ptr(mut u64), cap : usize }

## A pointer to bucket `i`'s `u64` field `f` (0 = used, 3 = value).
slot := fn(m : StrMap, i : usize, f : usize) -> ptr(mut u64) {
  base := unchecked bitcast(usize, m.ptr)
  off := (i * 4 + f) * 8
  unchecked bitcast(ptr(mut u64), base + off)
}

## A pointer to bucket `i`'s **pointer-width** field `f` (1 = key_ptr,
## 2 = key_len) — stored as `usize`, so the key pointer round-trips at the
## native pointer width on every arch (not a fixed `u64`, which would mismatch
## a 32-bit pointer's bit-width on a `bitcast`).
pslot := fn(m : StrMap, i : usize, f : usize) -> ptr(mut usize) {
  base := unchecked bitcast(usize, m.ptr)
  off := (i * 4 + f) * 8
  unchecked bitcast(ptr(mut usize), base + off)
}

## The key stored at bucket `i`, reconstructed as a `[u8]` view over its bytes.
stored_key := fn(m : StrMap, i : usize) -> Slice(u8) {
  kp := deref(pslot(m, i, 1))
  kl := deref(pslot(m, i, 2))
  p := unchecked bitcast(ptr(u8), kp)
  Slice(u8)(ptr = p, len = kl)
}

## A new map with `cap` buckets (`cap >= 1`), backed by arena `a`; all buckets
## start empty (the arena's region pages are zero-filled). Traps on exhaustion.
pub strmap_new := fn(a : ptr(mut Arena), cap : usize) -> StrMap {
  idx := allocate(deref(a), u8, cap * 32, 8).expect("std::strmap: allocator out of memory").idx
  aa := deref(a)
  p := alloc::get(u8, aa, Handle(u8)(idx = idx))
  base := unchecked bitcast(ptr(mut u64), bitcast(usize, p))
  StrMap(ptr = base, cap = cap)
}

## Insert or overwrite `key -> value` (linear probing from `hash_bytes(key) %
## cap`, key compared by content). Traps if the map is full. Stores the key's
## pointer/length, not a copy (see the key-lifetime note above).
pub strmap_insert := fn(m : StrMap, key : Slice(u8), value : u64) {
  h := hash_bytes(key)
  mut i : usize = h % m.cap
  mut probes : usize = 0
  while probes < m.cap {
    if deref(slot(m, i, 0)) == 0 {
      kp := unchecked bitcast(usize, key.ptr)
      deref(slot(m, i, 0)) = 1
      deref(pslot(m, i, 1)) = kp
      deref(pslot(m, i, 2)) = key.len
      deref(slot(m, i, 3)) = value
      return
    }
    sk := stored_key(m, i)
    if bytes_eq(sk, key) {
      deref(slot(m, i, 3)) = value
      return
    }
    i = (i + 1) % m.cap
    probes += 1
  }
  panic("std::strmap: insert into a full map")
}

## Look up `key` by content; `Some(value)` if present, else `None`.
pub strmap_get := fn(m : StrMap, key : Slice(u8)) -> Option(u64) {
  h := hash_bytes(key)
  mut i : usize = h % m.cap
  mut probes : usize = 0
  while probes < m.cap {
    if deref(slot(m, i, 0)) == 0 {
      return Option(u64).None
    }
    sk := stored_key(m, i)
    if bytes_eq(sk, key) {
      return Option(u64).Some(deref(slot(m, i, 3)))
    }
    i = (i + 1) % m.cap
    probes += 1
  }
  Option(u64).None
}

## Whether `key` is present (by content).
pub strmap_contains := fn(m : StrMap, key : Slice(u8)) -> bool {
  h := hash_bytes(key)
  mut i : usize = h % m.cap
  mut probes : usize = 0
  while probes < m.cap {
    if deref(slot(m, i, 0)) == 0 {
      return false
    }
    sk := stored_key(m, i)
    if bytes_eq(sk, key) {
      return true
    }
    i = (i + 1) % m.cap
    probes += 1
  }
  false
}

## A **no-op** now: the backing pages belong to the **arena**, reclaimed in one
## shot when the caller frees it (`std::os::free`). Kept for API compatibility.
pub strmap_free := fn(m : StrMap) -> isize {
  0
}
