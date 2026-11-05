/* Per-call cost of HiGHS' C API reached two ways, in one R session:
 *   -DVIA_REGISTRY : through highs_ccallable.h (R_GetCCallable wrappers -> highs.so)
 *   (default)      : direct calls, linked against the bundled HiGHS inside the
 *                    Uno 2.9.2-1 shared object (exports Highs_*; same HiGHS 1.15.1,
 *                    same -O3 -DNDEBUG)
 * .Call entry points return elapsed seconds for n repetitions. */
#include <R.h>
#include <Rinternals.h>
#include <time.h>

#ifdef VIA_REGISTRY
#include <highs_ccallable.h>
#else
typedef int HighsInt;
const char* Highs_version(void);
void* Highs_create(void);
void Highs_destroy(void* highs);
HighsInt Highs_setBoolOptionValue(void* highs, const char* option, const HighsInt value);
HighsInt Highs_passModel(void* highs, const HighsInt num_col, const HighsInt num_row,
    const HighsInt num_nz, const HighsInt q_num_nz, const HighsInt a_format,
    const HighsInt q_format, const HighsInt sense, const double offset,
    const double* col_cost, const double* col_lower, const double* col_upper,
    const double* row_lower, const double* row_upper, const HighsInt* a_start,
    const HighsInt* a_index, const double* a_value, const HighsInt* q_start,
    const HighsInt* q_index, const double* q_value, const HighsInt* integrality);
HighsInt Highs_run(void* highs);
HighsInt Highs_getSolution(const void* highs, double* col_value, double* col_dual,
    double* row_value, double* row_dual);
HighsInt Highs_getModelStatus(const void* highs);
#define kHighsMatrixFormatColwise 1
#define kHighsHessianFormatTriangular 1
#define kHighsObjSenseMinimize 1
#endif

static double now(void) {
  struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double) ts.tv_sec + 1e-9 * (double) ts.tv_nsec;
}

SEXP bench_version(SEXP n_) {
  int n = asInteger(n_); volatile const char* v = NULL;
  double t0 = now();
  for (int i = 0; i < n; i++) v = Highs_version();
  double t1 = now(); (void) v;
  return ScalarReal(t1 - t0);
}

SEXP bench_create(SEXP n_) {
  int n = asInteger(n_);
  double t0 = now();
  for (int i = 0; i < n; i++) { void* h = Highs_create(); Highs_destroy(h); }
  return ScalarReal(now() - t0);
}

/* the 2-variable QP of the tinytests as HiGHS sees it from filtersqp:
   min (x1-1)^2 + (x2-2)^2 -> 0.5 x'Hx + c'x, H = 2I, c = (-2,-4); x1 + x2 <= 10 */
#ifdef VIA_REGISTRY
#else
HighsInt Highs_setIntOptionValue(void* highs, const char* option, const HighsInt value);
#endif
/* mode 0: create/solve/destroy per iteration (as Uno does)
   mode 1: same, but threads = 1 before the run
   mode 2: one instance reused: pass/run per iteration, destroyed once */
static SEXP bench_tiny_mode(int n, int mode) {
  const double col_cost[2] = {-2., -4.}, col_lower[2] = {-1e30, -1e30}, col_upper[2] = {1e30, 1e30};
  const double row_lower[1] = {-1e30}, row_upper[1] = {10.};
  const HighsInt a_start[3] = {0, 1, 2}, a_index[2] = {0, 0}; const double a_value[2] = {1., 1.};
  const HighsInt q_start[3] = {0, 1, 2}, q_index[2] = {0, 1}; const double q_value[2] = {2., 2.};
  double x[2], d[2], rd[1]; volatile HighsInt st = 0;
  void* h = NULL;
  if (mode == 2) { h = Highs_create(); Highs_setBoolOptionValue(h, "output_flag", 0); }
  double t0 = now();
  for (int i = 0; i < n; i++) {
    if (mode != 2) {
      h = Highs_create();
      Highs_setBoolOptionValue(h, "output_flag", 0);
      if (mode == 1) Highs_setIntOptionValue(h, "threads", 1);
    }
    Highs_passModel(h, 2, 1, 2, 2, kHighsMatrixFormatColwise, kHighsHessianFormatTriangular,
                    kHighsObjSenseMinimize, 0., col_cost, col_lower, col_upper, row_lower, row_upper,
                    a_start, a_index, a_value, q_start, q_index, q_value, NULL);
    Highs_run(h);
    st = Highs_getModelStatus(h);
    Highs_getSolution(h, x, d, NULL, rd);
    if (mode != 2) Highs_destroy(h);
  }
  double t1 = now(); (void) st;
  if (mode == 2) Highs_destroy(h);
  if (x[0] < 0.99 || x[0] > 1.01 || x[1] < 1.99 || x[1] > 2.01) error("wrong solution %g %g", x[0], x[1]);
  return ScalarReal(t1 - t0);
}
SEXP bench_tiny_t1(SEXP n_) { return bench_tiny_mode(asInteger(n_), 1); }
SEXP bench_tiny_reuse(SEXP n_) { return bench_tiny_mode(asInteger(n_), 2); }

SEXP bench_tiny(SEXP n_) {
  int n = asInteger(n_);
  const double col_cost[2] = {-2., -4.}, col_lower[2] = {-1e30, -1e30}, col_upper[2] = {1e30, 1e30};
  const double row_lower[1] = {-1e30}, row_upper[1] = {10.};
  const HighsInt a_start[3] = {0, 1, 2}, a_index[2] = {0, 0}; const double a_value[2] = {1., 1.};
  const HighsInt q_start[3] = {0, 1, 2}, q_index[2] = {0, 1}; const double q_value[2] = {2., 2.};
  double x[2], d[2], rd[1]; volatile HighsInt st = 0;
  double t0 = now();
  for (int i = 0; i < n; i++) {
    void* h = Highs_create();
    Highs_setBoolOptionValue(h, "output_flag", 0);
    Highs_passModel(h, 2, 1, 2, 2, kHighsMatrixFormatColwise, kHighsHessianFormatTriangular,
                    kHighsObjSenseMinimize, 0., col_cost, col_lower, col_upper, row_lower, row_upper,
                    a_start, a_index, a_value, q_start, q_index, q_value, NULL);
    Highs_run(h);
    st = Highs_getModelStatus(h);
    Highs_getSolution(h, x, d, NULL, rd);
    Highs_destroy(h);
  }
  double t1 = now(); (void) st;
  if (x[0] < 0.99 || x[0] > 1.01 || x[1] < 1.99 || x[1] > 2.01) error("wrong solution %g %g", x[0], x[1]);
  return ScalarReal(t1 - t0);
}
