# Exported R surface for the Uno solver. The cpp11-generated entry point is
# `uno_solve_impl()` (in R/cpp11.R); this thin wrapper adds the `options`
# default so existing call sites need not pass it.

#' Solve a nonlinear program with Uno
#'
#' @param n number of variables.
#' @param lb,ub variable lower/upper bounds (length `n`; use `-Inf`/`Inf`).
#' @param sense `"minimize"` or `"maximize"`.
#' @param obj,grad objective `function(x)` and its gradient `function(x)`.
#' @param m number of constraints (0 for unconstrained).
#' @param cl,cu constraint lower/upper bounds (length `m`).
#' @param cons constraint `function(x)` returning a length-`m` vector.
#' @param jac_rows,jac_cols COO row/column indices of the Jacobian nonzeros.
#' @param jac Jacobian `function(x)` returning the nonzero values.
#' @param hess_rows,hess_cols COO indices of the lower-triangular Hessian.
#' @param hess Lagrangian Hessian `function(x, sigma, lambda)` returning the
#'   lower-triangular nonzero values, or `NULL` (Uno then uses an L-BFGS
#'   approximation, which the HiGHS subproblem solver cannot use).
#' @param x0 initial primal iterate (length `n`).
#' @param preset Uno preset, e.g. `"filtersqp"` (SQP) or `"ipopt"` (interior
#'   point, using MUMPS as the linear solver).
#' @param base_indexing 0 for C-style or 1 for Fortran-style COO indices.
#' @param verbose if `FALSE`, suppress Uno's solution printout.
#' @param options a named list of Uno solver options applied AFTER the preset
#'   (so they override it), e.g. `list(max_iterations = 200L, tolerance = 1e-8,
#'   linear_solver = "MUMPS")`. Each value is coerced to the option's declared
#'   Uno type; an unknown option name or an unacceptable value raises an error.
#' @return a named list with the optimization/solution status, objective,
#'   primal and dual solutions, KKT residuals, and per-callback evaluation
#'   counters.
#' @export
uno_solve <- function(n, lb, ub, sense, obj, grad, m, cl, cu, cons,
                      jac_rows, jac_cols, jac, hess_rows, hess_cols, hess,
                      x0, preset, base_indexing, verbose, options = list()) {
  uno_solve_impl(n, lb, ub, sense, obj, grad, m, cl, cu, cons,
                 jac_rows, jac_cols, jac, hess_rows, hess_cols, hess,
                 x0, preset, base_indexing, verbose, options)
}
