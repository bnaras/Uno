/* Configure-time probe: can a C translation unit in THIS build use glibc's
 * fopencookie()?  Compiled (not linked) by inst/build_highs.sh; the exit status
 * selects the stdout-redirection strategy in highs/io/r_io.h.
 *
 * Why a probe rather than a platform #ifdef: glibc's feature guard on
 * fopencookie is VERSION-dependent, and no preprocessor test distinguishes the
 * two cases.
 *
 *   glibc <= 2.36 (Debian 12, Ubuntu 22.04, RHEL 9):
 *       stdio.h:  #ifdef __USE_GNU   -> hidden unless _GNU_SOURCE is defined
 *   glibc >= 2.39 (Ubuntu 24.04, Debian 13, Fedora 40+):
 *       stdio.h:  #ifdef __USE_MISC  -> visible by default
 *
 * and __USE_MISC is on by default in BOTH, so testing it would wrongly report
 * success on the older glibc.
 *
 * Two details make this probe faithful rather than optimistic:
 *
 *   1. It references the TYPE cookie_io_functions_t as well as calling the
 *      function.  They are hidden together but fail separately: HiGHS's C flags
 *      carry -Wno-implicit-function-declaration, so a call-only probe would
 *      compile while the type was still invisible -- exactly the state that let
 *      this ship.  Build with -Werror=implicit-function-declaration.
 *
 *   2. <stdio.h> is included FIRST, matching how the failing translation units
 *      actually reach r_io.h (cupdlp_utils.h:8 includes <stdio.h> eleven lines
 *      before cupdlp_defs.h -> HConfig.h -> r_io.h).  A probe that defined
 *      _GNU_SOURCE before <stdio.h> would report a capability the real build
 *      cannot use.
 */
#include <stdio.h>
#include <string.h>
#include <sys/types.h> /* ssize_t */

static ssize_t probe_write(void *cookie, const char *buf, size_t n) {
  (void) cookie;
  (void) buf;
  return (ssize_t) n;
}

int main(void) {
  cookie_io_functions_t io;
  FILE *f;
  memset(&io, 0, sizeof(io));
  io.write = &probe_write;
  f = fopencookie(NULL, "w", io);
  return f == NULL;
}
