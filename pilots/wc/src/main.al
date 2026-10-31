## wc — print the newline, word and byte counts of each FILE (#1125).
##
## Usage: wc [-l] [-w] [-c] [FILE]...
##
## With no FILE, or when FILE is `-`, reads standard input. `-l`, `-w` and `-c` select lines, words
## and bytes; with none of them all three are printed, in that order. Each output line is the
## selected counts separated by spaces, then the file name (none for standard input). With more
## than one FILE a `total` line follows.
##
## Exit status: 0 when every file was counted; 1 when some file could not be opened or read (the
## others are still counted, and the reason goes to standard error); 2 on a usage error.

Counter := count::Counter

## Which counts to print.
Select := struct {
  lines : bool,
  words : bool,
  bytes : bool,
}

## The size of one read.
CHUNK : usize = 4096

main := fn() -> u64 {
  match std::os::arena(1048576) {
    Ok(osa) => {
      mut ar := std::os::region(ptr(osa))
      rc := run(ptr(mut ar))
      std::os::free(osa)
      rc
    }
    Err(_) => {
      n := std::io::eprint("wc: cannot allocate memory\n")
      1
    }
  }
}

run := fn(a : ptr(mut Arena)) -> u64 {
  argv := std::os::args(a)
  mut sel := Select(lines = false, words = false, bytes = false)
  mut names : usize = 0
  ## blocked-by: #1211 — `argv` is a `Slice(str)` bound from a call, and a `for` over it (or over
  ## `argv[1..argv.len]`) yields wrong `str`s, so both walks over the arguments index the slice.
  mut i : usize = 1
  while i < argv.len {
    arg := argv[i]
    i += 1
    if arg == "-l" {
      sel.lines = true
    } else if arg == "-w" {
      sel.words = true
    } else if arg == "-c" {
      sel.bytes = true
    } else if arg.len > 1 and bytes(arg)[0] == 0x2D {
      e1 := std::io::eprint("wc: unknown option ")
      e2 := std::io::eprint(arg)
      e3 := std::io::eprint("\nusage: wc [-l] [-w] [-c] [FILE]...\n")
      return 2
    } else {
      names += 1
    }
  }
  if sel.lines == false and sel.words == false and sel.bytes == false {
    sel = Select(lines = true, words = true, bytes = true)
  }
  if names == 0 {
    return report_one(a, sel, "-", "")
  }
  mut rc : u64 = 0
  mut total := count::counter()
  i = 1
  while i < argv.len {
    arg := argv[i]
    i += 1
    if arg == "-l" or arg == "-w" or arg == "-c" { continue }
    mut k := count::counter()
    match count_path(arg, k) {
      Ok(_) => {
        show(a, sel, k, arg)
        total.lines += k.lines
        total.words += k.words
        total.bytes += k.bytes
      }
      Err(e) => {
        complain(arg, e)
        rc = 1
      }
    }
  }
  if names > 1 { show(a, sel, total, "total") }
  rc
}

## Count one input and print its line; 0 on success, 1 (after a message) on failure.
report_one := fn(a : ptr(mut Arena), sel : Select, path : str, label : str) -> u64 {
  mut k := count::counter()
  match count_path(path, k) {
    Ok(_) => {
      show(a, sel, k, label)
      0
    }
    Err(e) => {
      complain(path, e)
      1
    }
  }
}

## Why an input could not be counted.
## blocked-by: #876 — `Result(u64, std::io::IoError)` is refused as a result type, so the I/O
## error is mapped to this local enum where it arises.
Failure := enum {
  NotFound,
  Denied,
  Unreadable,
}

failure := fn(e : std::io::IoError) -> Failure {
  match e {
    std::io::IoError.NotFound => {
      Failure.NotFound
    }
    std::io::IoError.PermissionDenied => {
      Failure.Denied
    }
    std::io::IoError.AlreadyExists | std::io::IoError.InvalidInput | std::io::IoError.UnexpectedEof
      | std::io::IoError.Interrupted | std::io::IoError.WouldBlock | std::io::IoError.BrokenPipe
      | std::io::IoError.TimedOut | std::io::IoError.ConnectionRefused => {
      Failure.Unreadable
    }
    ## blocked-by: #1176 — `| std::io::IoError.Other(_)` in the arm above is refused as a binding.
    std::io::IoError.Other(_) => {
      Failure.Unreadable
    }
  }
}

## Count the file at `path` (`-` is standard input) into `k`.
count_path := fn(path : str, in out k : Counter) -> Result(u64, Failure) {
  if path == "-" {
    return count_fd(0, k)
  }
  match std::io::open(path, std::io::O_RDONLY) {
    Ok(f) => {
      r := count_fd(usize(f.fd), k)
      closed := std::io::file_close(f)
      r
    }
    Err(e) => {
      Result(u64, Failure).Err(failure(e))
    }
  }
}

## Read `fd` to its end, feeding every chunk to `k`; the byte count on success.
count_fd := fn(fd : usize, in out k : Counter) -> Result(u64, Failure) {
  mut buf : [u8; 4096] = [0; 4096]
  mut more := true
  while more {
    match std::io::read(fd, ptr(mut buf[0]), CHUNK) {
      Ok(n) => {
        if n == 0 {
          more = false
        } else {
          count::feed(k, buf[0..n])
        }
      }
      Err(e) => {
        return Result(u64, Failure).Err(failure(e))
      }
    }
  }
  Result(u64, Failure).Ok(k.bytes)
}

## Print the selected counts of `k`, then `label` when it is not empty.
show := fn(a : ptr(mut Arena), sel : Select, k : Counter, label : str) {
  mut out := alloc::string::new(a)
  mut first := true
  if sel.lines {
    field(out, k.lines, first)
    first = false
  }
  if sel.words {
    field(out, k.words, first)
    first = false
  }
  if sel.bytes {
    field(out, k.bytes, first)
    first = false
  }
  if label.len > 0 {
    r1 := alloc::string::push_str(out, " ")
    r2 := alloc::string::push_str(out, label)
  }
  r3 := alloc::string::push_str(out, "\n")
  n := std::io::print(alloc::string::as_str(ptr(out)))
}

## Append `n` to `out`, after a space unless it is the first field.
field := fn(in out out : alloc::string::String, n : u64, first : bool) {
  if first == false { r := alloc::string::push_str(out, " ") }
  r2 := alloc::fmt::display(u64, n, out)
}

## Report on standard error why `path` could not be counted.
complain := fn(path : str, f : Failure) {
  e1 := std::io::eprint("wc: ")
  e2 := std::io::eprint(path)
  e3 := std::io::eprint(reason(f))
}

reason := fn(f : Failure) -> str {
  match f {
    Failure.NotFound => {
      ": No such file or directory\n"
    }
    Failure.Denied => {
      ": Permission denied\n"
    }
    Failure.Unreadable => {
      ": read error\n"
    }
  }
}
