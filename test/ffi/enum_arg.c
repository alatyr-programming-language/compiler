/* Pure-arithmetic C stub (no libc). An Alatyr enum is a {disc, payload} pair passed by value in two
   INTEGER registers (disc=%rdi word 0, payload=%rsi word 1). useenum returns payload - disc, so a
   swapped eightbyte yields a wrong exit. E.B(43) => 43 - 1 = 42. */
struct E { long tag; long val; };
long useenum(struct E e) { return e.val - e.tag; }
