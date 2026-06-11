// R bindings to Uno via its C API (interfaces/C/Uno_C_API.h).
//
// The header carries its own `extern "C"` guards, so it is included directly.
// We expose:
//   * uno_version()  — version smoke test
//   * uno_solve(...) — solve a nonlinear program given R callbacks
//
// CALLBACK SAFETY: Uno calls our C trampolines from deep inside its C++
// optimize() stack. Each trampoline evaluates an R closure through R_tryEval,
// which installs a longjmp barrier: if the R code errors, R_tryEval returns
// with errorOccurred set instead of longjmp-ing through Uno's C++ frames
// (which would skip destructors and corrupt state). On any failure the
// trampoline returns UNO_EVALUATION_ERROR (a positive int) so Uno can abort
// the evaluation cleanly. Mirrors the contract documented in Uno_C_API.h.

#include <cpp11.hpp>
#include <cstring>
#include <string>
#include <vector>

#include "uno/Uno_C_API.h"

namespace {

// R closures + dimensions, passed to every trampoline via Uno's user_data.
// The SEXP closures are borrowed: they are arguments of uno_solve() and so
// stay protected by R for the whole solve. No finalizer needed.
struct RCallbacks {
  SEXP obj;   // function(x) -> double
  SEXP grad;  // function(x) -> double[n]
  SEXP cons;  // function(x) -> double[m]
  SEXP jac;   // function(x) -> double[nnz_jac]   (COO order)
  SEXP hess;  // function(x, sigma, lambda) -> double[nnz_hess] (lower-tri COO)
  SEXP iter;  // C4: function(info_list) -> logical (TRUE terminates); or NULL
  SEXP log;   // C5: function(text) -> NULL (logger stream sink); or NULL
  uno_int iter_terminate;  // C4: TRUE-request from the last notify, relayed to termination
};

// Wrap a C buffer as a REALSXP the R closure can read. Caller PROTECTs.
// Guard the copy: for an unconstrained iterate the callback passes a null
// `x` with n == 0 (e.g. the constraint-multiplier array), and memcpy declares
// both pointers nonnull -- passing NULL is UB even for length 0 and trips
// the gcc/clang -fsanitize=nonnull-attribute check (CRAN gcc-SAN/clang-SAN).
SEXP make_x(const double* x, uno_int n) {
  SEXP xr = Rf_allocVector(REALSXP, n);
  if (n > 0 && x != nullptr) {
    std::memcpy(REAL(xr), x, static_cast<size_t>(n) * sizeof(double));
  }
  return xr;
}

// Evaluate `call` via R_tryEval; on success copy the (coerced) numeric result
// into `out` (expecting `expected` entries). Returns 0 on success, else
// UNO_EVALUATION_ERROR. `call` must already be PROTECTed by the caller.
uno_int eval_into(SEXP call, double* out, uno_int expected) {
  int err = 0;
  SEXP res = R_tryEval(call, R_GlobalEnv, &err);
  if (err) {
    return UNO_EVALUATION_ERROR;
  }
  PROTECT(res);
  SEXP num = PROTECT(Rf_coerceVector(res, REALSXP));
  if (Rf_xlength(num) < expected) {
    UNPROTECT(2);
    return UNO_EVALUATION_ERROR;
  }
  std::memcpy(out, REAL(num), static_cast<size_t>(expected) * sizeof(double));
  UNPROTECT(2);
  return 0;
}

uno_int objective_trampoline(uno_int n, const double* x, double* objective_value,
                             void* user_data) {
  RCallbacks* cb = static_cast<RCallbacks*>(user_data);
  SEXP xr = PROTECT(make_x(x, n));
  SEXP call = PROTECT(Rf_lang2(cb->obj, xr));
  int err = 0;
  SEXP res = R_tryEval(call, R_GlobalEnv, &err);
  if (err) { UNPROTECT(2); return UNO_EVALUATION_ERROR; }
  *objective_value = Rf_asReal(res);
  UNPROTECT(2);
  return 0;
}

uno_int objective_gradient_trampoline(uno_int n, const double* x, double* gradient,
                                      void* user_data) {
  RCallbacks* cb = static_cast<RCallbacks*>(user_data);
  SEXP xr = PROTECT(make_x(x, n));
  SEXP call = PROTECT(Rf_lang2(cb->grad, xr));
  uno_int rc = eval_into(call, gradient, n);
  UNPROTECT(2);
  return rc;
}

uno_int constraints_trampoline(uno_int n, uno_int m, const double* x,
                               double* constraint_values, void* user_data) {
  RCallbacks* cb = static_cast<RCallbacks*>(user_data);
  SEXP xr = PROTECT(make_x(x, n));
  SEXP call = PROTECT(Rf_lang2(cb->cons, xr));
  uno_int rc = eval_into(call, constraint_values, m);
  UNPROTECT(2);
  return rc;
}

uno_int jacobian_trampoline(uno_int n, uno_int nnz, const double* x,
                            double* jacobian_values, void* user_data) {
  RCallbacks* cb = static_cast<RCallbacks*>(user_data);
  SEXP xr = PROTECT(make_x(x, n));
  SEXP call = PROTECT(Rf_lang2(cb->jac, xr));
  uno_int rc = eval_into(call, jacobian_values, nnz);
  UNPROTECT(2);
  return rc;
}

uno_int lagrangian_hessian_trampoline(uno_int n, uno_int m, uno_int nnz,
                                      const double* x, double objective_multiplier,
                                      const double* multipliers, double* hessian_values,
                                      void* user_data) {
  RCallbacks* cb = static_cast<RCallbacks*>(user_data);
  SEXP xr = PROTECT(make_x(x, n));
  SEXP sigma = PROTECT(Rf_ScalarReal(objective_multiplier));
  SEXP lambda = PROTECT(Rf_allocVector(REALSXP, m));
  if (m > 0) {
    std::memcpy(REAL(lambda), multipliers, static_cast<size_t>(m) * sizeof(double));
  }
  SEXP call = PROTECT(Rf_lang4(cb->hess, xr, sigma, lambda));
  uno_int rc = eval_into(call, hessian_values, nnz);
  UNPROTECT(4);
  return rc;
}

// C4: build the acceptable-iterate info list (primals, bound/constraint
// multipliers, objective multiplier, KKT residuals), pass it to the R `iter`
// closure, and return its TRUE -> terminate request. Shared by the notify
// (per-iterate) and termination (relay) trampolines below. An R error in the
// closure is caught (R_tryEval) and treated as "do not terminate" -- progress
// callbacks must never longjmp through Uno's optimize().
uno_int invoke_iter_callback(uno_int n, uno_int m, const double* primals,
                             const double* lb_mult, const double* ub_mult,
                             const double* con_mult, double obj_mult,
                             double primal_feas, double stationarity,
                             double complementarity, void* user_data) {
  RCallbacks* cb = static_cast<RCallbacks*>(user_data);
  SEXP info = PROTECT(Rf_allocVector(VECSXP, 8));
  SEXP names = PROTECT(Rf_allocVector(STRSXP, 8));
  SET_VECTOR_ELT(info, 0, make_x(primals, n));
  SET_VECTOR_ELT(info, 1, make_x(lb_mult, n));
  SET_VECTOR_ELT(info, 2, make_x(ub_mult, n));
  SET_VECTOR_ELT(info, 3, make_x(con_mult, m));
  SET_VECTOR_ELT(info, 4, Rf_ScalarReal(obj_mult));
  SET_VECTOR_ELT(info, 5, Rf_ScalarReal(primal_feas));
  SET_VECTOR_ELT(info, 6, Rf_ScalarReal(stationarity));
  SET_VECTOR_ELT(info, 7, Rf_ScalarReal(complementarity));
  SET_STRING_ELT(names, 0, Rf_mkChar("primals"));
  SET_STRING_ELT(names, 1, Rf_mkChar("lower_bound_dual"));
  SET_STRING_ELT(names, 2, Rf_mkChar("upper_bound_dual"));
  SET_STRING_ELT(names, 3, Rf_mkChar("constraint_dual"));
  SET_STRING_ELT(names, 4, Rf_mkChar("objective_multiplier"));
  SET_STRING_ELT(names, 5, Rf_mkChar("primal_feasibility"));
  SET_STRING_ELT(names, 6, Rf_mkChar("stationarity"));
  SET_STRING_ELT(names, 7, Rf_mkChar("complementarity"));
  Rf_setAttrib(info, R_NamesSymbol, names);
  SEXP call = PROTECT(Rf_lang2(cb->iter, info));
  int err = 0;
  SEXP res = R_tryEval(call, R_GlobalEnv, &err);
  uno_int terminate = 0;
  if (!err && res != R_NilValue && Rf_xlength(res) >= 1 &&
      Rf_asLogical(res) == TRUE) {
    terminate = 1;
  }
  UNPROTECT(3);
  return terminate;
}

// C4 (Uno >= 2.7.3): the per-iterate progress callback. notify_acceptable_iterate
// fires on every accepted iterate (unlike the termination callback, whose firing
// 2.7.3 made conditional). It is void, so we stash the R closure's TRUE-terminate
// request for the termination relay below.
void notify_acceptable_iterate_trampoline(uno_int n, uno_int m, const double* primals,
                                          const double* lb_mult, const double* ub_mult,
                                          const double* con_mult, double obj_mult,
                                          double primal_feas, double stationarity,
                                          double complementarity, void* user_data) {
  RCallbacks* cb = static_cast<RCallbacks*>(user_data);
  cb->iter_terminate = invoke_iter_callback(n, m, primals, lb_mult, ub_mult, con_mult,
                                            obj_mult, primal_feas, stationarity,
                                            complementarity, user_data);
}

// C4: termination check. Relays the flag set by the most recent notify (no extra
// R call), so iter_callback returning TRUE still stops the solve.
uno_int termination_trampoline(uno_int /*n*/, uno_int /*m*/, const double* /*primals*/,
                               const double* /*lb_mult*/, const double* /*ub_mult*/,
                               const double* /*con_mult*/, double /*obj_mult*/,
                               double /*primal_feas*/, double /*stationarity*/,
                               double /*complementarity*/, void* user_data) {
  RCallbacks* cb = static_cast<RCallbacks*>(user_data);
  return cb->iter_terminate;
}

// C5: logger stream callback. Forwards each Uno output buffer to the R `log`
// closure as a single string. Errors are swallowed (never propagate through
// Uno's C++ output path). user_data carries the RCallbacks.
uno_int logger_trampoline(const char* buffer, uno_int length, void* user_data) {
  RCallbacks* cb = static_cast<RCallbacks*>(user_data);
  SEXP txt = PROTECT(Rf_ScalarString(
      Rf_mkCharLen(buffer, static_cast<int>(length))));
  SEXP call = PROTECT(Rf_lang2(cb->log, txt));
  int err = 0;
  R_tryEval(call, R_GlobalEnv, &err);
  UNPROTECT(2);
  return 0;
}

// Copy a cpp11::integers into a contiguous uno_int (int32) buffer.
std::vector<uno_int> to_uno_int(cpp11::integers v) {
  std::vector<uno_int> out(static_cast<size_t>(v.size()));
  for (R_xlen_t i = 0; i < v.size(); ++i) {
    out[static_cast<size_t>(i)] = static_cast<uno_int>(v[i]);
  }
  return out;
}

}  // namespace

// Returns the Uno version as "major.minor.patch".
[[cpp11::register]]
std::string uno_version() {
  uno_int major = 0, minor = 0, patch = 0;
  uno_get_version(&major, &minor, &patch);
  return std::to_string(major) + "." + std::to_string(minor) + "." +
         std::to_string(patch);
}

// Solve a nonlinear program with Uno.
//
//   n            number of variables
//   lb, ub       variable bounds (length n; use Inf/-Inf for unbounded)
//   sense        "minimize" or "maximize"
//   obj, grad    objective value / dense gradient closures
//   m            number of constraints (0 for bound-constrained problems)
//   cl, cu       constraint bounds (length m)
//   cons         constraint-values closure, function(x) -> double[m]
//   jac_rows,    constraint-Jacobian sparsity (COO; in `base_indexing` base)
//   jac_cols
//   jac          Jacobian-values closure (COO order matching jac_rows/cols)
//   hess_rows,   Lagrangian-Hessian sparsity (lower triangle, COO); pass
//   hess_cols    length-0 vectors when `hess` is NULL
//   hess         Hessian-values closure, function(x, sigma, lambda); or NULL
//                (then Uno uses an L-BFGS quasi-Newton Hessian). Sign
//                convention: L = sigma*f - lambda^T c (UNO_MULTIPLIER_NEGATIVE).
//   x0           initial primal iterate (length n)
//   preset       Uno preset, e.g. "filtersqp" (HiGHS-backed SQP)
//   base_indexing 0 (C-style) or 1 (Fortran-style) for the COO indices
// Apply user-supplied solver options (a named R list) on top of the preset.
// Each value is coerced to the option's DECLARED Uno type (queried via
// uno_get_solver_option_type), so e.g. max_iterations = 200 (an R double) is
// accepted for an integer-typed option. An unknown option name, or a value the
// option rejects, raises a clean R error rather than silently being ignored.
static void apply_solver_options(void* solver, SEXP options) {
  const R_xlen_t k = Rf_xlength(options);
  if (k == 0) return;
  SEXP nms = Rf_getAttrib(options, R_NamesSymbol);
  if (nms == R_NilValue || Rf_xlength(nms) != k) {
    Rf_error("Uno: `options` must be a named list (every element needs a name).");
  }
  for (R_xlen_t i = 0; i < k; ++i) {
    const char* key = CHAR(STRING_ELT(nms, i));
    if (key[0] == '\0') {
      Rf_error("Uno: `options` element %lld has an empty name.", (long long)(i + 1));
    }
    SEXP val = VECTOR_ELT(options, i);
    if (Rf_xlength(val) != 1) {
      Rf_error("Uno: option '%s' must be a single scalar value.", key);
    }
    const uno_int otype = uno_get_solver_option_type(solver, key);
    bool ok = false;
    switch (otype) {
      case UNO_OPTION_TYPE_INTEGER: {
        const int v = Rf_asInteger(val);
        if (v == NA_INTEGER)
          Rf_error("Uno: option '%s' (integer) is NA or not coercible.", key);
        ok = uno_set_solver_integer_option(solver, key, static_cast<uno_int>(v));
        break;
      }
      case UNO_OPTION_TYPE_DOUBLE: {
        const double v = Rf_asReal(val);
        if (ISNA(v)) Rf_error("Uno: option '%s' (double) is NA.", key);
        ok = uno_set_solver_double_option(solver, key, v);
        break;
      }
      case UNO_OPTION_TYPE_BOOL: {
        const int v = Rf_asLogical(val);
        if (v == NA_LOGICAL)
          Rf_error("Uno: option '%s' (bool) is NA or not coercible.", key);
        ok = uno_set_solver_bool_option(solver, key, v != 0);
        break;
      }
      case UNO_OPTION_TYPE_STRING: {
        if (TYPEOF(val) != STRSXP)
          Rf_error("Uno: option '%s' (string) must be a character value.", key);
        ok = uno_set_solver_string_option(solver, key, CHAR(STRING_ELT(val, 0)));
        break;
      }
      case UNO_OPTION_TYPE_NOT_FOUND:
      default:
        Rf_error("Uno: unknown solver option '%s'.", key);
    }
    if (!ok) Rf_error("Uno: solver rejected option '%s'.", key);
  }
}

//   verbose      if FALSE, suppress Uno's solution printout
//   options      named list of Uno solver options applied AFTER the preset
//                (so they override it); values coerced to each option's type
//
// Returns a named list with the status, objective, primal/dual solutions,
// iteration count, KKT residuals and per-callback evaluation counters.

// Canonical string names for Uno's optimization/solution status enums, so the
// R surface mirrors unopy / CVXPY's string-keyed STATUS_MAP (robust to enum
// reordering). Uno_C_API.h: optimization_status 0..4, solution_status 0..6.
static std::string optimization_status_name(uno_int s) {
  switch (s) {
    case UNO_SUCCESS:           return "SUCCESS";
    case UNO_ITERATION_LIMIT:   return "ITERATION_LIMIT";
    case UNO_TIME_LIMIT:        return "TIME_LIMIT";
    case UNO_EVALUATION_ERROR:  return "EVALUATION_ERROR";
    case UNO_ALGORITHMIC_ERROR: return "ALGORITHMIC_ERROR";
    case UNO_USER_TERMINATION:  return "USER_TERMINATION";
    default:                    return "UNKNOWN";
  }
}
static std::string solution_status_name(uno_int s) {
  switch (s) {
    case UNO_NOT_OPTIMAL:                  return "NOT_OPTIMAL";
    case UNO_FEASIBLE_KKT_POINT:           return "FEASIBLE_KKT_POINT";
    case UNO_FEASIBLE_FJ_POINT:            return "FEASIBLE_FJ_POINT";
    case UNO_INFEASIBLE_STATIONARY_POINT:  return "INFEASIBLE_STATIONARY_POINT";
    case UNO_FEASIBLE_SMALL_STEP:          return "FEASIBLE_SMALL_STEP";
    case UNO_INFEASIBLE_SMALL_STEP:        return "INFEASIBLE_SMALL_STEP";
    case UNO_UNBOUNDED:                    return "UNBOUNDED";
    default:                               return "UNKNOWN";
  }
}

// A status returned as a named integer (the idiomatic R form): the value is
// Uno's enum code, the name is its canonical label, e.g. c(SUCCESS = 0L). The
// caller gets both -- numeric comparison and a string key, via names().
static cpp11::writable::integers named_status(uno_int code, const std::string& name) {
  cpp11::writable::integers v(1);
  v[0] = static_cast<int>(code);
  v.names() = cpp11::writable::strings({name});
  return v;
}

[[cpp11::register]]
cpp11::list uno_solve_impl(int n, cpp11::doubles lb, cpp11::doubles ub, std::string sense,
                      SEXP obj, SEXP grad, int m, cpp11::doubles cl, cpp11::doubles cu,
                      SEXP cons, cpp11::integers jac_rows, cpp11::integers jac_cols,
                      SEXP jac, cpp11::integers hess_rows, cpp11::integers hess_cols,
                      SEXP hess, cpp11::doubles x0, std::string preset,
                      int base_indexing, bool verbose, cpp11::list options,
                      std::string lagrangian_sign, SEXP dual0,
                      SEXP iter_callback, SEXP log_callback) {
  RCallbacks cb;
  cb.obj = obj;
  cb.grad = grad;
  cb.cons = cons;
  cb.jac = jac;
  cb.hess = hess;
  cb.iter = iter_callback;  // C4
  cb.log = log_callback;    // C5
  cb.iter_terminate = 0;    // C4: no termination requested yet

  const uno_int optimization_sense =
      (sense == "maximize") ? UNO_MAXIMIZE : UNO_MINIMIZE;
  const uno_int indexing = static_cast<uno_int>(base_indexing);

  // Sparsity arrays must outlive uno_optimize(): Uno keeps the pointers.
  std::vector<uno_int> jrows = to_uno_int(jac_rows);
  std::vector<uno_int> jcols = to_uno_int(jac_cols);
  std::vector<uno_int> hrows = to_uno_int(hess_rows);
  std::vector<uno_int> hcols = to_uno_int(hess_cols);

  // --- model -------------------------------------------------------------
  void* model = uno_create_model(UNO_PROBLEM_NONLINEAR, n, REAL(lb), REAL(ub),
                                 indexing);
  uno_set_user_data(model, &cb);
  uno_set_objective(model, optimization_sense, objective_trampoline,
                    objective_gradient_trampoline);

  if (m > 0) {
    uno_set_constraints(model, m, constraints_trampoline, REAL(cl), REAL(cu),
                        static_cast<uno_int>(jrows.size()), jrows.data(),
                        jcols.data(), jacobian_trampoline);
  }

  const bool has_hessian = (hess != R_NilValue);
  if (has_hessian) {
    uno_set_lagrangian_hessian(model, static_cast<uno_int>(hrows.size()),
                               UNO_LOWER_TRIANGLE, hrows.data(), hcols.data(),
                               lagrangian_hessian_trampoline);
    // C1: caller-chosen Lagrangian sign convention. The diff-engine oracle
    // (sparsediff) returns sigma*Hf + sum_i lambda_i*Hg_i = L = sigma*f + y^T c,
    // i.e. UNO_MULTIPLIER_POSITIVE; CVXR passes "positive". Default "negative"
    // matches Uno's own C-API default.
    const uno_int sign_conv = (lagrangian_sign == "positive")
        ? UNO_MULTIPLIER_POSITIVE : UNO_MULTIPLIER_NEGATIVE;
    uno_set_lagrangian_sign_convention(model, sign_conv);
  }

  uno_set_initial_primal_iterate(model, REAL(x0));
  // C3: optional warm-start dual iterate (length m + 2n bound duals per Uno's
  // layout; the caller supplies the full vector). NULL -> Uno's default.
  if (dual0 != R_NilValue) {
    uno_set_initial_dual_iterate(model, REAL(dual0));
  }

  // --- solver ------------------------------------------------------------
  void* solver = uno_create_solver();
  uno_set_solver_preset(solver, preset.c_str());
  uno_set_solver_bool_option(solver, "print_solution", verbose);
  if (has_hessian) {
    uno_set_solver_string_option(solver, "hessian_model", "exact");
  }
  // user options override the preset and the defaults set just above
  apply_solver_options(solver, options);

  // C4: per-iterate progress + termination callback. Uno 2.7.3 split these:
  // notify_acceptable_iterate fires reliably each accepted iterate (and carries
  // the iterate data), while the termination callback decides whether to stop.
  // Wire R's single `iter_callback` to both -- notify calls it and stashes the
  // TRUE-terminate request, termination relays that request (no double call).
  if (iter_callback != R_NilValue) {
    uno_set_solver_callbacks(solver, notify_acceptable_iterate_trampoline,
                             termination_trampoline, &cb);
  }
  // C5: route Uno's logger output to an R sink (global; reset after optimize).
  if (log_callback != R_NilValue) {
    uno_set_logger_stream_callback(logger_trampoline, &cb);
  }

  uno_optimize(solver, model);

  if (log_callback != R_NilValue) {
    uno_reset_logger_stream();
  }

  using namespace cpp11::literals;
  const uno_int opt_status = uno_get_optimization_status(solver);
  const uno_int sol_status = uno_get_solution_status(solver);
  const double objective = uno_get_solution_objective(solver);

  // Fill plain buffers via the C API, then copy into cpp11 vectors (cpp11
  // writable vectors do not expose a stable REAL() buffer to write through).
  std::vector<double> primal(n), lb_dual(n), ub_dual(n), con_dual(m > 0 ? m : 0);
  uno_get_primal_solution(solver, primal.data());
  uno_get_lower_bound_dual_solution(solver, lb_dual.data());
  uno_get_upper_bound_dual_solution(solver, ub_dual.data());
  if (m > 0) {
    uno_get_constraint_dual_solution(solver, con_dual.data());
  }
  auto to_dbls = [](const std::vector<double>& v) {
    cpp11::writable::doubles d(static_cast<R_xlen_t>(v.size()));
    for (size_t i = 0; i < v.size(); ++i) d[static_cast<R_xlen_t>(i)] = v[i];
    return d;
  };

  cpp11::writable::list out({
      // C2: status as a named integer c(LABEL = code) -- carries both Uno's
      // enum code and its canonical label (key a status map by names()).
      "optimization_status"_nm = named_status(opt_status, optimization_status_name(opt_status)),
      "solution_status"_nm = named_status(sol_status, solution_status_name(sol_status)),
      "objective"_nm = objective,
      "primal"_nm = to_dbls(primal),
      "constraint_dual"_nm = to_dbls(con_dual),
      "lower_bound_dual"_nm = to_dbls(lb_dual),
      "upper_bound_dual"_nm = to_dbls(ub_dual),
      "iterations"_nm = static_cast<int>(uno_get_number_iterations(solver)),
      "primal_feasibility"_nm = uno_get_solution_primal_feasibility(solver),
      "stationarity"_nm = uno_get_solution_stationarity(solver),
      "complementarity"_nm = uno_get_solution_complementarity(solver),
      // performance / diagnostic counters (mirror unopy's Result fields)
      "cpu_time"_nm = uno_get_cpu_time(solver),
      "objective_evaluations"_nm = static_cast<int>(uno_get_number_objective_evaluations(solver)),
      "constraint_evaluations"_nm = static_cast<int>(uno_get_number_constraint_evaluations(solver)),
      "objective_gradient_evaluations"_nm = static_cast<int>(uno_get_number_objective_gradient_evaluations(solver)),
      "jacobian_evaluations"_nm = static_cast<int>(uno_get_number_jacobian_evaluations(solver)),
      "hessian_evaluations"_nm = static_cast<int>(uno_get_number_hessian_evaluations(solver)),
      "subproblems_solved"_nm = static_cast<int>(uno_get_number_subproblem_solved_evaluations(solver)),
  });

  uno_destroy_solver(solver);
  uno_destroy_model(model);
  return out;
}
