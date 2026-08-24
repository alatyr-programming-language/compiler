## alloc::omap — an ORDERED MAP over an arena: two PARALLEL sorted arrays (keys + values) kept in
## ascending KEY order per a caller-supplied `less : fn(a, b) -> bool` on the key (the same shape
## `oset`/`base::slice::sort_by` take), so no `Ord` bound / trait system is needed and any key type with a
## strict-weak order works. O(log n) lookup (binary search on keys), O(n) insert (shift both tails). A
## duplicate key OVERWRITES its value (a map, not a multimap). Iterate in sorted-key order via
## `omap_keys` / `omap_values`. Handle-based like `alloc::vec` (stores the two backing ARENA INDICES,
## resolved per access) and `@owning` (D86 — a linear handle, its backing reclaimed with the arena).
##
## Growth copies each array BYTE-BY-BYTE into a fresh block (like `oset_grow`), so the value copy never
## routes through an aggregate move — the doubling preserves every key AND value. Names are `omap_*` so
## the map co-injects with vec/oset/deque without a same-name overload collision.

pub OMap := fn(K : type, V : type) -> type {
  @owning struct { kidx : usize, vidx : usize, len : usize, cap : usize, arena : ptr(mut Arena) }
}

## A new empty `OMap(K, V)` with room for `cap` pairs (`cap >= 1`), backed by arena `a`. Allocates two
## parallel blocks (keys, values); both start empty.
pub omap := fn(K : type, V : type, a : ptr(mut Arena), cap : usize) -> OMap(K, V) {
  c : usize = if cap > 0 { cap } else { 1 }
  kidx := allocate(deref(a), K, c * size(K), align(K)).expect("omap: allocator out of memory").idx
  vidx := allocate(deref(a), V, c * size(V), align(V)).expect("omap: allocator out of memory").idx
  OMap(K, V)(kidx = kidx, vidx = vidx, len = 0, cap = c, arena = a)
}

pub omap_len := fn(K : type, V : type, m : ptr(OMap(K, V))) -> usize { return deref(m).len }
pub omap_is_empty := fn(K : type, V : type, m : ptr(OMap(K, V))) -> bool { return deref(m).len == 0 }

## Byte address of KEY `i` (caller guarantees `i < cap`).
omap_key_elem := fn(K : type, V : type, m : ptr(OMap(K, V)), i : usize) -> ptr(mut K) {
  mm := deref(m)
  ab := deref(mm.arena)
  base := alloc::get(K, ab, Handle(K)(idx = mm.kidx))
  base_int := unchecked bitcast(usize, base)
  unchecked bitcast(ptr(mut K), base_int + i * size(K))
}

## Byte address of VALUE `i` (caller guarantees `i < cap`).
omap_val_elem := fn(K : type, V : type, m : ptr(OMap(K, V)), i : usize) -> ptr(mut V) {
  mm := deref(m)
  ab := deref(mm.arena)
  base := alloc::get(V, ab, Handle(V)(idx = mm.vidx))
  base_int := unchecked bitcast(usize, base)
  unchecked bitcast(ptr(mut V), base_int + i * size(V))
}

## The number of keys that compare LESS than `x` (the lower-bound insertion index) — a binary search
## over the sorted key array. `x` belongs at this index; the key there (if any) is `>= x`.
omap_lower_bound := fn(K : type, V : type, m : ptr(OMap(K, V)), x : K, less : fn(a : K, b : K) -> bool) -> usize {
  mut lo : usize = 0
  mut hi : usize = deref(m).len
  while lo < hi {
    mid := lo + (hi - lo) / 2
    e := deref(omap_key_elem(K, V, m, mid))
    if less(e, x) { lo = mid + 1 } else { hi = mid }
  }
  lo
}

## Whether `key` is present (its lower-bound slot holds an EQUAL key — equal iff neither is less than
## the other). O(log n).
pub omap_contains := fn(K : type, V : type, m : ptr(OMap(K, V)), key : K, less : fn(a : K, b : K) -> bool) -> bool {
  i := omap_lower_bound(K, V, m, key, less)
  if i >= deref(m).len { return false }
  e := deref(omap_key_elem(K, V, m, i))
  (not less(e, key)) and (not less(key, e))
}

## Look up `key`; `Some(value)` if present, else `None`. O(log n).
pub omap_get := fn(K : type, V : type, m : ptr(OMap(K, V)), key : K, less : fn(a : K, b : K) -> bool) -> Option(V) {
  i := omap_lower_bound(K, V, m, key, less)
  if i >= deref(m).len { return Option(V).None }
  e := deref(omap_key_elem(K, V, m, i))
  if (not less(e, key)) and (not less(key, e)) {
    ## bind the value to a LOCAL before wrapping — an `Option(V).Some(deref(<call>))` payload (a
    ## deref-of-call directly as the enum-literal argument) delivered 0 in this generic 2-type-param
    ## context; the intermediate local materializes the value into a frame slot first.
    v := deref(omap_val_elem(K, V, m, i))
    return Option(V).Some(v)
  }
  Option(V).None
}

## Grow to `2*cap`, copying the live keys AND values ELEMENT-by-element (a `deref(ptr(K))`/`deref(ptr(V))`
## typed move per element — the width the element type wants, NOT a byte loop) into fresh blocks (order
## preserved — both arrays are contiguous from 0). Word-sized (scalar/ptr) `K`/`V`; a struct element wider
## than one word is a follow-up (the same single-word `deref` limit `oset` has).
omap_grow := fn(K : type, V : type, in out m : OMap(K, V)) -> Result(usize, AllocError) {
  new_cap := m.cap * 2
  nkidx := allocate(deref(m.arena), K, new_cap * size(K), align(K))?.idx
  nvidx := allocate(deref(m.arena), V, new_cap * size(V), align(V))?.idx
  aa := deref(m.arena)
  oldk := unchecked bitcast(usize, alloc::get(K, aa, Handle(K)(idx = m.kidx)))
  newk := unchecked bitcast(usize, alloc::get(K, aa, Handle(K)(idx = nkidx)))
  oldv := unchecked bitcast(usize, alloc::get(V, aa, Handle(V)(idx = m.vidx)))
  newv := unchecked bitcast(usize, alloc::get(V, aa, Handle(V)(idx = nvidx)))
  ksz := size(K)
  vsz := size(V)
  mut i : usize = 0
  while i < m.len {
    ks := unchecked bitcast(ptr(mut K), oldk + i * ksz)
    kd := unchecked bitcast(ptr(mut K), newk + i * ksz)
    deref(kd) = deref(ks)
    vs := unchecked bitcast(ptr(mut V), oldv + i * vsz)
    vd := unchecked bitcast(ptr(mut V), newv + i * vsz)
    deref(vd) = deref(vs)
    i += 1
  }
  m.kidx = nkidx
  m.vidx = nvidx
  m.cap = new_cap
  Result(usize, AllocError).Ok(new_cap)
}

## Insert `key -> value`, keeping the map sorted by key. Returns `Ok(true)` if a NEW key was added,
## `Ok(false)` if an existing key's value was OVERWRITTEN. O(n) (binary-search the slot, shift both tails
## right one element). The tail shifts are single high-to-low BYTE moves (overlapping-safe), the element-0
## base computed once — the same shape `oset_insert` uses.
pub omap_insert := fn(K : type, V : type, in out m : OMap(K, V), key : K, value : V, less : fn(a : K, b : K) -> bool) -> Result(bool, AllocError) {
  pos := omap_lower_bound(K, V, ptr(m), key, less)
  if pos < m.len {
    e := deref(omap_key_elem(K, V, ptr(m), pos))
    if (not less(e, key)) and (not less(key, e)) {
      ## key already present — overwrite its value in place, len unchanged.
      slot := omap_val_elem(K, V, ptr(m), pos)
      deref(slot) = value
      return Result(bool, AllocError).Ok(false)
    }
  }
  if m.len >= m.cap { omap_grow(K, V, m)? }
  ## shift keys AND values [pos, len) right by one ELEMENT, high-to-low so the move never overwrites an
  ## un-copied source. Each step is a typed `deref(ptr(K))`/`deref(ptr(V))` element move (the width the
  ## element type wants — never a byte loop that would spill past the element into the neighbouring array).
  ## Bases computed once (a per-element `get` in the loop would re-resolve the handle each step).
  ksz := size(K)
  vsz := size(V)
  kbase := unchecked bitcast(usize, omap_key_elem(K, V, ptr(m), 0))
  vbase := unchecked bitcast(usize, omap_val_elem(K, V, ptr(m), 0))
  mut i : usize = m.len
  while i > pos {
    i -= 1
    ks := unchecked bitcast(ptr(mut K), kbase + i * ksz)
    kd := unchecked bitcast(ptr(mut K), kbase + (i + 1) * ksz)
    deref(kd) = deref(ks)
    vs := unchecked bitcast(ptr(mut V), vbase + i * vsz)
    vd := unchecked bitcast(ptr(mut V), vbase + (i + 1) * vsz)
    deref(vd) = deref(vs)
  }
  kslot := unchecked bitcast(ptr(mut K), kbase + pos * ksz)
  deref(kslot) = key
  vslot := unchecked bitcast(ptr(mut V), vbase + pos * vsz)
  deref(vslot) = value
  m.len += 1
  Result(bool, AllocError).Ok(true)
}

## The sorted KEYS as a borrowed `Slice(K)` view (ascending). Aliases the backing; valid while the map is
## unmodified. Non-consuming.
pub omap_keys := fn(K : type, V : type, m : ptr(OMap(K, V))) -> Slice(K) {
  mm := deref(m)
  base := alloc::get(K, deref(mm.arena), Handle(K)(idx = mm.kidx))
  Slice(K)(ptr = unchecked bitcast(ptr(K), bitcast(usize, base)), len = mm.len)
}

## The VALUES in sorted-KEY order as a borrowed `Slice(V)` view. Parallel to `omap_keys` (value `i`
## belongs to key `i`). Aliases the backing; valid while the map is unmodified. Non-consuming.
pub omap_values := fn(K : type, V : type, m : ptr(OMap(K, V))) -> Slice(V) {
  mm := deref(m)
  base := alloc::get(V, deref(mm.arena), Handle(V)(idx = mm.vidx))
  Slice(V)(ptr = unchecked bitcast(ptr(V), bitcast(usize, base)), len = mm.len)
}

## Release: consume the linear handle (the arena backing is reclaimed with the arena).
pub free := fn(K : type, V : type, m : OMap(K, V)) -> isize { 0 }
