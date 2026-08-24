## alloc::deque — a growable double-ended queue (ring buffer) over an arena, Stdlib §3 / Memory §5.3.1.
## Handle-based like `alloc::vec` (stores the backing's arena INDEX, not a pointer — resolved per access
## via `get`). Elements live in a circular buffer: logical element `i` (0-based from the FRONT) sits at
## physical slot `(head + i) mod cap`. Push/pop at either end are O(1); a full buffer doubles (copying
## the elements in logical order into a fresh, linearized block — `head` resets to 0). `@owning` (D86):
## a `Deque(T)` is a linear handle, consumed once (freed by `std::os::free` on its arena).
##
## Names are deliberately distinct from `alloc::vec` (push_back/pop_front… ; dq_len/dq_at) so the two
## containers co-inject without the ≥2-overload same-name routing collision.

pub Deque := fn(T : type) -> type {
  @owning struct { idx : usize, head : usize, len : usize, cap : usize, arena : ptr(mut Arena) }
}

## A new empty `Deque(T)` with room for `cap` elements (`cap >= 1`), backed by arena `a`.
pub deque := fn(T : type, a : ptr(mut Arena), cap : usize) -> Deque(T) {
  c : usize = if cap > 0 { cap } else { 1 }
  idx := allocate(deref(a), T, c * size(T), align(T)).expect("deque: allocator out of memory").idx
  Deque(T)(idx = idx, head = 0, len = 0, cap = c, arena = a)
}

## The element count / emptiness — non-consuming reads.
pub dq_len := fn(T : type, d : ptr(Deque(T))) -> usize { return deref(d).len }
pub dq_is_empty := fn(T : type, d : ptr(Deque(T))) -> bool { return deref(d).len == 0 }

## Physical byte address of logical element `i` (caller guarantees `i < len`).
dq_elem := fn(T : type, d : ptr(Deque(T)), i : usize) -> ptr(mut T) {
  dd := deref(d)
  ab := deref(dd.arena)
  base := alloc::get(T, ab, Handle(T)(idx = dd.idx))
  base_int := unchecked bitcast(usize, base)
  phys := (dd.head + i) - ((dd.head + i) / dd.cap) * dd.cap    ## (head + i) mod cap
  unchecked bitcast(ptr(mut T), base_int + phys * size(T))
}

## Grow to `2*cap`, copying the `len` live elements in LOGICAL order into a fresh block (head → 0).
## Byte-by-byte copy (a whole-aggregate store through a pointer is not lowered; a u8 is) → any `T`.
dq_grow := fn(T : type, in out d : Deque(T)) -> Result(usize, AllocError) {
  new_cap := d.cap * 2
  nidx := allocate(deref(d.arena), T, new_cap * size(T), align(T))?.idx
  aa := deref(d.arena)
  newp := alloc::get(T, aa, Handle(T)(idx = nidx))
  new_int := unchecked bitcast(usize, newp)
  mut i : usize = 0
  while i < d.len {
    srcp := dq_elem(T, ptr(d), i)
    src_int := unchecked bitcast(usize, srcp)
    dst_int := new_int + i * size(T)
    mut k : usize = 0
    while k < size(T) {
      sb := unchecked bitcast(ptr(mut u8), src_int + k)
      db := unchecked bitcast(ptr(mut u8), dst_int + k)
      deref(db) = deref(sb)
      k += 1
    }
    i += 1
  }
  d.idx = nidx
  d.head = 0
  d.cap = new_cap
  Result(usize, AllocError).Ok(new_cap)
}

## Append `x` at the BACK; doubles the ring when full. Fallible (D91).
pub push_back := fn(T : type, in out d : Deque(T), x : T) -> Result(usize, AllocError) {
  if d.len >= d.cap { dq_grow(T, d)? }
  slot := dq_elem(T, ptr(d), d.len)     ## logical index len = one past the back
  deref(slot) = x
  d.len += 1
  Result(usize, AllocError).Ok(d.len)
}

## Prepend `x` at the FRONT; doubles the ring when full. Fallible (D91).
pub push_front := fn(T : type, in out d : Deque(T), x : T) -> Result(usize, AllocError) {
  if d.len >= d.cap { dq_grow(T, d)? }
  d.head = (d.head + d.cap - 1) - ((d.head + d.cap - 1) / d.cap) * d.cap   ## (head - 1) mod cap
  slot := dq_elem(T, ptr(d), 0)
  deref(slot) = x
  d.len += 1
  Result(usize, AllocError).Ok(d.len)
}

## Remove and return the FRONT element, or `None` when empty. O(1); the backing is untouched.
pub pop_front := fn(T : type, in out d : Deque(T)) -> Option(T) {
  if d.len == 0 { return Option(T).None }
  slot := dq_elem(T, ptr(d), 0)
  v := deref(slot)
  d.head = (d.head + 1) - ((d.head + 1) / d.cap) * d.cap    ## (head + 1) mod cap
  d.len = d.len - 1
  Option(T).Some(v)
}

## Remove and return the BACK element, or `None` when empty. O(1).
pub pop_back := fn(T : type, in out d : Deque(T)) -> Option(T) {
  if d.len == 0 { return Option(T).None }
  slot := dq_elem(T, ptr(d), d.len - 1)
  v := deref(slot)
  d.len = d.len - 1
  Option(T).Some(v)
}

## Peek at the FRONT / BACK element without removing it, or `None` when empty.
pub front := fn(T : type, d : ptr(Deque(T))) -> Option(T) {
  if deref(d).len == 0 { return Option(T).None }
  Option(T).Some(deref(dq_elem(T, d, 0)))
}
pub back := fn(T : type, d : ptr(Deque(T))) -> Option(T) {
  n := deref(d).len
  if n == 0 { return Option(T).None }
  Option(T).Some(deref(dq_elem(T, d, n - 1)))
}

## The logical element at `i` from the front as `Some(x)`, or `None` when out of range.
pub dq_at := fn(T : type, d : ptr(Deque(T)), i : usize) -> Option(T) {
  if i >= deref(d).len { return Option(T).None }
  Option(T).Some(deref(dq_elem(T, d, i)))
}

## Release: consume the linear handle (the arena backing is reclaimed when the caller frees the arena).
pub free := fn(T : type, d : Deque(T)) -> isize { 0 }
