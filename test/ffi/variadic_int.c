/* Pure C-variadic stub for the FFI harness (no libc — va_start/va_arg/va_end are compiler builtins).
   SysV: the fixed `n` in %rdi, the `n` trailing longs in %rsi/%rdx/%rcx (integer arg registers); %al
   holds the count of XMM registers used (0 here). Sums the n following long varargs. */
#include <stdarg.h>
long sumv(long n, ...) {
  va_list ap;
  va_start(ap, n);
  long s = 0;
  for (long i = 0; i < n; i++) s += va_arg(ap, long);
  va_end(ap);
  return s;
}
