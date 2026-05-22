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
 * forwarder. The forwarder fetches rmumps' own dmumps_c via R_FindSymbol() and
 * calls through it. 'rmumps' itself is untouched: its R_init does
 * R_useDynamicSymbols(dll, TRUE), so dmumps_c (exported but NOT registered as a
 * callable) is discoverable by name. See the skill
 * `link-r-package-native-code` for the rationale ("shim in YOUR package, never
 * fork the provider").
 *
 * The MUMPS C API header (dmumps_c.h, which defines DMUMPS_STRUC_C and the
 * MUMPS_CALL macro) is supplied by `LinkingTo: rmumps`. 'rmumps' must be loaded
 * (Depends: rmumps) before any Uno solve that uses the MUMPS linear solver.
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
        p_dmumps_c = (dmumps_c_fn) R_FindSymbol("dmumps_c", "rmumps", NULL);
        if (p_dmumps_c == NULL) {
            Rf_error("Uno: could not resolve 'dmumps_c' from the 'rmumps' "
                     "package. Is 'rmumps' installed and loaded?");
        }
    }
    p_dmumps_c(dmumps_par);
}
