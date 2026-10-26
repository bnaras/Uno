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
expect_equal(uno_version(), "2.9.2")   # the bundled Uno (inst/uno submodule pin)

## @unopy NONE
## The status labels are generated from Uno_C_API.h at install time; the 2.9
## additions must be present and the pre-2.9 names unchanged.
labels <- uno_status_labels()
expect_equal(labels$optimization[["SUCCESS"]], 0L)
expect_equal(labels$optimization[["USER_TERMINATION"]], 5L)
expect_equal(labels$optimization[["USER_INTERRUPTION"]], 6L)   # Uno 2.9.1
expect_equal(labels$solution[["FEASIBLE_KKT_POINT"]], 1L)
expect_equal(labels$solution[["DIVERGING_ITERATE"]], 6L)       # Uno 2.9.0
expect_equal(labels$solution[["UNBOUNDED_OBJECTIVE"]], 7L)     # was UNBOUNDED = 6
expect_false("UNBOUNDED" %in% names(labels$solution))

## @unopy example_hs015.py (options iterator)
## uno_options() lists every option with its declared type
opts <- uno_options()
expect_true(is.data.frame(opts) && all(c("name", "type") %in% names(opts)))
expect_true(all(opts$type %in% c("integer", "double", "bool", "string")))
expect_equal(opts$type[opts$name == "max_iterations"], "integer")
expect_equal(opts$type[opts$name == "primal_tolerance"], "double")  # 2.9: no plain "tolerance"
expect_equal(opts$type[opts$name == "preset"], "string")

## @unopy NONE
## MUMPS is reached through rmumps; the version reported is rmumps' MUMPS
expect_true(grepl("^5\\.[0-9]+\\.[0-9]+$", uno_mumps_version()))

## @unopy NONE
## an invalid preset is rejected cleanly (Uno 2.9.2 validates preset names)
expect_error(uno_solve(
  n = 1L, lb = -Inf, ub = Inf, sense = "minimize",
  obj = function(x) x^2, grad = function(x) 2 * x,
  m = 0L, cl = numeric(), cu = numeric(), cons = function(x) numeric(),
  jac_rows = integer(), jac_cols = integer(), jac = function(x) numeric(),
  hess_rows = 0L, hess_cols = 0L, hess = function(x, sigma, lambda) 2 * sigma,
  x0 = 1, preset = "nosuchpreset", base_indexing = 0L, verbose = FALSE
), "not a valid preset")

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
## status is a named integer c(LABEL = code): names() gives the canonical label
## (e.g. to key a status map), and the integer code is preserved too. Note the
## R subtlety -- `x[1]` keeps the name, `x[[1]]` drops it to the bare code.
expect_equal(res$optimization_status, c(SUCCESS = 0L))
expect_equal(names(res$optimization_status), "SUCCESS")   # name survives the round-trip
expect_equal(res$optimization_status[[1L]], 0L)            # [[ ]] -> bare code
expect_equal(res$solution_status, c(FEASIBLE_KKT_POINT = 1L))
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
expect_equal(res_err$optimization_status, c(EVALUATION_ERROR = 3L))

## Everything below exercises the interior-point "ipopt" preset, whose KKT
## linear solver is MUMPS, reached at run time from 'rmumps' through the
## C-callables it registers (src/dmumps_shim.c: the versioned entry points of
## <rmumps/rmumps_api.h> with rmumps >= 5.2.1-44, else the legacy "dmumps_c").
## That registry resolves on every platform, INCLUDING Windows, so these tests
## run everywhere. (Before the R_GetCCallable fix the Windows build was
## HiGHS-only and skipped this whole section, because the old R_FindSymbol
## route could not see dmumps_c in rmumps.dll's export table. The regression
## block immediately below guards that fix on Windows.)

## @unopy NONE
## REGRESSION (MUMPS on Windows): an UNCONSTRAINED convex NLP under the "ipopt"
## preset. Uno routes an unconstrained problem to a pure-Newton method whose KKT
## system is factored by MUMPS, so this is the minimal shape that fails when
## dmumps_c resolution is broken -- exactly the solve that errored from CVXR's
## dnlp2smooth on Windows ("The linear solver MUMPS is unknown") before the shim
## switched from R_FindSymbol to R_GetCCallable. x* = (1, 2), f* = 0.
res_unc_ip <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj = obj, grad = grad,
  m = 0L, cl = numeric(), cu = numeric(), cons = function(x) numeric(),
  jac_rows = integer(), jac_cols = integer(), jac = function(x) numeric(),
  hess_rows = c(0L, 1L), hess_cols = c(0L, 1L), hess = hess,
  x0 = c(0, 0), preset = "ipopt", base_indexing = 0L, verbose = FALSE
)
expect_equal(res_unc_ip$optimization_status, c(SUCCESS = 0L))
expect_equal(res_unc_ip$solution_status, c(FEASIBLE_KKT_POINT = 1L))
expect_equal(res_unc_ip$objective, 0, tolerance = 1e-6)
expect_equal(res_unc_ip$primal, c(1, 2), tolerance = 1e-5)

## @unopy NONE
## R smoke test: the interior-point "ipopt" preset on the trivial convex NLP
## above (constrained form), also exercising the MUMPS linear-solver path.
## x* = (1, 2), f* = 0.
res_ip <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj = obj, grad = grad,
  m = 1L, cl = -Inf, cu = 10, cons = cons,
  jac_rows = c(0L, 0L), jac_cols = c(0L, 1L), jac = jac,
  hess_rows = c(0L, 1L), hess_cols = c(0L, 1L), hess = hess,
  x0 = c(0, 0), preset = "ipopt", base_indexing = 0L, verbose = FALSE
)
expect_equal(res_ip$optimization_status, c(SUCCESS = 0L))
expect_equal(res_ip$solution_status, c(FEASIBLE_KKT_POINT = 1L))
expect_equal(res_ip$objective, 0, tolerance = 1e-6)
expect_equal(res_ip$primal, c(1, 2), tolerance = 1e-5)

## @unopy NONE (reference: interfaces/Julia/test/check_auto_preset.jl, Uno 2.9.2)
## preset = "auto" (Uno 2.9.0, usable through the C API since 2.9.2): Uno picks
## the preset from the model size, uno/options/Presets.cpp pick_auto_preset():
## n + m >= 2000 or more than 50,000 Jacobian + Hessian nonzeros -> "ipopt",
## otherwise "filtersqp". The Julia test checks the choice through the method
## description ("SQP" for HS015); the R binding does not expose it, so the
## choice is read off Uno's log: the active-set branch allocates an
## "inequality-constrained (LP or QP) method" run by HiGHS, the barrier branch
## a "barrier method" run by MUMPS. (These strings are Uno's log text; update
## them with the bundled Uno if it rewords them.) The convex smoke problem is
## used because HS015 under the auto-selected filtersqp needs BQPD: in this
## HiGHS-only build it ends in ALGORITHMIC_ERROR on the indefinite subproblem.
auto_log <- character()
res_auto <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj = obj, grad = grad,
  m = 1L, cl = -Inf, cu = 10, cons = cons,
  jac_rows = c(0L, 0L), jac_cols = c(0L, 1L), jac = jac,
  hess_rows = c(0L, 1L), hess_cols = c(0L, 1L), hess = hess,
  x0 = c(0, 0), preset = "auto", base_indexing = 0L, verbose = FALSE,
  log_callback = function(s) { auto_log <<- c(auto_log, s); invisible(NULL) }
)
expect_equal(res_auto$optimization_status, c(SUCCESS = 0L))
expect_equal(res_auto$solution_status, c(FEASIBLE_KKT_POINT = 1L))
expect_equal(res_auto$objective, 0, tolerance = 1e-6)
expect_equal(res_auto$primal, c(1, 2), tolerance = 1e-5)
auto_text <- paste(auto_log, collapse = "")
expect_true(grepl("preset = auto", auto_text, fixed = TRUE))
expect_true(grepl("Optimization status:", auto_text, fixed = TRUE))   # log complete
expect_true(grepl("inequality-constrained (LP or QP) method", auto_text, fixed = TRUE))
expect_true(grepl("Running HiGHS", auto_text, fixed = TRUE))
expect_false(grepl("barrier method", auto_text, fixed = TRUE))

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
expect_equal(res_hs015$optimization_status, c(SUCCESS = 0L))
expect_equal(res_hs015$solution_status, c(FEASIBLE_KKT_POINT = 1L))
expect_equal(res_hs015$objective, 306.5, tolerance = 1e-4)  # example asserts <= 1e-4
expect_equal(res_hs015$primal, c(0.5, 2.0), tolerance = 1e-4)

## @unopy example_hs015.py (set_model_name)
## the optional model name is accepted (Uno >= 2.9.0) and does not change the solve
res_named <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(0.5, Inf), sense = "minimize",
  obj = hs015_obj, grad = hs015_grad,
  m = 2L, cl = c(1, 0), cu = c(Inf, Inf), cons = hs015_cons,
  jac_rows = c(0L, 1L, 0L, 1L), jac_cols = c(0L, 0L, 1L, 1L), jac = hs015_jac,
  hess_rows = c(0L, 1L, 1L), hess_cols = c(0L, 0L, 1L), hess = hs015_hess,
  x0 = c(-2, 1), preset = "ipopt", base_indexing = 0L, verbose = FALSE,
  name = "hs015"
)
expect_equal(res_named$objective, res_hs015$objective)
expect_error(uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(0.5, Inf), sense = "minimize",
  obj = hs015_obj, grad = hs015_grad,
  m = 2L, cl = c(1, 0), cu = c(Inf, Inf), cons = hs015_cons,
  jac_rows = c(0L, 1L, 0L, 1L), jac_cols = c(0L, 0L, 1L, 1L), jac = hs015_jac,
  hess_rows = c(0L, 1L, 1L), hess_cols = c(0L, 0L, 1L), hess = hs015_hess,
  x0 = c(-2, 1), preset = "ipopt", base_indexing = 0L, verbose = FALSE,
  name = c("a", "b")
), "single string")
## duals at the HS015 optimum. The example prints but does not assert them; the
## reference values are those of Uno's Julia test (interfaces/Julia/test/
## check_auto_preset.jl, 2.9.2): 700 for the active constraint x1*x2 >= 1, 0 for
## the inactive x1 + x2^2 >= 0, -1751 for the active upper bound x1 <= 0.5, with
## the default lagrangian_sign = "negative" (L = sigma*f - y^T c). The lower
## bounds are -Inf, so their multipliers are 0.
expect_equal(length(res_hs015$constraint_dual), 2L)
expect_equal(res_hs015$constraint_dual, c(700, 0), tolerance = 1e-4)
expect_equal(res_hs015$lower_bound_dual, c(0, 0), tolerance = 1e-4)
expect_equal(res_hs015$upper_bound_dual, c(-1751, 0), tolerance = 1e-4)

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
expect_equal(res_pos$optimization_status, c(SUCCESS = 0L))
expect_equal(res_pos$objective, 306.5, tolerance = 1e-4)
expect_equal(res_pos$primal, c(0.5, 2.0), tolerance = 1e-4)
## the multipliers come back in the convention the caller declared: the signs
## of the default-"negative" run above are flipped, the magnitudes are the same.
expect_equal(res_pos$constraint_dual, c(-700, 0), tolerance = 1e-4)
expect_equal(res_pos$upper_bound_dual, c(1751, 0), tolerance = 1e-4)

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
expect_equal(res_cb$optimization_status, c(SUCCESS = 0L))
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
expect_true(is.integer(res_term$optimization_status))
expect_false(is.null(names(res_term$optimization_status)))   # name preserved

## @unopy NONE
## C4 (regression): the iter_callback termination semantics must hold across a
## *multi-iteration* solve. The filtersqp smoke tests above converge in a single
## acceptable iterate, so check_termination returns at the already-optimal branch
## (Uno.cpp) before the user-termination callback ever governs anything -- they
## cannot catch an inverted termination test. Rosenbrock under the ipopt preset
## takes many iterations, so the callback's return value actually decides the
## solve. This guards the Uno_C_API.cpp fix (`!= 0`, not `== 0`): FALSE must run
## to SUCCESS over many callbacks, and TRUE must stop early as USER_TERMINATION.
ros_obj  <- function(x) (1 - x[1])^2 + 100 * (x[2] - x[1]^2)^2
ros_grad <- function(x) c(-2 * (1 - x[1]) - 400 * x[1] * (x[2] - x[1]^2),
                          200 * (x[2] - x[1]^2))
ros_hess <- function(x, sigma, lambda)
  sigma * c(2 - 400 * x[2] + 1200 * x[1]^2, -400 * x[1], 200)
ros_solve <- function(cb) uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj = ros_obj, grad = ros_grad,
  m = 0L, cl = numeric(), cu = numeric(), cons = function(x) numeric(),
  jac_rows = integer(), jac_cols = integer(), jac = function(x) numeric(),
  hess_rows = c(0L, 1L, 1L), hess_cols = c(0L, 0L, 1L), hess = ros_hess,
  x0 = c(-1.2, 1), preset = "ipopt", base_indexing = 0L, verbose = FALSE,
  iter_callback = cb
)
## FALSE -> runs to completion (fires on many acceptable iterates, converges)
ros_calls <- 0L
res_false <- ros_solve(function(info) { ros_calls <<- ros_calls + 1L; FALSE })
expect_true(ros_calls > 1L)                                  # multi-iteration
expect_equal(res_false$optimization_status, c(SUCCESS = 0L))
expect_equal(res_false$primal, c(1, 1), tolerance = 1e-4)
## TRUE on the 3rd acceptable iterate -> early stop, reported as USER_TERMINATION
stop_calls <- 0L
res_stop <- ros_solve(function(info) { stop_calls <<- stop_calls + 1L; stop_calls >= 3L })
expect_equal(stop_calls, 3L)
expect_equal(res_stop$optimization_status, c(USER_TERMINATION = 5L))

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
## the whole log arrives, exactly once. Uno's stream buffer treats a callback
## return value other than the chunk length as a failed flush: it re-sends the
## chunk at the next flush and drops everything after it (badbit). Before
## 2.9.2-1 the binding returned 0, so a log_callback saw the preamble twice and
## never the iteration table or the final summary.
log_text <- paste(unlist(log_chunks), collapse = "")
expect_equal(lengths(regmatches(log_text, gregexpr("User options:", log_text, fixed = TRUE))), 1L)
expect_true(grepl("Optimization status:", log_text, fixed = TRUE))   # the summary at the end
expect_true(grepl("Iterations:", log_text, fixed = TRUE))
