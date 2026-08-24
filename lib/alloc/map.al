## std::map — a hash map over OS memory (open addressing, linear probing).
##
## Concrete `u64 -> u64`, fixed-capacity (it traps if full — resize-on-load is a
## follow-up); the generic `HashMap(K, V)` is the typeinfo-driven version.
## **Allocator-borne**: the buckets come from a pluggable `Arena`
## (region protocol), not a direct `mmap`. Each bucket is 3 `u64` slots:
## `[used, key, value]`; the arena's region pages are zero-filled, so every bucket
## starts `used = 0` (empty).

Map := struct { ptr : ptr(mut u64), cap : usize }

## A pointer to bucket `i`'s field `f` (0 = used, 1 = key, 2 = value).
slot := fn(m : Map, i : usize, f : usize) -> ptr(mut u64) {
  base := unchecked bitcast(usize, m.ptr)
  off := (i * 3 + f) * 8
  unchecked bitcast(ptr(mut u64), base + off)
}

## A new map with `cap` buckets (`cap >= 1`), backed by arena `a`; all buckets
## start empty (the arena's region pages are zero-filled). Traps on exhaustion.
pub map_new := fn(a : ptr(mut Arena), cap : usize) -> Map {
  idx := allocate(deref(a), u8, cap * 24, 8).expect("std::map: allocator out of memory").idx
  aa := deref(a)
  ## Resolve the handle to a pointer from the arena base directly (this module
  ## defines its own `get` for map lookup, which would shadow `alloc::get`).
  base_int := unchecked bitcast(usize, aa.base) + idx
  base := unchecked bitcast(ptr(mut u64), base_int)
  Map(ptr = base, cap = cap)
}

## Insert or overwrite `key -> value` (linear probing from `key % cap`). Traps if
## the map is full. Takes the map **by value**: it mutates the shared backing
## *heap* through `m.ptr`, not the `{ptr, cap}` handle (fixed capacity — resize,
## which would mutate the handle, needs `in out` and is a follow-up).
pub insert := fn(m : Map, key : u64, value : u64) {
  mut i : usize = key % m.cap
  mut probes : usize = 0
  while probes < m.cap {
    if deref(slot(m, i, 0)) == 0 {
      deref(slot(m, i, 0)) = 1
      deref(slot(m, i, 1)) = key
      deref(slot(m, i, 2)) = value
      return
    }
    if deref(slot(m, i, 1)) == key {
      deref(slot(m, i, 2)) = value
      return
    }
    i = (i + 1) % m.cap
    probes += 1
  }
  panic("std::map: insert into a full map")
}

## Look up `key`; `Some(value)` if present, else `None`.
pub get := fn(m : Map, key : u64) -> Option(u64) {
  mut i : usize = key % m.cap
  mut probes : usize = 0
  while probes < m.cap {
    if deref(slot(m, i, 0)) == 0 {
      return Option(u64).None
    }
    if deref(slot(m, i, 1)) == key {
      return Option(u64).Some(deref(slot(m, i, 2)))
    }
    i = (i + 1) % m.cap
    probes += 1
  }
  Option(u64).None
}

## Whether `key` is present (linear probing).
pub contains := fn(m : Map, key : u64) -> bool {
  mut i : usize = key % m.cap
  mut probes : usize = 0
  while probes < m.cap {
    if deref(slot(m, i, 0)) == 0 {
      return false
    }
    if deref(slot(m, i, 1)) == key {
      return true
    }
    i = (i + 1) % m.cap
    probes += 1
  }
  false
}

## A **no-op** now: the backing pages belong to the **arena**, reclaimed in one
## shot when the caller frees it (`std::os::free`). Kept for API compatibility.
pub map_free := fn(m : Map) -> isize {
  0
}
