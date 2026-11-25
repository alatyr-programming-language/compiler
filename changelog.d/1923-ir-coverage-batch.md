- The shared IR now builds pointer subtraction (`p - n`), str-local reassignment, `panic` as
  noreturn, `str_at` by integer address, `str.ptr` field reads, pointer-to-pointer bitcasts,
  and pointer arithmetic through struct field pointees (#1923; Memory §4.5). The compiler's own
  `src/` builds 576 more functions through the IR (3050 to 3626 of 5458, 66.4%). MINOR.
