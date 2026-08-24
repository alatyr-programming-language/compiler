## selfhost::cli — the self-hosted compiler's command-line front (step 1).
##
## Turns the GAS-emitting passes into a driveable tool: read the process arguments, resolve the
## assembler/linker on `$PATH`, and (in `driver`) write the emitted `.s` + invoke `as`/`ld` to
## produce an executable — all on the lean `rt` runtime (raw syscalls; no `std::process`/`std::io`,
## which the lean lower cannot compile). Process inputs are read from `/proc/self/<…>` (the kernel
## puts argv/environ on the stack, but the emitted `_start` does not forward it, so `/proc` is the
## portable source). Byte access is via the spec-canonical `bytes(s)[i]` (NOT `deref(bitcast(ptr(u8),
## …))`, which the self-host lower reads as a WORD — the documented type-discard byte facet).

## Raw Linux x86_64 unlink(2) used only for temporary artifacts created by manifest-less `run`/`test`.
## Package artifacts are deliberately retained under their manifest's `target_dir`; this declaration
## keeps the cleanup primitive local to the CLI while the runtime module is being used by another lane.
cli_unlink := @abi(syscall) fn(num : usize, path : usize) -> isize

## Read a whole `/proc` (or any) file at the NUL-terminated C-string `path_cstr` into a fresh
## `StrBuf` on `a`; return it as a `str` over the bytes read (0-len on open failure). `cap` is the
## budget for a file whose size the kernel will NOT report (every `/proc` file); a regular file is
## sized from the file itself, so `cap` cannot clip it. `truncated` is set to 1 iff the file held
## MORE bytes than the budget allowed — see `read_proc` below for why that must never be swallowed.
read_proc_lim := fn(in out a : rt::Arena, path_cstr : usize, cap : usize, in out truncated : usize) -> str {
  truncated = 0
  fd := rt::sys_open(2, path_cstr, 0, 0)
  if fd < 0 {
    mut miss := rt::strbuf(a, 8)
    return str_at(miss.data, 0)
  }
  ufd := unchecked bitcast(usize, fd)
  ## Size the buffer from the FILE when the kernel can say how big it is (`parser::embed` uses the
  ## same lseek pair): the read is then exact and truncation is IMPOSSIBLE, so `cap` never silently
  ## clips a source file. `/proc` files report size 0 — those keep `cap` as the budget, and the
  ## probe below decides whether the budget was actually enough.
  mut want := cap
  szr := rt::sys_lseek(8, ufd, 0, 2)                       ## lseek(fd, 0, SEEK_END) -> byte length
  rwd := rt::sys_lseek(8, ufd, 0, 0)                       ## lseek(fd, 0, SEEK_SET) -> rewind
  if szr > 0 { want = unchecked bitcast(usize, szr) + 16 }
  mut sb := rt::strbuf(a, want)
  mut done := false
  while done == false {
    ## bound each read by the remaining capacity (keep 8 bytes of slack) so a large file never
    ## overruns the buffer into the arena.
    mut room := 0
    if sb.len + 8 < want { room = want - sb.len - 8 }
    mut chunk := 8192
    if room < chunk { chunk = room }
    if chunk == 0 {
      ## The buffer is full. That is NOT the same as end-of-file: one more read decides which
      ## happened, and a short read is a fact the caller has to be told about (I11 - a truncated
      ## answer that looks like a complete one is exactly how a malformed `envp` reached execve).
      done = true
      probe := rt::bump(a, 8)
      np := rt::sys_read(0, ufd, probe, 8)
      if np > 0 { truncated = 1 }
    } else {
      nr := rt::sys_read(0, ufd, sb.data + sb.len, chunk)
      if nr <= 0 { done = true } else { sb.len = sb.len + unchecked bitcast(usize, nr) }
    }
  }
  cc := rt::sys_close(3, ufd)
  return str_at(sb.data, sb.len)
}

## The `str` at the NUL-terminated C-string address `p` (the inverse of `cstr`), for naming a file
## in a diagnostic.
cstr_str := fn(p : usize) -> str {
  mut n := 0
  while bytes(str_at(p + n, 1))[0] != 0 { n = n + 1 }
  return str_at(p, n)
}

## Report a read that stopped at the capacity rather than at end-of-file. A silently short read is
## a wrong answer wearing a right answer's shape: it truncated `/proc/self/environ` mid-entry, which
## is how `build_envp` came to emit an unterminated `envp` array (see `build_envp`).
truncation_error := fn(in out a : rt::Arena, path_cstr : usize, cap : usize) {
  path := cstr_str(path_cstr)
  mut b := rt::strbuf(a, path.len + 160)
  rt::push_str(b, "alatyr: ")
  rt::push_str(b, path)
  rt::push_str(b, ": more than ")
  rt::push_int(b, cap)
  rt::push_str(b, " bytes; the rest was NOT read")
  msg := str_at(b.data, b.len)
  tool_error(msg)
}

## Read a whole file, REPORTING a truncated read on stderr. Every caller that can simply not cope
## with a short read uses this; the callers that must also FAIL (the process environment, which is
## handed to execve) call `read_proc_lim` and act on the flag themselves.
pub read_proc := fn(in out a : rt::Arena, path_cstr : usize, cap : usize) -> str {
  mut tr := 0
  s := read_proc_lim(a, path_cstr, cap, tr)
  if tr != 0 { truncation_error(a, path_cstr, cap) }
  return s
}

## Build the NUL-terminated C-string for `path` (a span, not NUL-terminated) in a scratch StrBuf
## on `a`; return its address (for `sys_open`/`sys_execve`).
pub cstr := fn(in out a : rt::Arena, path : str) -> usize {
  mut pb := rt::strbuf(a, path.len + 8)
  mut k := 0
  while k < path.len { kk := rt::push_byte(pb, bytes(path)[k]); k = k + 1 }
  kn := rt::push_byte(pb, 0)
  return unchecked bitcast(usize, rt::strbuf_base(pb))
}

## The whole process argv as a `str` (NUL-separated "prog\0arg1\0arg2\0…"), read from
## /proc/self/cmdline.
pub read_cmdline := fn(in out a : rt::Arena) -> str {
  pa := cstr(a, "/proc/self/cmdline")
  ## ARG_MAX-sized, not 64 KiB: argv and the environment share one kernel budget of a quarter of the
  ## stack rlimit (2 MiB on a default 8 MiB stack), so anything the kernel accepted fits here. A
  ## short read used to DROP arguments silently — the same truncation defect as the environ read.
  return read_proc(a, pa, 2097152)
}

## The number of NUL-separated arguments in a cmdline `str`. /proc/self/cmdline ends in a trailing
## NUL after the last arg, so the count is the number of NUL terminators.
pub arg_count := fn(cmd : str) -> usize {
  mut n := 0
  mut i := 0
  while i < cmd.len {
    if bytes(cmd)[i] == 0 { n = n + 1 }
    i += 1
  }
  return n
}

## The i-th (0-based) NUL-separated argument of a cmdline `str`, as a `str` span (0-len if past the
## end). Skips `i` NUL-terminated fields, then spans to the next NUL.
pub arg_at := fn(cmd : str, i : usize) -> str {
  mut off := 0
  mut idx := 0
  while idx < i and off < cmd.len {
    while off < cmd.len and bytes(cmd)[off] != 0 { off = off + 1 }
    off += 1
    idx += 1
  }
  mut e := off
  while e < cmd.len and bytes(cmd)[e] != 0 { e = e + 1 }
  if off > cmd.len { off = cmd.len }
  if e > cmd.len { e = cmd.len }
  base := unchecked bitcast(usize, cmd.ptr)
  return str_at(base + off, e - off)
}

## Resolve a program `name` (e.g. "as"/"ld") to an ABSOLUTE NUL-terminated C-string by searching
## `$PATH` inside the ALREADY-READ environment block `env` (NUL-separated `KEY=VAL`); returns the
## C-string address of the first `<dir>/<name>` that exists (probed via `sys_open` O_RDONLY), or 0
## if none is found. execve needs an absolute path; this is the lean `execvp`-style search the
## driver uses for as/ld (Tooling §6.1 — resolution on `$PATH`, never a silent fallback).
##
## `env` is a PARAMETER, not a second `/proc/self/environ` read. It used to re-read the environment
## into the SAME arena the caller had just built its execve `envp` array out of, so the caller's
## `envp` was immediately followed by a fresh 64 KiB environ copy and then by these `<dir>/<name>`
## candidate strings — which is why an `envp` array that ran one word long overflowed straight into
## a PATH probe string ("…n/as" showed up as an environment pointer). One read, one buffer, one
## answer: the environment the tool is handed and the `$PATH` it is found on are now the same bytes.
pub resolve_in_path := fn(in out a : rt::Arena, env : str, name : str) -> usize {
  mut i := 0
  mut pvs := 0
  mut pve := 0
  mut found := false
  while i < env.len and found == false {
    if i + 5 <= env.len and bytes(env)[i] == 80 and bytes(env)[i + 1] == 65 and bytes(env)[i + 2] == 84 and bytes(env)[i + 3] == 72 and bytes(env)[i + 4] == 61 {
      pvs = i + 5
      mut e := pvs
      while e < env.len and bytes(env)[e] != 0 { e = e + 1 }
      pve = e
      found = true
    } else {
      while i < env.len and bytes(env)[i] != 0 { i = i + 1 }
      i += 1
    }
  }
  if found == false { return 0 }
  mut ds := pvs
  mut res := 0
  while ds < pve and res == 0 {
    mut de := ds
    while de < pve and bytes(env)[de] != 58 { de = de + 1 }
    mut cb := rt::strbuf(a, (de - ds) + name.len + 16)
    mut k := ds
    while k < de { kk := rt::push_byte(cb, bytes(env)[k]); k = k + 1 }
    ksl := rt::push_byte(cb, 47)
    mut m := 0
    while m < name.len { mm := rt::push_byte(cb, bytes(name)[m]); m = m + 1 }
    kn := rt::push_byte(cb, 0)
    ca := unchecked bitcast(usize, rt::strbuf_base(cb))
    fd := rt::sys_open(2, ca, 0, 0)
    if fd >= 0 { cc := rt::sys_close(3, unchecked bitcast(usize, fd)); res = ca }
    ds = de + 1
  }
  return res
}

## Read the process environment for a toolchain hand-off, as ONE buffer that is both the `envp`
## source and the `$PATH` source. `truncated` is 1 iff the environment did not fit — the caller MUST
## refuse to spawn anything in that case (see `env_truncation_error`), because a mid-entry cut is
## exactly what `build_envp` cannot represent.
read_environ := fn(in out a : rt::Arena, in out truncated : usize) -> str {
  ec := cstr(a, "/proc/self/environ")
  ## ARG_MAX-sized (see `read_cmdline`): the kernel would have refused to start THIS process with a
  ## bigger environment, so a legitimate environment always fits and the error below stays unreachable.
  return read_proc_lim(a, ec, 2097152, truncated)
}

## The diagnostic for an environment that did not fit. It is a TOOLING diagnostic about the process
## environment (Tooling §6.1), never a statement about the emitted code.
env_truncation_error := fn() {
  tool_error("alatyr: the process environment is larger than alatyr can read (2 MiB); refusing to hand a truncated environment to the toolchain")
}

## Store a word `val` at byte address `addr` (for building execve's argv/envp pointer arrays). `addr`
## is a typed `ptr(mut u8)` (usize->ptr Phase 2); callers pass their usize slot addresses unchanged.
pub wword := fn(addr : ptr(mut u8), val : usize) {
  p : ptr(mut usize) = unchecked bitcast(ptr(mut usize), addr)
  deref(p) = val
}

## Concatenate two `str`s into a fresh StrBuf on `a`; return the result as a `str`.
pub cat2 := fn(in out a : rt::Arena, s1 : str, s2 : str) -> str {
  mut b := rt::strbuf(a, s1.len + s2.len + 16)
  k1 := rt::push_str(b, s1)
  k2 := rt::push_str(b, s2)
  return str_at(b.data, b.len)
}

## Build an execve `envp` pointer array from the NUL-separated `environ` str: one pointer per
## entry (pointing in-place into the buffer, which is already NUL-terminated per entry) + a
## trailing 0 word. Returns the array's address. Passing the real environ lets the NixOS `as`/`ld`
## wrapper scripts find their NIX_* / PATH vars.
##
## THE ARRAY IS SIZED BY THE NUMBER OF POINTERS THE FILL LOOP WRITES, and the fill loop is bounded
## by that same number. It used to be sized `(NUL count + 1) * 8` while the loop ran once per
## ENTRY — one iteration MORE than the NUL count whenever the buffer did not end in a NUL, which a
## truncated `/proc/self/environ` read produced. The extra iteration put a pointer in the slot
## reserved for the terminator and wrote the terminating 0 word 8 bytes PAST the block. The result
## was an `envp` array with no terminator: execve walked off its end into the next arena allocation
## and failed EFAULT, the child exited 127, and the driver blamed the assembler.
##
## Two guards, in that order. An entry with no NUL is not a C string and can never be handed to
## execve, so reaching here with one means the caller skipped the environment check: that TRAPS,
## it is not quietly repaired (I11 — a short buffer fails loud, it never yields aliasing memory).
## Independently, the `k < cnt` bound makes the terminator's slot structurally in-bounds, so no
## future caller can reproduce the overrun even if the trap is ever relaxed.
pub build_envp := fn(in out a : rt::Arena, env : str) -> usize {
  base := unchecked bitcast(usize, env.ptr)
  mut cnt := 0
  mut i := 0
  while i < env.len {
    if bytes(env)[i] == 0 { cnt = cnt + 1 }
    i += 1
  }
  if env.len > 0 and bytes(env)[env.len - 1] != 0 {
    panic("cli: refusing to build an execve envp from an environment buffer whose last entry has no NUL terminator (a truncated /proc/self/environ read)")
  }
  arr := rt::bump(a, (cnt + 1) * 8)
  mut k := 0
  mut off := 0
  while off < env.len and k < cnt {
    wword(arr + k * 8, base + off)
    while off < env.len and bytes(env)[off] != 0 { off = off + 1 }
    off += 1
    k += 1
  }
  wword(arr + k * 8, 0)
  return arr
}

## Remove one path if it exists. `unlink(2)` reports an error for an absent file, which is harmless
## here: cleanup must be best-effort after an assembler/linker failure and must not replace the original
## diagnostic with a second cleanup error.
unlink_artifact := fn(in out a : rt::Arena, path : str) {
  path_c := cstr(a, path)
  ignored := cli_unlink(87, path_c)
}

## Construct a split-link intermediate name beside `<out>`, using the source module path when
## available (for example `geometry__vec.s` / `.o`).
## Keep the returned string in a local before passing it to `unlink_artifact`; this is the same
## self-host string materialization boundary used by the link path itself.
split_artifact_path := fn(in out a : rt::Arena, out : str, i : usize, suffix : str) -> str {
  mut b := rt::strbuf(a, out.len + suffix.len + 48)
  k0 := rt::push_str(b, out)
  k1 := rt::push_byte(b, 46)
  rt::push_int(b, i)
  k2 := rt::push_str(b, suffix)
  str_at(b.data, b.len)
}

## Return the driver's exact span-to-input list when a split build has one. The raw CLI path list is
## only the front-end input order; declaration-module ranges can additionally contain the package root,
## ambient modules, and synthetic manifest declarations, so it is not a safe attribution source.
emission_paths_for := fn(paths : str) -> str {
  p := driver::emission_paths_ptr()
  n := driver::emission_paths_len()
  if p != 0 and n != 0 { return str_at(p, n) }
  return paths
}

## The stable module-path stem for a split span. Package paths normally contain `/src/`; strip that
## source root, remove `.al`, and mangle path separators to `__` (Modules §6.1). Bare inputs fall
## back to the file basename. The final span is the compiler-generated monomorphized instance set.
split_module_path := fn(in out a : rt::Arena, paths : str, i : usize, nspan : usize) -> str {
  if i + 1 == nspan { return "instances" }
  span_paths := emission_paths_for(paths)
  ip := emission_input_path(span_paths, i)
  mut start := 0
  mut j := 0
  while j + 4 < ip.len {
    if bytes(ip)[j] == 47 and bytes(ip)[j + 1] == 115 and bytes(ip)[j + 2] == 114 and bytes(ip)[j + 3] == 99 and bytes(ip)[j + 4] == 47 { start = j + 5 }
    j += 1
  }
  if start == 0 {
    j = 0
    while j < ip.len { if bytes(ip)[j] == 47 { start = j + 1 } ; j += 1 }
  }
  mut end := ip.len
  if end >= 3 and bytes(ip)[end - 3] == 46 and bytes(ip)[end - 2] == 97 and bytes(ip)[end - 1] == 108 { end -= 3 }
  mut b := rt::strbuf(a, end - start + 32)
  if ip == "<unmapped-module>" {
    rt::push_str(b, "<unmapped-module>__")
    rt::push_int(b, i)
  } else {
    mut k := start
    while k < end {
      if bytes(ip)[k] == 47 { rt::push_str(b, "__") } else { rt::push_byte(b, bytes(ip)[k]) }
      k += 1
    }
  }
  return str_at(b.data, b.len)
}

split_module_artifact_path := fn(in out a : rt::Arena, out : str, paths : str, i : usize, nspan : usize, suffix : str) -> str {
  d := dir_of(out)
  stem := split_module_path(a, paths, i, nspan)
  mut b := rt::strbuf(a, d.len + stem.len + suffix.len + 32)
  if d.len != 0 { rt::push_str(b, d); rt::push_byte(b, 47) }
  rt::push_str(b, stem)
  ## Several declaration ranges can legitimately share one source path (the package root and
  ## manifest-generated declarations are the current example). Keep every intermediate name unique
  ## by span index; otherwise ld receives the same `.o` twice and reports duplicate local rodata labels.
  rt::push_str(b, "__")
  rt::push_int(b, i)
  rt::push_str(b, suffix)
  return str_at(b.data, b.len)
}

## Delete every file the split or single-object link path can create for a temporary artifact. A
## package caller never invokes this function: TOOL-10 intentionally leaves its `.s`/`.o`, sidecars and
## executable under `target_dir` for inspection. `spanbase` identifies the split case, including a
## partially completed link where only an initial subset of span files exists.
cleanup_temp_artifact := fn(in out a : rt::Arena, out : str, spanbase : usize, paths : str) {
  mut nspan := 0
  if spanbase != 0 {
    nspan = rt::rec_get(unchecked bitcast(ptr(mut u8), spanbase), 0)
  }
  if nspan > 1 {
    mut i := 0
    while i < nspan {
      sp := split_module_artifact_path(a, out, paths, i, nspan, ".s")
      unlink_artifact(a, sp)
      op := split_module_artifact_path(a, out, paths, i, nspan, ".o")
      unlink_artifact(a, op)
      i += 1
    }
    mp := cat2(a, out, ".manifest")
    unlink_artifact(a, mp)
    ip := cat2(a, out, ".interface")
    unlink_artifact(a, ip)
  } else {
    ss := cat2(a, out, ".s")
    unlink_artifact(a, ss)
    oo := cat2(a, out, ".o")
    unlink_artifact(a, oo)
  }
  unlink_artifact(a, out)
}

## Join args [fi, n) of `cmd` into a newline-separated path list `str` (the form compile_files
## expects). Extracted so `run_cli` stays small (the self-host lower has a per-function complexity
## ceiling — keep each driver fn lean).
pub join_files := fn(in out a : rt::Arena, cmd : str, fi : usize, n : usize) -> str {
  mut pb := rt::strbuf(a, 1048576)
  mut i := fi
  while i < n {
    f := arg_at(cmd, i)
    ks := rt::push_str(pb, f)
    kn := rt::push_byte(pb, 10)
    i += 1
  }
  return str_at(pb.data, pb.len)
}

## execve `prog_c` with argv = [prog_c, a1, a2, a3, NULL] and `envp`; block until it exits; return
## the CLASSIFIED outcome (`rt::Spawned` — check `.kind` for "the tool could not be run at all"
## BEFORE reading `.code`, the tool's own status). The 3-argument shape both `as <in> -o <out>`
## invocations need.
pub exec4 := fn(in out a : rt::Arena, prog_c : usize, a1 : usize, a2 : usize, a3 : usize, envp : usize) -> rt::Spawned {
  av := rt::bump(a, 40)
  wword(av + 0, prog_c)
  wword(av + 8, a1)
  wword(av + 16, a2)
  wword(av + 24, a3)
  wword(av + 32, 0)
  return rt::run(a, prog_c, av, envp)
}

## Like exec4 but with FIVE positional args (argv `[prog, a1..a5, NULL]`) — used to pass `ld … -e <entry>`
## when the manifest selects a non-default ELF entry symbol. Same `rt::Spawned` contract.
pub exec6 := fn(in out a : rt::Arena, prog_c : usize, a1 : usize, a2 : usize, a3 : usize, a4 : usize, a5 : usize, envp : usize) -> rt::Spawned {
  av := rt::bump(a, 56)
  wword(av + 0, prog_c)
  wword(av + 8, a1)
  wword(av + 16, a2)
  wword(av + 24, a3)
  wword(av + 32, a4)
  wword(av + 40, a5)
  wword(av + 48, 0)
  return rt::run(a, prog_c, av, envp)
}

## Report a toolchain failure on stderr. Every `link_exe` failure path used to return a BARE numeric
## code with no message at all — so `alatyr build` in a shell without binutils exited 11 in total
## silence, and a link error exited 14 with only `ld`'s own line and nothing saying which alatyr step
## produced it. The status codes are unchanged; only the diagnostic is new.
tool_error := fn(msg : str) {
  w := rt::sys_write(1, 2, unchecked bitcast(usize, msg.ptr), msg.len)
  ## Bind the literal to a LOCAL before taking `.ptr`/`.len`. `"\n".ptr` applied DIRECTLY to a
  ## literal handed `sys_write` an address that wrote nothing, so every toolchain diagnostic came
  ## out WITHOUT its line break and ran into whatever the caller printed next
  ## (`…rejected the emitted assemblyrc=13`). A `str` local materializes the {ptr,len} pair, which
  ## is the same rule `link_exe` documents for forwarding a `str` argument.
  nl := "\n"
  n := rt::sys_write(1, 2, unchecked bitcast(usize, nl.ptr), nl.len)
}

## Report a failure to RUN a toolchain program at all. This is a DIFFERENT diagnosis from "the tool
## ran and rejected its input", and the two must never share a message: `link_exe` used to print
## "the assembler (`as`) rejected the emitted assembly" for a spawn failure too, and `rt::run`
## folded its own fork/wait errors into the same non-zero return — so a driver defect read as a
## codegen regression and was chased in the wrong subsystem for weeks. Tooling §6.1 puts a failed
## toolchain hand-off in the Tooling class: name the tool, say what failed, and claim nothing about
## the emitted code.
spawn_error := fn(in out a : rt::Arena, role : str, tool : str, sp : rt::Spawned) {
  mut b := rt::strbuf(a, role.len + tool.len + 256)
  rt::push_str(b, "alatyr: could not run the ")
  rt::push_str(b, role)
  rt::push_str(b, " (`")
  rt::push_str(b, tool)
  rt::push_str(b, "`): ")
  if sp.kind == 1 {
    rt::push_str(b, "execve failed, errno ")
    rt::push_int(b, 0 - sp.code)
  } else if sp.kind == 2 {
    rt::push_str(b, "fork failed, errno ")
    rt::push_int(b, 0 - sp.code)
  } else if sp.kind == 3 {
    rt::push_str(b, "wait4 failed, errno ")
    rt::push_int(b, 0 - sp.code)
  } else {
    rt::push_str(b, "the exec-status pipe could not be created, errno ")
    rt::push_int(b, 0 - sp.code)
  }
  rt::push_str(b, " -- the tool never ran, so this says nothing about the emitted code")
  msg := str_at(b.data, b.len)
  tool_error(msg)
}

## Write the emitted GAS `[gbase, gbase+glen)` to `<out>.s`, then assemble + link it into the
## executable `<out>` by driving `as`/`ld` (resolved on $PATH, execve'd with the real environ).
## Returns 0, or 10 (write) / 11 (no as) / 12 (no ld) / 13 (`as` RAN and rejected the input) /
## 14 (`ld` ran and failed) / 19 (a tool could not be RUN AT ALL — fork/execve/wait failed) /
## 21 (the process environment could not be read whole), each accompanied by a stderr diagnostic.
## 13/14 and 19 are deliberately distinct codes: the first pair is about the input, 19 is about
## this driver and its environment.
## `libnames` (newline-joined foreign-library names → `-l<name>`) + `lflags` (newline-joined
## `linker_flags`) + `any_dyn` (any lib is `LinkMode.dynamic`) drive MOD-9 foreign-library linking:
## when BOTH lists are empty the plain raw-`ld` path below runs unchanged (the compiler's own build
## has no libs → byte-identical → the TOOL-1 fixpoint holds); otherwise `link_with_libs` links via
## `cc` (any dynamic lib) or `ld -static` (all static). Non-manifest callers pass "", false, "".
pub link_exe := fn(in out a : rt::Arena, out : str, gbase : usize, glen : usize, entry : str, libnames : str, any_dyn : bool, lflags : str) -> usize {
  ## Bind each `str`-returning intermediate to a LOCAL before forwarding it as a `str` argument:
  ## the lean self-host lower passes a `str` PARAM by pointer, so an inline str-returning call as a
  ## str arg (`cstr(a, cat2(…))`) would forward only the value's data pointer (%rax), dropping the
  ## length (%rdx) — the callee then mis-reads the bytes as a {ptr,len} pair. A `name := <str-call>`
  ## binding materializes the {ptr,len} into a 2-word slot, and a str LOCAL forwards correctly.
  ssfx := cat2(a, out, ".s")
  osfx := cat2(a, out, ".o")
  outs_c := cstr(a, ssfx)
  outo_c := cstr(a, osfx)
  out_c := cstr(a, out)
  w := rt::write_file(outs_c, gbase, glen)
  if w != 0 { tool_error("alatyr: cannot write the emitted assembly"); return 10 }
  mut etr := 0
  environ := read_environ(a, etr)
  if etr != 0 { env_truncation_error(); return 21 }
  envp := build_envp(a, environ)
  as_c := resolve_in_path(a, environ, "as")
  ld_c := resolve_in_path(a, environ, "ld")
  if as_c == 0 { tool_error("alatyr: `as` not found on PATH (the assembler is required to build)"); return 11 }
  if ld_c == 0 { tool_error("alatyr: `ld` not found on PATH (the linker is required to build)"); return 12 }
  dash_o := cstr(a, "-o")
  ra := exec4(a, as_c, outs_c, dash_o, outo_c, envp)
  if ra.kind != 0 { spawn_error(a, "assembler", "as", ra); return 19 }
  if ra.code != 0 { tool_error("alatyr: the assembler (`as`) rejected the emitted assembly"); return 13 }
  ## MOD-9: with foreign libraries / linker_flags, hand off to `link_with_libs` (cc/ld with a
  ## dynamically-built argv). With NEITHER (the compiler's own self-build, and every non-manifest
  ## build), fall through to the plain raw-`ld` path below — byte-identical to before → fixpoint-neutral.
  if libnames.len > 0 or lflags.len > 0 {
    return link_with_libs(a, outo_c, out_c, entry, libnames, any_dyn, lflags, environ, envp)
  }
  ## Default ELF entry (`_start`) → the plain 3-arg `ld` (byte-identical to before / the self-build);
  ## a custom manifest entry → `ld … -e <entry>` so the loader jumps to that symbol.
  if entry == "_start" {
    rl := exec4(a, ld_c, outo_c, dash_o, out_c, envp)
    if rl.kind != 0 { spawn_error(a, "linker", "ld", rl); return 19 }
    if rl.code != 0 { tool_error("alatyr: the linker (`ld`) failed"); return 14 }
  } else {
    dash_e := cstr(a, "-e")
    entry_c := cstr(a, entry)
    rl := exec6(a, ld_c, outo_c, dash_o, out_c, dash_e, entry_c, envp)
    if rl.kind != 0 { spawn_error(a, "linker", "ld", rl); return 19 }
    if rl.code != 0 { tool_error("alatyr: the linker (`ld`) failed"); return 14 }
  }
  return 0
}

## Assemble a library object without inventing an executable entry point. The emitted GAS is retained as
## `<out>.s` for diagnostics/reproducibility, while `<out>` is the requested object artifact.
assemble_object := fn(in out a : rt::Arena, out : str, gbase : usize, glen : usize) -> usize {
  ssfx := cat2(a, out, ".s")
  outs_c := cstr(a, ssfx)
  out_c := cstr(a, out)
  w := rt::write_file(outs_c, gbase, glen)
  if w != 0 { tool_error("alatyr: cannot write the library assembly"); return 10 }
  mut etr := 0
  environ := read_environ(a, etr)
  if etr != 0 { env_truncation_error(); return 21 }
  envp := build_envp(a, environ)
  as_c := resolve_in_path(a, environ, "as")
  if as_c == 0 { tool_error("alatyr: `as` not found on PATH (the assembler is required for library targets)"); return 11 }
  dash_o := cstr(a, "-o")
  ra := exec4(a, as_c, outs_c, dash_o, out_c, envp)
  if ra.kind != 0 { spawn_error(a, "assembler", "as", ra); return 19 }
  if ra.code != 0 { tool_error("alatyr: the assembler (`as`) rejected the library assembly"); return 13 }
  return 0
}

## Build the deterministic one-object static archive required by Target.kind = static_lib. The current
## compiler emits one combined GAS stream for a package; archiving that one object is sufficient and keeps
## member order deterministic. The object is retained beside the archive as an inspectable intermediate.
build_static_archive := fn(in out a : rt::Arena, out : str, gbase : usize, glen : usize) -> usize {
  obj := cat2(a, out, ".o")
  ao := assemble_object(a, obj, gbase, glen)
  if ao != 0 { return ao }
  mut etr := 0
  environ := read_environ(a, etr)
  if etr != 0 { env_truncation_error(); return 21 }
  envp := build_envp(a, environ)
  ar_c := resolve_in_path(a, environ, "ar")
  if ar_c == 0 { tool_error("alatyr: `ar` not found on PATH (the archiver is required for static_lib targets)"); return 16 }
  flags := cstr(a, "rcs")
  out_c := cstr(a, out)
  obj_c := cstr(a, obj)
  rr := exec4(a, ar_c, flags, out_c, obj_c, envp)
  if rr.kind != 0 { spawn_error(a, "archiver", "ar", rr); return 19 }
  if rr.code != 0 { tool_error("alatyr: the archiver (`ar`) failed to create the static library"); return 17 }
  return 0
}

## Dispatch the two currently supported non-executable Target.kind values. A package target cannot
## smuggle executable-only foreign-link inputs into an object/archive: those inputs belong to a final
## executable target and are rejected until shared-library packaging defines their ABI surface.
emit_library_artifact := fn(in out a : rt::Arena, kind : str, out : str, gbase : usize, glen : usize, libnames : str, any_dyn : bool, lflags : str) -> usize {
  if libnames.len > 0 or any_dyn or lflags.len > 0 {
    tool_error("alatyr: object/static_lib targets cannot declare executable linker inputs")
    return 18
  }
  if kind == "object" { return assemble_object(a, out, gbase, glen) }
  return build_static_archive(a, out, gbase, glen)
}

## MOD-9 foreign-library link of the already-assembled `<out>.o` (at `outo_c`) into the executable
## `out_c`. Builds the linker argv word-by-word into a fixed arena slot array (a `-l<name>` per library
## name, each `linker_flag` verbatim BEFORE the `-l`s so `-L` search dirs are in effect), NUL-
## terminates it, and execve's the linker via `rt::run` with the real environ. Two link modes:
##   • any `LinkMode.dynamic` lib → `cc -nostartfiles <obj> -o <out> <flags> -l<name>…` — a dynamic
##     (PIE) binary; `-nostartfiles` keeps the program's OWN `_start`, and cc supplies the ELF
##     interpreter + default library search paths so `-lm` etc. resolve.
##   • all libs `LinkMode.static` (the hermetic default) → `ld -static <obj> -o <out> <flags> -l<name>…`.
##     (`cc -static` is unreliable in this environment — no system static libs on cc's default search
##     path — so a `-L<dir>` in `linker_flags` points `ld` at the `.a` archive to absorb.)
## A non-default `entry` symbol adds `-e <entry>` (ld) / `-Wl,-e,<entry>` (cc). Returns 0, or 12 (no
## ld) / 15 (no cc) / 14 (linker failed).
link_with_libs := fn(in out a : rt::Arena, outo_c : usize, out_c : usize, entry : str, libnames : str, any_dyn : bool, lflags : str, environ : str, envp : usize) -> usize {
  dash_o := cstr(a, "-o")
  mut prog_c := 0
  ## argv slots (a generous fixed cap — a manifest names a handful of libs/flags).
  av := rt::bump(a, 4096)
  mut k := 0
  if any_dyn {
    prog_c = resolve_in_path(a, environ, "cc")
    if prog_c == 0 { tool_error("alatyr: neither `cc` nor `ld` found on PATH (needed to link)"); return 15 }
    nostart := cstr(a, "-nostartfiles")
    wword(av + k * 8, prog_c) ; k = k + 1
    wword(av + k * 8, nostart) ; k = k + 1
  } else {
    prog_c = resolve_in_path(a, environ, "ld")
    if prog_c == 0 { tool_error("alatyr: `ld` not found on PATH (the linker is required to build)"); return 12 }
    dstatic := cstr(a, "-static")
    wword(av + k * 8, prog_c) ; k = k + 1
    wword(av + k * 8, dstatic) ; k = k + 1
  }
  ## <obj> -o <out>
  wword(av + k * 8, outo_c) ; k = k + 1
  wword(av + k * 8, dash_o) ; k = k + 1
  wword(av + k * 8, out_c) ; k = k + 1
  ## a non-default ELF entry symbol (default `_start` is the ELF entry with no flag).
  if entry == "_start" {
    ## nothing — `_start` is the conventional ELF entry
  } else {
    if any_dyn {
      wl := cat2(a, "-Wl,-e,", entry)
      wlc := cstr(a, wl)
      wword(av + k * 8, wlc) ; k = k + 1
    } else {
      dash_e := cstr(a, "-e")
      entry_c := cstr(a, entry)
      wword(av + k * 8, dash_e) ; k = k + 1
      wword(av + k * 8, entry_c) ; k = k + 1
    }
  }
  ## the raw linker_flags (each already a whole flag token, e.g. `-L/abs/dir`), BEFORE the `-l`s.
  lb := unchecked bitcast(usize, lflags.ptr)
  mut fi := 0
  while fi < lflags.len {
    mut fe := fi
    while fe < lflags.len and bytes(lflags)[fe] != 10 { fe = fe + 1 }
    if fe > fi {
      seg := str_at(lb + fi, fe - fi)
      fc := cstr(a, seg)
      wword(av + k * 8, fc) ; k = k + 1
    }
    fi = fe + 1
  }
  ## each library name as `-l<name>`.
  nb := unchecked bitcast(usize, libnames.ptr)
  mut li := 0
  while li < libnames.len {
    mut le := li
    while le < libnames.len and bytes(libnames)[le] != 10 { le = le + 1 }
    if le > li {
      nm := str_at(nb + li, le - li)
      lopt := cat2(a, "-l", nm)
      lc := cstr(a, lopt)
      wword(av + k * 8, lc) ; k = k + 1
    }
    li = le + 1
  }
  wword(av + k * 8, 0)
  rl := rt::run(a, prog_c, av, envp)
  if rl.kind != 0 { spawn_error(a, "linker", "ld", rl); return 19 }
  if rl.code != 0 { tool_error("alatyr: the linker (`ld`) failed"); return 14 }
  return 0
}

## TOOL-6 slice 1c-γ: assemble + link a PER-MODULE SPLIT build. `spanbase` holds the lower's span table
## (word 0 = span count N; then N × (start,len) byte spans of the GAS `[gbase, gbase+glen)`), already
## rewritten to post-peephole offsets by `lower::peephole_and_respan`. Each span is one module's block
## (plus one trailing instances span): it is written to its own `<out>.<i>.s`, assembled with `as` into
## `<out>.<i>.o`, and one `ld` links all N objects into `<out>`. Cross-module symbols were made `.globl`
## (slice 1c-α) so `as` leaves them as external references that `ld` resolves across the objects; the
## remaining `.L*` labels (control flow, strings, floats) are module-local. Falls back to the single-`.s`
## `link_exe` (byte-identical to the pre-split build) when N<=1 or foreign libraries are present (the
## split + `cc`/`-l` path is a later slice). `paths` is the same newline-joined, deterministic module
## input list passed to `driver::compile_files`; the lower records one span per path and one final
## instances span. Returns the same status codes as `link_exe`.
emission_span_hash := fn(base : usize, start : usize, len : usize) -> u64 {
  ## Stable GAS-span fingerprint: 64-bit FNV-1a over the exact post-peephole bytes, represented in
  ## the manifest as unsigned decimal. This is deliberately local to cli.al: no source reread,
  ## filesystem metadata, host hash, or platform-dependent tool is part of the fingerprint.
  mut h : u64 = 1469598103934665603
  mut i := 0
  while i < len {
    b := u64(bytes(str_at(base + start + i, 1))[0])
    h = unchecked ((h ^ b) * 1099511628211)
    i += 1
  }
  h
}

## Append an unsigned u64 in decimal without routing through the signed `rt::push_int` surface.
## Hashes above 2^63 therefore remain self-describing and stable instead of acquiring a sign. The
## recursive decimal shape is the existing `alloc::strbuf::push_uint` idiom; using division in the
## guard keeps the comparison unsigned for the full u64 range.
emission_push_u64 := fn(in out b : rt::StrBuf, n : u64) {
  if n / 10 != 0 {
    emission_push_u64(b, n / 10)
  }
  rt::push_byte(b, u8(n % 10 + 48))
}

## Return the `want`-th non-empty line of the newline-joined compile list. Source paths cannot contain
## newlines, so this is an unambiguous claimed-input mapping. A mismatch is retained as an explicit
## marker rather than silently assigning a neighboring source to a GAS span.
emission_input_path := fn(paths : str, want : usize) -> str {
  base := unchecked bitcast(usize, paths.ptr)
  mut seg := 0
  mut i := 0
  mut seen := 0
  while i <= paths.len {
    mut end_line := false
    if i == paths.len { end_line = true }
    else if bytes(paths)[i] == 10 { end_line = true }
    if end_line {
      if i > seg {
        if seen == want { return str_at(base + seg, i - seg) }
        seen += 1
      }
      seg = i + 1
    }
    i += 1
  }
  "<unmapped-module>"
}

## Write the deterministic sidecar after every per-module `.s` has been materialized. The manifest
## records the exact FINAL span geometry, GAS hash, and driver-resolved source path; source bytes are not
## reread here because the emitted span is already the authoritative input to `as`. The final span
## is explicitly attributed to monomorphized instances, which have no source path of their own.
emission_manifest := fn(in out a : rt::Arena, out : str, paths : str, gbase : usize, glen : usize, spanbase : usize, nspan : usize) -> usize {
  mp := cat2(a, out, ".manifest")
  span_paths := emission_paths_for(paths)
  mut b := rt::strbuf(a, out.len + span_paths.len + nspan * 160 + 256)
  rt::push_str(b, "format=alatyr-emission-manifest\n")
  rt::push_str(b, "version=2\n")
  rt::push_str(b, "output=")
  rt::push_str(b, out)
  rt::push_byte(b, 10)
  rt::push_str(b, "hash=fnv1a64\n")
  rt::push_str(b, "hash_encoding=unsigned-decimal\n")
  rt::push_str(b, "emission_size=")
  emission_push_u64(b, u64(glen))
  rt::push_byte(b, 10)
  rt::push_str(b, "span_count=")
  emission_push_u64(b, u64(nspan))
  rt::push_byte(b, 10)
  mut prev := 0
  mut bad_geometry := false
  mut bad_attribution := false
  mut i := 0
  while i < nspan {
    st := rt::rec_get(unchecked bitcast(ptr(mut u8), spanbase), 1 + i * 2)
    ln := rt::rec_get(unchecked bitcast(ptr(mut u8), spanbase), 2 + i * 2)
    if st != prev { bad_geometry = true }
    if st > glen { bad_geometry = true }
    else if ln > glen - st { bad_geometry = true }
    prev = st + ln
    rt::push_str(b, "span=")
    emission_push_u64(b, u64(i))
    if i + 1 == nspan {
      rt::push_str(b, " kind=instances")
    } else {
      rt::push_str(b, " kind=module")
    }
    rt::push_str(b, " start=")
    emission_push_u64(b, u64(st))
    rt::push_str(b, " len=")
    emission_push_u64(b, u64(ln))
    rt::push_str(b, " gas_hash=")
    emission_push_u64(b, emission_span_hash(gbase, st, ln))
    rt::push_str(b, " input=")
    if i + 1 == nspan {
      rt::push_str(b, "<monomorphized-instances>")
    } else {
      ip := emission_input_path(span_paths, i)
      if ip == "<unmapped-module>" { bad_attribution = true }
      rt::push_str(b, ip)
    }
    rt::push_byte(b, 10)
    i += 1
  }
  if prev != glen { bad_geometry = true }
  if bad_geometry {
    tool_error("alatyr: emission manifest span geometry does not tile the final GAS")
    return 10
  }
  if bad_attribution {
    tool_error("alatyr: emission manifest has an unmapped module span")
    return 10
  }
  w := rt::write_file(cstr(a, mp), b.data, b.len)
  if w != 0 {
    tool_error("alatyr: cannot write the emission manifest")
    return 10
  }
  0
}

## Write the deterministic interface/layout summary beside the split artifact. The compiler owns
## the summary bytes; cli only chooses the stable `<output>.interface` path and performs the write.
interface_summary_sidecar := fn(in out a : rt::Arena, out : str) -> usize {
  p := driver::interface_summary_ptr()
  n := driver::interface_summary_len()
  if p == 0 or n == 0 {
    tool_error("alatyr: interface summary is empty")
    return 10
  }
  ip := cat2(a, out, ".interface")
  w := rt::write_file(cstr(a, ip), p, n)
  if w != 0 {
    tool_error("alatyr: cannot write the interface summary")
    return 10
  }
  0
}

link_exe_split := fn(in out a : rt::Arena, out : str, paths : str, gbase : usize, glen : usize, spanbase : usize, entry : str, libnames : str, any_dyn : bool, lflags : str) -> usize {
  ## The per-module .o split is DISABLED (safe no-op) pending a base-emit codegen fix: under some heap
  ## layouts a mis-addressed store in this path corrupts a live StrBuf cap (→ `rt: StrBuf overflow`).
  ## It is fail-loud / never a silent miscompile, and the split's own payoff is <2% (perf showed as+ld is
  ## ~0.67 s of a ~28 s build — the compiler's OWN execution dominates). The wild write is UN-OBSERVABLE:
  ## it evaporates under gdb, rr (Zen), and any diagnostic recompile (each shifts the codegen lottery), so
  ## it needs a probe-free static audit or a non-Zen rr host. Until then, always take the proven single-`.s`
  ## `link_exe`; the split body below is retained (dead) so re-enabling is a one-line delete of this guard.
  ## See memory `link-exe-split-selfhost-miscompile`. `ALATYR_OSPLIT=1` therefore builds correctly (no split).
  ## The disabling guard is GONE: the "un-pinnable codegen fault" was a 64-byte name StrBuf overflowing
  ## for any `out` path >= 54 bytes (see the two `out.len + 64` sizings below). Fail-loud, deterministic.
  mut nspan := 0
  if spanbase != 0 { nspan = rt::rec_get(unchecked bitcast(ptr(mut u8), spanbase), 0) }
  if nspan <= 1 { return link_exe(a, out, gbase, glen, entry, libnames, any_dyn, lflags) }
  if libnames.len > 0 or lflags.len > 0 { return link_exe(a, out, gbase, glen, entry, libnames, any_dyn, lflags) }
  ## Dedicated scratch arena for ALL of the link step's transient allocations (environ read, envp array,
  ## ld argv, per-span `.s`/`.o` name buffers), kept off the shared `a` where the span table + GAS live.
  mut sc := rt::Arena(base = 0, off = 0, cap = 0)
  rt::arena_init(sc, 16777216)
  mut etr := 0
  environ := read_environ(sc, etr)
  if etr != 0 { env_truncation_error(); return 21 }
  envp := build_envp(sc, environ)
  as_c := resolve_in_path(sc, environ, "as")
  ld_c := resolve_in_path(sc, environ, "ld")
  if as_c == 0 { tool_error("alatyr: `as` not found on PATH (the assembler is required to build)"); return 11 }
  if ld_c == 0 { tool_error("alatyr: `ld` not found on PATH (the linker is required to build)"); return 12 }
  dash_o := cstr(sc, "-o")
  ## ld argv slots: ld + N object cstrs + `-o` + out + optional `-e <entry>` + NUL terminator.
  av := rt::bump(sc, nspan * 8 + 128)
  mut k := 0
  wword(av + k * 8, ld_c) ; k = k + 1
  ## Build every module-path `.s` / `.o` name UP FRONT into its own scratch buffer, storing the `.o` cstr
  ## pointers in `av`, BEFORE running any `as`. Doing the name-building and the `as`/`write_file` in one
  ## interleaved loop tripped a self-host-lower codegen fault (a transient buffer's bytes bled into a live
  ## StrBuf header → "rt: StrBuf overflow", heisen-sensitive to allocation order); separating the two
  ## phases keeps each loop body simple and sidesteps it. `sos`/`oos` hold the per-span `.s`/`.o` cstrs.
  sos := rt::bump(sc, nspan * 8 + 64)
  oos := rt::bump(sc, nspan * 8 + 64)
  mut i := 0
  while i < nspan {
    sname0 := split_module_artifact_path(sc, out, paths, i, nspan, ".s")
    mut nbs := rt::strbuf(sc, sname0.len + 8)
    rt::push_str(nbs, sname0)
    ## Bind `str_at(...)` to a LOCAL before forwarding it to `cstr` (a `str` param): the lean self-host
    ## lower passes a str arg by pointer, so an INLINE str-returning call as a str arg forwards only the
    ## data pointer (%rax) and DROPS the length (%rdx). (link_exe documents the same rule at its head.)
    sname := str_at(nbs.data, nbs.len)
    snc := cstr(sc, sname)
    oname0 := split_module_artifact_path(sc, out, paths, i, nspan, ".o")
    mut nbo := rt::strbuf(sc, oname0.len + 8)
    rt::push_str(nbo, oname0)
    oname := str_at(nbo.data, nbo.len)
    onc := cstr(sc, oname)
    wword(sos + i * 8, snc)
    wword(oos + i * 8, onc)
    wword(av + k * 8, onc) ; k = k + 1
    i = i + 1
  }
  ## Phase 2: write each span's bytes to its `.s` and assemble it into its `.o`. NO early `return` from
  ## inside the loop — the lean self-host lower mis-lowers an in-loop return into a layout-dependent stack
  ## corruption (documented at `lower::ra_env_init`; here it surfaced as a heisen "rt: StrBuf overflow").
  ## Accumulate an error code and return AFTER the loop instead.
  mut err := 0
  mut j := 0
  while j < nspan and err == 0 {
    st := rt::rec_get(unchecked bitcast(ptr(mut u8), spanbase), 1 + j * 2)
    ln := rt::rec_get(unchecked bitcast(ptr(mut u8), spanbase), 2 + j * 2)
    snc := rt::rec_get(unchecked bitcast(ptr(mut u8), sos), j)
    onc := rt::rec_get(unchecked bitcast(ptr(mut u8), oos), j)
    w := rt::write_file(snc, gbase + st, ln)
    if w != 0 { err = 10 }
    if err == 0 {
      ra := exec4(sc, as_c, snc, dash_o, onc, envp)
      if ra.kind != 0 { spawn_error(sc, "assembler", "as", ra); err = 19 }
      else if ra.code != 0 { err = 13 }
    }
    j = j + 1
  }
  if err != 0 { return err }
  em := emission_manifest(a, out, paths, gbase, glen, spanbase, nspan)
  if em != 0 { return em }
  im := interface_summary_sidecar(a, out)
  if im != 0 { return im }
  out_c := cstr(sc, out)
  wword(av + k * 8, dash_o) ; k = k + 1
  wword(av + k * 8, out_c) ; k = k + 1
  if entry == "_start" {
    ## default ELF entry — no `-e` flag (the plain `ld` path, matching link_exe's fixpoint-neutral case)
  } else {
    dash_e := cstr(sc, "-e")
    entry_c := cstr(sc, entry)
    wword(av + k * 8, dash_e) ; k = k + 1
    wword(av + k * 8, entry_c) ; k = k + 1
  }
  wword(av + k * 8, 0)
  rl := rt::run(sc, ld_c, av, envp)
  if rl.kind != 0 { spawn_error(sc, "linker", "ld", rl); return 19 }
  if rl.code != 0 { tool_error("alatyr: the linker (`ld`) failed"); return 14 }
  return 0
}

## Does `s` end with `suf`?
pub ends_with := fn(s : str, suf : str) -> bool {
  if s.len < suf.len { return false }
  off := s.len - suf.len
  mut i := 0
  while i < suf.len {
    if bytes(s)[off + i] != bytes(suf)[i] { return false }
    i += 1
  }
  return true
}

## The directory part of a `/`-path (everything before the LAST `/`); 0-len if there is no `/`.
pub dir_of := fn(path : str) -> str {
  mut last := 0
  mut seen := false
  mut i := 0
  while i < path.len {
    if bytes(path)[i] == 47 { last = i; seen = true }
    i += 1
  }
  base := unchecked bitcast(usize, path.ptr)
  if seen == false { return str_at(base, 0) }
  return str_at(base, last)
}

## The parent of a lexical directory path. Discovery deliberately walks the filesystem tree by path
## spelling, not by VCS boundaries or realpath: TOOL-14 says the first package.al on the upward walk
## wins. The root is its own parent, which gives the caller a terminating comparison.
parent_dir := fn(path : str) -> str {
  if path.len == 0 { return "." }
  mut last := 0
  mut seen := false
  mut i := 0
  while i < path.len {
    if bytes(path)[i] == 47 { last = i ; seen = true }
    i += 1
  }
  if seen == false { return "." }
  base := unchecked bitcast(usize, path.ptr)
  if last == 0 { return str_at(base, 1) }
  return str_at(base, last)
}

## The stem of the first root source file for a manifest-less invocation (TOOL-11/14). Keep the
## directory out of the artifact name; the location is chosen separately by the CLI build mode.
file_stem := fn(path : str) -> str {
  mut start := 0
  mut i := 0
  while i < path.len {
    if bytes(path)[i] == 47 { start = i + 1 }
    i += 1
  }
  base := unchecked bitcast(usize, path.ptr)
  mut n := path.len - start
  if n >= 3 and str_at(base + start + n - 3, 3) == ".al" { n = n - 3 }
  return str_at(base + start, n)
}

## List the `.al` module files below directory `dir`, EXCLUDING every `package.al` manifest, as a
## newline-joined `str` of paths for `driver::compile_files`. `list_al_in_tree` is the single
## getdents64 walker used by both package discovery and package-wide `fmt`; keeping the I/O in one
## implementation avoids the old one-level scan and a second recursive directory traversal drifting
## apart. The filter is deliberately path-based, so a nested directory named `package.al` cannot
## accidentally become a build module either. The result remains byte-lexicographically sorted by
## the shared tree walker, which is the deterministic module order required by the tooling contract.
## Byte-lexicographic `<` over two spans of the same `str` `astr` (`[s1,s1+l1)` vs `[s2,s2+l2)`): the
## first differing byte decides; a proper prefix is less. Deterministic ordering key for the module sort.
str_lt := fn(astr : str, s1 : usize, l1 : usize, s2 : usize, l2 : usize) -> bool {
  mut mn := l1
  if l2 < l1 { mn = l2 }
  mut i := 0
  while i < mn {
    c1 := bytes(astr)[s1 + i]
    c2 := bytes(astr)[s2 + i]
    if c1 < c2 { return true }
    if c2 < c1 { return false }
    i += 1
  }
  return l1 < l2
}

## Sort a newline-joined path list `astr` into byte-lexicographic order (deterministic across
## filesystems — the getdents order is FS-state-dependent). Collect each line's (start, len) into
## fixed arrays (≤256 modules), selection-sort them by `str_lt` (array element SWAP — the lean lower
## handles it; the earlier svec-record swap did not), then rebuild the joined list. Returns the sorted
## newline-joined `str`. (Selection sort: N≤256 module files, so O(N²) is irrelevant.)
sort_path_lines := fn(in out a : rt::Arena, astr : str) -> str {
  mut starts : [usize; 256] = [0; 256]
  mut lens : [usize; 256] = [0; 256]
  mut n := 0
  mut p := 0
  while p < astr.len {
    mut e := p
    while e < astr.len and bytes(astr)[e] != 10 { e = e + 1 }
    if e > p and n < 256 {
      starts[n] = p
      lens[n] = e - p
      n += 1
    }
    p = e + 1
  }
  mut i := 0
  while i < n {
    mut mnj := i
    mut j := i + 1
    while j < n {
      if str_lt(astr, starts[j], lens[j], starts[mnj], lens[mnj]) { mnj = j }
      j += 1
    }
    ts := starts[i]; starts[i] = starts[mnj]; starts[mnj] = ts
    tl := lens[i]; lens[i] = lens[mnj]; lens[mnj] = tl
    i += 1
  }
  mut out := rt::strbuf(a, astr.len + 16)
  ab := unchecked bitcast(usize, astr.ptr)
  mut k := 0
  while k < n {
    kp := rt::push_str(out, str_at(ab + starts[k], lens[k]))
    kn := rt::push_byte(out, 10)
    k += 1
  }
  return str_at(out.data, out.len)
}

pub list_al_in_dir := fn(in out a : rt::Arena, dir : str) -> str {
  ## The tree walk includes the manifest for fmt, so retain its output as the source list and
  ## remove only basename-exact `package.al` entries. This preserves the walk's sorted order and
  ## avoids opening any directory twice.
  all := list_al_in_tree(a, dir)
  mut out := rt::strbuf(a, all.len + 16)
  base := unchecked bitcast(usize, all.ptr)
  mut p := 0
  while p < all.len {
    mut e := p
    while e < all.len and bytes(all)[e] != 10 { e += 1 }
    if e > p {
      mut last := p
      mut j := p
      while j < e {
        if bytes(all)[j] == 47 { last = j + 1 }
        j += 1
      }
      is_manifest := e - last == 10 and str_at(base + e - 10, 10) == "package.al"
      if is_manifest == false {
        k1 := rt::push_str(out, str_at(base + p, e - p))
        k2 := rt::push_byte(out, 10)
      }
    }
    p = e + 1
  }
  return str_at(out.data, out.len)
}

## List every `.al` file below `root`, including the manifest, in deterministic path order. This is
## the package-wide `fmt` discovery surface (Tooling §4.2): unlike build module discovery, it walks
## subdirectories and must not discard `package.al`. Linux getdents64 supplies the directory-entry
## type byte, so the queue can descend without a stat pass. Paths are kept newline-joined because that
## is the proven self-host I/O boundary shape; the fixed arena bounds match the existing package scan.
list_al_in_tree := fn(in out a : rt::Arena, root : str) -> str {
  mut files := rt::strbuf(a, 1048576)
  mut dirs := rt::strbuf(a, 262144)
  k0 := rt::push_str(dirs, root)
  k1 := rt::push_byte(dirs, 10)
  mut qpos := 0
  while qpos < dirs.len {
    mut qe := qpos
    while qe < dirs.len and bytes(str_at(dirs.data, dirs.len))[qe] != 10 { qe += 1 }
    if qe > qpos {
      dir := str_at(dirs.data + qpos, qe - qpos)
      dc := cstr(a, dir)
      fd := rt::sys_open(2, dc, 0, 0)
      if fd >= 0 {
        ufd := unchecked bitcast(usize, fd)
        buf := rt::bump(a, 65536)
        mut going := true
        while going {
          nr := rt::sys_getdents64(217, ufd, buf, 65536)
          if nr <= 0 { going = false } else {
            m := unchecked bitcast(usize, nr)
            bs := str_at(buf, m)
            mut pos := 0
            while pos < m {
              reclen := bytes(bs)[pos + 16] + bytes(bs)[pos + 17] * 256
              if reclen == 0 { pos = m } else {
                mut e := pos + 19
                while e < m and bytes(bs)[e] != 0 { e += 1 }
                nlen := e - (pos + 19)
                mut dot := false
                if nlen == 1 and bytes(bs)[pos + 19] == 46 { dot = true }
                if nlen == 2 and bytes(bs)[pos + 19] == 46 and bytes(bs)[pos + 20] == 46 { dot = true }
                if dot == false {
                  dtype := bytes(bs)[pos + 18]
                  if dtype == 4 {
                    kd := rt::push_str(dirs, dir)
                    kds := rt::push_byte(dirs, 47)
                    mut j := pos + 19
                    while j < e { kn := rt::push_byte(dirs, bytes(bs)[j]); j += 1 }
                    kdn := rt::push_byte(dirs, 10)
                  } else {
                    mut isal := false
                    if nlen >= 3 {
                      if bytes(bs)[e - 3] == 46 and bytes(bs)[e - 2] == 97 and bytes(bs)[e - 1] == 108 { isal = true }
                    }
                    if isal {
                      kf := rt::push_str(files, dir)
                      kfs := rt::push_byte(files, 47)
                      mut j := pos + 19
                      while j < e { kn := rt::push_byte(files, bytes(bs)[j]); j += 1 }
                      kfn := rt::push_byte(files, 10)
                    }
                  }
                }
                pos += reclen
              }
            }
          }
        }
        cc := rt::sys_close(3, ufd)
      }
    }
    qpos = qe + 1
  }
  return sort_path_lines(a, str_at(files.data, files.len))
}

## Reformat each path in the newline-joined package list in place. `compile_file_fmt` only writes
## after a complete parse and therefore a malformed file remains byte-for-byte untouched; its
## fail-loud parse diagnostic still aborts the command. Valid files are processed in sorted order,
## making both the rewrite order and the first reported invalid path deterministic.
fmt_package_files := fn(in out a : rt::Arena, paths : str) -> usize {
  mut p := 0
  while p < paths.len {
    mut e := p
    while e < paths.len and bytes(paths)[e] != 10 { e += 1 }
    if e > p {
      path := str_at(unchecked bitcast(usize, paths.ptr) + p, e - p)
      mut fsb := driver::compile_file_fmt(path, a)
      wr := rt::write_file(cstr(a, path), fsb.data, fsb.len)
      if wr != 0 { return 41 }
    }
    p = e + 1
  }
  return 0
}

## Is `needle` present as a whole newline-delimited line in the accumulated set buffer `setbuf`?
## (The dedup membership test for transitive-dep package directories — terminates cycles + drops
## a dep reached by more than one path.)
line_in_set := fn(in out setbuf : rt::StrBuf, needle : str) -> bool {
  s := str_at(setbuf.data, setbuf.len)
  mut found := false
  mut i := 0
  mut ls := 0
  while i <= s.len and found == false {
    mut isnl := true
    if i < s.len { isnl = bytes(s)[i] == 10 }
    if isnl {
      if i - ls == needle.len {
        mut eq := true
        mut j := 0
        while j < needle.len {
          if bytes(s)[ls + j] != bytes(needle)[j] { eq = false }
          j += 1
        }
        if eq { found = true }
      }
      ls = i + 1
    }
    i += 1
  }
  return found
}

## Collapse `seg/../` and `./` segments in a `/`-path purely as a string (no realpath syscall), so
## two spellings of the same directory normalize to one form — this DEDUPS a diamond dependency
## (reached two ways) and TERMINATES a dependency cycle (whose `..`-laden paths would otherwise keep
## differing and never match the seen-set). Preserves a leading `/` (absolute) vs none (relative).
normalize_path := fn(in out a : rt::Arena, p : str) -> str {
  abs := p.len > 0 and bytes(p)[0] == 47
  mut out := rt::strbuf(a, p.len + 16)
  if abs { kk := rt::push_byte(out, 47) }
  pbase := unchecked bitcast(usize, p.ptr)
  mut minlen := 0
  if abs { minlen = 1 }
  mut i := 0
  while i < p.len {
    while i < p.len and bytes(p)[i] == 47 { i = i + 1 }   ## skip a run of '/'
    s := i
    while i < p.len and bytes(p)[i] != 47 { i = i + 1 }   ## the segment [s, i)
    if i > s {
      seg := str_at(pbase + s, i - s)
      if seg == ".." {
        ## pop the last out-segment (truncate to the previous '/', not below the root)
        obase := unchecked bitcast(usize, out.data)
        ob := str_at(out.data, out.len)
        mut cut := minlen        ## where the head ends once the last segment is dropped
        mut segs := minlen       ## where the last segment begins
        mut t := minlen
        while t < out.len {
          if bytes(ob)[t] == 47 { cut = t ; segs = t + 1 }
          t += 1
        }
        mut popped := false
        if out.len > minlen {
          lastseg := str_at(obase + segs, out.len - segs)
          if abs or lastseg != ".." { out.len = cut ; popped = true }
        }
        ## A RELATIVE path with nothing left to pop — or whose last segment is ITSELF `..` — keeps the
        ## `..`: `../dep` names a real directory ABOVE the package, not `dep`. Swallowing it silently
        ## retargeted a `DepSource.Path("../dep")` resolved from a BARE manifest path (empty pkgdir) at
        ## the wrong directory. An ABSOLUTE path still clamps at `/` (there is nothing above the root).
        if popped == false and abs == false {
          if out.len > 0 { ksep2 := rt::push_byte(out, 47) }
          kdd2 := rt::push_str(out, "..")
        }
      } else if seg == "." {
        ## drop a `.` segment
      } else {
        mut need_sep := out.len > 0
        if abs and out.len == 1 { need_sep = false }
        if need_sep { ksep := rt::push_byte(out, 47) }
        kseg := rt::push_str(out, seg)
      }
    }
  }
  ## A RELATIVE path whose every segment was dropped names the CURRENT directory, so its canonical
  ## form is `.`, never the empty string. The empty answer was a real defect: `DepSource.Path(".")`
  ## resolved from a bare `package.al` (empty `pkgdir` → base `.`) normalized `./.` to "", and the
  ## dependency manifest then came out as the ABSOLUTE `/package.al` — a self-dependency was reported
  ## as a missing manifest at the filesystem root instead of as the MOD-11 cycle it is. An ABSOLUTE
  ## path keeps its `/` (the loop already pushed it) and cannot reach here empty.
  if out.len == 0 and abs == false { kdot := rt::push_str(out, ".") }
  return str_at(out.data, out.len)
}

## MOD-10 / Modules §8 — a path dependency's IDENTITY IN THE GRAPH: its LEXICALLY-NORMALIZED
## ABSOLUTE path. An alias is package-local naming and never identifies a package, and a *relative*
## spelling does not either: `../c` reached from `a/` and `../../dia/c` reached from `b/` are the SAME
## dependency, so keying the graph by the relative spelling split one package into two — it was then
## walked twice, its modules compiled twice under the same alias, and the build died on a duplicate
## symbol (`c__math__answer` already defined) instead of resolving a diamond.
##
## Absolute means resolved against the process's current directory, and normalization stays
## LEXICAL — `..` pops a segment as text, no `realpath`, because MOD-10's rule is a lexical one and a
## filesystem query would make identity depend on the state of the disk. (The one unavoidable
## exception is the BASE: `/proc/self/cwd` is the kernel's already-resolved current directory. Two
## spellings that differ only by a symlink BELOW the cwd therefore remain two sources — the same
## deliberate choice MOD-10 makes for two spellings of one git URL.) A path that is already absolute
## is normalized as-is; an unreadable cwd link leaves it relative, which can only under-dedup.
abs_norm_path := fn(in out a : rt::Arena, p : str) -> str {
  if p.len > 0 { if bytes(p)[0] == 47 { return normalize_path(a, p) } }
  cw := cwd_dir(a)
  j1 := cat2(a, cw, "/")
  raw := cat2(a, j1, p)
  return normalize_path(a, raw)
}

## The first out-edge target of node `from` in `edges` (newline-joined `<from>TAB<to>` rows) whose
## target is NOT in `dead`; an EMPTY str when `from` has no live out-edge. The primitive both halves
## of the MOD-11 cycle check are built from — sink peeling asks "does this node still have one?" and
## the chain walk asks "which one?", and both must agree on the answer, so they share this scan.
edge_live_target := fn(in out edges : rt::StrBuf, in out dead : rt::StrBuf, from : str) -> str {
  s := str_at(edges.data, edges.len)
  sbase := unchecked bitcast(usize, s.ptr)
  mut res := str_at(sbase, 0)
  mut found := false
  mut ls := 0
  mut i := 0
  while i <= s.len {
    mut isnl := true
    if i < s.len { isnl = bytes(s)[i] == 10 }
    if isnl {
      if i > ls and found == false {
        mut t := ls
        while t < i and bytes(s)[t] != 9 { t = t + 1 }
        if t < i {
          f := str_at(sbase + ls, t - ls)
          if f == from {
            to := str_at(sbase + t + 1, i - (t + 1))
            if line_in_set(dead, to) == false { res = to ; found = true }
          }
        }
      }
      ls = i + 1
    }
    i += 1
  }
  return res
}

## MOD-11 — the head node of the cycle `graph_cycle_chain` last found, published as (ptr, len) scalars
## so the caller can locate the diagnostic at the manifest that declares a closing edge. Zero length
## means "no cycle found" (the acyclic case never reads it).
mut CYCLE_HEAD_P := 0
mut CYCLE_HEAD_N := 0

## MOD-11 / Modules §8 — the closing chain of a cycle in the resolved package graph, rendered as
## `<src> -> <src> -> … -> <src>` (the first source repeated last), or an EMPTY str when the graph is
## acyclic. `nodes` is the newline-joined set of every package the walk resolved and `edges` its
## `<from>TAB<to>` dependency edges, both keyed by the package's SOURCE (MOD-10).
##
## Detection is SINK PEELING (Kahn on out-degree): a node with no out-edge to a still-live node cannot
## lie on a cycle, so it is removed, and the removal is repeated to a fixpoint. Whatever survives lies
## on a cycle or leads into one; following one live out-edge from a survivor therefore must revisit a
## node, and the revisited node opens the cycle. Peeling over the WHOLE edge set is what makes this
## sound: the walk visits each package exactly once, so a chain carried along the traversal path would
## miss a cycle that closes BESIDE it (`b -> c -> b`, discovered while walking `root -> a -> c`) —
## while every edge of that cycle is nonetheless recorded here.
graph_cycle_chain := fn(in out a : rt::Arena, nodes : str, in out edges : rt::StrBuf) -> str {
  nbase := unchecked bitcast(usize, nodes.ptr)
  mut dead := rt::strbuf(a, 65536)
  mut changed := true
  while changed {
    changed = false
    mut ls := 0
    mut i := 0
    while i <= nodes.len {
      mut isnl := true
      if i < nodes.len { isnl = bytes(nodes)[i] == 10 }
      if isnl {
        if i > ls {
          nn := str_at(nbase + ls, i - ls)
          if line_in_set(dead, nn) == false {
            tgt := edge_live_target(edges, dead, nn)
            if tgt.len == 0 {
              kd := rt::push_str(dead, nn)
              kdn := rt::push_byte(dead, 10)
              changed = true
            }
          }
        }
        ls = i + 1
      }
      i += 1
    }
  }
  ## the first SURVIVOR, in the walk's (deterministic) discovery order — so the reported chain is the
  ## same one on every run and on every conforming implementation of this walk.
  mut start := str_at(nbase, 0)
  mut have := false
  mut ls1 := 0
  mut i1 := 0
  while i1 <= nodes.len {
    mut isnl := true
    if i1 < nodes.len { isnl = bytes(nodes)[i1] == 10 }
    if isnl {
      if i1 > ls1 and have == false {
        nn := str_at(nbase + ls1, i1 - ls1)
        if line_in_set(dead, nn) == false { start = nn ; have = true }
      }
      ls1 = i1 + 1
    }
    i1 += 1
  }
  if have == false { return str_at(nbase, 0) }
  ## follow one live out-edge at a time, recording the path, until a node repeats
  mut path := rt::strbuf(a, 65536)
  mut cur := start
  mut closing := str_at(nbase, 0)
  mut done := false
  while done == false {
    if line_in_set(path, cur) { closing = cur ; done = true }
    else {
      kp := rt::push_str(path, cur)
      kpn := rt::push_byte(path, 10)
      nxt := edge_live_target(edges, dead, cur)
      if nxt.len == 0 { done = true } else { cur = nxt }
    }
  }
  CYCLE_HEAD_P = unchecked bitcast(usize, closing.ptr)
  CYCLE_HEAD_N = closing.len
  ## render from the FIRST occurrence of the repeated node (the path may start with a tail that only
  ## LEADS INTO the cycle — those nodes survive the peel too, but they are not part of the cycle)
  ps := str_at(path.data, path.len)
  pbase := unchecked bitcast(usize, ps.ptr)
  mut out := rt::strbuf(a, path.len + 256)
  mut emitting := false
  mut ls2 := 0
  mut i2 := 0
  while i2 <= ps.len {
    mut isnl := true
    if i2 < ps.len { isnl = bytes(ps)[i2] == 10 }
    if isnl {
      if i2 > ls2 {
        nn := str_at(pbase + ls2, i2 - ls2)
        if emitting == false and nn == closing { emitting = true }
        if emitting {
          if out.len > 0 { karr := rt::push_str(out, " -> ") }
          kseg := rt::push_str(out, nn)
        }
      }
      ls2 = i2 + 1
    }
    i2 += 1
  }
  if out.len > 0 {
    karr2 := rt::push_str(out, " -> ")
    kcl := rt::push_str(out, closing)
  }
  return str_at(out.data, out.len)
}

## Set when a dependency DECLARATION is unsupported or unresolvable (Modules §8 / Tooling §2.4). The
## command aborts on it: a manifest whose dependency graph could not be honoured must never produce an
## artifact built from a SILENTLY different graph (the git source ignored, a missing package skipped).
mut DEP_CONFIG_BAD := false

## Report an unsupported/unresolvable dependency declaration as a LOCATED manifest diagnostic and mark
## the configuration bad. The dependency scanner is a byte scan (the manifest schema is not evaluated
## yet), so the reported anchor is the manifest's `dependencies` field — a file-relative line the user
## can act on — and `detail` names the offending source.
dep_config_error := fn(in out a : rt::Arena, msg : str, pkg_al : str, detail : str) {
  DEP_CONFIG_BAD = true
  mc := cstr(a, pkg_al)
  mtext := read_proc(a, mc, 262144)
  mut off := 0
  fi := mf_find_word(mtext, 0, "dependencies")
  if fi >= 0 { off = usize(fi) }
  mut line := 1
  mut i := 0
  while i < off and i < mtext.len { if bytes(mtext)[i] == 10 { line = line + 1 } ; i = i + 1 }
  mut db := rt::strbuf(a, msg.len + pkg_al.len + detail.len + 64)
  k0 := rt::push_str(db, msg)
  if detail.len != 0 {
    k1 := rt::push_str(db, " (")
    k2 := rt::push_str(db, detail)
    k3 := rt::push_byte(db, 41)
  }
  k4 := rt::push_str(db, " at line ")
  k5 := rt::push_int(db, i64(line))
  k6 := rt::push_str(db, " in ")
  k7 := rt::push_str(db, pkg_al)
  k8 := rt::push_byte(db, 10)
  w := rt::sys_write(1, 2, unchecked bitcast(usize, db.data), db.len)
}

## MOD-7 / Modules §8 — the EFFECTIVE ALIAS of the `Dependency(…)` record whose source expression sits
## at byte `hit`: the record's `alias = "…"` when non-empty, else its `name = "…"` (an empty alias means
## the dependency is reached under its own name). The scan walks BACK to the record's opening
## `Dependency(` so a LIST of dependencies attributes each source to its own record, then reads the
## fields lying between that opening and the source expression. Empty when the record names neither.
dep_alias_at := fn(mtext : str, hit : usize) -> str {
  mbase := unchecked bitcast(usize, mtext.ptr)
  mut rs := 0
  mut k := 0
  while k + 11 <= hit {
    if amb_lit_at(mtext, k, mtext.len, "Dependency(") { rs = k + 11 }
    k = k + 1
  }
  seg := str_at(mbase + rs, hit - rs)
  ai := mf_find_word(seg, 0, "alias")
  if ai >= 0 {
    av := mf_quoted(seg, usize(ai), 5)
    if av.len != 0 { return av }
  }
  ni := mf_find_word(seg, 0, "name")
  if ni >= 0 { return mf_quoted(seg, usize(ni), 4) }
  return str_at(mbase, 0)
}

## Read the manifest at `pkg_al`, scan it for `DepSource.Path("relpath")` dependencies (a byte scan for
## the literal `DepSource.Path(` + the following string — the FULLY-QUALIFIED spelling, so a bare
## `Path(` inside a comment / a `linker_flags` string is not mistaken for a dependency), resolve each
## relative to the package dir `pkgdir`, and enqueue `<normalized dep dir>/package.al` TAB the
## dependency's effective ALIAS onto `queue` (one newline-terminated row per dependency). A missing /
## dep-less manifest enqueues nothing. The lean dual of the Rust seed's manifest dep walk.
##
## FAIL-LOUD (Modules §8 / Tooling §2.4): a `DepSource.Git(…)` source and a path dependency with no
## `package.al` are LOCATED Config diagnostics — v1 here resolves PATH sources only, and silently
## dropping a declared dependency builds a different program than the manifest asks for.
##
## Every resolved edge is ALSO recorded in `edges` as `<this package's source>TAB<the dependency's
## source>`, so the caller can check MOD-11 acyclicity over the complete edge set once the walk is
## done (`graph_cycle_chain`) rather than along one traversal path.
scan_deps_into_queue := fn(in out a : rt::Arena, pkg_al : str, pkgdir : str, in out queue : rt::StrBuf, in out edges : rt::StrBuf) {
  mc := cstr(a, pkg_al)
  mtext := read_proc(a, mc, 262144)
  mbase := unchecked bitcast(usize, mtext.ptr)
  ## `base_dir` — the directory relative dependency paths resolve AGAINST, kept in the spelling the
  ## caller used so every file this resolver opens stays as relative as the manifest argument was. A
  ## BARE manifest path has an empty `pkgdir`: the package is then the CURRENT directory, `.`.
  mut base_dir := pkgdir
  if base_dir.len == 0 { base_dir = "." }
  ## this package's own graph IDENTITY (MOD-10) — the same key the BFS records in its seen-set, so an
  ## edge's two endpoints and the node set agree.
  from_key := abs_norm_path(a, base_dir)
  mut i := 0
  while i < mtext.len {
    if amb_lit_at(mtext, i, mtext.len, "DepSource.Git(") {
      dep_config_error(a, "config: a git dependency source is not supported yet — v1 resolves DepSource.Path only", pkg_al, "")
      i = i + 14
    } else if amb_lit_at(mtext, i, mtext.len, "DepSource.Path(") {
      mut j := i + 15
      while j < mtext.len and bytes(mtext)[j] != 34 { j = j + 1 }   ## to the opening quote (34)
      mut e := j + 1
      while e < mtext.len and bytes(mtext)[e] != 34 { e = e + 1 }   ## to the closing quote
      relp := str_at(mbase + j + 1, e - (j + 1))
      dalias := dep_alias_at(mtext, i)
      ## resolve + NORMALIZE `<pkgdir>/<relp>` to a canonical dir (collapsing `..`), so the seen-set
      ## dedup is exact (a diamond dep is compiled once; a dep cycle terminates). Bind every cat2 step
      ## to a local (the str-call-as-str-arg trap). The package manifest is `<normdir>/package.al`.
      ## A BARE manifest path (`package.al`) has an EMPTY `pkgdir`: the dep is then resolved against
      ## the CURRENT directory (`.`), never against `/` — which would make it absolute.
      d1 := cat2(a, base_dir, "/")
      rawdir := cat2(a, d1, relp)
      normdir := normalize_path(a, rawdir)
      deppkg := cat2(a, normdir, "/package.al")
      if dalias.len == 0 {
        dep_config_error(a, "config: a dependency declares neither a name nor an alias", pkg_al, relp)
      }
      dc := cstr(a, deppkg)
      dtext := read_proc(a, dc, 4096)
      if dtext.len == 0 {
        dep_config_error(a, "config: a path dependency has no package manifest", pkg_al, deppkg)
      }
      depkey := abs_norm_path(a, normdir)
      ke1 := rt::push_str(edges, from_key)
      ke2 := rt::push_byte(edges, 9)
      ke3 := rt::push_str(edges, depkey)
      ke4 := rt::push_byte(edges, 10)
      kq := rt::push_str(queue, deppkg)
      kt := rt::push_byte(queue, 9)
      ka := rt::push_str(queue, dalias)
      kn := rt::push_byte(queue, 10)
      i = e + 1
    } else if bytes(mtext)[i] == 35 {
      ## a `#`/`##` COMMENT runs to end of line — a manifest whose doc comment SPELLS a dependency
      ## (`## … DepSource.Path("../dep_lib") …`) must not thereby acquire one.
      while i < mtext.len and bytes(mtext)[i] != 10 { i = i + 1 }
    } else if bytes(mtext)[i] == 34 {
      ## a STRING literal — skip it whole, so a `#` inside one starts no comment and a `DepSource.…`
      ## spelled inside one declares no dependency.
      i = i + 1
      while i < mtext.len and bytes(mtext)[i] != 34 { i = i + 1 }
      i = i + 1
    } else {
      i += 1
    }
  }
}

## Read the manifest at `pkg_al` and return the string value of field `field` — the byte scan finds
## the literal field name then its following `"…"` string. Returns an EMPTY str when the field is
## absent (the caller applies the field's default). The lean dual of reading `‹name›.<field>` off
## the manifest comptime constant; a plain byte scan since the lean parser does not evaluate the
## manifest's `Package(…)` value. (Robustness matches `scan_deps_into_queue`'s `Path(` scan.)
manifest_field := fn(in out a : rt::Arena, pkg_al : str, field : str) -> str {
  mc := cstr(a, pkg_al)
  mtext := read_proc(a, mc, 262144)
  mbase := unchecked bitcast(usize, mtext.ptr)
  if field.len == 0 { return str_at(mbase, 0) }
  mut i := 0
  while i + field.len <= mtext.len {
    mut j := 0
    mut ok := true
    while j < field.len {
      if bytes(mtext)[i + j] != bytes(field)[j] { ok = false }
      j += 1
    }
    if ok {
      ## require the field name to be FOLLOWED BY `=` (after optional whitespace), so a mention of
      ## the field in a COMMENT (`## modules live under source_dir`) is not mistaken for the
      ## assignment — which would then grab the next unrelated `"…"` (e.g. version's). Only a real
      ## `field = "…"` matches; a bare mention is skipped and the scan continues.
      mut p := i + field.len
      while p < mtext.len and (bytes(mtext)[p] == 32 or bytes(mtext)[p] == 9 or bytes(mtext)[p] == 10 or bytes(mtext)[p] == 13) { p = p + 1 }
      if p < mtext.len and bytes(mtext)[p] == 61 {   ## '=' (61)
        mut q := p + 1
        while q < mtext.len and bytes(mtext)[q] != 34 { q = q + 1 }   ## to the opening quote (34)
        if q < mtext.len {
          mut e := q + 1
          while e < mtext.len and bytes(mtext)[e] != 34 { e = e + 1 }   ## to the closing quote
          return str_at(mbase + q + 1, e - (q + 1))
        }
      }
    }
    i += 1
  }
  return str_at(mbase, 0)
}

## Normalize one manifest limit-list member to the spelling consumed by the common limit walkers.
## Manifest values are enum projections (`Limit.no_alloc`, `Limit.freestanding`, …), while the file
## attribute and sema/driver walkers intentionally use bare names. Keep every delimiter byte verbatim,
## but remove the one syntactic `Limit.` qualifier from each complete member. This is done at the single
## CLI extraction boundary so check/build/run/test cannot disagree about the package contract.
manifest_limits_normalize := fn(in out a : rt::Arena, raw : str) -> str {
  ## `rt::StrBuf` keeps eight bytes of slack for every push; the normalized list is no longer a view,
  ## so reserve the input length plus that invariant's headroom.
  mut out := rt::strbuf(a, raw.len + 16)
  base := unchecked bitcast(usize, raw.ptr)
  mut i := 0
  while i < raw.len {
    c := bytes(raw)[i]
    if c == 44 or c == 32 or c == 9 or c == 10 or c == 13 or c == 91 or c == 93 or c == 40 or c == 41 {
      rt::push_byte(out, c)
      i += 1
    } else {
      mut j := i
      mut scanning := true
      while j < raw.len and scanning {
        d := bytes(raw)[j]
        if d == 44 or d == 32 or d == 9 or d == 10 or d == 13 or d == 91 or d == 93 or d == 40 or d == 41 { scanning = false }
        else { j += 1 }
      }
      mut start := i
      if j - i >= 6 and str_at(base + i, 6) == "Limit." { start = i + 6 }
      rt::push_str(out, str_at(base + start, j - start))
      i = j
    }
  }
  str_at(out.data, out.len)
}

## The package's `limits` CEILING (Manifest appendix §140; FND-11) — the bracketed list text between
## `limits = [` and the matching `]`, e.g. `Limit.no_alloc, Limit.freestanding`. A file's `@limits(…)`
## may only be STRICTER (⊇ this ceiling; Tooling §2.3). The returned list is normalized to the bare
## names consumed by the shared `sema`/`driver` walkers. Empty str when absent — the byte scan is the
## LIST dual of `manifest_field` (which captures a `"…"` scalar): find the `limits` field name (preceded
## by a non-identifier byte so `no_limits`/`sublimits` never match, and followed by `=`), then the
## opening `[`, then capture to the matching `]`. A mention in a `##` comment lacks the `=` → skipped.
manifest_limits := fn(in out a : rt::Arena, pkg_al : str) -> str {
  mc := cstr(a, pkg_al)
  mtext := read_proc(a, mc, 262144)
  mbase := unchecked bitcast(usize, mtext.ptr)
  mut i := 0
  while i + 6 <= mtext.len {
    hit := bytes(mtext)[i] == 108 and bytes(mtext)[i+1] == 105 and bytes(mtext)[i+2] == 109 and bytes(mtext)[i+3] == 105 and bytes(mtext)[i+4] == 116 and bytes(mtext)[i+5] == 115   ## "limits"
    mut boundary := true
    if i > 0 { boundary = not amb_idc(bytes(mtext)[i-1]) }   ## a non-identifier byte precedes it
    if hit and boundary {
      mut p := i + 6
      while p < mtext.len and (bytes(mtext)[p] == 32 or bytes(mtext)[p] == 9 or bytes(mtext)[p] == 10 or bytes(mtext)[p] == 13) { p = p + 1 }
      if p < mtext.len and bytes(mtext)[p] == 61 {   ## '=' (61)
        mut q := p + 1
        while q < mtext.len and bytes(mtext)[q] != 91 { q = q + 1 }   ## to the opening '[' (91)
        if q < mtext.len {
          mut e := q + 1
          mut depth := 1
          mut in_str := false
          while e < mtext.len and depth > 0 {
            c := bytes(mtext)[e]
            if c == 34 { in_str = not in_str }
            else if not in_str {
              if c == 91 { depth = depth + 1 }
              else if c == 93 { depth = depth - 1 }
            }
            if depth > 0 { e = e + 1 }
          }
          raw := str_at(mbase + q + 1, e - (q + 1))
          return manifest_limits_normalize(a, raw)
        }
      }
    }
    i += 1
  }
  return str_at(mbase, 0)
}

## The RAW inner text of a bracketed LIST field `<field> = [ … ]` (the generic dual of
## `manifest_limits`, which is hard-wired to `limits`) — used for `libs = [Lib(…), …]` and
## `linker_flags = ["…", …]` (Manifest appendix §3.5/§3.7; MOD-9). Byte scan: find the field name at
## an identifier boundary (both sides — so `libs` never matches inside `sublibs`), require it to be
## FOLLOWED BY `=` (after optional whitespace) so a `##`-comment mention with no `=` is skipped, then
## capture from the opening `[` to the matching `]`. Empty str when absent (the caller's default).
manifest_list_field := fn(in out a : rt::Arena, pkg_al : str, field : str) -> str {
  mc := cstr(a, pkg_al)
  mtext := read_proc(a, mc, 262144)
  mbase := unchecked bitcast(usize, mtext.ptr)
  if field.len == 0 { return str_at(mbase, 0) }
  mut i := 0
  while i + field.len <= mtext.len {
    mut ok := true
    mut j := 0
    while j < field.len {
      if bytes(mtext)[i + j] != bytes(field)[j] { ok = false }
      j += 1
    }
    mut boundary := true
    if i > 0 { boundary = not amb_idc(bytes(mtext)[i - 1]) }
    mut tboundary := true
    if i + field.len < mtext.len { tboundary = not amb_idc(bytes(mtext)[i + field.len]) }
    if ok and boundary and tboundary {
      mut p := i + field.len
      while p < mtext.len and (bytes(mtext)[p] == 32 or bytes(mtext)[p] == 9 or bytes(mtext)[p] == 10 or bytes(mtext)[p] == 13) { p = p + 1 }
      if p < mtext.len and bytes(mtext)[p] == 61 {   ## '=' (61)
        mut q := p + 1
        while q < mtext.len and bytes(mtext)[q] != 91 { q = q + 1 }   ## to the opening '[' (91)
        if q < mtext.len {
          mut e := q + 1
          mut depth := 1
          mut in_str := false
          while e < mtext.len and depth > 0 {
            c := bytes(mtext)[e]
            if c == 34 {
              mut esc := false
              if e > 0 { if bytes(mtext)[e - 1] == 92 { esc = true } }
              if not esc { in_str = not in_str }
            }
            else if not in_str {
              if c == 91 { depth = depth + 1 }
              else if c == 93 { depth = depth - 1 }
            }
            if depth > 0 { e = e + 1 }
          }
          return str_at(mbase + q + 1, e - (q + 1))
        }
      }
    }
    i += 1
  }
  return str_at(mbase, 0)
}

## Every `"…"` string literal inside `s`, one per line (newline-joined). Within a `libs = […]` block
## the only strings are the `Lib(name = "…")` values, so this yields exactly the library names; within
## a `linker_flags = […]` block it yields each raw flag. A trailing quote-less remainder is ignored.
extract_quoted_lines := fn(in out a : rt::Arena, s : str) -> str {
  sbase := unchecked bitcast(usize, s.ptr)
  mut out := rt::strbuf(a, s.len + 64)
  mut i := 0
  while i < s.len {
    if bytes(s)[i] == 34 {   ## '"' (34)
      mut e := i + 1
      while e < s.len and bytes(s)[e] != 34 { e = e + 1 }
      seg := str_at(sbase + i + 1, e - (i + 1))
      ks := rt::push_str(out, seg)
      kn := rt::push_byte(out, 10)
      i = e + 1
    } else {
      i += 1
    }
  }
  return str_at(out.data, out.len)
}

## Does `hay` contain `needle` as a byte substring? (Used to detect `LinkMode.dynamic` in a libs block.)
str_contains := fn(hay : str, needle : str) -> bool {
  if needle.len == 0 { return false }
  if needle.len > hay.len { return false }
  mut i := 0
  while i + needle.len <= hay.len {
    mut ok := true
    mut j := 0
    while j < needle.len {
      if bytes(hay)[i + j] != bytes(needle)[j] { ok = false }
      j += 1
    }
    if ok { return true }
    i += 1
  }
  return false
}

## The package's foreign-library NAMES (Manifest appendix §3.5; MOD-9), newline-joined — each is a
## `Lib(name = "…")` value inside `libs = [ … ]`. Empty when the manifest declares no `libs`.
manifest_lib_names := fn(in out a : rt::Arena, pkg_al : str) -> str {
  blk := manifest_list_field(a, pkg_al, "libs")
  return extract_quoted_lines(a, blk)
}

## The package's `linker_flags` (Manifest appendix §3.7; FN-8 escape), newline-joined — each raw flag
## string fed verbatim to the linker (e.g. `-L/abs/dir`). Empty when the manifest declares none.
manifest_linker_flags := fn(in out a : rt::Arena, pkg_al : str) -> str {
  blk := manifest_list_field(a, pkg_al, "linker_flags")
  return extract_quoted_lines(a, blk)
}

## Next byte offset in `s` at/after `from` where the identifier `word` occurs at a LEFT identifier
## boundary AND is FOLLOWED (after optional whitespace) by `=` — i.e. a real `word = …` field, not a
## substring or a comment mention; `0 - 1` (−1) if none. Walks the `profile_flags` FlagDecl fields.
mf_find_word := fn(s : str, from : usize, word : str) -> i64 {
  mut i := from
  while i + word.len <= s.len {
    mut ok := true
    mut j := 0
    while j < word.len { if bytes(s)[i + j] != bytes(word)[j] { ok = false } ; j += 1 }
    mut lb := true
    if i > 0 { lb = not amb_idc(bytes(s)[i - 1]) }
    mut rb := true
    if i + word.len < s.len { rb = not amb_idc(bytes(s)[i + word.len]) }
    if ok and lb and rb {
      mut p := i + word.len
      while p < s.len and (bytes(s)[p] == 32 or bytes(s)[p] == 9 or bytes(s)[p] == 10 or bytes(s)[p] == 13) { p = p + 1 }
      if p < s.len and bytes(s)[p] == 61 { return i64(i) }   ## '=' (61)
    }
    i += 1
  }
  return 0 - 1
}

## The `"…"` string value of the `<field> = "…"` whose field name STARTS at `wi` (length `wl`) in `s`:
## skip to the opening quote, capture to the closing quote. Empty if malformed. (Used for `name = "…"`.)
mf_quoted := fn(s : str, wi : usize, wl : usize) -> str {
  bb := unchecked bitcast(usize, s.ptr)
  mut q := wi + wl
  while q < s.len and bytes(s)[q] != 34 { q = q + 1 }   ## opening '"' (34)
  if q >= s.len { return str_at(bb, 0) }
  mut e := q + 1
  while e < s.len {
    if bytes(s)[e] == 34 {
      mut esc := false
      if e > 0 { if bytes(s)[e - 1] == 92 { esc = true } }
      if not esc { return str_at(bb + q + 1, e - (q + 1)) }
    }
    e = e + 1
  }
  return str_at(bb + q + 1, e - (q + 1))
}

## The bare TOKEN value of the `<field> = <token>` whose field name STARTS at `wi` (length `wl`) in `s`:
## skip to `=`, skip whitespace, then a quoted `"…"` yields its inner text (a str-typed flag default) else
## read the token up to `,` / `)` / whitespace (a bool `true`/`false`, an integer, or an enum `E.V`).
mf_token := fn(s : str, wi : usize, wl : usize) -> str {
  bb := unchecked bitcast(usize, s.ptr)
  mut p := wi + wl
  while p < s.len and bytes(s)[p] != 61 { p = p + 1 }   ## to '=' (61)
  p = p + 1
  while p < s.len and (bytes(s)[p] == 32 or bytes(s)[p] == 9 or bytes(s)[p] == 10 or bytes(s)[p] == 13) { p = p + 1 }
  if p < s.len and bytes(s)[p] == 34 {   ## a quoted str default
    mut qe := p + 1
    while qe < s.len {
      if bytes(s)[qe] == 34 {
        mut esc := false
        if qe > 0 { if bytes(s)[qe - 1] == 92 { esc = true } }
        if not esc { return str_at(bb + p + 1, qe - (p + 1)) }
      }
      qe = qe + 1
    }
    return str_at(bb + p + 1, qe - (p + 1))
  }
  mut e := p
  while e < s.len and bytes(s)[e] != 44 and bytes(s)[e] != 41 and bytes(s)[e] != 32 and bytes(s)[e] != 9 and bytes(s)[e] != 10 and bytes(s)[e] != 13 { e = e + 1 }
  return str_at(bb + p, e - p)
}

## The target selected by `--target`, or the first Target when the option is absent. The manifest parser
## owns the full schema; this deliberately small scanner only recovers the one Target record that the
## package-aware command is about to build. Keep the selected name as pointer/length facts: the command
## arena owns both the argv span and the manifest text for the lifetime of every later scanner call.
mut CLI_SELECTED_TARGET_P : usize = 0
mut CLI_SELECTED_TARGET_N : usize = 0

manifest_target_record := fn(in out a : rt::Arena, pkg_al : str) -> str {
  blk := manifest_list_field(a, pkg_al, "targets")
  bb := unchecked bitcast(usize, blk.ptr)
  mut first_s := 0
  mut first_n := 0
  mut i := 0
  while i + 7 <= blk.len {
    mut is_target := true
    if bytes(blk)[i] != 84 { is_target = false }
    if bytes(blk)[i + 1] != 97 { is_target = false }
    if bytes(blk)[i + 2] != 114 { is_target = false }
    if bytes(blk)[i + 3] != 103 { is_target = false }
    if bytes(blk)[i + 4] != 101 { is_target = false }
    if bytes(blk)[i + 5] != 116 { is_target = false }
    if bytes(blk)[i + 6] != 40 { is_target = false }
    if is_target {
      mut e := i + 7
      mut depth := 1
      mut in_str := false
      while e < blk.len and depth > 0 {
        c := bytes(blk)[e]
        if c == 34 {
          mut esc := false
          if e > 0 and bytes(blk)[e - 1] == 92 { esc = true }
          if not esc { in_str = not in_str }
        } else if not in_str {
          if c == 40 { depth += 1 }
          if c == 41 { depth -= 1 }
        }
        e += 1
      }
      if first_n == 0 { first_s = i ; first_n = e - i }
      rec := str_at(bb + i, e - i)
      nwi := mf_find_word(rec, 0, "name")
      mut nm := str_at(0, 0)
      if nwi >= 0 { nm = mf_quoted(rec, usize(nwi), 4) }
      if CLI_SELECTED_TARGET_N != 0 and nm == str_at(CLI_SELECTED_TARGET_P, CLI_SELECTED_TARGET_N) {
        return rec
      }
      i = e
    } else {
      i += 1
    }
  }
  if CLI_SELECTED_TARGET_N == 0 and first_n != 0 { return str_at(bb + first_s, first_n) }
  str_at(bb, 0)
}

## Resolve the selector before any source parsing. An unknown target is a located Config error, never a
## silent fallback to the first record. Unnamed targets retain the stable `default` artifact component.
manifest_target_selection_resolve := fn(in out a : rt::Arena, pkg_al : str) -> usize {
  CLI_SELECTED_TARGET_P = 0
  CLI_SELECTED_TARGET_N = 0
  blk := manifest_list_field(a, pkg_al, "targets")
  if CLI_TARGET_SELECT_COUNT != 0 {
    wanted := str_at(CLI_TARGET_SELECT_P, CLI_TARGET_SELECT_N)
    CLI_SELECTED_TARGET_P = CLI_TARGET_SELECT_P
    CLI_SELECTED_TARGET_N = CLI_TARGET_SELECT_N
    rec := manifest_target_record(a, pkg_al)
    if rec.len == 0 {
      manifest_located_error(a, "config: --target names no Target in the manifest", pkg_al, "targets")
      return 43
    }
    ## `manifest_target_record` returns the first record when the selected name is empty only. An
    ## explicit selector is non-empty, so a returned record is a proof that the exact name matched.
    nwi := mf_find_word(rec, 0, "name")
    if nwi < 0 or mf_quoted(rec, usize(nwi), 4) != wanted {
      manifest_located_error(a, "config: --target names no Target in the manifest", pkg_al, "targets")
      return 43
    }
    return 0
  }
  ## No explicit selector: preserve the existing first-target default, but remember its name so every
  ## later field scanner (kind/code-size/output/entry/artifact directory) reads the same record.
  mut i := 0
  while i + 7 <= blk.len {
    if bytes(blk)[i] == 84 and bytes(blk)[i + 1] == 97 and bytes(blk)[i + 2] == 114 and bytes(blk)[i + 3] == 103 and bytes(blk)[i + 4] == 101 and bytes(blk)[i + 5] == 116 and bytes(blk)[i + 6] == 40 {
      mut e := i + 7
      mut depth := 1
      mut in_str := false
      while e < blk.len and depth > 0 {
        c := bytes(blk)[e]
        if c == 34 {
          mut esc := false
          if e > 0 and bytes(blk)[e - 1] == 92 { esc = true }
          if not esc { in_str = not in_str }
        } else if not in_str {
          if c == 40 { depth += 1 }
          if c == 41 { depth -= 1 }
        }
        e += 1
      }
      rec := str_at(unchecked bitcast(usize, blk.ptr) + i, e - i)
      nwi := mf_find_word(rec, 0, "name")
      if nwi >= 0 {
        nm := mf_quoted(rec, usize(nwi), 4)
        CLI_SELECTED_TARGET_P = unchecked bitcast(usize, nm.ptr)
        CLI_SELECTED_TARGET_N = nm.len
      }
      return 0
    }
    i += 1
  }
  0
}

## The selected Target.kind token (`executable`, `object`, `static_lib`, …). The manifest parser already
## validates the enum through the Package schema; this CLI scan only publishes the selected artifact shape
## to the build dispatcher. Missing kind keeps the spec's executable default.
manifest_target_kind := fn(in out a : rt::Arena, pkg_al : str) -> str {
  rec := manifest_target_record(a, pkg_al)
  wi := mf_find_word(rec, 0, "kind")
  if wi < 0 { return "executable" }
  tok := mf_token(rec, usize(wi), 4)
  if tok == "Kind.executable" { return "executable" }
  if tok == "Kind.object" { return "object" }
  if tok == "Kind.static_lib" { return "static_lib" }
  if tok == "Kind.shared_lib" { return "shared_lib" }
  if tok == "Kind.source" { return "source" }
  return "invalid"
}

## Tooling §2.7 — the scalar code carried across the CLI/driver boundary for the selected artifact
## kind. Keep this mapping beside `manifest_target_kind`: the string is the CLI's config spelling,
## while the lower's comptime fact is deliberately a closed integer set. Unknown input remains code 5
## here and is rejected by `manifest_kind_reject` before any lowering; 0 is the executable default.
manifest_target_kind_code := fn(kind : str) -> usize {
  if kind == "executable" { return 0 }
  if kind == "object" { return 1 }
  if kind == "static_lib" { return 2 }
  if kind == "source" { return 3 }
  if kind == "shared_lib" { return 4 }
  return 5
}

## Tooling §2.7 / Manifest §3.2 — publish the selected x86 code-encoding mode. The manifest
## parser supplies the Target field; this narrow CLI scan carries only its closed enum scalar across
## the existing package boundary. x86_64's omitted/default value is CodeSize.b64.
manifest_target_code_size := fn(in out a : rt::Arena, pkg_al : str) -> usize {
  rec := manifest_target_record(a, pkg_al)
  wi := mf_find_word(rec, 0, "code_size")
  if wi < 0 { return 2 }
  tok := mf_token(rec, usize(wi), 9)
  if tok == "CodeSize.b16" { return 0 }
  if tok == "CodeSize.b32" { return 1 }
  if tok == "CodeSize.b64" { return 2 }
  return 3
}

manifest_code_size_reject := fn(in out a : rt::Arena, pkg_al : str, code_size : usize) -> usize {
  if code_size < 3 { return 0 }
  manifest_located_error(a, "config: Target.code_size is invalid or unsupported", pkg_al, "code_size")
  return 1
}

## Print a manifest-configuration diagnostic LOCATED at the line holding field `anchor` (Tooling
## §2.2/§5): `<msg> at line <n> in <manifest>`, on stderr. The `dep_config_error` shape without the
## dependency-specific detail and without the DEP_CONFIG_BAD latch, for a rejection whose caller
## returns its own exit code. An absent anchor falls back to line 1 — the file is still named.
manifest_located_error := fn(in out a : rt::Arena, msg : str, pkg_al : str, anchor : str) {
  mc := cstr(a, pkg_al)
  mtext := read_proc(a, mc, 262144)
  mut off := 0
  fi := mf_find_word(mtext, 0, anchor)
  if fi >= 0 { off = usize(fi) }
  mut line := 1
  mut i := 0
  while i < off and i < mtext.len { if bytes(mtext)[i] == 10 { line = line + 1 } ; i = i + 1 }
  mut db := rt::strbuf(a, msg.len + pkg_al.len + 64)
  k0 := rt::push_str(db, msg)
  k1 := rt::push_str(db, " at line ")
  k2 := rt::push_int(db, i64(line))
  k3 := rt::push_str(db, " in ")
  k4 := rt::push_str(db, pkg_al)
  k5 := rt::push_byte(db, 10)
  w := rt::sys_write(1, 2, unchecked bitcast(usize, db.data), db.len)
}

## TOOL-16 — vendoring is post-v1. Keep this check at the manifest configuration boundary: an
## unknown Package field must not be silently ignored and must not reach source parsing/linking.
mut MANIFEST_CONFIG_BAD := false
manifest_vendor_reject := fn(in out a : rt::Arena, pkg_al : str) {
  mc := cstr(a, pkg_al)
  mtext := read_proc(a, mc, 262144)
  if mf_find_word(mtext, 0, "vendor_dir") >= 0 {
    MANIFEST_CONFIG_BAD = true
    manifest_located_error(a, "config: Package field vendor_dir is not supported in v1", pkg_al, "vendor_dir")
  }
}

## TOOL-11 — Target.output is an artifact FILE NAME, not a path. An omitted field keeps the
## deterministic default; an explicit empty value or path separator is a Config error before source
## compilation. NUL cannot occur in an Alatyr source literal.
manifest_output_reject := fn(in out a : rt::Arena, pkg_al : str) {
  ## Selection has already published the exact Target record; validate that record, not the first
  ## `output` anywhere in a multi-target manifest. An invalid unselected target must not poison the
  ## selected invocation, while the selected target must never inherit a safe field from a sibling.
  rec := manifest_target_record(a, pkg_al)
  wi := mf_find_word(rec, 0, "output")
  if wi < 0 { return }
  value := mf_quoted(rec, usize(wi), 6)
  mut bad := value.len == 0
  mut i := 0
  while i < value.len {
    if bytes(value)[i] == 47 or bytes(value)[i] == 92 { bad = true }
    i += 1
  }
  if bad {
    MANIFEST_CONFIG_BAD = true
    manifest_located_error(a, "config: Target.output must be a non-empty file name without path separators", pkg_al, "output")
  }
}

## TOOL-13 / Manifest §3.8 — validate only EXPLICIT project directories. The manifest parser's
## string extraction is deliberately reused here: this is the CLI configuration boundary, before
## source discovery can interpret a path. Paths are folded lexically (never realpath'd), so aliases
## such as `src/..` and `target/../target` are compared by their normalized package-relative form.
mf_path_has_escape := fn(v : str) -> bool {
  if v.len > 0 { if bytes(v)[0] == 47 { return true } }   ## an absolute POSIX path
  mut depth := 0
  mut i := 0
  mut base := unchecked bitcast(usize, v.ptr)
  while i <= v.len {
    s := i
    while i < v.len and bytes(v)[i] != 47 { i += 1 }
    if i > s {
      seg := str_at(base + s, i - s)
      if seg == ".." {
        if depth == 0 { return true }
        depth -= 1
      } else if seg != "." {
        depth += 1
      }
    }
    i += 1
  }
  return false
}

## Whether normalized relative directory `parent` contains normalized relative directory `child`.
## Equality counts as containment: a source tree may not be the target tree itself.
mf_path_contains := fn(parent : str, child : str) -> bool {
  if parent == "." { return true }
  if parent == child { return true }
  if child.len <= parent.len { return false }
  mut i := 0
  while i < parent.len {
    if bytes(parent)[i] != bytes(child)[i] { return false }
    i += 1
  }
  return bytes(child)[parent.len] == 47
}

manifest_path_reject := fn(in out a : rt::Arena, pkg_al : str) {
  mc := cstr(a, pkg_al)
  mtext := read_proc(a, mc, 262144)
  swi := mf_find_word(mtext, 0, "source_dir")
  twi := mf_find_word(mtext, 0, "target_dir")
  mut source_explicit := swi >= 0
  mut target_explicit := twi >= 0
  mut source_norm := "src"
  mut target_norm := "target"
  mut source_valid := true
  mut target_valid := true
  if source_explicit {
    sv := mf_quoted(mtext, usize(swi), 10)
    if mf_path_has_escape(sv) {
      source_valid = false
      MANIFEST_CONFIG_BAD = true
      manifest_located_error(a, "config: Package.source_dir must be relative and remain inside package root", pkg_al, "source_dir")
    } else {
      source_norm = normalize_path(a, sv)
    }
  }
  if target_explicit {
    tv := mf_quoted(mtext, usize(twi), 10)
    if mf_path_has_escape(tv) {
      target_valid = false
      MANIFEST_CONFIG_BAD = true
      manifest_located_error(a, "config: Package.target_dir must be relative and remain inside package root", pkg_al, "target_dir")
    } else {
      target_norm = normalize_path(a, tv)
    }
  }
  ## The effective source_dir is `src` when omitted. Apply containment to that effective value too:
  ## a target nested below the default source tree is just as invalid as one nested below an explicit
  ## source_dir. An explicit `.` normalizes to the package root and remains a located rejection.
  if source_valid {
    if source_norm == "." {
      MANIFEST_CONFIG_BAD = true
      manifest_located_error(a, "config: Package.source_dir must not contain the manifest file or package root", pkg_al, "source_dir")
    } else if target_valid and mf_path_contains(source_norm, target_norm) {
      MANIFEST_CONFIG_BAD = true
      if source_explicit {
        manifest_located_error(a, "config: Package.source_dir must not contain target_dir", pkg_al, "source_dir")
      } else if target_explicit {
        ## The effective default source_dir is not written in the manifest. Anchor this relation
        ## diagnostic on the written target_dir instead of inventing a span at line 1.
        manifest_located_error(a, "config: Package.target_dir must not be inside source_dir", pkg_al, "target_dir")
      } else {
        manifest_located_error(a, "config: Package.source_dir must not contain target_dir", pkg_al, "source_dir")
      }
    }
  }
}

## Tooling §2.2 / §5 — the selected target's `kind` decides what a command may produce, so a `kind`
## this toolchain cannot honour is a CONFIGURATION failure that must abort EVERY package-aware command
## consulting it, not only `build`. `check` used to return **0** on exactly the manifests `build`
## refuses (an unrecognized `Kind.…` → 40, `Kind.shared_lib` → 41, `Kind.source` → 42): the one command
## whose entire job is to say whether a package is well-formed WITHOUT producing an artifact was the
## one command that accepted an unbuildable configuration. Returns 0 for a kind that is implemented,
## else `build`'s own exit code, having printed the diagnostic LOCATED at the manifest's `kind` line —
## the same verdict and the same code from both commands, so neither can drift from the other.
manifest_kind_reject := fn(in out a : rt::Arena, pkg_al : str, kind : str) -> usize {
  if kind == "invalid" {
    manifest_located_error(a, "config: the target's kind is invalid or unsupported", pkg_al, "kind")
    return 40
  }
  if kind == "shared_lib" {
    manifest_located_error(a, "config: Target.kind = Kind.shared_lib is not implemented yet", pkg_al, "kind")
    return 41
  }
  if kind == "source" {
    manifest_located_error(a, "config: Target.kind = Kind.source is not implemented yet", pkg_al, "kind")
    return 42
  }
  return 0
}

## Tooling §2.7 — map the selected Target.arch to the small backend selector carried by the driver.
## Unsupported architectures fail at the configuration boundary; they must not fall through to the host
## assembler or silently run an artifact for a different machine. The non-x86 selector is currently
## consumed only by the cross-target `test` path; build/run/dump/check reject it until their own
## target-specific link/execute contract is implemented.
manifest_target_backend := fn(in out a : rt::Arena, pkg_al : str) -> usize {
  rec := manifest_target_record(a, pkg_al)
  if rec.len == 0 { return 0 }
  wi := mf_find_word(rec, 0, "arch")
  if wi < 0 { return 3 }
  tok := mf_token(rec, usize(wi), 4)
  if tok == "Arch.x86_64" { return 0 }
  if tok == "Arch.aarch64" { return 1 }
  if tok == "Arch.riscv64" { return 2 }
  return 3
}

manifest_target_arch_reject := fn(in out a : rt::Arena, pkg_al : str, backend : usize) -> usize {
  if backend < 3 { return 0 }
  manifest_located_error(a, "config: Target.arch is unsupported by this compiler", pkg_al, "arch")
  return 44
}

manifest_target_command_reject := fn(in out a : rt::Arena, pkg_al : str, backend : usize, mode : usize) -> usize {
  if backend == 0 or mode == 5 { return 0 }
  manifest_located_error(a, "config: non-x86 targets are supported only by `test`", pkg_al, "arch")
  return 45
}

## The `flags = [ … ]` inner text of the Profile whose `name = "<sel>"` within the `profiles` list,
## or "" when no such profile / no flags. From the `name = "<sel>"` occurrence, scan forward to the
## real `flags = [` (a LEFT-boundary `flags` — `as_flags`/`linker_flags` are skipped by `mf_find_word`)
## and capture to the matching `]`. The `flags` values are the per-profile FlagSet overrides (§2.6).
manifest_profile_flags_block := fn(in out a : rt::Arena, plist : str, sel : str) -> str {
  pbase := unchecked bitcast(usize, plist.ptr)
  mut i := 0
  mut done := false
  while not done {
    ni := mf_find_word(plist, i, "name")
    if ni < 0 { done = true }
    else {
      nus := usize(ni)
      nm := mf_quoted(plist, nus, 4)
      if nm == sel {
        fi := mf_find_word(plist, nus + 4, "flags")
        if fi >= 0 {
          mut q := usize(fi) + 5
          while q < plist.len and bytes(plist)[q] != 91 { q = q + 1 }   ## '['
          if q < plist.len {
            mut e := q + 1
            mut depth := 1
            mut in_str := false
            while e < plist.len and depth > 0 {
              c := bytes(plist)[e]
              if c == 34 {
                mut esc := false
                if e > 0 { if bytes(plist)[e - 1] == 92 { esc = true } }
                if not esc { in_str = not in_str }
              }
              else if not in_str {
                if c == 91 { depth = depth + 1 }
                else if c == 93 { depth = depth - 1 }
              }
              if depth > 0 { e = e + 1 }
            }
            return str_at(pbase + q + 1, e - (q + 1))
          }
        }
        done = true
      } else {
        i = nus + 4
      }
    }
  }
  return ""
}

## The VALUE override for a declared `profile_flags` flag within a Profile's `flags` block — the
## `FlagSet(name = "<flag_name>", value = <token>)` whose name matches; "" when the profile does not
## override that flag (the declared default then applies, §2.6).
profile_flag_override := fn(in out a : rt::Arena, fblk : str, flag_name : str) -> str {
  mut i := 0
  mut done := false
  while not done {
    ni := mf_find_word(fblk, i, "name")
    if ni < 0 { done = true }
    else {
      nus := usize(ni)
      nm := mf_quoted(fblk, nus, 4)
      if nm == flag_name {
        vi := mf_find_word(fblk, nus + 4, "value")
        if vi >= 0 { return mf_token(fblk, usize(vi), 5) }
        done = true
      } else {
        i = nus + 4
      }
    }
  }
  return ""
}

mf_is_int_type := fn(t : str) -> bool {
  return t == "u8" or t == "u16" or t == "u32" or t == "u64" or t == "usize" or t == "i8" or t == "i16" or t == "i32" or t == "i64" or t == "isize"
}

mf_is_digits := fn(v : str) -> bool {
  if v.len == 0 { return false }
  mut i := 0
  while i < v.len { c := bytes(v)[i] ; if c < 48 or c > 57 { return false } ; i += 1 }
  return true
}

mf_is_digits_from := fn(v : str, from : usize) -> bool {
  if from >= v.len { return false }
  mut i := from
  while i < v.len { c := bytes(v)[i] ; if c < 48 or c > 57 { return false } ; i += 1 }
  return true
}

mf_is_signed_int_type := fn(t : str) -> bool {
  return t == "i8" or t == "i16" or t == "i32" or t == "i64" or t == "isize"
}

mf_int_value_matches_type := fn(t : str, v : str) -> bool {
  if v.len == 0 { return false }
  if bytes(v)[0] == 45 {   ## '-'
    if not mf_is_signed_int_type(t) { return false }
    if v.len == 1 { return false }
    return mf_is_digits_from(v, 1)
  }
  return mf_is_digits(v)
}

mf_has_dot := fn(v : str) -> bool {
  mut i := 0
  while i < v.len { if bytes(v)[i] == 46 { return true } ; i += 1 }
  return false
}

mut PROFILE_CONFIG_BAD := false
## Report a malformed profile declaration/override as a located manifest diagnostic. The profile scanner
## intentionally remains a small byte parser, so `field` is the nearest stable manifest anchor
## (`profile_flags` or `profiles`); this gives users a file-relative line instead of the old unlocated
## stderr string while keeping the existing fail-loud status and message text.
mf_config_error := fn(in out a : rt::Arena, msg : str, pkg_al : str, field : str) {
  PROFILE_CONFIG_BAD = true
  mc := cstr(a, pkg_al)
  mtext := read_proc(a, mc, 262144)
  mut off := 0
  if field.len != 0 {
    fi := mf_find_word(mtext, 0, field)
    if fi >= 0 { off = usize(fi) }
  }
  mut line := 1
  mut i := 0
  while i < off and i < mtext.len { if bytes(mtext)[i] == 10 { line = line + 1 } ; i = i + 1 }
  mut db := rt::strbuf(a, msg.len + pkg_al.len + 48)
  k0 := rt::push_str(db, msg)
  k1 := rt::push_str(db, " at line ")
  k2 := rt::push_int(db, i64(line))
  k3 := rt::push_str(db, " in ")
  k4 := rt::push_str(db, pkg_al)
  k5 := rt::push_byte(db, 10)
  w := rt::sys_write(1, 2, unchecked bitcast(usize, db.data), db.len)
}

mf_value_matches_type := fn(t : str, v : str) -> bool {
  if t == "bool" { return v == "true" or v == "false" }
  if t == "str" { return true }
  if mf_is_int_type(t) { return mf_int_value_matches_type(t, v) }
  return mf_has_dot(v)
}

mf_declared_flag := fn(blk : str, flag_name : str) -> bool {
  mut i := 0
  mut done := false
  while not done {
    ni := mf_find_word(blk, i, "name")
    if ni < 0 { done = true }
    else {
      nus := usize(ni)
      if mf_quoted(blk, nus, 4) == flag_name { return true }
      i = nus + 4
    }
  }
  return false
}

mf_reject_bad_overrides := fn(in out a : rt::Arena, blk : str, fblk : str, pkg_al : str) {
  mut i := 0
  mut done := false
  while not done {
    ni := mf_find_word(fblk, i, "name")
    if ni < 0 { done = true }
    else {
      nus := usize(ni)
      nm := mf_quoted(fblk, nus, 4)
      if not mf_declared_flag(blk, nm) { mf_config_error(a, "config: profile flag override names an undeclared profile_flags entry", pkg_al, "profiles") }
      i = nus + 4
    }
  }
}

## The package's `profile_flags` DECLARATIONS (Manifest appendix §3.6 / Tooling §2.6) as a `name=value\n`
## blob — each `FlagDecl(name = "…", type = …, default = <token>)` yields its name + the value RESOLVED
## for the SELECTED profile `sel`: the per-profile override from `profiles.<sel>.flags` if present, else
## the declared default. Empty when no `profile_flags` are declared → `set_build_flags` gets an empty
## blob → the `build.*` path is dormant. The scan pairs each `name` with the NEXT `default` (their
## canonical order within a FlagDecl); `sel` is the CLI-selected / default profile (Tooling §4).
manifest_profile_flags := fn(in out a : rt::Arena, pkg_al : str, sel : str) -> str {
  blk := manifest_list_field(a, pkg_al, "profile_flags")
  plist := manifest_list_field(a, pkg_al, "profiles")
  fblk := manifest_profile_flags_block(a, plist, sel)
  mf_reject_bad_overrides(a, blk, fblk, pkg_al)
  mut out := rt::strbuf(a, blk.len + 64)
  mut done := false
  mut i := 0
  while not done {
    ni := mf_find_word(blk, i, "name")
    if ni < 0 { done = true }
    else {
      nus := usize(ni)
      nm := mf_quoted(blk, nus, 4)
      di := mf_find_word(blk, nus + 4, "default")
      if di < 0 { done = true }
      else {
        dus := usize(di)
        ti := mf_find_word(blk, nus + 4, "type")
        if ti < 0 { mf_config_error(a, "config: profile flag declaration missing type", pkg_al, "profile_flags") }
        typ := mf_token(blk, usize(ti), 4)
        mut dv : str = mf_token(blk, dus, 7)
        if not mf_value_matches_type(typ, dv) { mf_config_error(a, "config: profile flag default does not match declared type", pkg_al, "profile_flags") }
        ## a per-profile override (FlagSet) wins over the declared default for the selected profile.
        ov := profile_flag_override(a, fblk, nm)
        if ov.len != 0 {
          if not mf_value_matches_type(typ, ov) { mf_config_error(a, "config: profile flag override does not match declared type", pkg_al, "profiles") }
          dv = ov
        }
        ks := rt::push_str(out, nm)
        ke := rt::push_byte(out, 61)   ## '='
        kv := rt::push_str(out, dv)
        kn := rt::push_byte(out, 10)   ## newline
        i = dus + 7
      }
    }
  }
  return str_at(out.data, out.len)
}

## The SELECTED build profile (Tooling §2.6/§4), resolved from the CLI first: `--release` =
## `--profile release`; else `--profile <name>`; else the manifest's `default_profile`; else `debug`.
## Scanned over the arg list (a `--profile` consumes the next arg as its name).
cli_profile := fn(in out a : rt::Arena, cmd : str, n : usize, emp : str) -> str {
  mut k := 2
  while k < n {
    ak := arg_at(cmd, k)
    if ak == "--release" { return "release" }
    if ak == "--profile" and k + 1 < n { return arg_at(cmd, k + 1) }
    if ak == "--target-dir" or ak == "--target" { if k + 1 < n { k += 2 } else { k += 1 } } else { k += 1 }
  }
  dp := manifest_field(a, emp, "default_profile")
  if dp.len != 0 { return dp }
  return "debug"
}

## Is ANY library `LinkMode.dynamic` (MOD-9)? Then the whole binary is dynamic (hermetic-static is the
## default; any dynamic lib forfeits hermeticity). Detected by the presence of the literal `dynamic`
## inside the `libs = [ … ]` block — the only place it can occur (a `Lib`'s `link` field value).
manifest_any_dynamic := fn(in out a : rt::Arena, pkg_al : str) -> bool {
  blk := manifest_list_field(a, pkg_al, "libs")
  return str_contains(blk, "dynamic")
}

## The package's `source_dir` (Manifest appendix §3; Modules §1 — modules live by path under it), or
## `"src"` when absent (Tooling §2.6's package-local default). Modules are discovered there.
manifest_source_dir := fn(in out a : rt::Arena, pkg_al : str) -> str {
  v := manifest_field(a, pkg_al, "source_dir")
  if v.len == 0 { return "src" }
  return v
}

## The package's `target_dir` (where build artifacts go — the spec Paths config, Tooling §2.6),
## or "target" when absent (the implementation-chosen default, Rust-style).
manifest_target_dir := fn(in out a : rt::Arena, pkg_al : str) -> str {
  v := manifest_field(a, pkg_al, "target_dir")
  if v.len == 0 { return "target" }
  return v
}

## Whether the selected manifest actually contains a Package value. Zero-Package manifests use the
## synthesized package's root-file stem for the artifact, but keep the normal target_dir unchanged.
manifest_has_package := fn(in out a : rt::Arena, pkg_al : str) -> bool {
  mc := cstr(a, pkg_al)
  mt := read_proc(a, mc, 262144)
  mut q := 0
  while q + 8 <= mt.len {
    if amb_lit_at(mt, q, mt.len, "Package(") { return true }
    q += 1
  }
  return false
}

## The selected target's `output` artifact file name (Manifest appendix §3.1), or "a.out" when
## absent. Zero-Package naming is deliberately kept separate in manifest_artifact_basename below.
manifest_output := fn(in out a : rt::Arena, pkg_al : str) -> str {
  rec := manifest_target_record(a, pkg_al)
  wi := mf_find_word(rec, 0, "output")
  if wi < 0 { return "a.out" }
  v := mf_quoted(rec, usize(wi), 6)
  if v.len == 0 { return "a.out" }
  return v
}

manifest_artifact_basename := fn(in out a : rt::Arena, pkg_al : str) -> str {
  if manifest_has_package(a, pkg_al) == false { return file_stem(pkg_al) }
  return manifest_output(a, pkg_al)
}

## TOOL-13 / Manifest §4 — count the manifest's target records. The layout is a property of the
## manifest, not of the selected invocation, so the count is deliberately read from the targets list
## before choosing the output directory. This scanner is only a path fact; target semantics remain in
## the manifest checker and the future TOOL-18 target resolver.
manifest_target_count := fn(in out a : rt::Arena, pkg_al : str) -> usize {
  blk := manifest_list_field(a, pkg_al, "targets")
  mut n := 0
  mut i := 0
  while i + 7 <= blk.len {
    if bytes(blk)[i] == 84 and bytes(blk)[i + 1] == 97 and bytes(blk)[i + 2] == 114
       and bytes(blk)[i + 3] == 103 and bytes(blk)[i + 4] == 101 and bytes(blk)[i + 5] == 116
       and bytes(blk)[i + 6] == 40 { n += 1 ; i += 7 }
    else { i += 1 }
  }
  if n == 0 { return 1 }
  n
}

## The default target is the first manifest Target. TOOL-13 only needs its name to keep the
## multi-target directory stable; selecting a different target remains a later resolver increment.
manifest_default_target_name := fn(in out a : rt::Arena, pkg_al : str) -> str {
  rec := manifest_target_record(a, pkg_al)
  wi := mf_find_word(rec, 0, "name")
  if wi >= 0 { return mf_quoted(rec, usize(wi), 4) }
  return "default"
}

## Resolve and create the package artifact directory, then return the deterministic artifact path.
## `suffix` distinguishes the test artifact (`<output>.test`) from the package's normal executable;
## both retain the same `.s`/`.o` (and, when split emission is enabled, manifest/interface) convention.
## This is intentionally shared by `run`, `test` and manifest-driven `build`, so all package commands
## agree on the TOOL-10 location contract.
manifest_target_artifact := fn(in out a : rt::Arena, pkg_al : str, suffix : str, profile : str) -> str {
  mut tdir := manifest_target_dir(a, pkg_al)
  if CLI_TARGET_DIR_COUNT == 1 { tdir = str_at(CLI_TARGET_DIR_P, CLI_TARGET_DIR_N) }
  outnm := manifest_artifact_basename(a, pkg_al)
  name := cat2(a, outnm, suffix)
  pdir := dir_of(pkg_al)
  mut tpath := tdir
  if CLI_TARGET_DIR_COUNT != 1 and pdir.len != 0 {
    d1 := cat2(a, pdir, "/")
    tpath = cat2(a, d1, tdir)
  }
  ## Create the manifest/CLI-selected base before adding the multi-target component. mkdir(2) is not
  ## recursive; without this step `target/<target-name>` fails when target_dir is cold.
  base_c := cstr(a, tpath)
  base_mkdir := rt::sys_mkdir(83, base_c, 493)
  if manifest_target_count(a, pkg_al) > 1 {
    tname := manifest_default_target_name(a, pkg_al)
    t0 := cat2(a, tpath, "/")
    tpath = cat2(a, t0, tname)
  }
  tdir_c := cstr(a, tpath)
  mkdir_rc := rt::sys_mkdir(83, tdir_c, 493)
  prof0 := cat2(a, tpath, "/")
  profpath := cat2(a, prof0, profile)
  prof_c := cstr(a, profpath)
  mkdir_prof := rt::sys_mkdir(83, prof_c, 493)
  slash := cat2(a, profpath, "/")
  cat2(a, slash, name)
}

## The selected target's `entry` symbol (Manifest appendix §3.1) — the linker symbol
## selected with `ld -e <entry>` for a manifest build; default `_start` when absent (the conventional
## ELF entry, and the byte-identical self-build compatibility path).
manifest_entry := fn(in out a : rt::Arena, pkg_al : str) -> str {
  rec := manifest_target_record(a, pkg_al)
  wi := mf_find_word(rec, 0, "entry")
  if wi < 0 { return "_start" }
  v := mf_quoted(rec, usize(wi), 5)
  if v.len == 0 { return "_start" }
  return v
}

## The directory holding a package's MODULES: `<pkgdir>/<source_dir>` (normalized). The effective
## default is `<pkgdir>/src`; an explicit `.` is rejected by manifest_path_reject before discovery.
pkg_src_dir := fn(in out a : rt::Arena, pkg_al : str, pkgdir : str) -> str {
  srcsub := manifest_source_dir(a, pkg_al)
  if srcsub == "." {
    ## A legacy/explicit package-root source is rejected before this path is used. Keep the branch
    ## defensive for callers that publish a root source without the validation phase.
    if pkgdir.len == 0 { return "." }
    return pkgdir
  }
  ## a bare manifest path (`package.al`, no directory) has an empty `pkgdir` — the source dir is
  ## then just `<source_dir>` relative to the cwd; joining "" + "/" + src would wrongly make it
  ## ABSOLUTE (`/src`).
  if pkgdir.len == 0 { return srcsub }
  d1 := cat2(a, pkgdir, "/")
  raw := cat2(a, d1, srcsub)
  return normalize_path(a, raw)
}

## The full newline-joined module list for a PACKAGE rooted at `root_pkg` (a `…/package.al` path),
## INCLUDING transitive `Path` dependencies. BFS over the dep graph (a worklist queue — no recursion,
## which the lean lower's call-ABI handles less robustly), deduping each package directory so cycles
## terminate and a shared dep is compiled once. Dependency modules come FIRST; the ROOT package's own
## modules are appended LAST, so the last-module-is-entry rule keeps the entry in the root package
## (`<root-last-module>__main`). Each package's `package.al` manifest is excluded from its module list
## (it is the manifest, not a module). A dep should NOT define a `main` (it is a library).
pkg_module_paths := fn(in out a : rt::Arena, root_pkg : str) -> str {
  mut acc := rt::strbuf(a, 4194304)
  mut seen := rt::strbuf(a, 131072)
  mut queue := rt::strbuf(a, 131072)
  ## Modules §8 — one `<dep source dir>\t<alias>` row per resolved dependency, handed to the driver so
  ## a dependency's modules are named `<alias>__<module>` (its items live under the ALIAS namespace,
  ## `d::math::answer`, instead of being merged FLATLY into the consuming package's namespace).
  mut droots := rt::strbuf(a, 65536)
  ## MOD-11 — one `<from source>TAB<to source>` row per resolved dependency edge, checked for
  ## acyclicity once the whole graph is known (a cycle can close beside the traversal path).
  mut edges := rt::strbuf(a, 131072)
  rd := dir_of(root_pkg)
  rootdir := normalize_path(a, rd)   ## canonical form, so a dep pointing back at the root dedups
  ## the root dir is "seen" up front so a dep that points back at the root is skipped (and its
  ## modules are added LAST, below, not in the loop). The seen-set is keyed by the package's SOURCE
  ## identity (MOD-10 — the lexically-normalized ABSOLUTE path), never by the relative spelling the
  ## manifest happened to use, so two spellings of one dependency resolve to ONE package.
  rootkey := abs_norm_path(a, rootdir)
  ks := rt::push_str(seen, rootkey)
  ksn := rt::push_byte(seen, 10)
  ## seed the queue with the root's direct deps.
  scan_deps_into_queue(a, root_pkg, rootdir, queue, edges)
  mut qpos := 0
  while qpos < queue.len {
    qbase := unchecked bitcast(usize, queue.data)
    qstr := str_at(queue.data, queue.len)
    mut qe := qpos
    while qe < queue.len and bytes(qstr)[qe] != 10 { qe = qe + 1 }
    ## the row is `<pkg manifest path>\t<alias>`; the TAB splits them (neither field can contain one).
    mut qt := qpos
    while qt < qe and bytes(qstr)[qt] != 9 { qt = qt + 1 }
    deppkg := str_at(qbase + qpos, qt - qpos)
    mut dalias := str_at(qbase + qe, 0)
    if qt < qe { dalias = str_at(qbase + qt + 1, qe - (qt + 1)) }
    qpos = qe + 1
    ddir := dir_of(deppkg)
    ## MOD-10: dedup on the SOURCE identity, while every file this package's modules are read from
    ## keeps `ddir`'s spelling (as relative as the manifest argument was).
    dkey := abs_norm_path(a, ddir)
    if line_in_set(seen, dkey) == false {
      kd := rt::push_str(seen, dkey)
      kdn := rt::push_byte(seen, 10)
      dsrc := pkg_src_dir(a, deppkg, ddir)
      if dalias.len != 0 {
        kr1 := rt::push_str(droots, dsrc)
        kr2 := rt::push_byte(droots, 9)
        kr3 := rt::push_str(droots, dalias)
        kr4 := rt::push_byte(droots, 10)
      }
      mods := list_al_in_dir(a, dsrc)
      scan_deps_into_queue(a, deppkg, ddir, queue, edges)   ## enqueue this dep's transitive deps
      ## the accumulate is LAST on purpose: a bare CALL as the final statement of a nested block used
      ## to be emitted as this (value-returning) fn's RETURN, which aborted the walk here and returned
      ## an empty module list — the defect this slice fixes in `lower.al`. Ending the block on a
      ## BINDING keeps the discovery correct under a pre-fix compiler too (the bootstrap seed).
      ka := rt::push_str(acc, mods)
    }
  }
  ## MOD-11 / Modules §8 — the resolved graph MUST be acyclic. A chain that returns to a package
  ## already on it is a Config diagnostic printing the closing chain of sources, never a silently
  ## deduplicated edge: a package is compiled against its dependencies' FINISHED interfaces, so a
  ## cycle has no valid build order at all, and accepting one makes the artifact depend on traversal
  ## order. `seen` is exactly the node set (every enqueued dependency is visited once) and `edges` the
  ## complete edge set, so the check runs over the whole graph, not one path through it. The
  ## diagnostic is located at the manifest of the cycle's HEAD — a package ON the cycle, hence one
  ## whose own `dependencies` field declares a cycle edge — falling back to the root manifest.
  nodeset := str_at(seen.data, seen.len)
  cyc := graph_cycle_chain(a, nodeset, edges)
  if cyc.len != 0 {
    mut cycman := root_pkg
    if CYCLE_HEAD_N != 0 {
      hd := str_at(CYCLE_HEAD_P, CYCLE_HEAD_N)
      hm := cat2(a, hd, "/package.al")
      if path_exists(a, hm) { cycman = hm }
    }
    dep_config_error(a, "config: the package dependency graph has a cycle", cycman, cyc)
  }
  ## publish the alias table for `driver::push_module_name` (empty for a dependency-free package →
  ## every module keeps its existing name → the self-build's emission is untouched).
  drs := str_at(droots.data, droots.len)
  kdr := driver::set_dep_roots(unchecked bitcast(usize, drs.ptr), drs.len)
  ## the ROOT package's modules LAST (its `main` is the program entry). The modules live under the
  ## root's `source_dir` (`<rootdir>/src`, …) — `pkg_src_dir` resolves it.
  rsrc := pkg_src_dir(a, root_pkg, rootdir)
  rmods := list_al_in_dir(a, rsrc)
  kr := rt::push_str(acc, rmods)
  return str_at(acc.data, acc.len)
}

## The newline-joined source list to compile. `pkg_al` is the already-resolved manifest selected by
## TOOL-14 (explicit or upward-discovered); otherwise the command is a bare file list and its first
## file is moved to the last module position so the synthesized `_start` calls that root's `main`.
pub build_paths := fn(in out a : rt::Arena, cmd : str, fi : usize, n : usize, pkg_al : str) -> str {
  if pkg_al.len > 0 {
    ## the package's `.al` modules + every transitive `Path`-dependency's modules (deps first,
    ## the root package's modules last so the entry stays in the root). package.al is excluded.
    lst := pkg_module_paths(a, pkg_al)
    if lst.len > 0 { return lst }
    ## NO modules at all → a SINGLE-FILE package: compile the manifest itself. Its `Package(…)`
    ## value is inert top-level data; an ordinary `main` in that same file remains the entry module.
    return single_path_list(a, pkg_al)
  }
  return bare_file_paths(a, cmd, fi, n)
}

## The self-hosted compiler's CLI entry. Reads argv from /proc/self/cmdline:
##   <prog> <file.al>... | <prog> <pkg>/package.al   — emit the program's GAS to stdout (fixpoint form)
##   <prog> -o <out> ( <file.al>... | <pkg>/package.al )  — BUILD: write `<out>.s` + `as`/`ld` -> `<out>`
##   <prog> run ( <file.al>... | <pkg>/package.al )      — BUILD to an artifact + fork/exec it, return its code
##   <prog> check ( <file.al>... | <pkg>/package.al )    — TYPE-CHECK only (no emit): exit 0 ok / 1 reject / 9 parse
##   <prog> new <name>                                   — scaffold a package dir <name>/ (package.al + main.al)
##   <prog> test ( <file.al>... | <pkg>/package.al )     — build a @test runner + run it; exit = #failing tests
##   <prog> build <pkg>/package.al                       — manifest build: artifact → `<target_dir>/<output>`
## A lone `…/package.al` arg discovers the package's `.al` modules under the manifest's `source_dir`
## (default `src`); else the args are the file list. The entry is the module named `main` (the emitted
## `_start` → `main__main`), falling back to the last module for a single-file build.
## Compiles them (driver::compile_files), then flushes the GAS or self-assembles it (link_exe).
## The Unix wait4 status word → the code `alatyr run` / `alatyr test` reports for the child.
## The status packs the CAUSE of the state change, not just an exit code, so decoding it as a bare
## `WEXITSTATUS` reports a SIGNAL-KILLED child (bits 8..15 are zero there) as a clean `0` — a
## trap-detection hole: `alatyr run test/checked_add_ovf.al` said 0 while the built binary died on
## SIGILL. Decode the three `<sys/wait.h>` cases the way the C macros do, and map the abnormal ones
## to the SHELL convention `128 + signal` (SIGILL 4 → 132, SIGTRAP 5 → 133, SIGFPE 8 → 136,
## SIGSEGV 11 → 139) — exactly the codes `scripts/e2e.sh` and the sweeps already expect from an
## executed trap fixture, so `run` and build+execute now agree.
## `/256 %256`/`%128` avoid the `>>`/`&` bit operators (the lean self-host parser handles `/` and
## `%`, which lower to idivq); `status % 128` is `status & 0x7f`, `status % 256` is `status & 0xff`.
wexit := fn(status : usize) -> usize {
  low := status % 256
  sig := status % 128
  ## WIFSTOPPED — the low byte is 0x7f: the child STOPPED (ptrace/SIGSTOP), it did not exit.
  ## The stop signal is in bits 8..15; report it as an abnormal `128 + signal`, never success.
  if low == 127 { return 128 + ((status / 256) % 256) }
  ## WIFEXITED — the low 7 bits are 0: a normal exit, WEXITSTATUS is bits 8..15.
  if sig == 0 { return (status / 256) % 256 }
  ## WIFSIGNALED — the low 7 bits hold a real signal number (neither 0 nor 0x7f): killed by it.
  return 128 + sig
}

parse_uint_arg := fn(s : str) -> usize {
  mut v := 0
  mut i := 0
  if s.len == 0 { return 0 }
  while i < s.len {
    c := bytes(s)[i]
    if c < 48 or c > 57 { return 0 }
    v = v * 10 + (c - 48)
    i += 1
  }
  return v
}

test_jobs_diag := fn(in out a : rt::Arena, msg : str) -> usize {
  mut b := rt::strbuf(a, 128)
  k0 := rt::push_str(b, "Usage: ")
  k1 := rt::push_str(b, msg)
  k2 := rt::push_byte(b, 10)
  kf := diag_flush(b, 1)
  if kf != 0 { return kf }
  return 40
}

## `run`: link an artifact, fork/exec it and return ITS exit code. A package caller supplies a
## deterministic `target_dir` path and keeps every produced file; a manifest-less caller gets a
## per-process `/tmp/.alatyr-run-<pid>` path that is removed on every exit path. `cmd` is the compiler's
## NUL-separated process command line; `[arg_first, arg_last)` is the already-separated PROGRAM argv
## tail after the CLI `--` boundary (Tooling §4 / §6.1). Keeping this boundary here means those values
## never enter `build_paths` or the source parser, while the child receives ordinary OS argv for
## `std::os::args(allocator)` (Stdlib §7 / STD-3).
build_and_run := fn(in out a : rt::Arena, outp : str, keep_artifacts : bool, gbase : usize, glen : usize, paths : str, entry : str, spanbase : usize, cmd : str, arg_first : usize, arg_last : usize) -> usize {
  mut artifact := outp
  if artifact.len == 0 {
    ## Unique temp exe PER PROCESS: parallel manifest-less invocations must not share one fixed path.
    ## The suffix also propagates to link_exe's derived `.s`/`.o` names, all of which are cleaned below.
    pid := rt::sys_getpid(39)
    mut b := rt::strbuf(a, 48)
    k := rt::push_str(b, "/tmp/.alatyr-run-")
    k2 := rt::push_int(b, pid)
    artifact = str_at(b.data, b.len)
  }
  rc := link_exe_split(a, artifact, paths, gbase, glen, spanbase, entry, "", false, "")
  if rc != 0 {
    if keep_artifacts == false { cleanup_temp_artifact(a, artifact, spanbase, paths) }
    return rc
  }
  prog_c := cstr(a, artifact)
  ## argv = [temporary executable, program arguments..., NULL]. The target's `_start` remains
  ## unchanged: the kernel supplies this normal process input, and `std::os::args` reads it from
  ## `/proc/self/cmdline` as specified; no compiler-private entry ABI is introduced.
  argc := arg_last - arg_first
  av := rt::bump(a, (argc + 2) * 8)
  wword(av + 0, prog_c)
  mut ai := arg_first
  mut ak := 1
  while ai < arg_last {
    ac := cstr(a, arg_at(cmd, ai))
    wword(av + ak * 8, ac)
    ai += 1
    ak += 1
  }
  wword(av + ak * 8, 0)
  mut etr := 0
  environ := read_environ(a, etr)
  if etr != 0 { env_truncation_error(); return 21 }
  envp := build_envp(a, environ)
  st := rt::run(a, prog_c, av, envp)
  ## A program that could not be STARTED is not a program that ran and exited non-zero: report the
  ## spawn failure instead of inventing an exit status for it. Either way the temporary artifact is
  ## removed when it is not being kept (TOOL-10): a failed spawn leaves the same litter a successful
  ## one would.
  if st.kind != 0 {
    if keep_artifacts == false { cleanup_temp_artifact(a, artifact, spanbase, paths) }
    spawn_error(a, "program", "the built executable", st)
    return 19
  }
  result := wexit(unchecked bitcast(usize, st.code))
  if keep_artifacts == false { cleanup_temp_artifact(a, artifact, spanbase, paths) }
  return result
}

## Cross-target TOOL-5 link/run. The non-x86 emitters produce freestanding Linux GAS, so the selected
## target triple's binutils must assemble/link it and the matching user-mode QEMU must execute it. A
## missing cross tool is a Tooling failure, never a host-tool fallback or a skipped test.
cross_link_exe := fn(in out a : rt::Arena, out : str, gbase : usize, glen : usize, backend : usize) -> usize {
  ssfx := cat2(a, out, ".s")
  osfx := cat2(a, out, ".o")
  outs_c := cstr(a, ssfx)
  outo_c := cstr(a, osfx)
  out_c := cstr(a, out)
  w := rt::write_file(outs_c, gbase, glen)
  if w != 0 { tool_error("alatyr: cannot write the emitted cross-target assembly"); return 10 }
  mut etr := 0
  environ := read_environ(a, etr)
  if etr != 0 { env_truncation_error(); return 21 }
  envp := build_envp(a, environ)
  mut as_name := "aarch64-unknown-linux-gnu-as"
  mut ld_name := "aarch64-unknown-linux-gnu-ld"
  if backend == 2 { as_name = "riscv64-unknown-linux-gnu-as" ; ld_name = "riscv64-unknown-linux-gnu-ld" }
  as_c := resolve_in_path(a, environ, as_name)
  ld_c := resolve_in_path(a, environ, ld_name)
  if as_c == 0 { tool_error("alatyr: the selected target assembler is not found on PATH"); return 11 }
  if ld_c == 0 { tool_error("alatyr: the selected target linker is not found on PATH"); return 12 }
  dash_o := cstr(a, "-o")
  ra := exec4(a, as_c, outs_c, dash_o, outo_c, envp)
  if ra.kind != 0 { spawn_error(a, "cross-target assembler", as_name, ra); return 19 }
  if ra.code != 0 { tool_error("alatyr: the selected target assembler rejected the emitted assembly"); return 13 }
  rl := exec4(a, ld_c, outo_c, dash_o, out_c, envp)
  if rl.kind != 0 { spawn_error(a, "cross-target linker", ld_name, rl); return 19 }
  if rl.code != 0 { tool_error("alatyr: the selected target linker failed"); return 14 }
  0
}

cross_run_exe := fn(in out a : rt::Arena, out : str, backend : usize) -> usize {
  mut etr := 0
  environ := read_environ(a, etr)
  if etr != 0 { env_truncation_error(); return 21 }
  envp := build_envp(a, environ)
  mut qemu_name := "qemu-aarch64"
  if backend == 2 { qemu_name = "qemu-riscv64" }
  qemu_c := resolve_in_path(a, environ, qemu_name)
  if qemu_c == 0 { tool_error("alatyr: the selected target QEMU is not found on PATH; cross-target test cannot run"); return 19 }
  out_c := cstr(a, out)
  st := exec4(a, qemu_c, out_c, 0, 0, envp)
  if st.kind != 0 { spawn_error(a, "cross-target QEMU", qemu_name, st); return 19 }
  wexit(unchecked bitcast(usize, st.code))
}

build_and_run_cross := fn(in out a : rt::Arena, outp : str, keep_artifacts : bool, gbase : usize, glen : usize, backend : usize) -> usize {
  mut artifact := outp
  if artifact.len == 0 {
    pid := rt::sys_getpid(39)
    mut b := rt::strbuf(a, 64)
    k := rt::push_str(b, "/tmp/.alatyr-cross-test-")
    k2 := rt::push_int(b, pid)
    artifact = str_at(b.data, b.len)
  }
  rc := cross_link_exe(a, artifact, gbase, glen, backend)
  if rc != 0 {
    if keep_artifacts == false { cleanup_temp_artifact(a, artifact, 0, "") }
    return rc
  }
  result := cross_run_exe(a, artifact, backend)
  if keep_artifacts == false { cleanup_temp_artifact(a, artifact, 0, "") }
  result
}

## `new <name>`: scaffold a package directory `<name>/` containing a manifest `package.al` and the
## default-source directory `<name>/src/` with a runnable `main.al` that prints a deterministic success
## message through the ambient stdlib, so `<prog> build <name>/package.al` / `<prog> run <name>/package.al`
## works immediately. Returns 0 on success, or 30 (mkdir) / 31 (write package.al) / 32 (write main.al).
## String literals carry
## escaped quotes/newlines (`\"`/`\n`)
## — the lexer skips the escaped char, the parser collapses each `\X` to one byte, `as` decodes the
## emitted `.ascii`, so the written files contain real quotes and line breaks.
new_package := fn(in out a : rt::Arena, name : str) -> usize {
  ## mkdir <name> (0755)
  ndir := cstr(a, name)
  md := rt::sys_mkdir(83, ndir, 493)
  if md < 0 { return 30 }
  ## The manifest omits source_dir, so scaffold the spec-default `src` tree rather than a legacy
  ## flat root. A separate mkdir keeps a failed partial scaffold fail-loud.
  srcdir := cat2(a, name, "/src")
  src_c := cstr(a, srcdir)
  sd := rt::sys_mkdir(83, src_c, 493)
  if sd < 0 { return 30 }
  ## <name>/package.al — the manifest (a single Package value), output named after the package.
  pkgrel := cat2(a, name, "/package.al")
  pkg_c := cstr(a, pkgrel)
  mut mb := rt::strbuf(a, 4096)
  h1 := rt::push_str(mb, "app := Package(version = \"0.1.0\", targets = [\n  Target(arch = Arch.x86_64, os = Os.linux, env = Env.gnu, container = Container.elf,\n         entry = \"_start\", output = \"")
  h2 := rt::push_str(mb, name)
  h3 := rt::push_str(mb, "\"),\n])\n")
  wp := rt::write_file(pkg_c, mb.data, mb.len)
  if wp != 0 { return 31 }
  ## <name>/src/main.al — the entry module. NO `_start` here: the self-host build emits its own.
  mainrel := cat2(a, name, "/src/main.al")
  main_c := cstr(a, mainrel)
  mut cb := rt::strbuf(a, 256)
  j1 := rt::push_str(cb, "main := fn() -> u64 {\n  n := std::io::print(\"Alatyr package ready\\n\")\n  return 0\n}\n")
  wm := rt::write_file(main_c, cb.data, cb.len)
  if wm != 0 { return 32 }
  return 0
}

## The test runner emits one `.Ltestdesc<N>` label for each selected @test. This marker lets the CLI
## distinguish a successful zero-test runner from a successful run with ordinary test reports without
## changing the driver/lower test artifact or its exit-code contract.
test_gas_has_desc := fn(gas : str) -> bool {
  needle := ".Ltestdesc"
  mut i := 0
  while i + needle.len <= gas.len {
    mut j := 0
    mut same := true
    while j < needle.len {
      if bytes(gas)[i + j] != bytes(needle)[j] { same = false }
      j += 1
    }
    if same { return true }
    i += 1
  }
  return false
}

## Cross-target runners use backend-specific local labels, but the zero-test decision is the same
## CLI contract as the host runner. Keep this probe at the surface rather than teaching the backends
## about command-line diagnostics.
cross_test_gas_has_desc := fn(gas : str) -> bool {
  return str_contains(gas, ".La64testdesc") or str_contains(gas, ".Lrvtestdesc")
}

## Report the successful empty test selection on stdout. The wording is intentionally concise and
## deterministic; non-empty test runs keep the driver's existing per-test reports unchanged.
test_zero_diag := fn() {
  msg := "alatyr test: 0 tests\n"
  w := rt::sys_write(1, 1, unchecked bitcast(usize, msg.ptr), msg.len)
}

## ============================== AMBIENT STDLIB INJECTION (P2) ==============================
## The shipped stdlib lives in the compiler's `lib/` (base/alloc/std), provided AMBIENTLY: a user
## program writes `alloc::vec::push(…)` / `std::io::write(…)` without listing the file. The cli
## locates `lib/`, scans the program (+ transitively the pulled-in stdlib files) for 3-segment
## `alloc::sub::…` / `std::sub::…` references, and PREPENDS the matching `lib/<tier>/<sub>.al` files
## to the compile list. Each lib file's module name is its mangled path (`driver::push_module_name`:
## lib/std/io.al → "std__io"), so a `std::io::write` call's mangled label `std__io__write` matches.
## ONLY a 3-segment path triggers injection (a 2-segment alias like `vec := alloc::vec` does not), and
## the scan SKIPS `##` comments and string literals — so the self-host's own build (whose only
## `alloc::x::y`/`std::x::y` mentions are in prose comments) injects nothing and the fixpoint holds.

## byte is an identifier char (ASCII alnum or `_`).
amb_idc := fn(c : usize) -> bool { return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 }

## does the literal `lit` occur at `src[i..]`? (byte compare; false if it would run past the end)
amb_lit_at := fn(src : str, i : usize, n : usize, lit : str) -> bool {
  if i + lit.len > n { return false }
  mut j := 0
  mut ok := true
  while j < lit.len { if bytes(src)[i + j] != bytes(lit)[j] { ok = false } ; j = j + 1 }
  return ok
}

## Locate the compiler's shipped `lib/` directory by reading `/proc/self/exe` (a kernel symlink to
## the running binary) → its directory → `/../lib` (the dev/install layout `<root>/{target,bin}/exe`
## + `<root>/lib`). Returns 0-len on failure; callers then skip injection (per-file existence is also
## checked, so a wrong guess simply yields no ambient modules).
pub lib_dir := fn(in out a : rt::Arena) -> str {
  exe_c := cstr(a, "/proc/self/exe")
  mut buf := rt::strbuf(a, 8192)
  r := rt::sys_readlink(89, exe_c, buf.data, 8000)
  if r <= 0 { return str_at(buf.data, 0) }
  rl := unchecked bitcast(usize, r)
  exe := str_at(buf.data, rl)
  eb := unchecked bitcast(usize, exe.ptr)
  mut cut := 0
  mut i := 0
  while i < rl { if bytes(exe)[i] == 47 { cut = i } ; i = i + 1 }   ## last '/'
  mut prev := 0
  i = 0
  while i < cut { if bytes(exe)[i] == 47 { prev = i + 1 } ; i = i + 1 }
  dirbase := str_at(eb + prev, cut - prev)
  if dirbase == "debug" or dirbase == "release" { return cat2(a, str_at(eb, cut), "/../../lib") }
  return cat2(a, str_at(eb, cut), "/../lib")
}

## Does the file at `path` exist + open read-only?
path_exists := fn(in out a : rt::Arena, path : str) -> bool {
  pc := cstr(a, path)
  fd := rt::sys_open(2, pc, 0, 0)
  if fd < 0 { return false }
  ufd := unchecked bitcast(usize, fd)
  cc := rt::sys_close(3, ufd)
  return true
}

## The newline-joined list of ambient `lib/` module files a program (transitively) references via a
## 3-segment `alloc::<sub>::…` / `std::<sub>::…` / `base::<sub>::…` path (the three lib tiers — `base`
## exposes the base modules that are NOT in the always-prepended prelude closure, e.g. `base::str`,
## `base::char`; a base module also in the prelude is injected once, deduped by `seen`). A scan QUEUE holds the (ptr, len) of every
## source to scan — seeded with the user sources, grown with each pulled-in `lib/` file (transitive
## closure: `std::io` pulls in whatever it uses). The scan is INLINED (no helper) because threading an
## `in out` StrBuf accumulator through a helper clobbers it on copyback in the lean lower; the queue
## is a word-Vec, mutated by `vec_push` (which threads correctly). For each unseen `<tier>/<sub>` ref,
## the `<libdir>/<tier>/<sub>.al` path — if it exists — is added to the result and its source enqueued.
## `##` comments and `"…"` strings are skipped, and only a 3-segment path (not a 2-segment alias like
## `vec := alloc::vec`) triggers — so the self-host's own build (whose stdlib mentions are all in
## comments) injects nothing and the TOOL-1 fixpoint is unaffected. 0-len when nothing is referenced.
## `is_pkg` = a MANIFEST/package build (`build …/package.al`): its modules come from the manifest, so
## a 2-segment `X := alloc::vec` alias must NOT inject `lib/alloc/vec.al` (the self-host `src/` has real
## such aliases — injecting would duplicate + break the TOOL-1 fixpoint). A single-file compile
## (`is_pkg == false`) DOES inject a 2-seg alias's module — that is the ambient-stdlib convenience path.
pub ambient_paths := fn(in out a : rt::Arena, user_paths : str, libdir : str, is_pkg : bool) -> str {
  mut result := rt::strbuf(a, 1048576)
  if libdir.len == 0 { return str_at(result.data, 0) }
  mut seen := rt::strbuf(a, 262144)
  ## scan queue: parallel (ptr, len) words of each source already read into the arena.
  mut sq := rt::Vec(data = rt::bump(a, 4096 * 8), len = 0, cap = 4096)
  ## seed with the user sources
  ub := unchecked bitcast(usize, user_paths.ptr)
  mut up := 0
  while up < user_paths.len {
    mut ue := up
    while ue < user_paths.len and bytes(user_paths)[ue] != 10 { ue = ue + 1 }
    if ue > up {
      fsrc := read_proc(a, cstr(a, str_at(ub + up, ue - up)), 524288)
      pp := rt::vec_push(sq, unchecked bitcast(usize, fsrc.ptr))
      pl := rt::vec_push(sq, fsrc.len)
    }
    up = ue + 1
  }
  ## entries seeded so far are USER sources; everything pushed during the drain is an injected LIB
  ## file. A bare `<mod>::` reference (no `alloc`/`std` tier) is scanned ONLY in a LIB file — src/
  ## has bare `rt::`/`ast::`/… everywhere, so scanning USER sources for those would break the
  ## self-host inject-nothing invariant (fixpoint). (Harmless anyway — no `lib/*/rt.al` exists — but
  ## gated for clarity + safety.)
  user_q_end := rt::vec_len(sq)
  ## `@alloc(…)` in USER source (Memory §2.4) needs the base allocator surface even with no
  ## explicit `alloc::`/`std::` reference. The parser desugars it to a bare `alloc_into(a, init)` call
  ## resting on the base prelude closure (assert/result/option/alloc/slice), so a bare `@alloc` must
  ## FORCE that prelude to be injected. Just record the need here (the prelude block below does the
  ## actual injection, exactly once — injecting `base/alloc.al` here too would DUPLICATE it, since the
  ## prelude also lists `alloc`). Dormant for the self-host build (`src/` has no `@alloc`).
  mut needs_alloc := false
  ## A package's base `Result` prelude must not be seeded by a root `std::io`/`std::fmt` reference:
  ## `Result` is a bare-name base type and every user module may construct it independently. Keep a
  ## separate trigger so a package that declares its own `Result` can veto only this contribution;
  ## other prelude needs (for example an explicit std module) remain independent. The declaration
  ## scan is package-wide because declarations resolve across the whole compile and may be forward
  ## referenced. `is_lib == false` keeps injected stdlib declarations from becoming user overrides.
  mut needs_result := false
  mut has_result_decl := false
  mut has_option_decl := false
  ## `needs_derive` — a SINGLE-FILE program that declares a `struct`/`enum` may compare two aggregate
  ## values with a bare `==`/`!=`/`<`/… operator, which the lower routes to `base::derive::eq`/`lt`
  ## (§2.6). Those derives are referenced by NO textual `::` path (the routing synthesizes the call), so
  ## the 3-segment scan misses them — inject `lib/base/derive.al` when a struct/enum decl appears. It is
  ## self-contained (only builtins) and its generic derives + concrete `hash(str)` are DCE'd when
  ## uncalled → a struct program with only SCALAR compares stays byte-identical. Gated on `is_pkg ==
  ## false`: the self-host manifest build never sets it (`src/` makes no bare aggregate compare) → the
  ## TOOL-1 fixpoint is unaffected.
  mut needs_derive := false
  ## `u128` (Types §7 wider-than-native integer; now the TYP-10 `u128 ≡ uint(128)` alias)
  ## is an ambient PRELUDE library type (`lib/base/u128.al` — the generalized `uint(N)` recipe),
  ## referenced by BARE name in a single-file user program — the 3-segment scan misses it. A bare
  ## `u128` (word-boundary, `is_pkg == false`) forces the base-prelude block below, which lists
  ## `u128` (bi==8) alongside the base closure (like `Option`/`Result` via `needs_alloc`).
  ## Dormant for the self-host build (`src/` mentions `u128` only in comments) → fixpoint-neutral.
  mut needs_u128 := false
  ## A bare `uint(` INSTANTIATION (TYP-10, `uint(192)` / `uint(256)`) pulls the SAME module — it is
  ## where the prelude `uint` type-function lives. `has_uint_decl` vetoes the trigger when the file
  ## declares its OWN `uint := …` type-function (the slice-A/B machinery tests do): injecting then
  ## would duplicate the decl + its generic operators → the loud ambiguity reject.
  mut needs_uint := false
  mut has_uint_decl := false
  ## A bare `Slice(` INSTANTIATION (Stdlib §3.5 / appendix 160 — `Slice` is a LIBRARY pair, a
  ## `struct { ptr, len }` type-function in `lib/base/slice.al`, not a layout primitive) is reached
  ## by BARE name in a single-file user program, exactly like `Option`/`Result`/`u128` — and the
  ## 3-segment `alloc::`/`std::` scan misses it. WITHOUT this trigger a program whose ONLY prelude
  ## need was `Slice` compiled with NO `Slice` declaration in scope, so `field_words` sized a
  ## `v : Slice(u64)` struct field as ONE word: `v.len` read 0 and every later field overlapped —
  ## a SILENT MISCOMPILE that the very same program with any `Option` mention got right.
  ## `has_slice_decl` vetoes the trigger when the file declares its OWN `Slice := …` type-function
  ## (test/generic_struct_field.al, test/struct_lit_agg_field.al do): injecting then would duplicate
  ## the decl. Gated `is_pkg == false` like the others → the self-host manifest build never sets it.
  mut needs_slice := false
  mut has_slice_decl := false
  ## drain the scan queue (it grows as transitive refs are discovered)
  mut qi := 0
  while qi < rt::vec_len(sq) {
    entry_idx := qi
    sptr := rt::vec_get(sq, qi)
    slen := rt::vec_get(sq, qi + 1)
    qi += 2
    is_lib := entry_idx >= user_q_end
    src := str_at(sptr, slen)
    n := slen
    mut i := 0
    while i < n {
      c := bytes(src)[i]
      ## `@alloc(…)` in a USER source → force the base prelude (see `needs_alloc` above). An independent
      ## check (the `@` is not a `##`/`"`/ident lead, so the chain below no-ops on it); only sets a flag.
      if is_lib == false and c == 64 and amb_lit_at(src, i + 1, n, "alloc") { needs_alloc = true }
      ## A bare `Result` reference in any package user source forces the base prelude. Unlike the other
      ## legacy single-file triggers below, this must not be gated on `is_pkg`: a non-root package module
      ## may construct `Result` even when the package root has no std/alloc reference. A user declaration
      ## is recorded before the post-scan veto, so forward references and the self-host's own Result stay
      ## declaration-owned rather than pulling a duplicate shipped module.
      if is_lib == false and (i == 0 or amb_idc(bytes(src)[i - 1]) == false) {
        if amb_lit_at(src, i, n, "Result :=") { has_result_decl = true }
        if amb_lit_at(src, i, n, "Option :=") { has_option_decl = true }
        if amb_lit_at(src, i, n, "Result") { needs_result = true }
      }
      ## The remaining bare prelude triggers retain their single-file gate. A manifest build is the
      ## self-host path today and already owns its allocator/option/aggregate declarations; widening
      ## those triggers here would make this focused Result fix silently change the TOOL-1 input set.
      if is_lib == false and is_pkg == false and (i == 0 or amb_idc(bytes(src)[i - 1]) == false) {
        if amb_lit_at(src, i, n, "Option") { needs_alloc = true }
        ## bare overflow-policy op (`wrapping_`/`saturating_`/`checked_`/`overflowing_`, §6.3, lib/base/num.al) —
        ## a program using them WITHOUT Option/Result must still pull the base prelude that carries num.al.
        if amb_lit_at(src, i, n, "wrapping_") or amb_lit_at(src, i, n, "saturating_") or amb_lit_at(src, i, n, "overflowing_") { needs_alloc = true }
        ## bare `u128` at a word boundary (trailing char not an ident char) → the ambient prelude type.
        if amb_lit_at(src, i, n, "u128") and (i + 4 >= n or amb_idc(bytes(src)[i + 4]) == false) { needs_u128 = true }
        ## bare `uint(` (TYP-10) → the same prelude module; a local `uint :=` decl vetoes it (above).
        if amb_lit_at(src, i, n, "uint(") { needs_uint = true }
        if amb_lit_at(src, i, n, "uint :=") { has_uint_decl = true }
        ## bare `Slice(` (Stdlib §3.5) → the base prelude that carries `lib/base/slice.al`; a local
        ## `Slice :=` decl vetoes it (above).
        if amb_lit_at(src, i, n, "Slice(") { needs_slice = true }
        if amb_lit_at(src, i, n, "Slice :=") { has_slice_decl = true }
        ## a `struct`/`enum` DECLARATION (word boundary) → the aggregate types that a bare aggregate
        ## comparison can lower to `base::derive::eq`/`lt` — inject `derive` (harmless when uncalled).
        if amb_lit_at(src, i, n, "struct") and (i + 6 >= n or amb_idc(bytes(src)[i + 6]) == false) { needs_derive = true }
        if amb_lit_at(src, i, n, "enum") and (i + 4 >= n or amb_idc(bytes(src)[i + 4]) == false) { needs_derive = true }
      }
      if c == 35 and i + 1 < n and bytes(src)[i + 1] == 35 {
        while i < n and bytes(src)[i] != 10 { i = i + 1 }            ## `##` comment → EOL
      } else if c == 34 {
        i += 1                                                     ## `"…"` string
        while i < n and bytes(src)[i] != 34 {
          if bytes(src)[i] == 92 { i = i + 2 } else { i = i + 1 }
        }
        i += 1
      } else {
        mut boundary := true
        if i > 0 { boundary = amb_idc(bytes(src)[i - 1]) == false }
        mut rl := 0
        if boundary {
          if amb_lit_at(src, i, n, "alloc") { rl = 5 }
          else if amb_lit_at(src, i, n, "std") { rl = 3 }
          else if amb_lit_at(src, i, n, "base") { rl = 4 }
        }
        if rl > 0 {
          p := i + rl
          if p + 1 < n and bytes(src)[p] == 58 and bytes(src)[p + 1] == 58 {       ## root `::`
            s := p + 2
            mut e := s
            while e < n and amb_idc(bytes(src)[e]) { e = e + 1 }
            ## a SECOND `::` after the sub ident → a 3-segment submodule path; a 2-seg alias
            ## (`X := alloc::vec`) injects only in a single-file compile (`is_pkg == false`).
            mut do_inject := false
            if e > s and e + 1 < n and bytes(src)[e] == 58 and bytes(src)[e + 1] == 58 { do_inject = true }
            if e > s and is_pkg == false and do_inject == false { do_inject = true }
            if do_inject {
              ## build `<libdir>/<tier>/<sub>.al` via push (no `if`-valued str bind)
              mut pbuf := rt::strbuf(a, libdir.len + 64)
              k0 := rt::push_str(pbuf, libdir)
              k1 := rt::push_byte(pbuf, 47)
              if rl == 5 { ka := rt::push_str(pbuf, "alloc") } else if rl == 4 { kb := rt::push_str(pbuf, "base") } else { ks := rt::push_str(pbuf, "std") }
              k2 := rt::push_byte(pbuf, 47)
              k3 := rt::push_str(pbuf, str_at(sptr + s, e - s))
              k4 := rt::push_str(pbuf, ".al")
              lib_path := str_at(pbuf.data, pbuf.len)
              if line_in_set(seen, lib_path) == false {
                kp := rt::push_str(seen, lib_path)
                kn := rt::push_byte(seen, 10)
                if path_exists(a, lib_path) {
                  kr := rt::push_str(result, lib_path)
                  krn := rt::push_byte(result, 10)
                  lsrc := read_proc(a, cstr(a, lib_path), 524288)
                  qp := rt::vec_push(sq, unchecked bitcast(usize, lsrc.ptr))
                  ql := rt::vec_push(sq, lsrc.len)
                }
              }
            }
          }
        } else if is_lib and boundary {
          ## BARE module reference inside an injected LIB file — `<mod>::<name>` with NO `alloc`/`std`
          ## tier (e.g. `string.al`'s `strbuf::StrBuf` / `strbuf::strbuf(…)`). Try each tier's
          ## `lib/<tier>/<mod>.al`; `path_exists` filters non-module heads (`Option::`/`Result::`/
          ## `Arch::` → no such file, no injection). This closes the ambient `alloc::string` gap
          ## (String is a thin layer over `strbuf::StrBuf`). NOT run for USER/`src/` sources → the
          ## self-host build (bare `rt::`/`ast::` everywhere, none with a lib file) injects nothing.
          mut me := i
          while me < n and amb_idc(bytes(src)[me]) { me = me + 1 }
          if me > i and me + 1 < n and bytes(src)[me] == 58 and bytes(src)[me + 1] == 58 {
            modname := str_at(sptr + i, me - i)
            for ti in 0..3 {
              mut mbuf := rt::strbuf(a, libdir.len + 64)
              m0 := rt::push_str(mbuf, libdir)
              m1 := rt::push_byte(mbuf, 47)
              if ti == 0 { ma := rt::push_str(mbuf, "alloc") } else { if ti == 1 { ms := rt::push_str(mbuf, "std") } else { mbb := rt::push_str(mbuf, "base") } }
              m2 := rt::push_byte(mbuf, 47)
              m3 := rt::push_str(mbuf, modname)
              m4 := rt::push_str(mbuf, ".al")
              mod_path := str_at(mbuf.data, mbuf.len)
              if line_in_set(seen, mod_path) == false {
                mp := rt::push_str(seen, mod_path)
                mn := rt::push_byte(seen, 10)
                if path_exists(a, mod_path) {
                  mr := rt::push_str(result, mod_path)
                  mrn := rt::push_byte(result, 10)
                  msrc := read_proc(a, cstr(a, mod_path), 524288)
                  mqp := rt::vec_push(sq, unchecked bitcast(usize, msrc.ptr))
                  mql := rt::vec_push(sq, msrc.len)
                }
              }
            }
          }
        } else if boundary and is_lib == false {
          ## BARE-PRELUDE trigger (§5): a bare `print(…)` / `println(…)` call in USER source is the
          ## specified spelling of `std::fmt::print` (Functions §7.1) — the 3-segment scan above only
          ## reaches the qualified `std::fmt::print`. When the bare form is used, inject `std/fmt.al`;
          ## its own `std::io::`/`print_one` refs pull `io` + the base closure transitively. A `print`
          ## PRECEDED by `::` (a qualified `…::print`) is already handled above, so require the ident be
          ## a call (`(` follows). Dormant for the self-host build — `src/` makes no bare `print` call
          ## (only `rt::`/`::print` helpers), so nothing is injected and the TOOL-1 fixpoint is unaffected.
          mut pe := i
          while pe < n and amb_idc(bytes(src)[pe]) { pe = pe + 1 }
          pv := str_at(sptr + i, pe - i)
          if pv == "print" or pv == "println" {
            mut pj := pe
            while pj < n and (bytes(src)[pj] == 32 or bytes(src)[pj] == 9) { pj = pj + 1 }
            if pj < n and bytes(src)[pj] == 40 {                     ## a call — `(` follows
              mut fbuf := rt::strbuf(a, libdir.len + 32)
              f0 := rt::push_str(fbuf, libdir)
              f1 := rt::push_str(fbuf, "/std/fmt.al")
              fmt_path := str_at(fbuf.data, fbuf.len)
              if line_in_set(seen, fmt_path) == false {
                fp := rt::push_str(seen, fmt_path)
                fpn := rt::push_byte(seen, 10)
                if path_exists(a, fmt_path) {
                  fr := rt::push_str(result, fmt_path)
                  frn := rt::push_byte(result, 10)
                  fsrc := read_proc(a, cstr(a, fmt_path), 524288)
                  fqp := rt::vec_push(sq, unchecked bitcast(usize, fsrc.ptr))
                  fql := rt::vec_push(sq, fsrc.len)
                }
              }
            }
          }
          ## BARE-PRELUDE trigger for `exit(code)` — the base process control (`lib/base/process.al`:
          ## `exit(code) -> Never`, a raw `exit_group` syscall). A freestanding program's `_start` calls
          ## it to terminate; it is base-tier (bare name), so the qualified scan misses it — inject
          ## `base/process.al` when a bare `exit(` call appears in USER source. Self-contained (no `::`
          ## deps). Dormant for `src/` (its only `exit(` occurrences are in comments → skipped) → the
          ## TOOL-1 fixpoint is unaffected.
          if pv == "exit" {
            mut ej := pe
            while ej < n and (bytes(src)[ej] == 32 or bytes(src)[ej] == 9) { ej = ej + 1 }
            if ej < n and bytes(src)[ej] == 40 {                     ## a call — `(` follows
              mut ebuf := rt::strbuf(a, libdir.len + 32)
              eb0 := rt::push_str(ebuf, libdir)
              eb1 := rt::push_str(ebuf, "/base/process.al")
              proc_path := str_at(ebuf.data, ebuf.len)
              if line_in_set(seen, proc_path) == false {
                epp := rt::push_str(seen, proc_path)
                epn := rt::push_byte(seen, 10)
                if path_exists(a, proc_path) {
                  epr := rt::push_str(result, proc_path)
                  eprn := rt::push_byte(result, 10)
                  esrc := read_proc(a, cstr(a, proc_path), 524288)
                  eqp := rt::vec_push(sq, unchecked bitcast(usize, esrc.ptr))
                  eql := rt::vec_push(sq, esrc.len)
                }
              }
            }
          }
        }
        i += 1
      }
    }
  }
  ## A user-defined Result/Option owns that type name for the whole package. Veto only the corresponding
  ## ambient trigger/module; this preserves custom prelude definitions even when another module caused
  ## the global ambient result to become non-empty (for example a qualified std import).
  if has_result_decl { needs_result = false }
  if needs_result { needs_alloc = true }
  ## TYP-10: fold the `uint(` trigger into `needs_u128` (same module), vetoed by a local `uint` decl.
  if has_uint_decl { needs_uint = false }
  if needs_uint { needs_u128 = true }
  ## Stdlib §3.5: a bare `Slice(` needs the base closure (bi==4 = `lib/base/slice.al`), which is the
  ## same closure `needs_alloc` pulls — vetoed by a file-local `Slice :=` type-function.
  if has_slice_decl { needs_slice = false }
  if needs_slice { needs_alloc = true }
  ## PRELUDE (base tier) injection. The 3-segment scan above reaches only `std::x::`/`alloc::x::`
  ## paths; the base tier is referenced by BARE names (`Result`, `Option`, `Arena`, `allocate`,
  ## `get`, …), so it is not discoverable by that scan. When ANY std/alloc module was injected,
  ## PREPEND the core base modules it may rest on — the linkable prelude closure
  ## {assert, result, option, alloc}. (The overload-heavy `cmp`/`num` + the comptime-derive
  ## `derive` are deliberately NOT prepended — the lean lower does not yet emit distinct labels
  ## for a module's same-name overloads, so co-compiling `cmp` duplicates `cmp__lt`. A program
  ## needing those pulls them in explicitly for now.) Generic base fns (`allocate`/`get`/`buf_ptr`)
  ## emit only when instantiated, so an io-only program injects the prelude with zero dead calls.
  ## Gated on a non-empty result → the self-host build (no std/alloc refs) injects nothing, so the
  ## TOOL-1 fixpoint is unaffected.
  ## DERIVE-ONLY fast path: a single-file program whose ONLY prelude need is `derive` (a struct/enum
  ## decl, no std/alloc/u128 reference) injects JUST `lib/base/derive.al` and returns — the heavy base
  ## closure (assert…num) is not pulled for a program that merely compares aggregates. A program that
  ## ALSO needs the closure (Option/Result/alloc/u128) falls through, where the closure loop injects
  ## derive (bi==7) alongside the rest. Self-host: `needs_derive` is is_pkg-gated false → never taken.
  if needs_derive and result.len == 0 and needs_alloc == false and needs_u128 == false {
    mut dbuf := rt::strbuf(a, libdir.len + 32)
    d0 := rt::push_str(dbuf, libdir)
    d1 := rt::push_str(dbuf, "/base/derive.al")
    dpath := str_at(dbuf.data, dbuf.len)
    if path_exists(a, dpath) and line_in_set(seen, dpath) == false {
      dr := rt::push_str(result, dpath)
      drn := rt::push_byte(result, 10)
    }
    return str_at(result.data, result.len)
  }
  if result.len == 0 and needs_alloc == false and needs_u128 == false { return str_at(result.data, 0) }
  mut pre := rt::strbuf(a, 1048576)
  ## The base closure {assert, result, option, alloc, slice, cmp, num, derive} + the `u128`/`uint(N)`
  ## prelude recipe (Types §7 / TYP-10, `lib/base/u128.al`). bi==8 = `u128`; a program
  ## referencing `u128` by bare name or instantiating a bare `uint(` pulls it here (like
  ## `Option`/`Result` pull the base closure). Each is path-checked, so an absent file is skipped.
  ## Generic base fns emit only when instantiated (DCE), so an unused module is inert.
  mut bi := 0
  while bi < 9 {
    mut nb := rt::strbuf(a, libdir.len + 32)
    kd := rt::push_str(nb, libdir)
    ks := rt::push_str(nb, "/base/")
    if bi == 0 { kn := rt::push_str(nb, "assert") }
    else if bi == 1 { kn := rt::push_str(nb, "result") }
    else if bi == 2 { kn := rt::push_str(nb, "option") }
    else if bi == 3 { kn := rt::push_str(nb, "alloc") }
    ## `slice` — `Slice(T)` (the view type `as_slice`/`index_range` RETURN) + its algorithms
    ## (`len`/`first`/`reduce`/`sort`/…). Referenced by BARE names from `alloc::vec`, so the 3-seg
    ## scan misses it; part of the linkable base closure. No same-name overloads (co-compiles
    ## cleanly); its generic fns emit only when instantiated (an unused `reduce` stays dormant).
    else if bi == 4 { kn := rt::push_str(nb, "slice") }
    ## `cmp`/`num` — `min`/`max`/`clamp` + the library `lt`/`eq`/arithmetic operators. Their operators
    ## are same-name-per-type OVERLOADS (all `cmp__lt`/`num__+` etc.), but the lean lower uses BUILT-IN
    ## operators so none is reached → DEAD-CODE ELIMINATION drops every unused overload before emission
    ## (no duplicate-label collision); `min`/`max`/`clamp` are generic (emit per instantiated type).
    else if bi == 5 { kn := rt::push_str(nb, "cmp") }
    else if bi == 6 { kn := rt::push_str(nb, "num") }
    ## `derive` — the comptime-derive `eq`/`lt`/`hash` (generic over any T, §5.4). Formerly excluded
    ## (its per-type overloads collided on one label); the per-signature overload mangling now emits
    ## distinct labels, and its generic derives emit only when instantiated (DCE), so it co-compiles
    ## cleanly. Needed by `alloc::hashmap` (`hash(key)`/`eq`) and any comptime-derived container.
    else if bi == 7 { kn := rt::push_str(nb, "derive") }
    ## `u128` (Types §7 wider-than-native integer; TYP-10) — the generalized `uint(N)`
    ## recipe (`uint := fn(comptime N : u64) -> type { struct { words : [u64; N/64] } }`, the
    ## `u128 ≡ uint(128)` alias, and the full `@inline` generic-operator set); injected when a
    ## program references `u128` by bare name or instantiates a bare `uint(`.
    else { kn := rt::push_str(nb, "u128") }
    ke := rt::push_str(nb, ".al")
    bpath := str_at(nb.data, nb.len)
    ## Skip a base module already injected explicitly via a `base::<mod>::` reference (the `base`
    ## root, rl==4) — it is already in `result`/`seen`; re-adding it here would DUPLICATE the module.
    mut skip_base := false
    if bi == 1 and has_result_decl { skip_base = true }
    if bi == 2 and has_option_decl { skip_base = true }
    if skip_base == false and path_exists(a, bpath) and line_in_set(seen, bpath) == false {
      kp := rt::push_str(pre, bpath)
      kpn := rt::push_byte(pre, 10)
    }
    bi += 1
  }
  kr := rt::push_str(pre, str_at(result.data, result.len))
  str_at(pre.data, pre.len)
}

## TOOL-6 1c-γ opt-in: is `ALATYR_OSPLIT=1` set? When true, the build hands the compiler a span buffer
## and `link_exe_split` assembles the per-module `.o` split; otherwise (the DEFAULT) the whole build takes
## the proven single-`.s` path (span recording off, one `as`+`ld`), so the fixpoint + every ordinary build
## are byte-for-byte the pre-split behaviour. The split path currently trips a self-host-lower codegen
## fault under some allocation layouts (a transient buffer bleeds into a live StrBuf header → "rt: StrBuf
## overflow"); it stays behind this flag until that root cause is fixed. Scans NUL-separated
## /proc/self/environ with the same byte-index loop `lower::ra_env_init` uses (NO early return inside the
## loop — that mis-lowers to a layout-dependent stack corruption in the lean lower); returns via a flag.
## This probe allocates both the path C-string and the full environment buffer on `a`. The caller owns
## that arena and immediately uses its advanced offset for the optional span buffer and compilation;
## `in` would pass a three-word copy and discard those bumps on return. `in out` is therefore required
## by Functions §2.1–§2.3/§4.1: the probe mutates the caller's place, while its boolean result remains
## only the flag decision. This fixes ownership propagation; it does NOT enable or repair split codegen.
osplit_on := fn(in out a : rt::Arena) -> bool {
  ## read the FULL environ. A large (nix) environ is ~25 KB; the old single 8 KB read MISSED
  ## `ALATYR_OSPLIT=1` whenever it landed past byte 8191 (e.g. run under `env`/gdb/setarch, which
  ## enlarge/reorder environ) → the flag went undetected → the split silently fell back to a single-`.s`
  ## build. `read_proc` loops until EOF and a 256 KB cap covers any realistic environ. (This was NOT the
  ## split codegen fault — it was this env-read truncation; a correct fallback, but the flag was ignored.)
  env := read_proc(a, cstr(a, "/proc/self/environ"), 2097152)
  mut found := false
  mut i := 0
  while i < env.len and (not found) {
    ## match `ALATYR_OSPLIT=1` (A L A T Y R _ O S P L I T = 1 → 15 bytes).
    if i + 15 <= env.len and bytes(env)[i] == 65 and bytes(env)[i + 1] == 76 and bytes(env)[i + 2] == 65 and bytes(env)[i + 3] == 84 and bytes(env)[i + 4] == 89 and bytes(env)[i + 5] == 82 and bytes(env)[i + 6] == 95 and bytes(env)[i + 7] == 79 and bytes(env)[i + 8] == 83 and bytes(env)[i + 9] == 80 and bytes(env)[i + 10] == 76 and bytes(env)[i + 11] == 73 and bytes(env)[i + 12] == 84 and bytes(env)[i + 13] == 61 and bytes(env)[i + 14] == 49 {
      found = true
    }
    if not found {
      while i < env.len and bytes(env)[i] != 0 { i = i + 1 }
      i = i + 1
    }
  }
  found
}

## The process's CURRENT WORKING DIRECTORY, read from the kernel symlink `/proc/self/cwd` (there is
## no `getcwd` in the lean `rt` syscall set, and `/proc/self/exe` is read the same way by `lib_dir`).
## Returns "." when the link cannot be read — the diagnostic then still names a real (relative) place.
cwd_dir := fn(in out a : rt::Arena) -> str {
  cc := cstr(a, "/proc/self/cwd")
  mut buf := rt::strbuf(a, 8192)
  r := rt::sys_readlink(89, cc, buf.data, 8000)
  if r <= 0 { return "." }
  return str_at(buf.data, unchecked bitcast(usize, r))
}

## TOOL-14 discovery: search package.al from the current directory upward to the filesystem root. The
## returned path is the actual manifest path, so all later package-root-relative readers use the same
## root regardless of the shell directory from which the command was launched.
discover_manifest := fn(in out a : rt::Arena) -> str {
  mut dir := cwd_dir(a)
  mut done := false
  mut found := ""
  while done == false {
    mut cb := rt::strbuf(a, dir.len + 24)
    rt::push_str(cb, dir)
    if dir != "/" { rt::push_byte(cb, 47) }
    rt::push_str(cb, "package.al")
    candidate := str_at(cb.data, cb.len)
    if path_exists(a, candidate) {
      found = candidate
      done = true
    } else {
      parent := parent_dir(dir)
      if parent == dir {
        done = true
      } else {
        dir = parent
      }
    }
  }
  found
}

## A package-aware command was given NO input at all: TOOL-14 requires a Config diagnostic after the
## upward discovery walk finds no package.al. This must not fall through to an empty file list, which
## would emit a lone `_start` wrapper calling a main nothing defines and surface as an ld error about a
## symbol the user never wrote.
no_input_diag := fn(in out a : rt::Arena, what : str) -> usize {
  cw := cwd_dir(a)
  mut b := rt::strbuf(a, 8192)
  k0 := rt::push_str(b, "alatyr: ")
  k1 := rt::push_str(b, what)
  k2 := rt::push_str(b, ": config: no discoverable package.al and no file list (searched upward from ")
  k3 := rt::push_str(b, cw)
  k4 := rt::push_str(b, ")\n")
  kf := diag_flush(b, 2)
  if kf != 0 { return kf }
  return 40
}

## TOOL-14's other invocation-level Config diagnostic. A manifest and a bare file list answer different
## questions about the package root, so accepting both would make source_dir, dependencies and the
## artifact name depend on argument order. Keep the message at the CLI boundary; there is no manifest
## span to locate for a conflict between two invocation forms.
cli_config_diag := fn(in out a : rt::Arena, msg : str) -> usize {
  mut b := rt::strbuf(a, msg.len + 64)
  k0 := rt::push_str(b, "alatyr: config: ")
  k1 := rt::push_str(b, msg)
  k2 := rt::push_byte(b, 10)
  kf := diag_flush(b, 2)
  if kf != 0 { return kf }
  return 40
}

## The input facts collected while scanning package-command options. They stay scalar/string facts at
## the run_cli boundary, avoiding a temporary record whose copyback would be fragile in the self-host
## lower. The manifest path is published as pointer/length facts into the command-line arena.
mut CLI_MANIFEST_COUNT := 0
mut CLI_MANIFEST_P := 0
mut CLI_MANIFEST_N := 0
mut CLI_INPUT_COUNT := 0
mut CLI_INPUT_FIRST := 0
mut CLI_TARGET_DIR_COUNT := 0
mut CLI_TARGET_DIR_P := 0
mut CLI_TARGET_DIR_N := 0
mut CLI_TARGET_SELECT_COUNT := 0
mut CLI_TARGET_SELECT_P := 0
mut CLI_TARGET_SELECT_N := 0
mut CLI_VENDOR_DIR_COUNT := 0
mut CLI_OPTION_BAD := false

## Scan the source/options portion of a package-aware command. Profiles may be in the leading selector
## position (run_cli already advances over those), but skipping them here too keeps `--manifest` valid
## after a profile. Runtime argv after `run --` is excluded by the caller's `path_n` bound.
scan_cli_inputs := fn(cmd : str, fi : usize, n : usize) {
  CLI_MANIFEST_COUNT = 0
  CLI_MANIFEST_P = 0
  CLI_MANIFEST_N = 0
  CLI_INPUT_COUNT = 0
  CLI_INPUT_FIRST = n
  CLI_TARGET_DIR_COUNT = 0
  CLI_TARGET_DIR_P = 0
  CLI_TARGET_DIR_N = 0
  CLI_TARGET_SELECT_COUNT = 0
  CLI_TARGET_SELECT_P = 0
  CLI_TARGET_SELECT_N = 0
  CLI_VENDOR_DIR_COUNT = 0
  CLI_OPTION_BAD = false
  mut i := fi
  while i < n {
    x := arg_at(cmd, i)
    if x == "--manifest" {
      CLI_MANIFEST_COUNT += 1
      if i + 1 < n {
        ma := arg_at(cmd, i + 1)
        CLI_MANIFEST_P = unchecked bitcast(usize, ma.ptr)
        CLI_MANIFEST_N = ma.len
        i += 2
      } else {
        CLI_OPTION_BAD = true
        i += 1
      }
    } else if x == "--target-dir" {
      CLI_TARGET_DIR_COUNT += 1
      if i + 1 < n {
        td := arg_at(cmd, i + 1)
        CLI_TARGET_DIR_P = unchecked bitcast(usize, td.ptr)
        CLI_TARGET_DIR_N = td.len
        i += 2
      } else {
        CLI_OPTION_BAD = true
        i += 1
      }
    } else if x == "--target" {
      CLI_TARGET_SELECT_COUNT += 1
      if i + 1 < n {
        ts := arg_at(cmd, i + 1)
        CLI_TARGET_SELECT_P = unchecked bitcast(usize, ts.ptr)
        CLI_TARGET_SELECT_N = ts.len
        i += 2
      } else {
        CLI_OPTION_BAD = true
        i += 1
      }
    } else if x == "--vendor-dir" {
      CLI_VENDOR_DIR_COUNT += 1
      if i + 1 < n { i += 2 } else { CLI_OPTION_BAD = true ; i += 1 }
    } else if x == "--release" {
      i += 1
    } else if x == "--profile" {
      if i + 1 < n { i += 2 } else { CLI_OPTION_BAD = true ; i += 1 }
    } else {
      if CLI_INPUT_COUNT == 0 { CLI_INPUT_FIRST = i }
      CLI_INPUT_COUNT += 1
      i += 1
    }
  }
}

## The source list for a manifest-less invocation. The first listed source is the synthesized package's
## root module, and the driver convention makes the LAST module the `_start` wrapper's `main` module,
## so the root is emitted last after any additional listed modules. Option tokens are not source files.
bare_file_paths := fn(in out a : rt::Arena, cmd : str, fi : usize, n : usize) -> str {
  mut first := n
  mut i := fi
  while i < n and first == n {
    x := arg_at(cmd, i)
    if x == "--release" { i += 1 }
    else if x == "--profile" { if i + 1 < n { i += 2 } else { i += 1 } }
    else if x == "--manifest" { if i + 1 < n { i += 2 } else { i += 1 } }
    else if x == "--target-dir" or x == "--target" { if i + 1 < n { i += 2 } else { i += 1 } }
    else { first = i }
  }
  if first == n { return "" }
  mut out := rt::strbuf(a, 1048576)
  i = fi
  while i < n {
    x := arg_at(cmd, i)
    mut skip := false
    if x == "--release" { skip = true ; i += 1 }
    else if x == "--profile" { skip = true ; if i + 1 < n { i += 2 } else { i += 1 } }
    else if x == "--manifest" { skip = true ; if i + 1 < n { i += 2 } else { i += 1 } }
    else if x == "--target-dir" or x == "--target" { skip = true ; if i + 1 < n { i += 2 } else { i += 1 } }
    else { i += 1 }
    if skip == false {
      if i - 1 != first {
        rt::push_str(out, x)
        rt::push_byte(out, 10)
      }
    }
  }
  root := arg_at(cmd, first)
  rt::push_str(out, root)
  rt::push_byte(out, 10)
  str_at(out.data, out.len)
}

## Re-read the first non-option source at the artifact boundary. Keeping this as a local span avoids
## relying on a mutable global index after the ambient prelude and dependency scans have advanced the
## caller's arena.
cli_first_input := fn(cmd : str, fi : usize, n : usize) -> str {
  mut i := fi
  while i < n {
    x := arg_at(cmd, i)
    if x == "--release" { i += 1 }
    else if x == "--profile" { if i + 1 < n { i += 2 } else { i += 1 } }
    else if x == "--manifest" { if i + 1 < n { i += 2 } else { i += 1 } }
    else if x == "--target-dir" or x == "--target" { if i + 1 < n { i += 2 } else { i += 1 } }
    else { return x }
  }
  ""
}

single_path_list := fn(in out a : rt::Arena, path : str) -> str {
  mut b := rt::strbuf(a, path.len + 8)
  rt::push_str(b, path)
  rt::push_byte(b, 10)
  str_at(b.data, b.len)
}

## The default artifact for a manifest-less `build`: the synthetic Package root is the first source
## file's directory, and the artifact base is that file's stem (TOOL-11/14). This deliberately stays
## flat `target/` until the independent TOOL-13 profile/target layout lane lands.
bare_target_artifact := fn(in out a : rt::Arena, root_file : str, profile : str) -> str {
  root_dir := dir_of(root_file)
  mut tpath := "target"
  if CLI_TARGET_DIR_COUNT == 1 {
    tpath = str_at(CLI_TARGET_DIR_P, CLI_TARGET_DIR_N)
  } else if root_dir.len == 0 {
    cw := cwd_dir(a)
    if cw == "/" { tpath = "/target" } else { tpath = cat2(a, cw, "/target") }
  } else if root_dir == "/" {
    tpath = "/target"
  } else {
    slash := cat2(a, root_dir, "/")
    tpath = cat2(a, slash, "target")
  }
  tc := cstr(a, tpath)
  md := rt::sys_mkdir(83, tc, 493)
  p0 := cat2(a, tpath, "/")
  profpath := cat2(a, p0, profile)
  pc := cstr(a, profpath)
  mp := rt::sys_mkdir(83, pc, 493)
  stem := file_stem(root_file)
  slash := cat2(a, profpath, "/")
  cat2(a, slash, stem)
}

## Append `extra` to the cmdline blob `cmd` as ONE more NUL-terminated argument field, returning the
## new blob. `/proc/self/cmdline` is "prog\0arg1\0…\0" (a trailing NUL after the last arg), so the
## result is byte-for-byte the blob the kernel would have produced had the user typed `extra` — every
## downstream `arg_at`/`arg_count` reader then sees the argument WITHOUT knowing it was synthesized.
## `rt::push_str` copies by BYTE LENGTH (never stops at a NUL), so the embedded separators survive.
append_arg := fn(in out a : rt::Arena, cmd : str, extra : str) -> str {
  mut b := rt::strbuf(a, cmd.len + extra.len + 8)
  k0 := rt::push_str(b, cmd)
  k1 := rt::push_str(b, extra)
  k2 := rt::push_byte(b, 0)
  return str_at(b.data, b.len)
}

## Did the single `write(2)` behind `rt::sb_flush` put EVERY byte the caller built onto the
## descriptor? THE one comparison for that question, shared by every surface in this file that
## flushes a buffer it built and then returns a status. `rt::sb_flush` returns the raw `write(2)`
## result — the byte count on success, a negative errno on failure — and the bitcast folds a negative
## errno into a huge `usize`, so this SINGLE comparison covers both failures at once: the write that
## FAILED (ENOSPC on a full filesystem, EBADF on a closed descriptor, EPIPE) and the write that was
## SHORT (fewer bytes accepted than offered). Nothing built means nothing can be lost, so a
## zero-length buffer is vacuously complete here; the surfaces for which an empty buffer is itself a
## bug assert that separately, in `emit_dump_status`. 70 = internal error.
flush_status := fn(nwrote : isize, want : usize) -> usize {
  if want == 0 { return 0 }
  if unchecked bitcast(usize, nwrote) != want { return 70 }
  return 0
}

## Invocation diagnostics all write a completed StrBuf to stderr and then return their Config/usage
## status. Keep the fallible flush and its result check in one helper: adding a new CLI diagnostic must
## not create another dropped `rt::sb_flush` decision (idiom gate DROPPED), and a short/failed write is
## still an internal write failure rather than a falsely successful diagnostic.
diag_flush := fn(in out b : rt::StrBuf, fd : usize) -> usize {
  d := rt::sb_flush(b, fd)
  return flush_status(d, b.len)
}

## The exit status of an EMIT-to-stdout surface (`alatyr wat|aarch64|riscv64 <file>`, and `alatyr
## <file>` — the x86 GAS dump). Each of those modes used to `return 0` unconditionally right after
## flushing, so NO failure on the path could be reported through the exit code — not a failed write,
## not a short write, and not an emitter that produced nothing at all. `flush_status` answers the
## write question; on top of it, treat a zero-length buffer as an internal failure, because every one
## of these backends emits at least a module preamble (measured: the x86 dump of an EMPTY `.al` file
## is 93 bytes), so an empty buffer means the emitter produced nothing while reporting success. 70 =
## internal error; an ill-typed program is refused earlier and separately, fail-loud from inside the
## driver's own check (exit 1), before any byte is written.
emit_dump_status := fn(nwrote : isize, want : usize) -> usize {
  if want == 0 { return 70 }
  return flush_status(nwrote, want)
}

pub run_cli := fn(in out a : rt::Arena) -> usize {
  mut cmd := read_cmdline(a)
  mut n := arg_count(cmd)
  ## modes: 0 = emit GAS to stdout; 1 = build to `<out>` (`-o`); 2 = build to a temp exe + run it;
  ## 3 = check (type-check only); 4 = new (scaffold a pkg); 5 = test (build a @test runner + run it);
  ## 6 = build (manifest-driven: artifact → `<target_dir>/<output>`, the spec `alatyr build`)
  mut mode := 0
  mut oi := 0
  mut fi := 1
  mut test_jobs := 1
  mut test_keep_going := false
  if n == 1 { return test_jobs_diag(a, "run") }
  if n >= 2 {
    a1 := arg_at(cmd, 1)
    if a1 == "run" { mode = 2; fi = 2 }
    if a1 == "check" { mode = 3; fi = 2 }
    if a1 == "new" { mode = 4; fi = 2 }
    if a1 == "test" { mode = 5; fi = 2 }
    if a1 == "build" { mode = 6; fi = 2 }
    if a1 == "wat" { mode = 7; fi = 2 }
    if a1 == "aarch64" { mode = 8; fi = 2 }
    if a1 == "riscv64" { mode = 9; fi = 2 }
    if a1 == "fmt" { mode = 10; fi = 2 }
    if a1 == "selftest-regalloc" { mode = 11; fi = 2 }
  }
  if n >= 4 {
    if arg_at(cmd, 1) == "-o" { mode = 1; oi = 2; fi = 3 }
  }
  if mode == 4 {
    ## scaffold a new package directory — takes a NAME, not a file list; no compilation.
    if n < 3 { return 40 }
    nm := arg_at(cmd, 2)
    return new_package(a, nm)
  }
  if mode == 7 {
    ## (WASM→WAT), tracer: emit a WAT module for a SINGLE `.al` file to stdout.
    ## Bind the path to a local FIRST — an inline str-returning call as a str argument drops its
    ## length in the lean lower (the path would arrive 0-len → read_file_into faults).
    if n < 3 { return 40 }
    wpath := arg_at(cmd, fi)
    ## TYPE-CHECK BEFORE EMITTING (I11 correct-or-trap). Without this the three emit-to-stdout
    ## surfaces handed the user code for a program the compiler already knows is ill-typed: the
    ## `-o` build path rejects it with a located `alatyr: check: …` and exit 1, while these three
    ## printed a whole module and exited 0. `driver::check_file_emit` runs the SAME front end +
    ## type-checker the `check` subcommand runs, over the SAME ambient module closure this emit
    ## resolves, prints the same located diagnostic to stderr, and returns its status — so the
    ## surface exits nonzero having emitted NOTHING (the emitter is not even called).
    wsbc := driver::check_file_emit(wpath, a)
    if wsbc != 0 { return wsbc }
    mut wsb := driver::compile_file_wat(wpath, a)
    ## the emitted length is read BEFORE the flush and passed to `emit_dump_status`, so the surface's
    ## exit code reflects what actually reached stdout instead of a hardcoded 0.
    wsblen := wsb.len
    d := rt::sb_flush(wsb, 1)
    return emit_dump_status(d, wsblen)
  }
  if mode == 8 {
    ## (aarch64): emit an AArch64 GAS program for a SINGLE `.al` file to stdout.
    ## Bind the path to a local first (inline str-returning call as a str arg drops its length).
    if n < 3 { return 40 }
    apath := arg_at(cmd, fi)
    ## TYPE-CHECK BEFORE EMITTING (I11 correct-or-trap). Without this the three emit-to-stdout
    ## surfaces handed the user code for a program the compiler already knows is ill-typed: the
    ## `-o` build path rejects it with a located `alatyr: check: …` and exit 1, while these three
    ## printed a whole module and exited 0. `driver::check_file_emit` runs the SAME front end +
    ## type-checker the `check` subcommand runs, over the SAME ambient module closure this emit
    ## resolves, prints the same located diagnostic to stderr, and returns its status — so the
    ## surface exits nonzero having emitted NOTHING (the emitter is not even called).
    asbc := driver::check_file_emit(apath, a)
    if asbc != 0 { return asbc }
    mut asb := driver::compile_file_aarch64(apath, a)
    ## the emitted length is read BEFORE the flush and passed to `emit_dump_status`, so the surface's
    ## exit code reflects what actually reached stdout instead of a hardcoded 0.
    asblen := asb.len
    d := rt::sb_flush(asb, 1)
    return emit_dump_status(d, asblen)
  }
  if mode == 9 {
    ## (riscv64): emit a RISC-V64 GAS program for a SINGLE `.al` file to stdout.
    if n < 3 { return 40 }
    rpath := arg_at(cmd, fi)
    ## TYPE-CHECK BEFORE EMITTING (I11 correct-or-trap). Without this the three emit-to-stdout
    ## surfaces handed the user code for a program the compiler already knows is ill-typed: the
    ## `-o` build path rejects it with a located `alatyr: check: …` and exit 1, while these three
    ## printed a whole module and exited 0. `driver::check_file_emit` runs the SAME front end +
    ## type-checker the `check` subcommand runs, over the SAME ambient module closure this emit
    ## resolves, prints the same located diagnostic to stderr, and returns its status — so the
    ## surface exits nonzero having emitted NOTHING (the emitter is not even called).
    rsbc := driver::check_file_emit(rpath, a)
    if rsbc != 0 { return rsbc }
    mut rsb := driver::compile_file_riscv64(rpath, a)
    ## the emitted length is read BEFORE the flush and passed to `emit_dump_status`, so the surface's
    ## exit code reflects what actually reached stdout instead of a hardcoded 0.
    rsblen := rsb.len
    d := rt::sb_flush(rsb, 1)
    return emit_dump_status(d, rsblen)
  }
  if mode == 10 {
    ## (`alatyr fmt`): with a path, preserve the existing filter-friendly stdout form;
    ## with no path, Tooling §4.2 formats every `.al` below the current package root in place.
    if n < 3 {
      allpaths := list_al_in_tree(a, ".")
      return fmt_package_files(a, allpaths)
    }
    fpath := arg_at(cmd, fi)
    mut fsb := driver::compile_file_fmt(fpath, a)
    ## `fmt` is THE path a user pipes or redirects, and it used to `return 0` right after flushing:
    ## `alatyr fmt <valid file> > /dev/full` reported success having written nothing. The length is
    ## read BEFORE the flush and compared with what the write accepted, so the exit code reflects what
    ## actually reached stdout. `flush_status`, not `emit_dump_status`: a formatted output of ZERO
    ## bytes is LEGITIMATE here — measured, an empty, a blank and a comment-only `.al` file all format
    ## to 0 bytes and exit 0 — so the emit surfaces' "an empty buffer is an internal failure" rule
    ## would reject a correct run. The in-place mode above writes through `rt::write_file`, which
    ## already loops to completion and already reports its own failure (41).
    fsblen := fsb.len
    d := rt::sb_flush(fsb, 1)
    return flush_status(d, fsblen)
  }
  if mode == 11 {
    ## (register allocator, COMMIT 1): run the DORMANT linear-scan allocator's self-test
    ## (6 ported unit cases over hand-built instruction streams). Not wired into emission; takes no
    ## file arguments. Exit code = the number of failing cases (0 = all passed).
    return regalloc::selftest(a)
  }
  ## FND-11 manifest limits CEILING: package-aware commands read it from the manifest and pass it to
  ## the front end. Bare file-list commands pass "" (no ceiling).
  ## Tooling §4: test-specific scheduling flags precede the package selector, then run/check/test/build
  ## all accept one leading profile selector before the manifest path. The selected profile remains part
  ## of the build input for every package-aware command.
  if mode == 5 {
    mut scanning_test_opts := true
    while scanning_test_opts and fi < n {
      ta := arg_at(cmd, fi)
      if ta == "-k" { test_keep_going = true; fi = fi + 1 }
      else if ta == "-j" {
        if fi + 1 >= n { return test_jobs_diag(a, "missing job count") }
        tv := parse_uint_arg(arg_at(cmd, fi + 1))
        if tv == 0 { return test_jobs_diag(a, "invalid -j: job count must be a positive integer") }
        test_jobs = tv
        fi = fi + 2
      }
      else if ta.len > 2 and str_at(ta.ptr, 2) == "-j" {
        tv2 := parse_uint_arg(str_at(ta.ptr + 2, ta.len - 2))
        if tv2 == 0 { return test_jobs_diag(a, "invalid -j: job count must be a positive integer") }
        test_jobs = tv2
        fi = fi + 1
      }
      else { scanning_test_opts = false }
    }
  }
  if mode == 2 or mode == 3 or mode == 5 or mode == 6 {
    if fi < n and arg_at(cmd, fi) == "--release" { fi = fi + 1 }
    else if fi < n and arg_at(cmd, fi) == "--profile" { fi = fi + 2 }
  }
  ## `run <source> -- <program-args…>`: only the run command has a program-argv tail. The separator
  ## is found before source-path normalization, so neither it nor anything after it can be mistaken
  ## for a source path. A separator with no source remains an input error rather than silently
  ## changing the established bare-run/package fallback.
  mut path_n := n
  mut run_arg_first := n
  if mode == 2 {
    mut si := fi
    mut separated := false
    while si < n and separated == false {
      if arg_at(cmd, si) == "--" {
        path_n = si
        run_arg_first = si + 1
        separated = true
      }
      si += 1
    }
  }
  ## TOOL-14 ARGUMENT NORMALIZATION — resolve exactly one of: an explicit `--manifest`, the first
  ## upward-discovered package.al, or a bare file list. A file list plus a manifest is ambiguous and an
  ## empty invocation is never allowed to fall through to code generation.
  if mode == 2 or mode == 3 or mode == 5 or mode == 6 {
    if fi > path_n { return no_input_diag(a, arg_at(cmd, 1)) }
  }
  ## TOOL-5: `alatyr test <paths...> [substring]` treats a final non-source argument as a test
  ## description filter. The filter is forwarded as raw pointer/length facts at the cli→driver
  ## boundary, avoiding aggregate-string copyback loss in the lean lower.
  mut test_filter_p := 0
  mut test_filter_n := 0
  if mode == 5 and n - fi >= 2 {
    last := arg_at(cmd, n - 1)
    if ends_with(last, ".al") == false {
      test_filter_p = unchecked bitcast(usize, last.ptr)
      test_filter_n = last.len
      path_n = n - 1
    }
  }
  mut pkg_arg := ""
  mut is_pkg := false
  mut selected_profile := "debug"
  ## `-o` has a long-standing bare file-list surface. Inspect its arguments only when the
  ## invocation can actually select a package; scanning every ordinary `-o <files>` call changes
  ## the direct-file diagnostic contract for nested corpus fixtures. Package-aware verbs always scan
  ## because an empty input invokes upward discovery and their option grammar is shared.
  mut scan_package_inputs := mode != 1
  if mode == 1 {
    mut si := fi
    while si < path_n {
      sx := arg_at(cmd, si)
      if sx == "--manifest" or sx == "--target-dir" or sx == "--target" {
        scan_package_inputs = true
        si = path_n
      } else if ends_with(sx, "package.al") {
        scan_package_inputs = true
        si = path_n
      } else {
        si += 1
      }
    }
  }
  if scan_package_inputs {
    scan_cli_inputs(cmd, fi, path_n)
    if CLI_OPTION_BAD { return cli_config_diag(a, "an option is missing its argument") }
    if CLI_VENDOR_DIR_COUNT > 0 { return cli_config_diag(a, "--vendor-dir is not supported in v1") }
    if CLI_TARGET_DIR_COUNT > 1 { return cli_config_diag(a, "--target-dir was specified more than once") }
    if CLI_MANIFEST_COUNT > 1 { return cli_config_diag(a, "--manifest was specified more than once") }
    if CLI_MANIFEST_COUNT == 1 {
      if CLI_INPUT_COUNT != 0 { return cli_config_diag(a, "a file list cannot be combined with --manifest") }
      pkg_arg = str_at(CLI_MANIFEST_P, CLI_MANIFEST_N)
      if pkg_arg.len == 0 { return cli_config_diag(a, "--manifest requires a path") }
      if path_exists(a, pkg_arg) == false { return cli_config_diag(a, "the --manifest path does not exist") }
      is_pkg = true
    } else if CLI_INPUT_COUNT == 1 {
      ## Preserve the established package shorthand `alatyr build package.al`: a lone explicitly
      ## named manifest is a package selector, while two or more `.al` paths remain a manifest-less
      ## file list and never trigger discovery.
      lone := cli_first_input(cmd, fi, path_n)
      if ends_with(lone, "package.al") and path_exists(a, lone) {
        pkg_arg = lone
        is_pkg = true
      }
    } else if CLI_INPUT_COUNT == 0 {
      pkg_arg = discover_manifest(a)
      if pkg_arg.len == 0 { return no_input_diag(a, arg_at(cmd, 1)) }
      is_pkg = true
    }
  }
  selected_profile = cli_profile(a, cmd, n, pkg_arg)
  mut lim_ceiling := ""
  if is_pkg and (mode == 2 or mode == 3 or mode == 5 or mode == 6) {
    lim_ceiling = manifest_limits(a, pkg_arg)
  }
  mut paths := build_paths(a, cmd, fi, path_n, pkg_arg)
  mut target_backend := 0
  ## Modules §8 / Tooling §2.4 — a dependency DECLARATION the resolver cannot honour (a git source, a
  ## path dependency with no `package.al`, a record naming neither a name nor an alias) is a Config
  ## failure for EVERY command. The scanner already printed the located diagnostic; abort here rather
  ## than build/check a program whose dependency graph differs from the one the manifest declares.
  if DEP_CONFIG_BAD { return 1 }
  if is_pkg {
    manifest_vendor_reject(a, pkg_arg)
    manifest_path_reject(a, pkg_arg)
    if manifest_target_selection_resolve(a, pkg_arg) != 0 { MANIFEST_CONFIG_BAD = true }
    if MANIFEST_CONFIG_BAD == false { manifest_output_reject(a, pkg_arg) }
    if MANIFEST_CONFIG_BAD == false {
      backend := manifest_target_backend(a, pkg_arg)
      if manifest_target_arch_reject(a, pkg_arg, backend) != 0 { MANIFEST_CONFIG_BAD = true }
      if MANIFEST_CONFIG_BAD == false and manifest_target_command_reject(a, pkg_arg, backend, mode) != 0 { MANIFEST_CONFIG_BAD = true }
      if MANIFEST_CONFIG_BAD == false { target_backend = backend }
    }
    if MANIFEST_CONFIG_BAD { return 1 }
  }
  ## TOOL-17 — publish the selected Target.code_size before package parsing/lowering. The default
  ## is x86_64's CodeSize.b64; an explicit unsupported spelling is a located Config error.
  if is_pkg {
    csz := manifest_target_code_size(a, pkg_arg)
    if manifest_code_size_reject(a, pkg_arg, csz) != 0 { return 1 }
    cszset := driver::set_target_code_size(csz)
  } else {
    cszset0 := driver::set_target_code_size(2)
  }
  ## Publish the package source root so the driver can derive nested module paths from arbitrary
  ## `source_dir` values (including package-local nested paths) instead of falling back to a basename.
  ## Non-package/file-list commands clear the context; this prevents a previous in-process compile
  ## from changing the module name of an unrelated direct-file invocation.
  mut module_root := ""
  if is_pkg {
    root_dir0 := dir_of(pkg_arg)
    root_dir := normalize_path(a, root_dir0)
    module_root = pkg_src_dir(a, pkg_arg, root_dir)
  } else {
    ## TOOL-14's synthesized source_dir is the first file's directory. Publish that exact lexical
    ## prefix for every bare-list command so a nested path keeps its module namespace (`sub::child`)
    ## instead of falling back to the basename-only direct-file convention.
    root_file := cli_first_input(cmd, fi, path_n)
    root_dir := dir_of(root_file)
    if root_dir.len != 0 { module_root = root_dir }
  }
  mrp := unchecked bitcast(usize, module_root.ptr)
  mrs := driver::set_module_root(mrp, module_root.len)
  ## AMBIENT STDLIB: prepend the `lib/` modules the program (transitively) references via a
  ## 3-segment `alloc::…::…` / `std::…::…` path. Lib modules go FIRST so the user's entry module
  ## (named `main`, or the last) stays the entry. Zero ambient refs (the self-host's own build) →
  ## empty → `paths` unchanged → the TOOL-1 fixpoint is unaffected.
  ## bind `lib_dir`'s result to a local before forwarding it — an inline str-returning call as a str
  ## argument drops its length in the lean lower (the `libdir` would arrive 0-len).
  ldir := lib_dir(a)
  mut entry_sym := "_start"
  ## Tooling §2.2/§4 — `check` is also the command for a `Kind.source` target: it validates configuration,
  ## parsing and semantics without requiring an artifact-producing kind. Other package commands still
  ## reject source targets through the same predicate used by `build`, while `check` rejects only kinds
  ## that are invalid configuration for the selected command. This stays AFTER dependency resolution,
  ## so the commands report a bad graph before a bad kind in the same order.
  ## `run` (2) and `test` (5) compile the package too, so they get the same predicate: a `Kind.shared_lib`
  ## or `Kind.source` target cannot produce something to run or to test, and an unrecognized `Kind.…` is a
  ## Config error whatever the verb. `build` (6) runs it at its own site below, where it also needs the
  ## resolved kind to pick the artifact shape.
  if is_pkg and (mode == 2 or mode == 3 or mode == 5) {
    ckp := pkg_arg
    ckind := manifest_target_kind(a, ckp)
    if mode == 3 and ckind == "source" { }
    else {
      ckrc := manifest_kind_reject(a, ckp, ckind)
      if ckrc != 0 { return ckrc }
    }
    ## `check` has no lower/codegen phase, but publish the same selected configuration at its
    ## command boundary before semantic validation. Its target.kind expressions remain metadata-only;
    ## source is allowed here, while unsupported kinds have already returned through the located
    ## Config diagnostic above.
    if mode == 3 { kset := driver::set_target_kind(manifest_target_kind_code(ckind)) }
  }
  if mode == 3 and not is_pkg { kset0 := driver::set_target_kind(0) }
  apaths := ambient_paths(a, paths, ldir, is_pkg)
  if apaths.len > 0 { paths = cat2(a, apaths, paths) }
  if is_pkg and (mode == 2 or mode == 3) {
    ## Package `run` and `check` select profiles by the same CLI/default rules as build/test. `run`
    ## needs the resolved facts before lowering; `check` receives the same configuration even though
    ## its current semantic-only path does not fold values. This keeps argument routing and build input
    ## uniform across all four commands (Tooling §4).
    emp := pkg_arg
    if mode == 2 { entry_sym = manifest_entry(a, emp) }
    sel := cli_profile(a, cmd, n, emp)
    mut dbg := "false"
    if sel == "debug" { dbg = "true" }
    pf := manifest_profile_flags(a, emp, sel)
    if PROFILE_CONFIG_BAD { return 1 }
    mut fb := rt::strbuf(a, pf.len + 64)
    kb1 := rt::push_str(fb, "debug=")
    kb2 := rt::push_str(fb, dbg)
    kb3 := rt::push_byte(fb, 10)
    kb4 := rt::push_str(fb, "profile=")
    kb5 := rt::push_str(fb, sel)
    kb6 := rt::push_byte(fb, 10)
    kb7 := rt::push_str(fb, pf)
    fbs := str_at(fb.data, fb.len)
    fbp := unchecked bitcast(usize, fbs.ptr)
    ksb := driver::set_build_flags(fbp, fbs.len)
	    if mode == 3 { return driver::check_files(paths, a, lim_ceiling) }
	  }
	  if mode == 3 {
    ## type-check only: lex + parse + sema over the file list; no GAS emitted, no as/ld.
    return driver::check_files(paths, a, lim_ceiling)
  }
  if mode == 5 {
    ## Package tests inherit the selected build profile exactly like `build`: `--release` and
    ## `--profile NAME` are parsed above, then the manifest's profile flags are folded before the
    ## runner is emitted. Bare file-list tests have no manifest and therefore retain empty flags.
    if is_pkg {
      emp := pkg_arg
      sel := cli_profile(a, cmd, n, emp)
      mut dbg := "false"
      if sel == "debug" { dbg = "true" }
	      pf := manifest_profile_flags(a, emp, sel)
	      if PROFILE_CONFIG_BAD { return 1 }
      mut fb := rt::strbuf(a, pf.len + 64)
      kb1 := rt::push_str(fb, "debug=")
      kb2 := rt::push_str(fb, dbg)
      kb3 := rt::push_byte(fb, 10)
      kb4 := rt::push_str(fb, "profile=")
      kb5 := rt::push_str(fb, sel)
      kb6 := rt::push_byte(fb, 10)
      kb7 := rt::push_str(fb, pf)
      fbs := str_at(fb.data, fb.len)
      fbp := unchecked bitcast(usize, fbs.ptr)
      ksb := driver::set_build_flags(fbp, fbs.len)
    }
    ## TOOL-7 — the test artifact supplies the RUNNER's entry, so the PACKAGE's own entry (the manifest
    ## `Target.entry`, default `_start`; a program may also declare the symbol itself) is NOT linked into
    ## it. Publish that entry — the SAME notion `build`/`run` link the executable with (`ld -e <entry>`) —
    ## so the driver can exclude the declaration that emits it. A bare file-list `test` has no manifest and
    ## therefore the default entry. Forwarded as scalar (ptr, len) facts like the filter, and the manifest
    ## path is bound to a local first (the lean lower drops a str arg forwarded from an inline call).
    mut test_entry := "_start"
    if is_pkg {
      tep := pkg_arg
      test_entry = manifest_entry(a, tep)
    }
    kte := driver::set_test_entry(unchecked bitcast(usize, test_entry.ptr), test_entry.len)
    ## test: build a runner that calls every @test fn, then run it; its exit code = failure count.
    kst := driver::set_test_filter(test_filter_p, test_filter_n)
    mut cross_filter_p := test_filter_p
    mut cross_filter_n := test_filter_n
    kcf0 := driver::set_cross_test_filter(cross_filter_p, cross_filter_n)
    kto := driver::set_test_options(test_jobs, test_keep_going)
    mut cross_test := false
    mut tsb := driver::compile_files_test_with_options(paths, a, test_keep_going, lim_ceiling)
    if target_backend != 0 {
      ## The x86 front end remains the canonical type/limits check. Cross-target backends are
      ## emitters, not a second semantic implementation; reject before assembling anything.
      crc := driver::check_files(paths, a, lim_ceiling)
      if crc != 0 { return crc }
      tsb = driver::compile_files_cross_test(paths, a, target_backend, test_keep_going, lim_ceiling)
      cross_test = true
    }
    tgas := str_at(unchecked bitcast(usize, tsb.data), tsb.len)
    mut has_tests := test_gas_has_desc(tgas)
    if cross_test { has_tests = cross_test_gas_has_desc(tgas) }
    mut test_out := ""
    mut keep_test_artifact := false
    if is_pkg {
      tep := pkg_arg
      test_out = manifest_target_artifact(a, tep, ".test", selected_profile)
      keep_test_artifact = true
    }
    mut rc := 0
    if cross_test {
      rc = build_and_run_cross(a, test_out, keep_test_artifact, tsb.data, tsb.len, target_backend)
    } else {
      rc = build_and_run(a, test_out, keep_test_artifact, tsb.data, tsb.len, paths, "_start", 0, "", 0, 0)
    }
    if rc == 0 and has_tests == false {
      test_zero_diag()
      return 0
    }
    return rc
  }
  ## the ELF entry symbol comes from the manifest's `Target.entry` for a manifest build
  ## (default `_start`), else `_start`. Bind the manifest path to a local first (the lean lower drops a
  ## str arg forwarded from an inline str-returning call).
  mut artifact_kind := "executable"
  if mode == 6 {
    if is_pkg { artifact_kind = manifest_target_kind(a, pkg_arg) }
    ## the same predicate `check` runs (Tooling §2.2/§5): one function, so the two commands cannot
    ## drift into disagreeing about which manifests are buildable.
    if is_pkg { krc := manifest_kind_reject(a, pkg_arg, artifact_kind) ; if krc != 0 { return krc } }
    ## Publish the actual manifest/default artifact kind before the front end reaches lowering.
    ## This is the same resolved value that selects the executable versus object/archive emitter.
    kset := driver::set_target_kind(manifest_target_kind_code(artifact_kind))
    ## Tooling §2.6/§4 — publish the SELECTED profile's `build.<name>` comptime facts to the lower.
    ## The profile is `--release` / `--profile <name>` / the manifest `default_profile` / `debug`.
    ## `build.debug` = (selected == "debug"); `build.profile` = the profile name; each declared
    ## profile flag resolves to its per-profile override (from `profiles.<sel>.flags`) or its declared
    ## default. A blob line per flag (`name=value`), with `debug=` and `profile=` prepended. `src/`'s
    ## own `package.al` declares no `profile_flags` → the custom part is empty and nothing reads a
    ## `build.*` fact → fixpoint-neutral.
    mut emp := pkg_arg
    mut sel := "debug"
    if is_pkg { sel = cli_profile(a, cmd, n, emp) }
    mut dbg := "false"
    if sel == "debug" { dbg = "true" }
    mut pf := ""
    if is_pkg { pf = manifest_profile_flags(a, emp, sel) }
    if PROFILE_CONFIG_BAD { return 1 }
    mut fb := rt::strbuf(a, pf.len + 64)
    kb1 := rt::push_str(fb, "debug=")
    kb2 := rt::push_str(fb, dbg)
    kb3 := rt::push_byte(fb, 10)
    kb4 := rt::push_str(fb, "profile=")
    kb5 := rt::push_str(fb, sel)
    kb6 := rt::push_byte(fb, 10)
    kb7 := rt::push_str(fb, pf)
    fbs := str_at(fb.data, fb.len)
    fbp := unchecked bitcast(usize, fbs.ptr)
    ksb := driver::set_build_flags(fbp, fbs.len)
  }
  ## TOOL-6 1c-γ: for any non-dump (build/run) mode, hand the compiler a span buffer so it records the
  ## per-module GAS spans (and peepholes per-span, rewriting the table to post-peephole offsets). The
  ## build link then splits the single `.s` into per-module `.o`. Mode 0 (GAS dump to stdout) passes 0 →
  ## the whole-buffer peephole, byte-identical output (the fixpoint dump path is untouched). Buffer sized
  ## for word0 + N×(start,len): 262144 B / 16 = 16384 spans >> the module count.
  mut spb := 0
  if mode != 0 and osplit_on(a) { spb = rt::bump(a, 262144) }
  mut sb := driver::compile_files_target(paths, a, entry_sym, lim_ceiling, spb, artifact_kind == "object" or artifact_kind == "static_lib")
  if mode == 6 {
    ## Re-resolve manifest entry after compile to avoid transient corruption of `entry_sym`
    ## in pathological self-host compiles.
    if is_pkg { entry_sym = manifest_entry(a, pkg_arg) }
  }
  if mode == 0 {
    ## The x86 GAS dump to stdout, and the one flush that is on the FIXPOINT path:
    ## `scripts/fixpoint.sh` captures this stdout into `target/gas_seed.s`, `gas1.s` and `gas2.s` and
    ## then compares line counts and bytes. It used to `return 0` right after flushing, so a
    ## TRUNCATED dump exited 0 and the gate compared two files, one of them short, reporting whatever
    ## that comparison happened to say — a gate reading a lie. Same shape as `wat`/`aarch64`/
    ## `riscv64`: read the length BEFORE the flush and ask `emit_dump_status` whether the write took
    ## it all. `emit_dump_status`, so the zero-length assertion applies too — the x86 dump of even an
    ## EMPTY `.al` file is 93 bytes, so an empty buffer here means the emitter produced nothing.
    ## Every exit code this mode can already reach is preserved: 0 on a complete dump, 1 for a check
    ## reject / an unopenable source / a parse abort / a bad dependency graph. 70 is new and reachable
    ## only through a failed or short write.
    sblen := sb.len
    d := rt::sb_flush(sb, 1)
    return emit_dump_status(d, sblen)
  }
  if mode == 2 {
    mut run_out := ""
    mut keep_run_artifact := false
    if is_pkg {
      rep := pkg_arg
      run_out = manifest_target_artifact(a, rep, "", selected_profile)
      keep_run_artifact = true
    }
    return build_and_run(a, run_out, keep_run_artifact, sb.data, sb.len, paths, entry_sym, spb, cmd, run_arg_first, n)
  }
  if mode == 6 {
    ## manifest-driven build: artifact at `<pkgdir>/<target_dir>/<output>` (the dir is created;
    ## an already-existing dir is fine — sys_mkdir's EEXIST is ignored). `alatyr build <pkg>`.
    mut mpath := pkg_arg
    mut outp := ""
    if is_pkg { outp = manifest_target_artifact(a, mpath, "", selected_profile) }
    else {
      root_file := cli_first_input(cmd, fi, path_n)
      if root_file.len == 0 { return cli_config_diag(a, "the bare file list is empty") }
      outp = bare_target_artifact(a, root_file, selected_profile)
    }
    ## MOD-9 foreign-library linking: the manifest's `libs` (names + any-dynamic) + `linker_flags`.
    ## Empty for the compiler's own `package.al` → `link_exe` takes its plain raw-`ld` path (neutral).
    mut libnames := ""
    mut anyd := false
    mut lflags := ""
    if is_pkg {
      libnames = manifest_lib_names(a, mpath)
      anyd = manifest_any_dynamic(a, mpath)
      lflags = manifest_linker_flags(a, mpath)
    }
    if artifact_kind == "object" or artifact_kind == "static_lib" {
      return emit_library_artifact(a, artifact_kind, outp, sb.data, sb.len, libnames, anyd, lflags)
    }
    return link_exe_split(a, outp, paths, sb.data, sb.len, spb, entry_sym, libnames, anyd, lflags)
  }
  out := arg_at(cmd, oi)
  return link_exe_split(a, out, paths, sb.data, sb.len, spb, "_start", "", false, "")
}
