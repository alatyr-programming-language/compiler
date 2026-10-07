## selfhost::ir::golden — the builder's golden builds, run by `alatyr ir --self-test`
## (`docs/ir-slice-1.md` §5.2).
##
## Each golden is a small source program and the exact report `alatyr ir` prints for it: every function
## the builder built, as verified IR, and every refusal with its reason. The program goes through the
## real verb's pipeline (`driver::compile_file_ir`: the twins' front half, sema recording types over the
## tree it hands the builder, the builder, the verifier), so a golden that passes says the whole path
## means what its text says. A change to the builder or the printer changes these strings in the same
## commit, on purpose.
##
## The programs live here, not under `test/`, so the corpus manifest gains no row for them (slice 1b is
## inert). Each one is written to a private directory under `/tmp`, built, compared and removed; the
## directory's path is stripped from the report before the comparison, so a location reads
## `<golden>.al:<line>:<col>`.

## One golden: its module name (the file stem), its source, and the report it must print.
Golden := struct { name : str, src : str, want : str }

golden_count := fn() -> usize { 9 }
golden_at := fn(i : usize) -> Golden {
  if i == 0 { return Golden(name = "ig_arith", src = g_arith_src(), want = g_arith_want()) }
  if i == 1 { return Golden(name = "ig_logic", src = g_logic_src(), want = g_logic_want()) }
  if i == 2 { return Golden(name = "ig_flow", src = g_flow_src(), want = g_flow_want()) }
  if i == 3 { return Golden(name = "ig_shift", src = g_shift_src(), want = g_shift_want()) }
  if i == 4 { return Golden(name = "ig_call", src = g_call_src(), want = g_call_want()) }
  if i == 5 { return Golden(name = "ig_litfold", src = g_litfold_src(), want = g_litfold_want()) }
  if i == 6 { return Golden(name = "ig_sys", src = g_sys_src(), want = g_sys_want()) }
  if i == 7 { return Golden(name = "ig_agg", src = g_agg_src(), want = g_agg_want()) }
  Golden(name = "ig_notyet", src = g_notyet_src(), want = g_notyet_want())
}

## Checked arithmetic and its traps, narrow widths, `unchecked`, width conversions.
g_arith_src := fn() -> str {
  "## checked signed `/` and `%`: the zero and MIN / -1 guards, then the op\ndiv := fn(a : i64, b : i64) -> i64 { a / b + a % b }\n## narrow unsigned: computed at 64 bits, narrowed back by a checked `fit`\nadd8 := fn(x : u8, y : u8) -> u8 { x + y }\n## inside `unchecked`: wrapping arithmetic narrowed by `ext`, the hardware divide\nwrap := fn(x : i32, y : i32) -> i32 { unchecked (x * y - x / y) }\n## conversions: a checked narrowing `fit`, a widening `ext`\nconv := fn(x : u64) -> u16 { u16(x) }\nwiden := fn(x : u8) -> u64 { u64(x) + 1 }\n"
}
g_arith_want := fn() -> str {
  "fn ig_arith::div Built\nfn div(%0 : i64 s, %1 : i64 s) -> i64 s {\n  %2 = cmp.== i64 %1, 0\n  trap_if %2 div_zero  @118\n  %3 = cmp.== i64 %0, -9223372036854775808\n  %4 = cmp.== i64 %1, -1\n  if %3 {\n    %5 = mov bool %4\n  } else {\n    %6 = const bool 0\n    %5 = mov bool %6\n  }\n  trap_if %5 div_overflow  @118\n  %7 = div.chk.s i64 %0, %1 div_zero  @118\n  %8 = cmp.== i64 %1, 0\n  trap_if %8 div_zero  @126\n  %9 = cmp.== i64 %0, -9223372036854775808\n  %10 = cmp.== i64 %1, -1\n  if %9 {\n    %11 = mov bool %10\n  } else {\n    %12 = const bool 0\n    %11 = mov bool %12\n  }\n  trap_if %11 div_overflow  @126\n  %13 = rem.chk.s i64 %0, %1 div_zero  @126\n  %14 = add.chk.s i64 %7, %13 overflow  @118\n  ret %14\n}\nfn ig_arith::add8 Built\nfn add8(%0 : i8 u, %1 : i8 u) -> i8 u {\n  %2 = ext.u i64 <- i8 %0\n  %3 = ext.u i64 <- i8 %1\n  %4 = add.chk.u i64 %2, %3 overflow  @243\n  %5 = fit.u i8 <- i64 %4 overflow  @243\n  ret %5\n}\nfn ig_arith::wrap Built\nfn wrap(%0 : i32 s, %1 : i32 s) -> i32 s {\n  unchecked {\n    %2 = ext.s i64 <- i32 %0\n    %3 = ext.s i64 <- i32 %1\n    %4 = mul.wrap.s i64 %2, %3\n    %5 = ext.s i32 <- i64 %4\n    %6 = ext.s i64 <- i32 %0\n    %7 = ext.s i64 <- i32 %1\n    %8 = div.hw.s i64 %6, %7\n    %9 = ext.s i32 <- i64 %8\n    %10 = ext.s i64 <- i32 %5\n    %11 = ext.s i64 <- i32 %9\n    %12 = sub.wrap.s i64 %10, %11\n    %13 = ext.s i32 <- i64 %12\n  }\n  ret %13\n}\nfn ig_arith::conv Built\nfn conv(%0 : i64 u) -> i16 u {\n  %1 = fit.u i16 <- i64 %0 narrow  @488\n  ret %1\n}\nfn ig_arith::widen Built\nfn widen(%0 : i8 u) -> i64 u {\n  %1 = ext.u i64 <- i8 %0\n  %2 = const.u i64 1\n  %3 = add.chk.u i64 %1, %2 overflow  @526\n  ret %3\n}\nir: functions=5 built=5 notyet=0 sema_gaps=0 verify_failed=0\n"
}

## Comparison signedness, short-circuit logic, bitwise operators at their width.
g_logic_src := fn() -> str {
  "lt_u := fn(a : u64, b : u64) -> bool { a < b }\nlt_s := fn(a : i64, b : i64) -> bool { a < b }\n## `and` is a region: the division runs only when `a > 0`\nguard := fn(a : u64, b : u64) -> bool { a > 0 and b / a > 2 }\neither := fn(x : bool, y : bool) -> bool { x or not y }\nbits := fn(x : u8, y : u8) -> u8 { (x & y) | (x ^ 15) }\n"
}
g_logic_want := fn() -> str {
  "fn ig_logic::lt_u Built\nfn lt_u(%0 : i64 u, %1 : i64 u) -> bool {\n  %2 = cmp.<.u i64 %0, %1\n  ret %2\n}\nfn ig_logic::lt_s Built\nfn lt_s(%0 : i64 s, %1 : i64 s) -> bool {\n  %2 = cmp.<.s i64 %0, %1\n  ret %2\n}\nfn ig_logic::guard Built\nfn guard(%0 : i64 u, %1 : i64 u) -> bool {\n  %3 = const.u i64 0\n  %4 = cmp.>.u i64 %0, %3\n  if %4 {\n    %5 = cmp.== i64 %0, 0\n    trap_if %5 div_zero  @210\n    %6 = div.chk.u i64 %1, %0 div_zero  @210\n    %7 = const.u i64 2\n    %8 = cmp.>.u i64 %6, %7\n    %2 = mov bool %8\n  } else {\n    %9 = const bool 0\n    %2 = mov bool %9\n  }\n  ret %2\n}\nfn ig_logic::either Built\nfn either(%0 : bool, %1 : bool) -> bool {\n  if %0 {\n    %3 = const bool 1\n    %2 = mov bool %3\n  } else {\n    if %1 {\n      %5 = const bool 0\n      %4 = mov bool %5\n    } else {\n      %6 = const bool 1\n      %4 = mov bool %6\n    }\n    %2 = mov bool %4\n  }\n  ret %2\n}\nfn ig_logic::bits Built\nfn bits(%0 : i8 u, %1 : i8 u) -> i8 u {\n  %2 = and i8 %0, %1\n  %3 = const.u i8 15\n  %4 = xor i8 %0, %3\n  %5 = or i8 %2, %4\n  ret %5\n}\nir: functions=5 built=5 notyet=0 sema_gaps=0 verify_failed=0\n"
}

## Structured control flow: value `if`, `while` with `continue`, range `for` with `break`, a value
## `loop`, and a labelled `break` out of a nested loop.
g_flow_src := fn() -> str {
  "pick := fn(c : bool, x : i64) -> i64 { if c { x } else { 0 - x } }\ncount := fn(n : u64) -> u64 {\n  mut s : u64 = 0\n  mut i : u64 = 0\n  while i < n {\n    i = i + 1\n    if i == 3 { continue }\n    s = s + i\n  }\n  s\n}\nsum := fn(n : i64) -> i64 {\n  mut s : i64 = 0\n  for i in 0..n {\n    if i == 5 { break }\n    s = s + i\n  }\n  s\n}\n## a statement `loop` left by `break`, then a value `loop`\nroot := fn(n : u64) -> u64 {\n  mut i : u64 = 0\n  loop {\n    if i * i > n { break }\n    i = i + 1\n  }\n  r := loop { break i }\n  r\n}\n## a labelled `break` out of the inner loop leaves both\nfind := fn(n : i64) -> i64 {\n  mut hit : i64 = 0\n  @label(o) for i in 0..n {\n    for j in 0..n {\n      if i * j == 12 { hit = i; break o }\n    }\n  }\n  hit\n}\n"
}
g_flow_want := fn() -> str {
  "fn ig_flow::pick Built\nfn pick(%0 : bool, %1 : i64 s) -> i64 s {\n  if %0 {\n    %2 = mov i64 %1\n  } else {\n    %3 = const.s i64 0\n    %4 = sub.chk.s i64 %3, %1 overflow  @64\n    %2 = mov i64 %4\n  }\n  ret %2\n}\nfn ig_flow::count Built\nfn count(%0 : i64 u) -> i64 u {\n  %1 = const.u i64 0\n  %2 = mov i64 %1\n  %3 = const.u i64 0\n  %4 = mov i64 %3\n  block L0 {\n    loop L1 {\n      %5 = cmp.<.u i64 %4, %0\n      if %5 {\n      } else {\n        br L0\n      }\n      %6 = const.u i64 1\n      %7 = add.chk.u i64 %4, %6 overflow  @164\n      %4 = mov i64 %7\n      %8 = const.u i64 3\n      %9 = cmp.== i64 %4, %8\n      if %9 {\n        br L1\n      } else {\n      }\n      %10 = add.chk.u i64 %2, %4 overflow  @205\n      %2 = mov i64 %10\n      br L1\n    }\n  }\n  ret %2\n}\nfn ig_flow::sum Built\nfn sum(%0 : i64 s) -> i64 s {\n  %1 = const.s i64 0\n  %2 = mov i64 %1\n  %3 = const.s i64 0\n  %4 = mov i64 %3\n  %5 = mov i64 %0\n  block L0 {\n    loop L1 {\n      %6 = cmp.>=.s i64 %4, %5\n      br_if %6 L0\n      block L2 {\n        %7 = const.s i64 5\n        %8 = cmp.== i64 %4, %7\n        if %8 {\n          br L0\n        } else {\n        }\n        %9 = add.chk.s i64 %2, %4 overflow  @317\n        %2 = mov i64 %9\n      }\n      %10 = add.wrap.s i64 %4, 1  !proven\n      %4 = mov i64 %10\n      br L1\n    }\n  }\n  ret %2\n}\nfn ig_flow::root Built\nfn root(%0 : i64 u) -> i64 u {\n  %1 = const.u i64 0\n  %2 = mov i64 %1\n  block L0 {\n    loop L1 {\n      %3 = mul.chk.u i64 %2, %2 overflow  @455\n      %4 = cmp.>.u i64 %3, %0\n      if %4 {\n        br L0\n      } else {\n      }\n      %5 = const.u i64 1\n      %6 = add.chk.u i64 %2, %5 overflow  @483\n      %2 = mov i64 %6\n      br L1\n    }\n  }\n  block L2 {\n    loop L3 {\n      %7 = mov i64 %2\n      br L2\n    }\n  }\n  %8 = mov i64 %7\n  ret %8\n}\nfn ig_flow::find Built\nfn find(%0 : i64 s) -> i64 s {\n  %1 = const.s i64 0\n  %2 = mov i64 %1\n  %3 = const.s i64 0\n  %4 = mov i64 %3\n  %5 = mov i64 %0\n  block L0 {\n    loop L1 {\n      %6 = cmp.>=.s i64 %4, %5\n      br_if %6 L0\n      block L2 {\n        %7 = const.s i64 0\n        %8 = mov i64 %7\n        %9 = mov i64 %0\n        block L3 {\n          loop L4 {\n            %10 = cmp.>=.s i64 %8, %9\n            br_if %10 L3\n            block L5 {\n              %11 = mul.chk.s i64 %4, %8 overflow  @685\n              %12 = const.s i64 12\n              %13 = cmp.== i64 %11, %12\n              if %13 {\n                %2 = mov i64 %4\n                br L0\n              } else {\n              }\n            }\n            %14 = add.wrap.s i64 %8, 1  !proven\n            %8 = mov i64 %14\n            br L4\n          }\n        }\n      }\n      %15 = add.wrap.s i64 %4, 1  !proven\n      %4 = mov i64 %15\n      br L1\n    }\n  }\n  ret %2\n}\nir: functions=5 built=5 notyet=0 sema_gaps=0 verify_failed=0\n"
}

## The shift and rotate operation-functions, at 64 bits and narrow.
g_shift_src := fn() -> str {
  "sh := fn(x : u64, n : usize) -> u64 { shl(x, n) }\n## `shr` on a signed value is the arithmetic shift\nhalf := fn(x : i64) -> i64 { shr(x, 1) }\n## a narrow shift: guarded by the TYPE's width, shifted at 64 bits, wrapped back\nlow := fn(x : u8, n : usize) -> u8 { shl(x, n) }\nraw := fn(x : u8, n : usize) -> u8 { unchecked { shl(x, n) } }\nrot := fn(x : u8) -> u8 { rotl(x, 3) }\nrot64 := fn(x : u64, n : usize) -> u64 { rotr(x, n) }\n"
}
g_shift_want := fn() -> str {
  "fn ig_shift::sh Built\nfn sh(%0 : i64 u, %1 : i64 u) -> i64 u {\n  %2 = shl.chk.u i64 %0, %1 shift_range  @46\n  ret %2\n}\nfn ig_shift::half Built\nfn half(%0 : i64 s) -> i64 s {\n  %1 = const.u i64 1\n  %2 = shr.chk.s i64 %0, %1 shift_range  @138\n  ret %2\n}\nfn ig_shift::low Built\nfn low(%0 : i8 u, %1 : i64 u) -> i8 u {\n  %2 = ext.u i64 <- i8 %0\n  %3 = cmp.>=.u i64 %1, 8\n  trap_if %3 shift_range  @268\n  %4 = shl.wrap.u i64 %2, %1  !proven\n  %5 = ext.u i8 <- i64 %4\n  ret %5\n}\nfn ig_shift::raw Built\nfn raw(%0 : i8 u, %1 : i64 u) -> i8 u {\n  unchecked {\n    %2 = ext.u i64 <- i8 %0\n    %3 = shl.hw.u i64 %2, %1\n    %4 = ext.u i8 <- i64 %3\n    ret %4\n  }\n}\nfn ig_shift::rot Built\nfn rot(%0 : i8 u) -> i8 u {\n  %1 = const.u i64 3\n  %2 = ext.u i64 <- i8 %0\n  %3 = and i64 %2, 255\n  %4 = and i64 %1, 7\n  %5 = const.u i64 8\n  %6 = sub.wrap.u i64 %5, %4  !proven\n  %7 = shl.wrap.u i64 %3, %4  !proven\n  %8 = shr.wrap.u i64 %3, %6  !proven\n  %9 = or i64 %7, %8\n  %10 = ext.u i8 <- i64 %9\n  ret %10\n}\nfn ig_shift::rot64 Built\nfn rot64(%0 : i64 u, %1 : i64 u) -> i64 u {\n  %2 = rotr i64 %0, %1\n  ret %2\n}\nir: functions=6 built=6 notyet=0 sema_gaps=0 verify_failed=0\n"
}

## Direct calls between scalar functions, a module constant, an immutable global.
g_call_src := fn() -> str {
  "K : u64 = 7\nG : u64 = K * 6\ntwice := fn(x : u64) -> u64 { x * 2 }\nbump := fn(x : u8) -> u64 { twice(x) + K }\nglobal := fn() -> u64 { G }\nnothing := fn(x : u64) { y := twice(x) }\n"
}
g_call_want := fn() -> str {
  "fn ig_call::twice Built\nfn twice(%0 : i64 u) -> i64 u {\n  %1 = const.u i64 2\n  %2 = mul.chk.u i64 %0, %1 overflow  @65\n  ret %2\n}\nfn ig_call::bump Built\nfn bump(%0 : i8 u) -> i64 u {\n  %1 = ext.u i64 <- i8 %0\n  %2 = call @twice(%1)\n  %3 = const.u i64 7\n  %4 = add.chk.u i64 %2, %3 overflow  @101\n  ret %4\n}\nfn ig_call::global Built\nfn global() -> i64 u {\n  %0 = addr @G\n  %1 = load.u i64 [%0 + 0]\n  ret %1\n}\nfn ig_call::nothing Built\nfn nothing(%0 : i64 u) {\n  %1 = call @twice(%0)\n  %2 = mov i64 %1\n  ret\n}\nir: functions=4 built=4 notyet=0 sema_gaps=0 verify_failed=0\n"
}

## Literal-only arithmetic is a comptime number (Types §2.3): folded exactly, then given the type its
## context gave the expression — never built literal by literal at that type (`128` is not an `i8`).
g_litfold_src := fn() -> str {
  "## a literal-only `+ - *` is a comptime number: folded exactly, then typed by its context\nlow := fn() -> i8 { 0 - 128 }\nspan := fn() -> u64 { 3 * 7 + 21 }\n## inside `unchecked` it wraps at the context type\nwrapped := fn() -> u8 { unchecked (0 - 1) }\n"
}
g_litfold_want := fn() -> str {
  "fn ig_litfold::low Built\nfn low() -> i8 s {\n  %0 = const.s i8 -128\n  ret %0\n}\nfn ig_litfold::span Built\nfn span() -> i64 u {\n  %0 = const.u i64 42\n  ret %0\n}\nfn ig_litfold::wrapped Built\nfn wrapped() -> i8 u {\n  unchecked {\n    %0 = const.u i8 255\n  }\n  ret %0\n}\nir: functions=3 built=3 notyet=0 sema_gaps=0 verify_failed=0\n"
}

## Slice 2a (`docs/ir-slice-2.md`): a bodyless `@abi(syscall)` declaration is a trampoline of one
## `syscall` op, and a pointer is a one-word scalar that crosses a call.
g_sys_src := fn() -> str {
  "sys_write := @abi(syscall) fn(num : usize, fd : usize, buf : ptr(u8), len : usize) -> isize\nnone := fn(p : ptr(u8)) -> isize { unchecked sys_write(1, 1, p, 0) }\nsame := fn(p : ptr(u8), q : ptr(u8)) -> bool { p == q }\n"
}
g_sys_want := fn() -> str {
  "fn ig_sys::sys_write Built\nfn sys_write(%0 : i64 u, %1 : i64 u, %2 : ptr, %3 : i64 u) -> i64 s {\n  %4 = syscall %0(%1, %2, %3)\n  ret %4\n}\nfn ig_sys::none Built\nfn none(%0 : ptr) -> i64 s {\n  unchecked {\n    %1 = const.u i64 1\n    %2 = const.u i64 1\n    %3 = const.u i64 0\n    %4 = call @sys_write(%1, %2, %0, %3)\n  }\n  ret %4\n}\nfn ig_sys::same Built\nfn same(%0 : ptr, %1 : ptr) -> bool {\n  %2 = cmp.== ptr %0, %1\n  ret %2\n}\nir: functions=3 built=3 notyet=0 sema_gaps=0 verify_failed=0\n"
}

## Slice 3a (`docs/ir-slice-3.md`): a struct local is a frame object; fields are loads and stores at
## their byte offsets, a whole-struct assignment is a `copy`, `size`/`align` are constants.
g_agg_src := fn() -> str {
  "P := struct { a : i64, b : u8 }\n## a literal into a fresh frame object (zeroed first: `b` leaves padding), a field write, a copy\nmk := fn(x : i64) -> i64 {\n  mut p := P(a = x, b = 7)\n  p.b = 9\n  q := p\n  q.a / 3 + i64(q.b)\n}\n## `size`/`align` of a struct and of a scalar are constants\nsz := fn() -> u64 { size(P) + align(u16) }\n## outside 3a: a struct with a layout attribute (slice 3e)\nR := @packed struct { a : u8, b : u64 }\npk := fn() -> u64 { r := R(a = 1, b = 2); r.b }\n"
}
g_agg_want := fn() -> str {
  "fn ig_agg::mk Built\nfn mk(%0 : i64 s) -> i64 s {\n  $0 : frame 16 align 8\n  $1 : frame 16 align 8\n  zero $0, 16\n  store i64 [$0 + 0], %0\n  %1 = const.u i8 7\n  store i8 [$0 + 8], %1\n  %2 = const.u i8 9\n  store i8 [$0 + 8], %2\n  copy $1, $0, 16\n  %3 = load.s i64 [$1 + 0]\n  %4 = const.s i64 3\n  %5 = cmp.== i64 %4, 0\n  trap_if %5 div_zero  @8389\n  %6 = cmp.== i64 %3, -9223372036854775808\n  %7 = cmp.== i64 %4, -1\n  if %6 {\n    %8 = mov bool %7\n  } else {\n    %9 = const bool 0\n    %8 = mov bool %9\n  }\n  trap_if %8 div_overflow  @8389\n  %10 = div.chk.s i64 %3, %4 div_zero  @8389\n  %11 = load.u i8 [$1 + 8]\n  %12 = ext.u i64 <- i8 %11\n  %13 = fit.u i64 <- i64 %12 narrow  @8399\n  %14 = add.chk.s i64 %10, %13 overflow  @8389\n  ret %14\n}\nfn ig_agg::sz Built\nfn sz() -> i64 u {\n  %0 = const.u i64 16\n  %1 = const.u i64 2\n  %2 = add.chk.u i64 %0, %1 overflow  @8490\n  ret %2\n}\nfn ig_agg::pk NotYet(stmt Assign, ig_agg.al:13:21)\nir: functions=3 built=2 notyet=1 sema_gaps=0 verify_failed=0\n"
}

## Refusals: constructs outside the subset, and sema gaps (D6).
g_notyet_src := fn() -> str {
  "S := struct { a : u64 }\n## outside the subset: an aggregate parameter (a struct local builds since slice 3a)\ntake := fn(s : S) -> u64 { s.a }\npair := fn(x : u64) -> u64 {\n  t := S(a = x)\n  t.a\n}\n## a sema gap, counted and never defaulted (D6): a default argument is filled after sema ran\n## (a value `loop`'s body is recorded since docs/ir.md §3.8.8, so `first` builds)\ndflt := fn(x : u64 = 5) -> u64 { x }\nfill := fn() -> u64 { dflt() }\nfirst := fn(n : u64) -> u64 {\n  mut i : u64 = 0\n  r := loop {\n    if i * i > n { break i }\n    i = i + 1\n  }\n  r\n}\n"
}
g_notyet_want := fn() -> str {
  "fn ig_notyet::take NotYet(signature (a parameter or result that is not a kernel scalar), ig_notyet.al:3:1)\nfn ig_notyet::pair Built\nfn pair(%0 : i64 u) -> i64 u {\n  $0 : frame 8 align 8\n  store i64 [$0 + 0], %0\n  %1 = load.u i64 [$0 + 0]\n  ret %1\n}\nfn ig_notyet::dflt Built\nfn dflt(%0 : i64 u) -> i64 u {\n  ret %0\n}\nfn ig_notyet::fill NotYet(sema-gap absent: expr Num, ig_notyet.al:10:22)\nfn ig_notyet::first Built\nfn first(%0 : i64 u) -> i64 u {\n  %1 = const.u i64 0\n  %2 = mov i64 %1\n  block L0 {\n    loop L1 {\n      %4 = mul.chk.u i64 %2, %2 overflow  @8696\n      %5 = cmp.>.u i64 %4, %0\n      if %5 {\n        %3 = mov i64 %2\n        br L0\n      } else {\n      }\n      %6 = const.u i64 1\n      %7 = add.chk.u i64 %2, %6 overflow  @8726\n      %2 = mov i64 %7\n      br L1\n    }\n  }\n  %8 = mov i64 %3\n  ret %8\n}\nir: functions=5 built=3 notyet=2 sema_gaps=1 verify_failed=0\n"
}

## ── the runner ──

gl_unlink := @abi(syscall) fn(num : usize, path : usize) -> isize
gl_rmdir := @abi(syscall) fn(num : usize, path : usize) -> isize

## Every buffer below is sized 16 bytes past its content: `rt::sb_byte` stores a whole word per byte.
## A NUL-terminated copy of `s`, for a syscall's path argument.
gl_cstr := fn(in out a : rt::Arena, s : str) -> usize {
  mut b := rt::strbuf(a, s.len + 16)
  k := rt::push_str(b, s)
  z := rt::push_byte(b, 0)
  ## unchecked-ok: a syscall takes the path as an address; the buffer is the NUL-terminated copy just built.
  unchecked bitcast(usize, b.data)
}
## `s` with every occurrence of `drop` removed.
gl_strip := fn(in out a : rt::Arena, s : str, drop : str) -> str {
  mut b := rt::strbuf(a, s.len + 16)
  mut i : usize = 0
  while i < s.len {
    if drop.len != 0 and i + drop.len <= s.len and str_at(s.ptr + i, drop.len) == drop {
      i = i + drop.len
    } else {
      k := rt::push_str(b, str_at(s.ptr + i, 1))
      i = i + 1
    }
  }
  str_at(b.data, b.len)
}

## Build every golden through the `ir` verb's pipeline and compare its report. Each result is one
## `ok`/`FAIL` line in `sb`; a failure prints the report it got. Answers the number of failures and
## counts each golden in `ran`.
pub golden_run := fn(in out sb : rt::StrBuf, in out a : rt::Arena, in out ran : usize) -> usize {
  mut fails : usize = 0
  pid := rt::sys_getpid(39)
  mut db := rt::strbuf(a, 64)
  kd := rt::push_str(db, "/tmp/alatyr-ir-golden.")
  kp := rt::push_int(db, i64(pid))
  dir := str_at(db.data, db.len)
  dc := gl_cstr(a, dir)
  mk := rt::sys_mkdir(83, dc, 448)
  if mk < 0 {
    put(sb, "FAIL golden: cannot create ")
    put(sb, dir)
    put(sb, "\n")
    ran = ran + 1
    return 1
  }
  mut pre := rt::strbuf(a, dir.len + 16)
  kq := rt::push_str(pre, dir)
  kr := rt::push_str(pre, "/")
  prefix := str_at(pre.data, pre.len)
  mut i : usize = 0
  while i < golden_count() {
    g : Golden = golden_at(i)
    mut pb := rt::strbuf(a, prefix.len + g.name.len + 16)
    k1 := rt::push_str(pb, prefix)
    k2 := rt::push_str(pb, g.name)
    k3 := rt::push_str(pb, ".al")
    path := str_at(pb.data, pb.len)
    pc := gl_cstr(a, path)
    ## unchecked-ok: `write_file` takes the source bytes by address; `g.src` is a whole str.
    wr := rt::write_file(pc, unchecked bitcast(usize, g.src.ptr), g.src.len)
    mut got : str = ""
    if wr >= 0 {
      out := driver::compile_file_ir(path, a)
      raw := str_at(out.data, out.len)
      got = gl_strip(a, raw, prefix)
    }
    ul := gl_unlink(87, pc)
    good := wr >= 0 and got == g.want
    if good { put(sb, "ok   golden ") } else { put(sb, "FAIL golden ") }
    put(sb, g.name)
    put(sb, ": the built IR and every refusal equal the golden report\n")
    if not good {
      fails = fails + 1
      put(sb, "---- got ----\n")
      put(sb, got)
      put(sb, "---- end ----\n")
    }
    ran = ran + 1
    i = i + 1
  }
  rd := gl_rmdir(84, dc)
  fails
}
