## std::sync — a futex-based `Mutex(T)` (Concurrency CC-4, contract v1-fixed / spec §5.2).
##
## `Mutex(T)` wraps a guarded `T`; `lock` yields a `ptr(mut T)` to the inner value (the
## v1-fixed contract's scoped reference — released by `defer`/`unlock`), and the mutex
## serializes holders, so two writers can never coexist (CC-4 path 3). This is provably an
## ordinary library type over the existing mechanisms (`atomic::cas_strong` + the raw `futex`
## syscall) — no new language entity. x86_64-only in v1 (the futex syscall number is Linux).
##
## Layout: `struct { state : u64, value : T }` — `state` 0 = free, 1 = locked. `state` is the
## first field (offset 0) and `value` the second (offset 8, `u64`-aligned): `lock`/`unlock`
## address them by `bitcast`ing the `Mutex` pointer, which is stable across the erased `T`.

## Linux `futex(2)` (syscall 202): op 0 = FUTEX_WAIT (sleep while `*uaddr == val`), op 1 =
## FUTEX_WAKE (wake up to `val` waiters). Raw level (I11) — the caller wraps it in `unchecked`.
sys_futex := @abi(syscall) fn(num : usize, uaddr : usize, op : usize, val : usize, timeout : usize, uaddr2 : usize, val3 : usize) -> isize

## The guarded cell: a lock word plus the owned datum. Generic over the guarded `T`.
pub Mutex := fn(T : type) -> type { struct { state : u64, value : T } }

## A fresh unlocked `Mutex(T)` guarding `v` (state = 0 = free).
pub new := fn(T : type, v : T) -> Mutex(T) {
  return Mutex(T)(state = 0, value = v)
}

## Acquire the lock and return a `ptr(mut T)` to the guarded value. Fast path: CAS the state
## 0 -> 1 (`atomic::cas_strong`, a single `lock cmpxchgq`). On contention (CAS fails, state is
## already 1) sleep in `futex(&state, FUTEX_WAIT=0, expected=1, NULL)` until the holder wakes us,
## then retry the CAS. The returned pointer is the guarded field (`&Mutex + 8`), reachable only
## while the lock is held (the scoped-reference discipline, spec §5.2).
pub lock := fn(T : type, m : ptr(Mutex(T))) -> ptr(mut T) {
  base := unchecked bitcast(usize, m)
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
  return unchecked bitcast(ptr(mut T), base + 8)
}

## Release the lock: store 0 into the state (an atomic release store) and FUTEX_WAKE one waiter
## (op 1, val 1). A wake with no waiters is a harmless no-op. Pairs with `lock`.
pub unlock := fn(T : type, m : ptr(Mutex(T))) {
  base := unchecked bitcast(usize, m)
  sp : ptr(mut u64) = unchecked bitcast(ptr(mut u64), base)
  atomic::store(sp, 0, Ordering.seq_cst)
  fr := unchecked sys_futex(202, base, 1, 1, 0, 0, 0)
}
