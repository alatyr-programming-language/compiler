/* Issue #168 reference: C reads both fields returned by the exported Alatyr function. */
struct Pair { unsigned char a; unsigned char b; };
extern struct Pair al_echo_u8_pair(struct Pair p);

long drive(void) {
  struct Pair p = { 7, 5 };
  struct Pair q = al_echo_u8_pair(p);
  return (long)q.a * 4L + (long)q.b * 8L;
}
