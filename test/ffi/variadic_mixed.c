/* Pure C-variadic stub for the FFI harness (no libc). MIXED int/double varargs: after the fixed `n`,
   reads a long, a double, a long, a double. SysV counts integer and SSE argument registers
   INDEPENDENTLY (the two longs ride %rsi/%rdx, the two doubles %xmm0/%xmm1) and %al carries the XMM
   count (2). Distinct weights (1,2,3,4) make any misordering / int<->SSE swap change the result. */
#include <stdarg.h>
long mixv(long n, ...) {
  va_list ap;
  va_start(ap, n);
  long a = va_arg(ap, long);
  double x = va_arg(ap, double);
  long b = va_arg(ap, long);
  double y = va_arg(ap, double);
  va_end(ap);
  return a * 1 + (long)(x * 2) + b * 3 + (long)(y * 4);
}
