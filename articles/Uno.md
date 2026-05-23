# Solving nonlinear programs with Uno

## What this package is

**Uno** wraps the [Uno](https://github.com/cvanaret/Uno) C++ solver
(Unifying Nonlinear Optimization) through its C API. You describe a
nonlinear program with R callbacks — objective, gradient, constraints,
Jacobian and Lagrangian Hessian — and Uno solves it. The package is the
R analog of the `unopy` Python binding, and is intended as the nonlinear
(DNLP) solver backend for **CVXR**.

Two solver paths are available out of the box:

- the **`filtersqp`** SQP preset, whose QP subproblems are solved by
  **HiGHS** (built from source with the package); and
- the **`ipopt`** interior-point preset, whose symmetric-indefinite KKT
  systems are solved by **MUMPS**, reached at run time through the
  [rmumps](https://cran.r-project.org/package=rmumps) package.

``` r

library(Uno)
uno_version()
#> [1] "2.7.2"
```

## A worked example: HS015

We solve Hock–Schittkowski problem 15, the canonical test used by Uno’s
own example:
``` math
\min_{x}\; 100\,(x_2 - x_1^2)^2 + (1 - x_1)^2
\quad\text{s.t.}\quad x_1 x_2 \ge 1,\; x_1 + x_2^2 \ge 0,\; x_1 \le 0.5 .
```
Its solution is $`x^\star = (0.5,\,2)`$ with objective $`306.5`$.

### Defining the callbacks

The Jacobian and Hessian are supplied in **COO (coordinate) form**: you
give the sparsity pattern as row/column index vectors once, and a
callback that returns the nonzero *values* at a point. Indices here are
0-based (`base_indexing = 0L`). The Hessian is the **lower triangle** of
the Lagrangian $`\sigma\,\nabla^2 f + \sum_i \lambda_i \nabla^2 c_i`$.

``` r

objective <- function(x) 100 * (x[2] - x[1]^2)^2 + (1 - x[1])^2
gradient  <- function(x) c(400 * x[1]^3 - 400 * x[1] * x[2] + 2 * x[1] - 2,
                           200 * (x[2] - x[1]^2))
constraints <- function(x) c(x[1] * x[2], x[1] + x[2]^2)

# Jacobian nonzeros at (rows, cols) = {(0,0),(1,0),(0,1),(1,1)} (0-based)
jacobian <- function(x) c(x[2], 1, x[1], 2 * x[2])

# lower-triangular Lagrangian Hessian nonzeros at {(0,0),(1,0),(1,1)}
hessian <- function(x, sigma, lambda)
  c(sigma * (1200 * x[1]^2 - 400 * x[2] + 2),
    -400 * sigma * x[1] - lambda[1],
    200 * sigma - 2 * lambda[2])
```

### Solving with the interior-point preset

The `ipopt` preset uses MUMPS as its linear solver. We pass
`options = list(logger = "SILENT")` to keep Uno quiet (see *Solver
options* below).

``` r

res <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(0.5, Inf), sense = "minimize",
  obj = objective, grad = gradient,
  m = 2L, cl = c(1, 0), cu = c(Inf, Inf), cons = constraints,
  jac_rows = c(0L, 1L, 0L, 1L), jac_cols = c(0L, 0L, 1L, 1L), jac = jacobian,
  hess_rows = c(0L, 1L, 1L), hess_cols = c(0L, 0L, 1L), hess = hessian,
  x0 = c(-2, 1), preset = "ipopt", base_indexing = 0L, verbose = FALSE,
  options = list(logger = "SILENT")
)

res$optimization_status   # 0 = success
#> [1] 0
res$objective             # 306.5
#> [1] 306.5
res$primal                # (0.5, 2)
#> [1] 0.5 2.0
```

The result also carries the dual solution and a set of diagnostic
counters:

``` r

res$constraint_dual
#> [1] 7.000000e+02 5.568458e-10
res$iterations
#> [1] 18
res$objective_evaluations
#> [1] 22
res$cpu_time
#> [1] 0.02268
```

## Solver options

Beyond `preset`, any Uno solver option can be passed through `options`
as a named list; values are coerced to each option’s declared type, and
the options are applied *after* the preset so they override it. A few
useful ones:

``` r

# cap the iteration count
uno_solve(..., preset = "ipopt", options = list(max_iterations = 50L))

# pick the linear solver explicitly, and silence output
uno_solve(..., preset = "ipopt",
          options = list(linear_solver = "MUMPS", logger = "SILENT"))
```

An unknown option name, or a value the option rejects, raises an error
rather than being silently ignored.

## Choosing a preset

- For **convex** problems — such as the smooth problems produced by
  CVXR’s DNLP reduction — `filtersqp` (HiGHS) and `ipopt` (MUMPS) both
  work, and an explicit Hessian must be supplied (HiGHS cannot use an
  L-BFGS approximation).
- For **nonconvex** problems like HS015, the SQP subproblems are
  indefinite; HiGHS cannot solve those, so use the interior-point
  `ipopt` preset (which handles indefiniteness through inertia
  correction in MUMPS), as above.

## Notes

- MUMPS is provided at run time by the `rmumps` package (a hard
  dependency); no separate MUMPS installation is needed.
- Errors thrown inside a callback are caught and reported back to Uno as
  an evaluation error — they will not crash the R session.
