# Uno

We provide R bindings to [Uno](https://github.com/cvanaret/Uno)
(Unifying Nonlinear Optimization), a C++ solver for nonlinearly
constrained optimization, via Uno’s C API. The interface allows you to
describe a nonlinear program with R callbacks for objective, gradient,
constraints, Jacobian and Lagrangian Hessian and Uno solves it. This is
the R analog of the `unopy` Python binding, intended as the nonlinear
(DNLP) solver backend for [CVXR](https://github.com/cvxgrp/CVXR).

Two solver paths are provided:

- the **`filtersqp`** SQP preset, whose QP subproblems are solved by
  **HiGHS** (built from source with the package), and
- the **`ipopt`** interior-point preset, whose KKT systems are solved by
  **MUMPS**, reached at run time through the
  [rmumps](https://cran.r-project.org/package=rmumps) package.

## Installation

Install from CRAN as usual or from the repo via:

``` r

# install.packages("remotes")
remotes::install_github("bnaras/Uno")
```

A C++17 compiler and CMake (\>= 3.16) are required for source builds as
the package builds the underlying Uno and HiGHS from source. MUMPS comes
from the `rmumps` dependency, so there is no separate MUMPS
installation.

## Quick example

Hock–Schittkowski problem 15 (`x* = (0.5, 2)`, `f* = 306.5`), solved
with the interior-point preset. Derivatives are supplied in COO form
(0-based indices); the Hessian is the lower triangle of the Lagrangian.

``` r

library(Uno)

objective   <- function(x) 100 * (x[2] - x[1]^2)^2 + (1 - x[1])^2
gradient    <- function(x) c(400 * x[1]^3 - 400 * x[1] * x[2] + 2 * x[1] - 2,
                             200 * (x[2] - x[1]^2))
constraints <- function(x) c(x[1] * x[2], x[1] + x[2]^2)
jacobian    <- function(x) c(x[2], 1, x[1], 2 * x[2])
hessian     <- function(x, sigma, lambda)
  c(sigma * (1200 * x[1]^2 - 400 * x[2] + 2),
    -400 * sigma * x[1] - lambda[1],
    200 * sigma - 2 * lambda[2])

res <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(0.5, Inf), sense = "minimize",
  obj = objective, grad = gradient,
  m = 2L, cl = c(1, 0), cu = c(Inf, Inf), cons = constraints,
  jac_rows = c(0L, 1L, 0L, 1L), jac_cols = c(0L, 0L, 1L, 1L), jac = jacobian,
  hess_rows = c(0L, 1L, 1L), hess_cols = c(0L, 0L, 1L), hess = hessian,
  x0 = c(-2, 1), preset = "ipopt", base_indexing = 0L, verbose = FALSE,
  options = list(logger = "SILENT")
)

res$objective   # 306.5
res$primal      # 0.5 2
```

Any Uno solver option can be passed through `options` as a named list
(applied after the preset). See
[`vignette("Uno")`](https://bnaras.github.io/Uno/articles/Uno.md) for
the full walk-through.

## Citation

If you use this package, please cite both the R package and the paper
describing the Uno solver. Run `citation("Uno")` for the up-to-date
entries, or:

> Narasimhan B, Vanaret C, Leyffer S (2026). *Uno: R Interface to the
> Uno Nonlinear Optimization Solver*. R package.
> <https://github.com/bnaras/Uno>.
>
> Vanaret C, Leyffer S (2024). *Implementing a unified solver for
> nonlinearly constrained optimization.* arXiv:2406.13454.
> <https://doi.org/10.48550/arXiv.2406.13454>.

## License

MIT. Uno is by Charlie Vanaret and Sven Leyffer.
