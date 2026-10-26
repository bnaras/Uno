/*
 * dmumps_shim.h -- what the R binding needs from src/dmumps_shim.c: the
 * load-time binding of Uno's MUMPS calls to the 'rmumps' package, and the
 * per-solve interrupt / message state. See dmumps_shim.c for the design.
 */
#ifndef UNO_DMUMPS_SHIM_H
#define UNO_DMUMPS_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

/* How this build reaches MUMPS (the value uno_dmumps_shim_load() returns). */
#define UNO_DMUMPS_SHIM_NONE   0  /* built with R_UNO_NO_MUMPS: no MUMPS at all   */
#define UNO_DMUMPS_SHIM_LEGACY 1  /* rmumps <= 5.2.1-43: legacy "dmumps_c" name   */
#define UNO_DMUMPS_SHIM_API    2  /* rmumps >= 5.2.1-44: <rmumps/rmumps_api.h>    */

/* Resolve rmumps' entry points. Called from .onLoad (through cpp11::safe), so
 * an rmumps that lacks the entry points this build was compiled for is a clean
 * R error at load time. Never call it from inside Uno's C++ frames: it may
 * longjmp. Returns one of the UNO_DMUMPS_SHIM_* values. */
int uno_dmumps_shim_load(void);

/* The DMUMPS_STRUC_C layout number this build was compiled against (1 = MUMPS
 * 5.2.1, 2 = MUMPS 5.9.1; 0 without MUMPS). */
int uno_dmumps_shim_abi(void);

/* The MUMPS version string reached at run time, or NULL without MUMPS. */
const char* uno_dmumps_shim_mumps_version(void);

/* Per-solve state, reset at the start of every uno_solve(): whether rmumps'
 * safe entry point reported a user interrupt during a MUMPS call, and the last
 * message it returned ("" if none). take_interrupt() clears the flag. */
void uno_dmumps_shim_reset(void);
int uno_dmumps_shim_take_interrupt(void);
const char* uno_dmumps_shim_last_message(void);

#ifdef __cplusplus
}
#endif

#endif /* UNO_DMUMPS_SHIM_H */
