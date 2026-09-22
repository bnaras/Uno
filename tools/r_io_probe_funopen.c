/* Configure-time probe: can a C translation unit in THIS build use the
 * BSD/macOS funopen()?  Compiled (not linked) by inst/build_highs.sh; the exit
 * status selects the stdout-redirection strategy in highs/io/r_io.h.
 *
 * Tried before the fopencookie probe because a platform offering both should
 * use funopen, matching r_io.h's existing preference order.
 *
 * The write callback signature is the BSD one -- int (*)(void *, const char *,
 * int) -- not the glibc cookie signature; passing the wrong one is a hard error
 * here, which is the point: this must fail on glibc rather than half-succeed.
 */
#include <stdio.h>

static int probe_write(void *cookie, const char *buf, int n) {
  (void) cookie;
  (void) buf;
  return n;
}

int main(void) {
  FILE *f = funopen(NULL, NULL, &probe_write, NULL, NULL);
  return f == NULL;
}
