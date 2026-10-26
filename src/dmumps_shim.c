/*
 * dmumps_shim.c -- bind Uno's MUMPS calls to the MUMPS library inside the
 * 'rmumps' package.
 *
 * Uno's MUMPSSolver.cpp calls dmumps_c() (the MUMPS C API entry point). The
 * bundled Uno is built with -DMUMPS_VIA_R=ON, which compiles MUMPSSolver.cpp
 * against rmumps' MUMPS headers and links NO MUMPS library: dmumps_c stays
 * undefined in libuno.a and this translation unit defines it, forwarding to
 * the C-callables rmumps registers (R_RegisterCCallable), which resolve on
 * every platform including Windows (a DLL exports only what it declares, so
 * the old R_FindSymbol route failed there).
 *
 * Two generations of rmumps are supported; ./configure picks one by looking at
 * the installed headers and defines the matching macro:
 *
 *   UNO_RMUMPS_API  -- rmumps >= 5.2.1-44 installs <rmumps/rmumps_api.h>. The
 *     entry points are named after the DMUMPS_STRUC_C layout they were built
 *     for (RMUMPS_DMUMPS_ABI: 1 = MUMPS 5.2.1, 2 = MUMPS 5.9.1), so this build
 *     can only bind to an rmumps that serves the layout it was compiled
 *     against; a mismatch is R's clean "function ... not provided by package
 *     'rmumps'" error at load time instead of memory corruption. The "safe"
 *     entry point never longjmps: an R error or user interrupt raised while
 *     MUMPS runs comes back as a return code plus a message, and the MUMPS
 *     instance is poisoned (INFO(1) = -99999), which Uno sees as a failed
 *     factorization and turns into an error status. uno_solve() then reports
 *     the interrupt as USER_INTERRUPTION and the message as a warning.
 *
 *   (neither macro) -- rmumps <= 5.2.1-43: the legacy "dmumps_c" callable and
 *     the MUMPS 5.2.1 layout of the top-level dmumps_c.h. rmumps >= 5.9.1-1
 *     keeps serving this name through a generated adapter, so a Uno binary
 *     built this way keeps working after an rmumps upgrade.
 *
 *   UNO_R_NO_MUMPS  -- built with R_UNO_NO_MUMPS=1: no MUMPS, HiGHS presets only.
 *
 * Binding happens in .onLoad (uno_dmumps_shim_load) and never lazily inside a
 * MUMPS call, because R_GetCCallable raises an R error (longjmp) when the name
 * is missing and dmumps_c() is reached from deep inside Uno's C++ optimize().
 */

#include <string.h>
#include <R.h>
#include <R_ext/Rdynload.h>
#include "dmumps_shim.h"

#if defined(UNO_R_NO_MUMPS)

int uno_dmumps_shim_load(void) { return UNO_DMUMPS_SHIM_NONE; }
int uno_dmumps_shim_abi(void) { return 0; }
const char* uno_dmumps_shim_mumps_version(void) { return NULL; }
void uno_dmumps_shim_reset(void) {}
int uno_dmumps_shim_take_interrupt(void) { return 0; }
const char* uno_dmumps_shim_last_message(void) { return ""; }

#elif defined(UNO_RMUMPS_API)

#include <rmumps/rmumps_api.h>   /* LinkingTo: rmumps; brings dmumps_c.h of the same layout */

static rmumps_api api;
static int loaded = 0;
static int interrupted = 0;
static char last_message[256];

int uno_dmumps_shim_load(void) {
    if (!loaded) {
        rmumps_api_load(&api);   /* R error if rmumps lacks the ABI-named entry points */
        loaded = 1;
    }
    uno_dmumps_shim_reset();
    return UNO_DMUMPS_SHIM_API;
}
int uno_dmumps_shim_abi(void) { return RMUMPS_DMUMPS_ABI; }
const char* uno_dmumps_shim_mumps_version(void) {
    return loaded ? api.mumps_version() : NULL;
}
void uno_dmumps_shim_reset(void) {
    interrupted = 0;
    last_message[0] = '\0';
}
int uno_dmumps_shim_take_interrupt(void) {
    int flag = interrupted;
    interrupted = 0;
    return flag;
}
const char* uno_dmumps_shim_last_message(void) { return last_message; }

void MUMPS_CALL dmumps_c(DMUMPS_STRUC_C *id) {
    char msg[256];
    int rc;
    if (!loaded) {
        /* .onLoad binds before any solve; if we get here anyway, fail the
         * instance the way rmumps does instead of longjmp-ing out of Uno. */
        id->info[0] = RMUMPS_INFO_POISONED;
        id->info[1] = RMUMPS_ERR_POISONED;
        strncpy(last_message, "rmumps entry points were not resolved at load time",
                sizeof last_message - 1);
        last_message[sizeof last_message - 1] = '\0';
        return;
    }
    rc = RMUMPS_DMUMPS_C(&api, id, msg, sizeof msg);
    if (rc != RMUMPS_OK) {
        if (rc == RMUMPS_ERR_INTERRUPT) interrupted = 1;
        strncpy(last_message, msg, sizeof last_message - 1);
        last_message[sizeof last_message - 1] = '\0';
    }
}

#else  /* legacy rmumps <= 5.2.1-43 */

#include <dmumps_c.h>   /* LinkingTo: rmumps -- DMUMPS_STRUC_C (MUMPS 5.2.1), MUMPS_CALL */

typedef void (*dmumps_c_fn)(DMUMPS_STRUC_C *);
static dmumps_c_fn p_dmumps_c = NULL;

int uno_dmumps_shim_load(void) {
    if (p_dmumps_c == NULL) {
        /* R error if rmumps is not loaded or is older than 5.2.1-43 */
        p_dmumps_c = (dmumps_c_fn) R_GetCCallable("rmumps", "dmumps_c");
    }
    return UNO_DMUMPS_SHIM_LEGACY;
}
int uno_dmumps_shim_abi(void) { return 1; }
const char* uno_dmumps_shim_mumps_version(void) { return MUMPS_VERSION; }
void uno_dmumps_shim_reset(void) {}
int uno_dmumps_shim_take_interrupt(void) { return 0; }
const char* uno_dmumps_shim_last_message(void) { return ""; }

void MUMPS_CALL dmumps_c(DMUMPS_STRUC_C *dmumps_par) {
    if (p_dmumps_c == NULL) {
        p_dmumps_c = (dmumps_c_fn) R_GetCCallable("rmumps", "dmumps_c");
    }
    p_dmumps_c(dmumps_par);
}

#endif
