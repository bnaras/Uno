# Parity annotations
# ------------------
# unopy (Uno's official Python binding) ships NO test suite -- its only
# behavioral reference is interfaces/Python/example/example_hs015.py. Each block
# below is annotated, mirroring CVXR's `## @cvxpy` convention:
#   ## @unopy example_hs015.py [(which run / call)]   -- parity with the example
#   ## @unopy NONE                                    -- R-specific (no unopy counterpart)

## @unopy example_hs015.py (current_uno_version)
## uno_version reports the linked Uno version
expect_true(grepl("^[0-9]+\\.[0-9]+\\.[0-9]+$", uno_version()))

## @unopy NONE
## R smoke test: a simple convex NLP via filtersqp + HiGHS (not in unopy).
## min (x1-1)^2 + (x2-2)^2  s.t.  x1 + x2 <= 10
## the unconstrained optimum (1, 2) is feasible, so x* = (1, 2), f* = 0.
obj  <- function(x) (x[1] - 1)^2 + (x[2] - 2)^2
grad <- function(x) c(2 * (x[1] - 1), 2 * (x[2] - 2))
cons <- function(x) x[1] + x[2]
jac  <- function(x) c(1, 1)                              # rows{0,0} cols{0,1}
hess <- function(x, sigma, lambda) c(2 * sigma, 2 * sigma)  # rows{0,1} cols{0,1}

res <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj = obj, grad = grad,
  m = 1L, cl = -Inf, cu = 10, cons = cons,
  jac_rows = c(0L, 0L), jac_cols = c(0L, 1L), jac = jac,
  hess_rows = c(0L, 1L), hess_cols = c(0L, 1L), hess = hess,
  x0 = c(0, 0), preset = "filtersqp", base_indexing = 0L, verbose = FALSE
)
expect_equal(res$optimization_status, "SUCCESS")
expect_equal(res$solution_status, "FEASIBLE_KKT_POINT")
expect_equal(res$objective, 0, tolerance = 1e-6)
expect_equal(res$primal, c(1, 2), tolerance = 1e-5)

## @unopy NONE
## R-specific: an R error inside a callback must abort cleanly via
## UNO_EVALUATION_ERROR (R_tryEval catches it rather than longjmp-ing through
## Uno's C++ optimize() stack). No unopy counterpart.
obj_err <- function(x) stop("boom")
res_err <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj = obj_err, grad = grad,
  m = 1L, cl = -Inf, cu = 10, cons = cons,
  jac_rows = c(0L, 0L), jac_cols = c(0L, 1L), jac = jac,
  hess_rows = c(0L, 1L), hess_cols = c(0L, 1L), hess = hess,
  x0 = c(0, 0), preset = "filtersqp", base_indexing = 0L, verbose = FALSE
)
expect_equal(res_err$optimization_status, "EVALUATION_ERROR")

## Everything below exercises the interior-point "ipopt" preset, whose KKT
## linear solver is MUMPS, reached at runtime from 'rmumps' via
## R_FindSymbol("dmumps_c","rmumps"). That lookup cannot succeed on Windows (a
## DLL only exports declared symbols and rmumps.dll does not export dmumps_c),
## so the Windows build is HiGHS-only and these tests do not apply there. The
## filtersqp/HiGHS smoke tests above already validate the Windows build.
if (.Platform$OS.type == "windows")
  exit_file("ipopt/MUMPS tests skipped on Windows (HiGHS-only build)")

## @unopy NONE
## R smoke test: the interior-point "ipopt" preset on the trivial convex NLP
## above, exercising the MUMPS linear-solver path (reached at runtime from the
## 'rmumps' package via R_FindSymbol; see src/dmumps_shim.c). x* = (1, 2), f* = 0.
res_ip <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj = obj, grad = grad,
  m = 1L, cl = -Inf, cu = 10, cons = cons,
  jac_rows = c(0L, 0L), jac_cols = c(0L, 1L), jac = jac,
  hess_rows = c(0L, 1L), hess_cols = c(0L, 1L), hess = hess,
  x0 = c(0, 0), preset = "ipopt", base_indexing = 0L, verbose = FALSE
)
expect_equal(res_ip$optimization_status, "SUCCESS")
expect_equal(res_ip$solution_status, "FEASIBLE_KKT_POINT")
expect_equal(res_ip$objective, 0, tolerance = 1e-6)
expect_equal(res_ip$primal, c(1, 2), tolerance = 1e-5)

## @unopy example_hs015.py (run 3: ipopt preset, MUMPS linear solver)
## HS015 (Hock-Schittkowski #15) -- the canonical unopy reference problem:
##   min  100*(x2 - x1^2)^2 + (1 - x1)^2
##   s.t. x1*x2 >= 1,  x1 + x2^2 >= 0,  x1 <= 0.5
## Known solution: x* = (0.5, 2.0), f* = 306.5 (active first constraint + active
## upper bound). The Lagrangian Hessian is INDEFINITE, so the example solves the
## filtersqp/filterslp runs with BQPD. In this HiGHS-only build the QP/LP-based
## presets fail on the indefinite subproblem ("HiGHS encountered negative
## curvature"), so ONLY the interior-point "ipopt" preset (with MUMPS as the
## symmetric-indefinite linear solver) reproduces HS015 here. The filtersqp
## (run 2) and filterslp (run 4) runs require BQPD and are out of scope for a
## HiGHS-only build -- they are therefore not asserted (not faked as passing).
hs015_obj  <- function(x) 100 * (x[2] - x[1]^2)^2 + (1 - x[1])^2
hs015_grad <- function(x) c(400 * x[1]^3 - 400 * x[1] * x[2] + 2 * x[1] - 2,
                            200 * (x[2] - x[1]^2))
hs015_cons <- function(x) c(x[1] * x[2], x[1] + x[2]^2)
hs015_jac  <- function(x) c(x[2], 1, x[1], 2 * x[2])     # rows{0,1,0,1} cols{0,0,1,1}
hs015_hess <- function(x, sigma, lambda)                 # rows{0,1,1} cols{0,0,1}
  c(sigma * (1200 * x[1]^2 - 400 * x[2] + 2),
    -400 * sigma * x[1] - lambda[1],
    200 * sigma - 2 * lambda[2])

res_hs015 <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(0.5, Inf), sense = "minimize",
  obj = hs015_obj, grad = hs015_grad,
  m = 2L, cl = c(1, 0), cu = c(Inf, Inf), cons = hs015_cons,
  jac_rows = c(0L, 1L, 0L, 1L), jac_cols = c(0L, 0L, 1L, 1L), jac = hs015_jac,
  hess_rows = c(0L, 1L, 1L), hess_cols = c(0L, 0L, 1L), hess = hs015_hess,
  x0 = c(-2, 1), preset = "ipopt", base_indexing = 0L, verbose = FALSE
)
expect_equal(res_hs015$optimization_status, "SUCCESS")
expect_equal(res_hs015$solution_status, "FEASIBLE_KKT_POINT")
expect_equal(res_hs015$objective, 306.5, tolerance = 1e-4)  # example asserts <= 1e-4
expect_equal(res_hs015$primal, c(0.5, 2.0), tolerance = 1e-4)
## duals are returned for both constraints and both bounds (HS015 has an active
## constraint and an active upper bound); the example prints but does not assert
## their values, so we only check they are present and finite.
expect_equal(length(res_hs015$constraint_dual), 2L)
expect_true(all(is.finite(res_hs015$lower_bound_dual)))
expect_true(all(is.finite(res_hs015$upper_bound_dual)))

## the diagnostic / performance fields the example prints are all exposed and
## populated: cpu_time plus the per-callback evaluation counters, the iteration
## count and the number of subproblems solved.
expect_true(is.finite(res_hs015$cpu_time) && res_hs015$cpu_time >= 0)
expect_true(res_hs015$iterations > 0L)
expect_true(res_hs015$objective_evaluations > 0L)
expect_true(res_hs015$constraint_evaluations > 0L)
expect_true(res_hs015$objective_gradient_evaluations > 0L)
expect_true(res_hs015$jacobian_evaluations > 0L)
expect_true(res_hs015$hessian_evaluations > 0L)
expect_true(res_hs015$subproblems_solved > 0L)

## @unopy example_hs015.py (set_option)
## the `options` passthrough forwards named Uno solver options, applied AFTER
## the preset so they override it. Verify an option takes effect, that a value
## is coerced to the option's declared type, and that misuse errors cleanly.
hs015_solve <- function(opts) uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(0.5, Inf), sense = "minimize",
  obj = hs015_obj, grad = hs015_grad,
  m = 2L, cl = c(1, 0), cu = c(Inf, Inf), cons = hs015_cons,
  jac_rows = c(0L, 1L, 0L, 1L), jac_cols = c(0L, 0L, 1L, 1L), jac = hs015_jac,
  hess_rows = c(0L, 1L, 1L), hess_cols = c(0L, 0L, 1L), hess = hs015_hess,
  x0 = c(-2, 1), preset = "ipopt", base_indexing = 0L, verbose = FALSE,
  options = opts
)
## max_iterations caps the solve well below the ~18 iterations it otherwise needs
capped_int <- hs015_solve(list(max_iterations = 3L))
expect_true(capped_int$iterations <= 3L)
## a value is coerced to the option's declared (integer) type: 3 (double) == 3L
capped_dbl <- hs015_solve(list(max_iterations = 3))
expect_equal(capped_dbl$iterations, capped_int$iterations)
## an unknown option name and an unnamed options list both error cleanly
expect_error(hs015_solve(list(not_a_real_option = 1)), "unknown solver option")
expect_error(hs015_solve(list(1)), "named list")

## @unopy NONE
## C1: lagrangian_sign = "positive" (L = sigma*f + y^T c). HS015 has NONLINEAR
## constraints, so the constraint-Hessian terms are nonzero and the sign matters
## (this is exactly the case the old hardcoded "negative" broke for a positive-
## convention oracle). The positive-convention Hessian flips the lambda terms;
## with lagrangian_sign="positive" Uno must reach the same optimum as the
## default-"negative" run above.
hs015_hess_pos <- function(x, sigma, lambda)
  c(sigma * (1200 * x[1]^2 - 400 * x[2] + 2),
    -400 * sigma * x[1] + lambda[1],     # + (positive convention) vs - above
    200 * sigma + 2 * lambda[2])
res_pos <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(0.5, Inf), sense = "minimize",
  obj = hs015_obj, grad = hs015_grad,
  m = 2L, cl = c(1, 0), cu = c(Inf, Inf), cons = hs015_cons,
  jac_rows = c(0L, 1L, 0L, 1L), jac_cols = c(0L, 0L, 1L, 1L), jac = hs015_jac,
  hess_rows = c(0L, 1L, 1L), hess_cols = c(0L, 0L, 1L), hess = hs015_hess_pos,
  x0 = c(-2, 1), preset = "ipopt", base_indexing = 0L, verbose = FALSE,
  lagrangian_sign = "positive"
)
expect_equal(res_pos$optimization_status, "SUCCESS")
expect_equal(res_pos$objective, 306.5, tolerance = 1e-4)
expect_equal(res_pos$primal, c(0.5, 2.0), tolerance = 1e-4)

## @unopy NONE
## C4: iter_callback fires per acceptable iterate with iterate info; returning
## FALSE runs to completion.
cb_calls <- 0L
cb_info  <- NULL
res_cb <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj = obj, grad = grad, m = 1L, cl = -Inf, cu = 10, cons = cons,
  jac_rows = c(0L, 0L), jac_cols = c(0L, 1L), jac = jac,
  hess_rows = c(0L, 1L), hess_cols = c(0L, 1L), hess = hess,
  x0 = c(0, 0), preset = "filtersqp", base_indexing = 0L, verbose = FALSE,
  iter_callback = function(info) { cb_calls <<- cb_calls + 1L; cb_info <<- info; FALSE }
)
expect_true(cb_calls >= 1L)
expect_equal(res_cb$optimization_status, "SUCCESS")
expect_true(all(c("primals", "constraint_dual", "stationarity") %in% names(cb_info)))
expect_equal(length(cb_info$primals), 2L)

## C4: returning TRUE terminates early; callback still fires, solve returns cleanly.
term_calls <- 0L
res_term <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj = obj, grad = grad, m = 1L, cl = -Inf, cu = 10, cons = cons,
  jac_rows = c(0L, 0L), jac_cols = c(0L, 1L), jac = jac,
  hess_rows = c(0L, 1L), hess_cols = c(0L, 1L), hess = hess,
  x0 = c(0, 0), preset = "filtersqp", base_indexing = 0L, verbose = FALSE,
  iter_callback = function(info) { term_calls <<- term_calls + 1L; TRUE }
)
expect_true(term_calls >= 1L)
expect_true(is.character(res_term$optimization_status))

## @unopy NONE
## C5: log_callback receives Uno's output stream (a sink for the solver log).
log_chunks <- character(0)
res_log <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj = obj, grad = grad, m = 1L, cl = -Inf, cu = 10, cons = cons,
  jac_rows = c(0L, 0L), jac_cols = c(0L, 1L), jac = jac,
  hess_rows = c(0L, 1L), hess_cols = c(0L, 1L), hess = hess,
  x0 = c(0, 0), preset = "filtersqp", base_indexing = 0L, verbose = TRUE,
  log_callback = function(t) log_chunks[[length(log_chunks) + 1L]] <<- t
)
expect_true(length(log_chunks) >= 1L)
expect_true(is.character(unlist(log_chunks)))
