## pipeline — WORKERS threads hash the CHUNKS chunks of a generated input. The chunk numbers go
## out over a bounded channel, and each worker folds its hashes into a mutex-guarded total (#1125).
##
## The input is generated before any worker starts and is only read while they run, so the threads
## share it immutably. The total is the same whatever order the chunks are hashed in, because
## folding is addition. The program checks it against the same fold done on one thread, and
## against the value an independent implementation computes.
##
## Exit status: 0 when both checks hold; 1 when memory cannot be allocated; 2 when the threaded
## total differs from the single-threaded one; 3 when the single-threaded total differs from
## EXPECTED.

Channel := std::channel::Channel
Mutex := std::sync::Mutex
Thread := std::thread::Thread

WORKERS : usize = 4
CHUNKS : u64 = 64
CHUNK_LEN : usize = 4096
SEED : u64 = 0x9e3779b97f4a7c15

## The fold of every chunk's FNV-1a hash over the input from SEED, computed by an independent
## implementation of the same three definitions (src/hash.al).
EXPECTED : u64 = 0xe38adc33bf54150f

## What a worker needs: the input, the queue of chunk numbers and the shared total.
Job := struct {
  input : Slice(u8),
  queue : ptr(mut Channel(u64)),
  total : ptr(mut Mutex(u64)),
}

## The bytes of chunk `k`.
chunk := fn(input : Slice(u8), k : u64) -> Slice(u8) {
  lo := usize(k) * CHUNK_LEN
  input[lo..lo + CHUNK_LEN]
}

## Take chunk numbers until the queue is closed and empty, folding each chunk's hash into the
## total.
worker := fn(arg : usize) {
  ## blocked-by: #1210 — `std::thread::spawn` passes the worker's argument as a `usize`.
  ## blocked-by: #1209 — `deref(unchecked bitcast(ptr(Job), arg))` copies the wrong struct, so
  ## the pointer is bound first.
  jp := unchecked bitcast(ptr(Job), arg)
  job := deref(jp)
  mut open := true
  while open {
    match std::channel::recv_opt(u64, job.queue) {
      Some(k) => {
        h := hash::fnv1a(k, chunk(job.input, k))
        t := std::sync::lock(u64, job.total)
        deref(t) = hash::fold(deref(t), h)
        std::sync::unlock(u64, job.total)
      }
      None => {
        open = false
      }
    }
  }
}

main := fn() -> u64 {
  match std::os::arena(1048576) {
    Ok(osa) => {
      mut ar := std::os::region(ptr(osa))
      rc := run(ptr(mut ar))
      std::os::free(osa)
      rc
    }
    Err(_) => {
      n := std::io::eprint("pipeline: cannot allocate memory\n")
      1
    }
  }
}

run := fn(a : ptr(mut Arena)) -> u64 {
  len := usize(CHUNKS) * CHUNK_LEN
  mut bytes_v := alloc::vec::with_capacity(u8, a, len)
  mut s := SEED
  for i in 0..len {
    s = hash::xorshift(s)
    match alloc::vec::push(u8, bytes_v, u8(s & 0xff)) {
      Ok(_) => {}
      Err(_) => {
        n := std::io::eprint("pipeline: cannot allocate the input\n")
        return 1
      }
    }
  }
  input := alloc::vec::as_slice(u8, ptr(bytes_v))

  mut queue := std::channel::channel(u64, a, 8)
  mut total := std::sync::new(u64, 0)
  job := Job(input = input, queue = ptr(mut queue), total = ptr(mut total))
  ## blocked-by: #1211 — a `for` over a `Vec(Thread)`'s slice yields wrong handles, and
  ## blocked-by: #1212 — `alloc::vec::get` returns a wrong `Thread`, so the handles live in a fixed
  ## array whose unused value is overwritten before any join.
  ## blocked-by: #1213 — `[v; WORKERS]` is refused, so the count is written out.
  mut threads : [Thread; WORKERS] = [Thread(ctid_addr = 0, stack_base = 0, stack_len = 0); 4]
  for w in 0..WORKERS {
    ## blocked-by: #1210 — `std::thread::spawn` takes the worker and its argument as `usize`s.
    threads[w] = std::thread::spawn(unchecked bitcast(usize, worker), unchecked bitcast(usize, ptr(job)))
  }
  for k in 0..CHUNKS {
    std::channel::send(u64, ptr(mut queue), k)
  }
  std::channel::close(u64, ptr(mut queue))
  for t in threads {
    std::thread::join(t)
  }
  threaded := deref(std::sync::lock(u64, ptr(total)))
  std::sync::unlock(u64, ptr(total))

  mut single : u64 = 0
  for k in 0..CHUNKS {
    single = hash::fold(single, hash::fnv1a(k, chunk(input, k)))
  }
  if threaded != single { return 2 }
  if single != EXPECTED { return 3 }
  0
}
