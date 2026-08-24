## std::hashmap — a **generic** `HashMap(K, V)` over OS memory (open addressing,
## linear probing), keyed by the structural derives `hash(K)` / `eq(K)`
## (base prelude `derive.al`; Stdlib §2.6, Comptime §5). Any `K` that is a
## struct of scalar fields (or a scalar) is a usable key with **no** per-type
## boilerplate — the derive monomorphizes to per-field code.
##
## Allocator-borne (as for `std::vec`): the three regions come from a
## pluggable **`Arena`** (the region protocol), not a direct `mmap`, so a
## compiler can run many maps over one arena it owns and frees in one shot. Fixed
## capacity (it traps if full — resize is a follow-up), so the map does NOT need to
## keep the arena after construction. Layout is **struct of arrays** — parallel
## `used` / `keys` / `vals` regions — so a key/value of any type is stored/loaded
## **by value** through a `ptr(mut K)` / `(mut V)` (the `Vec(T)` element path),
## never as an aggregate field through a pointer.

## { used flags, keys, values, bucket count }. `used[i]`: `0` = empty (an anonymous
## `mmap` is zero-filled), `1` = occupied, `2` = **tombstone** (a removed entry —
## probing skips past it but does not stop, so a later key in the same cluster stays
## findable; `insert` reuses the first tombstone it passes). §160 `remove`.
## `@owning`: a `HashMap` is a linear handle — consumed by `hashmap_free`
## exactly once. **Handle-based (Memory §5.3.1):** it stores the three regions'
## arena **indices** (`Handle` values), NOT pointers — a long-lived reference into an
## arena is a handle (a number, no lifetime problem), resolved to a scoped pointer
## per access by threading the arena (the same discipline as `Buf`). So every op
## takes the arena `in a : Arena`; the scoped pointer the slot helpers form is used
## immediately and never stored. `hashmap_free` takes the map `in` (the consume).
pub HashMap := fn(K : type, V : type) -> type {
  @owning struct {
    used : usize,
    keys : usize,
    vals : usize,
    cap  : usize,
  }
}

## Allocate `n` bytes (aligned to `align`) from arena `a` and return the **handle
## index** (the arena offset), not a pointer. Traps on exhaustion (I11).
arena_alloc := fn(a : ptr(mut Arena), n : usize, align : usize) -> usize {
  allocate(deref(a), u8, n, align).expect("HashMap: allocator out of memory").idx
}

## A new map with `cap` buckets (`cap >= 1`), backed by arena `a`; all buckets start
## empty (the arena's `region` mechanism hands out zeroed `mmap` pages). Stores the
## three regions' handle indices; later ops re-thread the arena to reach them.
hashmap_new := fn(K : type, V : type, a : ptr(mut Arena), cap : usize) -> HashMap(K, V) {
  ub := arena_alloc(a, cap * 8, 8)
  kb := arena_alloc(a, cap * size(K), align(K))
  vb := arena_alloc(a, cap * size(V), align(V))
  HashMap(K, V)(used = ub, keys = kb, vals = vb, cap = cap)
}

## `with_capacity` — canonical v1 constructor name (Stdlib §160), alias of `hashmap_new`.
pub with_capacity := fn(K : type, V : type, a : ptr(mut Arena), cap : usize) -> HashMap(K, V) {
  hashmap_new(K, V, a, cap)
}

## `new` — the **basic** constructor: an empty map backed by arena `a`, with a small
## default bucket count (it grows on `insert`). The stutter-free everyday name (Stdlib
## §160); reach for `with_capacity` when the entry count is known, to avoid rehashing.
pub new := fn(K : type, V : type, a : ptr(mut Arena)) -> HashMap(K, V) {
  hashmap_new(K, V, a, 8)
}

## Address of bucket `i`'s used-flag / key / value slot: the arena base plus the
## region's stored handle index plus the in-region offset (`arena.base + region +
## i·stride`). The arena is threaded in (`in a : Arena`); the returned scoped
## pointer is used immediately by the caller, never stored (§5.3.1).
used_at := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena, i : usize) -> ptr(mut u64) {
  base := unchecked bitcast(usize, a.base) + deref(m).used + i * 8
  unchecked bitcast(ptr(mut u64), base)
}
key_at := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena, i : usize) -> ptr(mut K) {
  base := unchecked bitcast(usize, a.base) + deref(m).keys + i * size(K)
  unchecked bitcast(ptr(mut K), base)
}
val_at := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena, i : usize) -> ptr(mut V) {
  base := unchecked bitcast(usize, a.base) + deref(m).vals + i * size(V)
  unchecked bitcast(ptr(mut V), base)
}

## The live-entry count, scanning the used-flags (counts only occupied = 1, not
## tombstones). A non-consuming scoped read — used by `insert` to decide growth.
occupied := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena) -> usize {
  mut n : usize = 0
  mut j : usize = 0
  while j < deref(m).cap {
    if deref(used_at(K, V, m, a, j)) == 1 { n = n + 1 }
    j += 1
  }
  n
}

## Grow to `new_cap` buckets and **rehash** the live entries into the fresh regions
## (linear-probing placement, tombstones dropped — only occupied slots migrate).
## Allocates the three new regions from the arena (fallible — `AllocError` on
## exhaustion), re-stores their handle indices, and updates `cap`. The old
## regions are left to the arena's bulk reclaim (the standard arena trade-off).
rehash := fn(K : type, V : type, m : ptr(mut HashMap(K, V)), in out a : Arena, new_cap : usize) -> Result(usize, AllocError) {
  old_cap := deref(m).cap
  old_used := deref(m).used
  old_keys := deref(m).keys
  old_vals := deref(m).vals
  abase := unchecked bitcast(usize, a.base)
  ## Allocate the three new regions from the **real** arena (`a` is `in out`, so the
  ## bump cursor advances in the caller's arena, not a copy) — bytes, like
  ## `arena_alloc`; the handle index is a byte offset. OOM propagates as `AllocError`.
  nu := allocate(a, u8, new_cap * 8, 8)?.idx
  nk := allocate(a, u8, new_cap * size(K), align(K))?.idx
  nv := allocate(a, u8, new_cap * size(V), align(V))?.idx
  ## Point the map at the (zeroed) new regions, then re-insert each live old entry.
  deref(m).used = nu
  deref(m).keys = nk
  deref(m).vals = nv
  deref(m).cap = new_cap
  mut s : usize = 0
  while s < old_cap {
    ou := unchecked bitcast(ptr(mut u64), abase + old_used + s * 8)
    if deref(ou) == 1 {
      okp := unchecked bitcast(ptr(mut K), abase + old_keys + s * size(K))
      ovp := unchecked bitcast(ptr(mut V), abase + old_vals + s * size(V))
      k := deref(okp)
      v := deref(ovp)
      ## Comptime §3.3 — `K` is spelled EXPLICITLY here (unlike the `hash(key)` sites below, whose
      ## argument is a parameter declared `key : K`). `k` is a LOCAL bound from `deref(ptr(mut K))`,
      ## and a local's slot carries no type span, so the comptime type argument was NOT inferable:
      ## the call silently took `k` ITSELF for the erased type argument, tagged the instance
      ## `derive__hash__k` and passed NO value at all — `rehash` hashed whatever was in the argument
      ## register. A SILENT wrong value that only shows once a map outgrows its initial capacity,
      ## which no fixture did. The compiler now REJECTS an un-inferable omitted type argument.
      mut i := usize(hash(K, k)) % new_cap
      mut placed : bool = false
      while placed == false {
        if deref(used_at(K, V, m, a, i)) == 0 {
          deref(used_at(K, V, m, a, i)) = 1
          deref(key_at(K, V, m, a, i)) = k
          deref(val_at(K, V, m, a, i)) = v
          placed = true
        } else {
          i = (i + 1) % new_cap
        }
      }
    }
    s += 1
  }
  Result(usize, AllocError).Ok(new_cap)
}

## Insert or overwrite `key -> value` (linear probing from `hash(key) % cap`),
## returning the **previous** value as `Ok(Some(old))` on overwrite or `Ok(None)`
## on a fresh key (§160). **Grows** when the live load factor would exceed ~75%
## (doubling + rehash, §160) so the table stays fast and a fresh key always finds a
## home; a growth that exhausts the allocator surfaces `AllocError`, it does
## not trap. Borrows the handle by a **scoped reference** (the regions are reached
## through the slot pointers; growth updates the stored indices in place); called
## `m.hashmap_insert(key, value)` via auto-ref.
pub hashmap_insert := fn(K : type, V : type, m : ptr(mut HashMap(K, V)), in out a : Arena, key : K, value : V) -> Result(Option(V), AllocError) {
  ## Grow before inserting a fresh key once the table is ~75% full: a load over 3/4
  ## of capacity degrades linear probing. (`occupied` ignores tombstones — a table
  ## thick with tombstones also rehashes here, reclaiming them.) `a` is `in out` so
  ## a grow's allocation advances the caller's real arena cursor.
  live := occupied(K, V, m, a)
  if (live + 1) * 4 > deref(m).cap * 3 {
    rehash(K, V, m, a, deref(m).cap * 2)?
  }
  mut i := usize(hash(key)) % deref(m).cap
  mut probes : usize = 0
  ## The first tombstone passed (`cap` = none yet, an out-of-range sentinel): a
  ## fresh key is inserted there, reclaiming a removed slot, once we've confirmed
  ## the key is not already present further along the cluster.
  mut tomb := deref(m).cap
  while probes < deref(m).cap {
    u := deref(used_at(K, V, m, a, i))
    if u == 0 {
      slot := if tomb < deref(m).cap { tomb } else { i }
      deref(used_at(K, V, m, a, slot)) = 1
      deref(key_at(K, V, m, a, slot)) = key
      deref(val_at(K, V, m, a, slot)) = value
      return Result(Option(V), AllocError).Ok(Option(V).None)
    }
    if u == 1 {
      existing := deref(key_at(K, V, m, a, i))
      if eq(existing, key) {
        old := deref(val_at(K, V, m, a, i))
        deref(val_at(K, V, m, a, i)) = value
        return Result(Option(V), AllocError).Ok(Option(V).Some(old))
      }
    } else {
      if tomb == deref(m).cap { tomb = i }
    }
    i = (i + 1) % deref(m).cap
    probes += 1
  }
  ## Every bucket occupied or tombstoned: reuse a tombstone if one was seen.
  if tomb < deref(m).cap {
    deref(used_at(K, V, m, a, tomb)) = 1
    deref(key_at(K, V, m, a, tomb)) = key
    deref(val_at(K, V, m, a, tomb)) = value
    return Result(Option(V), AllocError).Ok(Option(V).None)
  }
  Result(Option(V), AllocError).Err(AllocError.OutOfMemory)
}

## The value mapped to `key`, or `None`. A non-consuming scoped-reference read
## (`m.hashmap_get(key)` via auto-ref).
pub hashmap_get := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena, key : K) -> Option(V) {
  mut i := usize(hash(key)) % deref(m).cap
  mut probes : usize = 0
  while probes < deref(m).cap {
    u := deref(used_at(K, V, m, a, i))
    if u == 0 {
      return Option(V).None
    }
    if u == 1 {
      existing := deref(key_at(K, V, m, a, i))
      if eq(existing, key) {
        v := deref(val_at(K, V, m, a, i))
        return Option(V).Some(v)
      }
    }
    i = (i + 1) % deref(m).cap
    probes += 1
  }
  Option(V).None
}

## Whether `key` is present. A non-consuming scoped-reference read.
pub hashmap_contains := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena, key : K) -> bool {
  mut i := usize(hash(key)) % deref(m).cap
  mut probes : usize = 0
  while probes < deref(m).cap {
    u := deref(used_at(K, V, m, a, i))
    if u == 0 {
      return false
    }
    if u == 1 {
      existing := deref(key_at(K, V, m, a, i))
      if eq(existing, key) {
        return true
      }
    }
    i = (i + 1) % deref(m).cap
    probes += 1
  }
  false
}

## `hashmap_remove` — delete `key`'s entry, returning `Some(old)` or `None` if
## absent (§160). Marks the bucket a **tombstone** (`used = 2`) so the cluster's
## probe chain is preserved (`get`/`insert` skip past it; `insert` may reclaim it).
## A non-consuming scoped-reference read of the handle (only the region mutates).
pub hashmap_remove := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena, key : K) -> Option(V) {
  mut i := usize(hash(key)) % deref(m).cap
  mut probes : usize = 0
  while probes < deref(m).cap {
    u := deref(used_at(K, V, m, a, i))
    if u == 0 {
      return Option(V).None
    }
    if u == 1 {
      existing := deref(key_at(K, V, m, a, i))
      if eq(existing, key) {
        old := deref(val_at(K, V, m, a, i))
        deref(used_at(K, V, m, a, i)) = 2
        return Option(V).Some(old)
      }
    }
    i = (i + 1) % deref(m).cap
    probes += 1
  }
  Option(V).None
}

## The number of occupied buckets (§160) — an O(cap) scan of the used-flags
## (the struct-of-arrays layout keeps no separate counter). A non-consuming read.
pub hashmap_len := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena) -> usize {
  mut n : usize = 0
  mut i : usize = 0
  while i < deref(m).cap {
    if deref(used_at(K, V, m, a, i)) == 1 { n = n + 1 }
    i += 1
  }
  n
}

## True when the map holds no entries (§160). A non-consuming read.
pub hashmap_is_empty := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena) -> bool {
  hashmap_len(K, V, m, a) == 0
}

## Remove all entries (§160): clear every bucket's used-flag (the flags gate
## access, so the key/value regions need not be touched); capacity is retained.
pub hashmap_clear := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena) {
  mut i : usize = 0
  while i < deref(m).cap {
    deref(used_at(K, V, m, a, i)) = 0
    i += 1
  }
}

## Canonical v1 names from appendix §160. The implementation-prefixed names above
## remain as compatibility aliases for existing compiler and library code.
pub insert := fn(K : type, V : type, m : ptr(mut HashMap(K, V)), in out a : Arena, key : K, value : V) -> Result(Option(V), AllocError) {
  hashmap_insert(K, V, m, a, key, value)
}

pub get := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena, key : K) -> Option(V) {
  hashmap_get(K, V, m, a, key)
}

pub remove := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena, key : K) -> Option(V) {
  hashmap_remove(K, V, m, a, key)
}

pub contains := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena, key : K) -> bool {
  hashmap_contains(K, V, m, a, key)
}

pub len := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena) -> usize {
  hashmap_len(K, V, m, a)
}

pub is_empty := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena) -> bool {
  hashmap_is_empty(K, V, m, a)
}

pub clear := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena) {
  hashmap_clear(K, V, m, a)
}

## A key/value pair yielded by the map's iterator (§160). v1 has no first-class
## tuple (audit blocker 5), so the Iterator's element is this named pair.
pub Entry := fn(K : type, V : type) -> type { struct { key : K, val : V } }

## The iteration cursor over a `HashMap`'s buckets (§160). It captures the arena's
## **base** and the three region offsets as raw `usize` at iteration start — a flat
## snapshot, so the iterator carries **no scoped reference** (§5.3.1) and `next`
## needs no arena argument. `K`/`V` are carried (unused in the fields) so `next` can
## infer them from the receiver. Plus the bucket count and current index.
pub HashMapIter := fn(K : type, V : type) -> type {
  struct { base : usize, used : usize, keys : usize, vals : usize, cap : usize, i : usize }
}

## `hashmap_iter` — begin iterating the map's **live** entries (§160): `for e in
## m.hashmap_iter(a)` walks the occupied buckets, yielding an `Entry(key, val)`.
## Snapshots the arena base + region offsets now (a raw `usize` view, no scoped
## reference held). A non-consuming scoped-reference read of the map (auto-ref); the
## map and arena must outlive the loop. (Impl name, like `hashmap_insert`; the
## canonical `iter` is the deferred name-rename, as for `insert`/`len`.)
pub hashmap_iter := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena) -> HashMapIter(K, V) {
  base := unchecked bitcast(usize, a.base)
  HashMapIter(K, V)(base = base, used = deref(m).used, keys = deref(m).keys, vals = deref(m).vals, cap = deref(m).cap, i = 0)
}

## Canonical iterator constructor from appendix §160.
pub iter := fn(K : type, V : type, m : ptr(HashMap(K, V)), a : Arena) -> HashMapIter(K, V) {
  hashmap_iter(K, V, m, a)
}

## A `HashMapIter` **is** the iterator — the Iterator protocol's `iter` (identity,
## §2.4): returns a constructor copy (a non-place aggregate), not the place `it`.
iter := fn(K : type, V : type, it : HashMapIter(K, V)) -> HashMapIter(K, V) {
  HashMapIter(K, V)(base = it.base, used = it.used, keys = it.keys, vals = it.vals, cap = it.cap, i = it.i)
}

## The next live entry, then advance past it; `None` once every occupied bucket has
## been yielded (§160). Skips empty (`0`) and tombstone (`2`) buckets, reading the
## key/value through the snapshot's raw region pointers.
next := fn(K : type, V : type, in out it : HashMapIter(K, V)) -> Option(Entry(K, V)) {
  while it.i < it.cap {
    u := deref(unchecked bitcast(ptr(u64), it.base + it.used + it.i * 8))
    if u == 1 {
      kp := unchecked bitcast(ptr(K), it.base + it.keys + it.i * size(K))
      vp := unchecked bitcast(ptr(V), it.base + it.vals + it.i * size(V))
      e := Entry(K, V)(key = deref(kp), val = deref(vp))
      it.i = it.i + 1
      return Option(Entry(K, V)).Some(e)
    }
    it.i = it.i + 1
  }
  Option(Entry(K, V)).None
}

## **Consume** the owning handle (the linear release): the three regions
## belong to the **arena**, not the map, so this no longer `munmap`s — it only
## `forget(m)`s, discharging the consume obligation. The pages are reclaimed when
## the caller frees the arena (`std::os::free`), one shot.
pub hashmap_free := fn(K : type, V : type, m : HashMap(K, V)) {
  forget(m)
}
