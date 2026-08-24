## std::channel — a bounded MPMC channel (share-nothing message passing, Concurrency CC-4 path 1).
##
## CC-4 gives three ways to share across threads; this is **path 1** (message passing): a value
## `send`-ed down a channel is conceptually MOVED out of the sender (the spec's linearity checker
## enforces the move at the type level — the library does not re-enforce it), so no two threads ever
## touch the same datum. Provably an ordinary library type over the mechanisms std already ships:
## a `std::sync`-style futex mutex (`atomic::cas_strong` + raw `futex`) guarding a ring buffer, plus
## two futex "condition" words for blocking. No new language entity. x86_64-only in v1 (the futex
## syscall number is Linux), and the element `T` is **word-sized** in v1 (scalar `u64`/`usize`/ptr):
## a slot is read/written with a single scalar load/store, so a multi-word struct `T` — which needs
## the byte-by-byte aggregate copy — is a follow-up (see).
##
## Layout (`Channel(T)`) — all fields are 8-byte scalars, so their offsets are FIXED regardless of
## `T` (the ring elements live OUT of line, in the arena, reached through `data`): this lets `send`/
## `recv` address the lock + the two futex words by `bitcast`ing the channel pointer + a constant
## offset (the `std::sync` idiom), stable across the erased `T`.
##   state @0  (mutex: 0 = free, 1 = locked)   r_seq @8  (not-empty seq; bumped by senders)
##   w_seq @16 (not-full seq; bumped by receivers)   data @24 (ring base ptr)   cap @32
##   head @40   tail @48   count @56   closed @64 (0 = open, 1 = closed — set by `close`)

## Linux `futex(2)` (syscall 202): op 0 = FUTEX_WAIT (sleep while the 32-bit `*uaddr == val`),
## op 1 = FUTEX_WAKE (wake up to `val` waiters). Raw level (I11) — wrapped in `unchecked` at the call.
sys_futex := @abi(syscall) fn(num : usize, uaddr : usize, op : usize, val : usize, timeout : usize, uaddr2 : usize, val3 : usize) -> isize

## Linux `sched_yield(2)` (syscall 24): relinquish the CPU to another runnable thread and return.
## The v1 `select` backoff — a cooperative yield between poll rounds so the loop makes progress and
## does not hard-spin a core while every channel is momentarily empty. Raw level (I11).
sys_sched_yield := @abi(syscall) fn(num : usize) -> isize

## `Channel(T)` — a bounded ring buffer of `cap` `T`s guarded by an embedded futex mutex, with two
## futex sequence words for the blocking handshake. Generic over `T` but layout-invariant (the
## elements are out of line in the arena), like `Handle(T)`.
pub Channel := fn(T : type) -> type {
  struct { state : u64, r_seq : u64, w_seq : u64, data : usize, cap : usize, head : usize, tail : usize, count : usize, closed : u64 }
}

## Acquire the channel's embedded mutex (the `state` word at the channel base). Fast path: CAS
## 0 -> 1 (`atomic::cas_strong`, one `lock cmpxchgq`); on contention futex-wait on `state` until the
## holder wakes us, then retry (a stale/changed word makes the wait return EAGAIN — no lost wakeup).
ch_lock := fn(base : usize) {
  sp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), base)
  mut held := false
  while held == false {
    r := atomic::cas_strong(sp, 0, 1, Ordering.seq_cst, Ordering.acquire)
    if r.1 {
      held = true
    } else {
      fr := unchecked sys_futex(202, base, 0, 1, 0, 0, 0)
    }
  }
}

## Release the channel's mutex: an atomic release store of 0 into `state`, then FUTEX_WAKE one
## waiter (a wake with no waiter is a harmless no-op). Pairs with `ch_lock`.
ch_unlock := fn(base : usize) {
  sp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), base)
  atomic::store(sp, 0, Ordering.seq_cst)
  fr := unchecked sys_futex(202, base, 1, 1, 0, 0, 0)
}

## Create a `Channel(T)` with room for `cap` elements, backing the ring in arena `a` (mirrors
## `alloc::hashmap`'s `arena_alloc`: `allocate` the bytes, take the handle index, resolve it to an
## absolute pointer via the arena base). `cap` must be >= 1. All control words start zeroed (empty,
## unlocked). The channel value itself is placed by the caller (typically a shared `mut` global, so
## the `CLONE_VM` child sees the same cell — the ring pages are shared for the same reason).
pub channel := fn(T : type, a : ptr(mut Arena), cap : usize) -> Channel(T) {
  idx := allocate(deref(a), u8, cap * size(T), align(T)).expect("channel: allocator out of memory").idx
  abase := unchecked bitcast(usize, deref(a).base)
  data := abase + idx
  return Channel(T)(state = 0, r_seq = 0, w_seq = 0, data = data, cap = cap, head = 0, tail = 0, count = 0, closed = 0)
}

## Send `v` down the channel, blocking while the ring is full. Loop: lock; if there is room, store
## `v` at `tail`, advance `tail` (wrapping) and bump `count`, then signal not-empty — atomically bump
## `r_seq` and FUTEX_WAKE a receiver — unlock, done. If full, read the not-full sequence `w_seq` UNDER
## THE LOCK, unlock, then `futex(&w_seq, FUTEX_WAIT, seq)`: if a receiver freed a slot in the gap it
## already bumped `w_seq`, so the wait returns EAGAIN at once and we re-check (no lost wakeup). After
## `send` the source is conceptually MOVED (CC-4 — enforced by the linearity checker, not here).
pub send := fn(T : type, ch : ptr(mut Channel(T)), v : T) {
  base := unchecked bitcast(usize, ch)
  raddr := base + 8
  waddr := base + 16
  wp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), waddr)
  mut done := false
  while done == false {
    ch_lock(base)
    cnt := deref(ch).count
    cp := deref(ch).cap
    if cnt < cp {
      tail := deref(ch).tail
      slot := deref(ch).data + tail * size(T)
      dp : ptr(mut T) = unchecked bitcast(ptr(mut T), slot)
      deref(dp) = v
      mut nt := tail + 1
      if nt >= cp { nt = 0 }
      deref(ch).tail = nt
      deref(ch).count = cnt + 1
      rp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), raddr)
      old := atomic::fetch_add(rp, 1, Ordering.seq_cst)
      ch_unlock(base)
      fw := unchecked sys_futex(202, raddr, 1, 1, 0, 0, 0)
      done = true
    } else {
      seq := atomic::load(wp, Ordering.seq_cst)
      ch_unlock(base)
      fr := unchecked sys_futex(202, waddr, 0, unchecked bitcast(usize, seq), 0, 0, 0)
    }
  }
}

## Receive the next value, blocking while the ring is empty. `out` is seeded from ring slot 0 (valid
## allocated memory) purely so the generic `T` local has an initializer; it is overwritten before any
## real read. Loop: lock; if there is an element, read it at `head`, advance `head` (wrapping) and drop
## `count`, then signal not-full — atomically bump `w_seq` and FUTEX_WAKE a sender — unlock, done, return
## it. If empty, read the not-empty sequence `r_seq` UNDER THE LOCK, unlock, `futex(&r_seq, FUTEX_WAIT,
## seq)`; a sender that enqueued in the gap already bumped `r_seq`, so the wait returns EAGAIN (no lost wakeup).
pub recv := fn(T : type, ch : ptr(mut Channel(T))) -> T {
  base := unchecked bitcast(usize, ch)
  raddr := base + 8
  waddr := base + 16
  rp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), raddr)
  data0 := deref(ch).data
  mut out : T = unchecked deref(bitcast(ptr(T), data0))
  mut done := false
  while done == false {
    ch_lock(base)
    cnt := deref(ch).count
    if cnt > 0 {
      head := deref(ch).head
      slot := deref(ch).data + head * size(T)
      out = unchecked deref(bitcast(ptr(T), slot))
      cp := deref(ch).cap
      mut nh := head + 1
      if nh >= cp { nh = 0 }
      deref(ch).head = nh
      deref(ch).count = cnt - 1
      wp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), waddr)
      old := atomic::fetch_add(wp, 1, Ordering.seq_cst)
      ch_unlock(base)
      fw := unchecked sys_futex(202, waddr, 1, 1, 0, 0, 0)
      done = true
    } else {
      seq := atomic::load(rp, Ordering.seq_cst)
      ch_unlock(base)
      fr := unchecked sys_futex(202, raddr, 0, unchecked bitcast(usize, seq), 0, 0, 0)
    }
  }
  return out
}

## Non-blocking send: try to enqueue `v` without ever blocking. Under the lock: if the channel is
## closed OR the ring is full, unlock and return `false` (the caller decides what to do); otherwise
## store `v` at `tail`, advance (wrapping), bump `count`, signal not-empty (bump `r_seq` + FUTEX_WAKE
## a receiver) and return `true`. Same store/signal path as blocking `send`, minus the wait.
pub try_send := fn(T : type, ch : ptr(mut Channel(T)), v : T) -> bool {
  base := unchecked bitcast(usize, ch)
  raddr := base + 8
  ch_lock(base)
  if deref(ch).closed != 0 {
    ch_unlock(base)
    return false
  }
  cnt := deref(ch).count
  cp := deref(ch).cap
  if cnt < cp {
    tail := deref(ch).tail
    slot := deref(ch).data + tail * size(T)
    dp : ptr(mut T) = unchecked bitcast(ptr(mut T), slot)
    deref(dp) = v
    mut nt := tail + 1
    if nt >= cp { nt = 0 }
    deref(ch).tail = nt
    deref(ch).count = cnt + 1
    rp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), raddr)
    old := atomic::fetch_add(rp, 1, Ordering.seq_cst)
    ch_unlock(base)
    fw := unchecked sys_futex(202, raddr, 1, 1, 0, 0, 0)
    return true
  }
  ch_unlock(base)
  return false
}

## Non-blocking receive: take the next value without ever blocking, as an `Option(T)`. Under the
## lock: if the ring is empty (whether the channel is open or a drained closed channel) return
## `Option(T).None`; otherwise read at `head`, advance (wrapping), drop `count`, signal not-full
## (bump `w_seq` + FUTEX_WAKE a sender) and return `Option(T).Some(v)`. `T` is word-sized in v1, so
## the `Option`'s payload is a single scalar (sound scalar-payload delivery).
pub try_recv := fn(T : type, ch : ptr(mut Channel(T))) -> Option(T) {
  base := unchecked bitcast(usize, ch)
  waddr := base + 16
  data0 := deref(ch).data
  mut out : T = unchecked deref(bitcast(ptr(T), data0))
  ch_lock(base)
  cnt := deref(ch).count
  if cnt > 0 {
    head := deref(ch).head
    slot := deref(ch).data + head * size(T)
    out = unchecked deref(bitcast(ptr(T), slot))
    cp := deref(ch).cap
    mut nh := head + 1
    if nh >= cp { nh = 0 }
    deref(ch).head = nh
    deref(ch).count = cnt - 1
    wp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), waddr)
    old := atomic::fetch_add(wp, 1, Ordering.seq_cst)
    ch_unlock(base)
    fw := unchecked sys_futex(202, waddr, 1, 1, 0, 0, 0)
    return Option(T).Some(out)
  }
  ch_unlock(base)
  return Option(T).None
}

## Blocking receive with EOF, as an `Option(T)`: like `recv`, but a `recv_opt` on an empty CLOSED
## channel returns `Option(T).None` instead of blocking forever — the drain-and-EOF end used by
## consumer loops (`while let Some = recv_opt`). Loop: lock; if there is an element, take it as in
## `recv` and return `Some`; else if the channel is closed, return `None`; else read `r_seq` under
## the lock, unlock, `futex(&r_seq, FUTEX_WAIT, seq)`. `close` bumps `r_seq` under the lock before
## waking, so a receiver that read the old seq and is about to wait returns EAGAIN and re-checks —
## it then sees `closed` and returns `None` (no lost wakeup / no missed close).
pub recv_opt := fn(T : type, ch : ptr(mut Channel(T))) -> Option(T) {
  base := unchecked bitcast(usize, ch)
  raddr := base + 8
  waddr := base + 16
  rp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), raddr)
  data0 := deref(ch).data
  mut out : T = unchecked deref(bitcast(ptr(T), data0))
  mut got := false
  mut done := false
  while done == false {
    ch_lock(base)
    cnt := deref(ch).count
    if cnt > 0 {
      head := deref(ch).head
      slot := deref(ch).data + head * size(T)
      out = unchecked deref(bitcast(ptr(T), slot))
      cp := deref(ch).cap
      mut nh := head + 1
      if nh >= cp { nh = 0 }
      deref(ch).head = nh
      deref(ch).count = cnt - 1
      wp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), waddr)
      old := atomic::fetch_add(wp, 1, Ordering.seq_cst)
      ch_unlock(base)
      fw := unchecked sys_futex(202, waddr, 1, 1, 0, 0, 0)
      got = true
      done = true
    } else {
      if deref(ch).closed != 0 {
        ch_unlock(base)
        done = true
      } else {
        seq := atomic::load(rp, Ordering.seq_cst)
        ch_unlock(base)
        fr := unchecked sys_futex(202, raddr, 0, unchecked bitcast(usize, seq), 0, 0, 0)
      }
    }
  }
  if got { return Option(T).Some(out) }
  return Option(T).None
}

## Close the channel: mark it drained-once-empty and wake EVERY blocked party so no one waits on a
## dead channel forever. Under the lock: set `closed`, then atomically bump BOTH sequence words
## (`r_seq`/`w_seq`) so any receiver/sender that read an old seq and is about to `futex_wait` returns
## EAGAIN and re-checks (closing the lost-wakeup race). Then FUTEX_WAKE a large count (INT_MAX) on
## BOTH words to release everyone actually parked. After `close`: `try_send`/blocking `send` refuse,
## `recv_opt`/`try_recv` drain the remaining elements then report `None` (EOF).
pub close := fn(T : type, ch : ptr(mut Channel(T))) {
  base := unchecked bitcast(usize, ch)
  raddr := base + 8
  waddr := base + 16
  ch_lock(base)
  deref(ch).closed = 1
  rp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), raddr)
  wp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), waddr)
  ro := atomic::fetch_add(rp, 1, Ordering.seq_cst)
  wo := atomic::fetch_add(wp, 1, Ordering.seq_cst)
  ch_unlock(base)
  fr := unchecked sys_futex(202, raddr, 1, 2147483647, 0, 0, 0)
  fw := unchecked sys_futex(202, waddr, 1, 2147483647, 0, 0, 0)
}

## The outcome of a `select`: WHICH channel fired (`idx`, 0-based over the arguments), whether a value
## was actually received (`some`), and the value (`value`, meaningful only when `some`). `some = false`
## is the all-inputs-EOF marker — every selected channel is closed AND drained, so no value will ever
## arrive again (the caller stops its select loop). Word-sized `T` in v1, like the rest of this module.
pub SelectResult := fn(T : type) -> type {
  struct { idx : usize, some : bool, value : T }
}

## Is `ch` permanently out of values — closed AND drained? Under the lock read `closed` and `count`:
## a closed channel with `count == 0` can never yield another value (`close` refuses further `send`s),
## so this condition is monotonic (once true it stays true) and is safe to use as the select EOF test.
ch_drained_closed := fn(T : type, ch : ptr(mut Channel(T))) -> bool {
  base := unchecked bitcast(usize, ch)
  ch_lock(base)
  cl := deref(ch).closed
  cnt := deref(ch).count
  ch_unlock(base)
  if cl != 0 {
    if cnt == 0 { return true }
  }
  return false
}

## v1 `select` over TWO channels: wait until EITHER `ch_a` or `ch_b` has a value ready to receive,
## then take it and report which one fired (`idx` 0 = `ch_a`, 1 = `ch_b`) — the common "wait on any"
## concurrency pattern. This is a **bounded polling** select (simple + correct for v1): each round
## `try_recv`s `ch_a` (preferred on a tie) then `ch_b`; the first `Some` wins and returns
## `SelectResult{idx, some = true, value}`. When BOTH are momentarily empty it checks for all-inputs
## EOF — both channels closed AND drained — and if so returns the `some = false` marker (so a consumer
## loop terminates instead of spinning on two dead channels); otherwise it `sched_yield`s and retries.
## The yield keeps the loop making progress without hard-spinning a core. Word-sized `T` only in v1.
## N-way select (a `Slice(ptr(mut Channel(T)))`) and a true multi-futex blocking select are follow-ups.
pub select2_recv := fn(T : type, ch_a : ptr(mut Channel(T)), ch_b : ptr(mut Channel(T))) -> SelectResult(T) {
  data0 := deref(ch_a).data
  mut out : T = unchecked deref(bitcast(ptr(T), data0))
  mut ridx : usize = 0
  mut rsome := false
  mut done := false
  while done == false {
    oa := try_recv(T, ch_a)
    match oa {
      Option::Some(v) => {
        out = v
        ridx = 0
        rsome = true
        done = true
      }
      Option::None => {
        ob := try_recv(T, ch_b)
        match ob {
          Option::Some(v) => {
            out = v
            ridx = 1
            rsome = true
            done = true
          }
          Option::None => {
            ea := ch_drained_closed(T, ch_a)
            eb := ch_drained_closed(T, ch_b)
            if ea {
              if eb {
                done = true
              }
            }
            if done == false {
              y := unchecked sys_sched_yield(24)
            }
          }
        }
      }
    }
  }
  return SelectResult(T)(idx = ridx, some = rsome, value = out)
}

## Seed a generic `T` local from a channel: read ring slot 0 (valid allocated memory, `cap >= 1`),
## exactly as `recv`/`try_recv` seed their `out` — a value of the right type, overwritten before any
## real use. Split out as its OWN function (a plain `ptr(mut Channel(T))` param) so the field deref
## happens on an ordinary pointer, NOT on a pointer just read inline from a slice element: an inline
## `deref(chans[i]).field` over a `Slice(ptr(mut Channel(T)))` element currently mis-addresses (reads
## a wrong base), whereas passing the element pointer across a call boundary is correct — see.
ch_seed := fn(T : type, ch : ptr(mut Channel(T))) -> T {
  data0 := deref(ch).data
  return unchecked deref(bitcast(ptr(T), data0))
}

## v1 `select` over N channels — the N-way generalization of `select2_recv`, taking a
## `Slice(ptr(mut Channel(T)))` (a slice of channel POINTERS, so the caller can wait on any number
## of channels chosen at runtime). Same bounded-polling model: each round scans the slice IN ORDER
## and `try_recv`s each channel; the FIRST `Some` wins and returns `SelectResult{idx, some = true,
## value}` where `idx` is that channel's slice index (lower index preferred on a tie, matching
## select2's `ch_a`-first bias). When EVERY channel is momentarily empty it checks for all-inputs EOF
## — every channel closed AND drained (`ch_drained_closed`) — and if so returns the `some = false`
## marker so a consumer loop terminates instead of spinning on N dead channels; otherwise it
## `sched_yield`s and retries (cooperative backoff, no hard core-spin). The slice must be NON-EMPTY
## (element 0 seeds the generic `out`'s initializer, as in `recv`). Word-sized `T` only in v1, like
## the rest of this module. A true multi-futex blocking select (park on all N at once) is a follow-up.
pub select_recv := fn(T : type, chans : Slice(ptr(mut Channel(T)))) -> SelectResult(T) {
  first := chans[0]
  mut out : T = ch_seed(T, first)
  mut ridx : usize = 0
  mut rsome := false
  mut done := false
  n := chans.len()
  while done == false {
    mut i : usize = 0
    mut fired := false
    mut alleof := true
    while i < n {
      if fired == false {
        chp := chans[i]
        o := try_recv(T, chp)
        match o {
          Option::Some(v) => {
            out = v
            ridx = i
            rsome = true
            fired = true
          }
          Option::None => {
            e := ch_drained_closed(T, chp)
            if e == false { alleof = false }
          }
        }
      }
      i = i + 1
    }
    if fired {
      done = true
    } else {
      if alleof {
        done = true
      } else {
        y := unchecked sys_sched_yield(24)
      }
    }
  }
  return SelectResult(T)(idx = ridx, some = rsome, value = out)
}
