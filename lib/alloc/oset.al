## alloc::oset — an ORDERED SET over an arena: a sorted array with O(log n) membership and O(n) insert
## (binary search for the position, shift the tail). Elements are kept in ascending order per a caller-
## supplied comparator `less : fn(a, b) -> bool` (a<b — the same shape `base::slice::sort_by` takes), so
## no `Ord` bound / trait system is needed and any `T` with a strict-weak order works. Duplicates are
## rejected (a SET). Iterate in sorted order via `oset_as_slice`. Handle-based like `alloc::vec`; `@owning`
## (a linear handle, its backing reclaimed when the caller frees the arena). Names are `oset_*` so
## the set co-injects with vec/deque without a same-name overload collision.

pub OSet := fn(T : type) -> type {
  @owning struct { idx : usize, len : usize, cap : usize, arena : ptr(mut Arena) }
}

## A new empty `OSet(T)` with room for `cap` elements (`cap >= 1`), backed by arena `a`.
pub oset := fn(T : type, a : ptr(mut Arena), cap : usize) -> OSet(T) {
  c : usize = if cap > 0 { cap } else { 1 }
  idx := allocate(deref(a), T, c * size(T), align(T)).expect("oset: allocator out of memory").idx
  OSet(T)(idx = idx, len = 0, cap = c, arena = a)
}

pub oset_len := fn(T : type, s : ptr(OSet(T))) -> usize { return deref(s).len }
pub oset_is_empty := fn(T : type, s : ptr(OSet(T))) -> bool { return deref(s).len == 0 }

## Byte address of element `i` (caller guarantees `i < cap`).
oset_elem := fn(T : type, s : ptr(OSet(T)), i : usize) -> ptr(mut T) {
  ss := deref(s)
  ab := deref(ss.arena)
  base := alloc::get(T, ab, Handle(T)(idx = ss.idx))
  base_int := unchecked bitcast(usize, base)
  unchecked bitcast(ptr(mut T), base_int + i * size(T))
}

## The number of elements that compare LESS than `x` (the lower-bound insertion index) — a binary
## search over the sorted backing. `x` belongs at this index; element there (if any) is `>= x`.
oset_lower_bound := fn(T : type, s : ptr(OSet(T)), x : T, less : fn(a : T, b : T) -> bool) -> usize {
  mut lo : usize = 0
  mut hi : usize = deref(s).len
  while lo < hi {
    mid := lo + (hi - lo) / 2
    e := deref(oset_elem(T, s, mid))
    if less(e, x) { lo = mid + 1 } else { hi = mid }
  }
  lo
}

## Whether `x` is present (its lower-bound slot holds an element EQUAL to `x` — equal iff neither is
## less than the other). O(log n).
pub oset_contains := fn(T : type, s : ptr(OSet(T)), x : T, less : fn(a : T, b : T) -> bool) -> bool {
  i := oset_lower_bound(T, s, x, less)
  if i >= deref(s).len { return false }
  e := deref(oset_elem(T, s, i))
  (not less(e, x)) and (not less(x, e))
}

## Grow to `2*cap`, copying the live elements byte-by-byte into a fresh block (order preserved — a
## sorted array is already contiguous from 0). Any `T`.
oset_grow := fn(T : type, in out s : OSet(T)) -> Result(usize, AllocError) {
  new_cap := s.cap * 2
  nidx := allocate(deref(s.arena), T, new_cap * size(T), align(T))?.idx
  aa := deref(s.arena)
  oldp := alloc::get(T, aa, Handle(T)(idx = s.idx))
  newp := alloc::get(T, aa, Handle(T)(idx = nidx))
  old_int := unchecked bitcast(usize, oldp)
  new_int := unchecked bitcast(usize, newp)
  nbytes := s.len * size(T)
  mut k : usize = 0
  while k < nbytes {
    sb := unchecked bitcast(ptr(mut u8), old_int + k)
    db := unchecked bitcast(ptr(mut u8), new_int + k)
    deref(db) = deref(sb)
    k += 1
  }
  s.idx = nidx
  s.cap = new_cap
  Result(usize, AllocError).Ok(new_cap)
}

## Insert `x`, keeping the set sorted and duplicate-free. Returns `true` if it was added, `false` if an
## equal element was already present (a no-op). O(n) (binary-search the slot, shift the tail right one).
pub oset_insert := fn(T : type, in out s : OSet(T), x : T, less : fn(a : T, b : T) -> bool) -> Result(bool, AllocError) {
  pos := oset_lower_bound(T, ptr(s), x, less)
  if pos < s.len {
    e := deref(oset_elem(T, ptr(s), pos))
    if (not less(e, x)) and (not less(x, e)) { return Result(bool, AllocError).Ok(false) }
  }
  if s.len >= s.cap { oset_grow(T, s)? }
  ## shift the tail [pos, len) right by one ELEMENT as a single high-to-low BYTE move (overlapping-safe).
  ## The element-0 base is computed ONCE (a per-element oset_elem in the loop clobbered scratch across
  ## the nested byte copy and mis-shifted); esz = one element's byte size.
  esz := size(T)
  base0 := unchecked bitcast(usize, oset_elem(T, ptr(s), 0))
  lo_byte := pos * esz
  mut b : usize = (s.len - pos) * esz
  while b > 0 {
    b -= 1
    sb := unchecked bitcast(ptr(mut u8), base0 + lo_byte + b)
    db := unchecked bitcast(ptr(mut u8), base0 + lo_byte + esz + b)
    deref(db) = deref(sb)
  }
  slot := unchecked bitcast(ptr(mut T), base0 + lo_byte)
  deref(slot) = x
  s.len += 1
  Result(bool, AllocError).Ok(true)
}

## The sorted elements as a borrowed `Slice(T)` view (ascending) — iterate with `for x in ...`. Aliases
## the backing; valid while the set is unmodified (an insert may move the region). Non-consuming.
pub oset_as_slice := fn(T : type, s : ptr(OSet(T))) -> Slice(T) {
  ss := deref(s)
  base := alloc::get(T, deref(ss.arena), Handle(T)(idx = ss.idx))
  Slice(T)(ptr = unchecked bitcast(ptr(T), bitcast(usize, base)), len = ss.len)
}

## Release: consume the linear handle (the arena backing is reclaimed with the arena).
pub free := fn(T : type, s : OSet(T)) -> isize { 0 }
