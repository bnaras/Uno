/*
 * dmumps_shim.c -- resolve MUMPS' dmumps_c from the 'rmumps' package at runtime.
 *
 * Uno's MUMPSSolver.cpp calls dmumps_c() (the MUMPS C API entry point). When
 * Uno is built with -DMUMPS_VIA_R=ON that symbol is intentionally left
 * UNDEFINED in libuno.a -- we link no MUMPS library, because a full sequential
 * MUMPS 5.2.1 (plus PORD/METIS/libseq) already lives inside the 'rmumps'
 * package's shared object.
 *
 * This translation unit DEFINES dmumps_c with the matching C linkage and
 * signature, so the final package .so link resolves MUMPSSolver's call to this
 * forwarder. The forwarder fetches rmumps' own dmumps_c and calls through it.
 *
 * Resolution uses R_GetCCallable("rmumps", "dmumps_c"), NOT R_FindSymbol: as of
 * rmumps >= 5.2.1-43, rmumps' R_init registers dmumps_c with
 * R_RegisterCCallable (see rmumps' src/init.c). The C-callable registry works on
 * EVERY platform, including Windows. The earlier R_FindSymbol("dmumps_c",
 * "rmumps") route relied on the dynamic symbol table and only worked on
 * Linux/macOS (where a shared object exports all non-static symbols by default);
 * on Windows a DLL exports only symbols it explicitly declares, so dmumps_c was
 * invisible there and the lookup returned NULL. Switching to the C-callable the
 * provider registers is the portable fix. See the skill
 * `link-r-package-native-code` for the rationale ("shim in YOUR package, never
 * fork the provider").
 *
 * The MUMPS C API header (dmumps_c.h, which defines DMUMPS_STRUC_C and the
 * MUMPS_CALL macro) is supplied by `LinkingTo: rmumps`. 'rmumps' must be loaded
 * (Imports: rmumps) before any Uno solve that uses the MUMPS linear solver, so
 * its DLL -- and the registered C-callable -- are available.
 *
 * Fragility note (R-exts): a DMUMPS_STRUC_C layout mismatch is silent memory
 * corruption, not a clean error. We compile against rmumps' OWN dmumps_c.h and
 * pin Depends: rmumps (>= 5.2.1-41), so the struct layout matches by
 * construction.
 */

#include <R.h>
#include <R_ext/Rdynload.h>
#include <dmumps_c.h>   /* from LinkingTo: rmumps -- DMUMPS_STRUC_C, MUMPS_CALL */

typedef void (*dmumps_c_fn)(DMUMPS_STRUC_C *);

void MUMPS_CALL dmumps_c(DMUMPS_STRUC_C *dmumps_par) {
    static dmumps_c_fn p_dmumps_c = NULL;
    if (p_dmumps_c == NULL) {
        /* R_GetCCallable raises a clear error itself if rmumps is not loaded or
         * does not register the callable (rmumps < 5.2.1-43). */
        p_dmumps_c = (dmumps_c_fn) R_GetCCallable("rmumps", "dmumps_c");
    }
    p_dmumps_c(dmumps_par);
}
