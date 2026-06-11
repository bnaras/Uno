# Solving nonlinear programs with Uno

## Introduction

**Uno** wraps the [Uno](https://github.com/cvanaret/Uno) C++ solver
(Unifying Nonlinear Optimization) through its C API. One describes a
nonlinear program with R callbacks — objective, gradient, constraints,
constraint Jacobian, and Lagrangian Hessian — and Uno solves it. The
package is the R analog of the `unopy` Python binding, and is intended
as the nonlinear (DNLP) solver backend for
[CVXR](https://cvxr.rbind.io).

``` r

uno_version()
#> [1] "2.7.4"
```

Two solver paths are available, selected with the `preset` argument:

- **`ipopt`** — an interior-point method whose symmetric-indefinite KKT
  systems are factored by **MUMPS**, reached at run time through the
  [rmumps](https://cran.r-project.org/package=rmumps) package. It
  handles indefiniteness (nonconvex problems) through inertia
  correction.
- **`filtersqp`** — a filter SQP method whose QP subproblems are solved
  by **HiGHS** (built from source with this package). HiGHS solves
  *convex* QPs, so this preset is the right choice for convex problems.

We provide some examples to illustrate how the **callbacks** and their
**sparsity structures** fit together.

## Problem Description

Uno minimizes (or maximizes) a smooth objective subject to smooth
constraints and bounds,

``` math
\begin{aligned}
\min_{x \in \mathbb{R}^n} \quad & f(x) \\
\text{subject to} \quad & c^{\mathrm{L}} \le c(x) \le c^{\mathrm{U}}, \\
                        & x^{\mathrm{L}} \le x \le x^{\mathrm{U}},
\end{aligned}
```

where bounds may be infinite. As with most NLP solvers, the *type* of
each constraint is encoded entirely in its bounds: an equality sets the
lower and upper bound equal, and a one-sided inequality leaves the open
side infinite.

## Anatomy of `uno_solve()`

``` r

uno_solve(
  n, lb, ub, sense,                 # variables, bounds, minimize/maximize
  obj, grad,                        # objective f and its gradient
  m, cl, cu, cons,                  # constraints c and their bounds
  jac_rows, jac_cols, jac,          # constraint Jacobian (COO form)
  hess_rows, hess_cols, hess,       # Lagrangian Hessian (lower triangle, COO)
  x0, preset, base_indexing, verbose,
  options = list(),                 # Uno options, applied after the preset
  lagrangian_sign = "negative",     # sign convention of the Hessian you return
  ...
)
```

### Variables, bounds, and sense

`n` is the number of variables; `lb`/`ub` are length-`n` bound vectors
(use `-Inf`/`Inf` for free, and `lb[i] == ub[i]` to fix a variable).
`sense` is `"minimize"` or `"maximize"`.

``` r

# maximize -(x - 3)^2 on [0, 10]  ->  x = 3
mx <- uno_solve(
  n = 1L, lb = 0, ub = 10, sense = "maximize",
  obj  = function(x) -(x[1] - 3)^2,
  grad = function(x) -2 * (x[1] - 3),
  m = 0L, cl = numeric(), cu = numeric(), cons = function(x) numeric(),
  jac_rows = integer(), jac_cols = integer(), jac = function(x) numeric(),
  hess_rows = 1L, hess_cols = 1L, hess = function(x, sigma, lambda) sigma * (-2),
  x0 = 0, preset = "ipopt", base_indexing = 1L, verbose = FALSE,
  options = list(logger = "SILENT")
)
mx$primal
#> [1] 3
```

### Objective and gradient

`obj(x)` returns the scalar $`f(x)`$; `grad(x)` returns the **dense**
length-`n` gradient $`\nabla f(x)`$ (all `n` partials in variable order,
including zeros).

### Constraints and their bounds

`m` is the number of constraints (`0` for an unconstrained problem, in
which case the constraint and Jacobian callbacks return empty vectors).
`cons(x)` returns the length-`m` vector $`c(x)`$, and `cl`/`cu` are its
bounds:

| Constraint             |  `cl`  | `cu`  |
|------------------------|:------:|:-----:|
| $`c_j(x) = b`$         |  `b`   |  `b`  |
| $`c_j(x) \ge a`$       |  `a`   | `Inf` |
| $`c_j(x) \le d`$       | `-Inf` |  `d`  |
| $`a \le c_j(x) \le d`$ |  `a`   |  `d`  |

### The constraint Jacobian (COO form)

The Jacobian $`J_{jk} = \partial c_j/\partial x_k`$ is supplied in
**coordinate (COO) form**: you declare its sparsity pattern *once* as
parallel `jac_rows`/`jac_cols` index vectors, and `jac(x)` returns just
the nonzero *values* in that same order.

The index vectors must be **integer** (`1L`, `2L`, …, or wrapped with
[`as.integer()`](https://rdrr.io/r/base/integer.html)), and their base
is controlled by `base_indexing`:

- `base_indexing = 1L` — Fortran/R-style **one-based** indices (used
  throughout this vignette);
- `base_indexing = 0L` — C-style **zero-based** indices.

The base declared must match the indices you actually provided in
`jac_rows`/`jac_cols` (and `hess_rows`/`hess_cols`).

### The Lagrangian Hessian (lower triangle)

Like most interior-point/SQP solvers, Uno does not use the Hessian of
the objective, rather the Hessian of the **Lagrangian**, supplied as the
**lower triangle** in COO form (`hess_rows`/`hess_cols` with
`row >= col`). The callback receives the objective scale `sigma`
($`\sigma`$) and the constraint multipliers `lambda`:

``` r

hess <- function(x, sigma, lambda) ...   # lower-triangular nonzero values
```

The one subtlety unique to Uno is the **sign convention**. By default
Uno uses

``` math
\nabla^2_{xx} L = \sigma\, \nabla^2 f(x) \;-\; \sum_j \lambda_j\, \nabla^2 c_j(x)
\qquad (\texttt{lagrangian\_sign = "negative"}),
```

so the constraint-Hessian terms are **subtracted**. If your derivations
instead produce the IPOPT/`sparsediff` convention

``` math
\nabla^2_{xx} L = \sigma\, \nabla^2 f(x) \;+\; \sum_j \lambda_j\, \nabla^2 c_j(x)
\qquad (\texttt{lagrangian\_sign = "positive"}),
```

pass `lagrangian_sign = "positive"` so the terms get the right sign.
**The convention you pass must match the convention your `hess`
returns.** When all constraints are *linear* their Hessians vanish and
the choice is irrelevant.

### Options and the return value

`options` is a named list of Uno options applied *after* the preset (so
they override it); each value is coerced to the option’s declared type,
and an unknown name or unacceptable value raises an error. We use
`list(logger = "SILENT")` below to keep Uno quiet.

[`uno_solve()`](https://bnaras.github.io/Uno/reference/uno_solve.md)
returns a named list. The `optimization_status` and `solution_status`
are **named integers** of the form `c(SUCCESS = 0L)` — the value is
Uno’s enum code and the name its canonical label — so you can key a
status map on `names(status)` and still read the bare code with
`status[[1L]]`. The list also carries `objective`, `primal`, the dual
solution (`constraint_dual`, `lower_bound_dual`, `upper_bound_dual`),
KKT residuals, and per-callback evaluation counters.

``` r

quiet <- list(logger = "SILENT")
```

## Example 1: HS071 — the full machinery

The Hock–Schittkowski problem \#71 exercises everything at once: a
nonlinear objective, one nonlinear inequality, one nonlinear equality,
and bounds.

``` math
\begin{aligned}
\min_{x \in \mathbb{R}^4} \quad & x_1 x_4 (x_1 + x_2 + x_3) + x_3 \\
\text{s.t.}\quad & x_1 x_2 x_3 x_4 \ge 25, \\
                 & x_1^2 + x_2^2 + x_3^2 + x_4^2 = 40, \\
                 & 1 \le x_i \le 5.
\end{aligned}
```

Both constraints depend on every variable, so the Jacobian is dense (8
nonzeros). The Lagrangian Hessian is a full symmetric $`4\times4`$
matrix; its lower triangle has 10 nonzeros. We write the Hessian in the
**positive** convention (matching, e.g., the `ipopt` package’s
vignette).

``` r

hs071 <- uno_solve(
  n = 4L, lb = rep(1, 4), ub = rep(5, 4), sense = "minimize",

  obj  = function(x) x[1] * x[4] * (x[1] + x[2] + x[3]) + x[3],
  grad = function(x) c(
    x[4] * (2 * x[1] + x[2] + x[3]),
    x[1] * x[4],
    x[1] * x[4] + 1,
    x[1] * (x[1] + x[2] + x[3])
  ),

  m = 2L, cl = c(25, 40), cu = c(Inf, 40),   # g1 >= 25 ; g2 == 40
  cons = function(x) c(prod(x), sum(x^2)),

  # dense 2 x 4 Jacobian, one-based COO
  jac_rows = rep(1:2, each = 4L),
  jac_cols = rep(1:4, times = 2L),
  jac = function(x) c(
    x[2] * x[3] * x[4], x[1] * x[3] * x[4], x[1] * x[2] * x[4], x[1] * x[2] * x[3],
    2 * x[1], 2 * x[2], 2 * x[3], 2 * x[4]
  ),

  # lower triangle of the 4 x 4 Lagrangian Hessian, row by row
  hess_rows = as.integer(c(1, 2, 2, 3, 3, 3, 4, 4, 4, 4)),
  hess_cols = as.integer(c(1, 1, 2, 1, 2, 3, 1, 2, 3, 4)),
  hess = function(x, sigma, lambda) {
    l1 <- lambda[1]; l2 <- lambda[2]
    c(
      sigma * (2 * x[4])                  + l2 * 2,        # (1,1)
      sigma * x[4]            + l1 * (x[3] * x[4]),        # (2,1)
      l2 * 2,                                             # (2,2)
      sigma * x[4]            + l1 * (x[2] * x[4]),        # (3,1)
      l1 * (x[1] * x[4]),                                 # (3,2)
      l2 * 2,                                             # (3,3)
      sigma * (2 * x[1] + x[2] + x[3]) + l1 * (x[2] * x[3]),  # (4,1)
      sigma * x[1]            + l1 * (x[1] * x[3]),        # (4,2)
      sigma * x[1]            + l1 * (x[1] * x[2]),        # (4,3)
      l2 * 2                                              # (4,4)
    )
  },

  x0 = c(1, 5, 5, 1), preset = "ipopt", base_indexing = 1L, verbose = FALSE,
  options = quiet, lagrangian_sign = "positive"
)

names(hs071$optimization_status)
#> [1] "SUCCESS"
hs071$objective                    # 17.014
#> [1] 17.01402
hs071$primal                       # (1, 4.743, 3.821, 1.379)
#> [1] 1.000000 4.743000 3.821150 1.379408
hs071$constraint_dual
#> [1] -0.5522937  0.1614686
```

## Example 2: HS015 — nonconvex, the default (negative) convention

HS015 is nonconvex, which makes it a good illustration of two things:
the **default** Lagrangian sign convention, and *why nonconvex problems
need the interior-point preset*.

``` math
\min_{x}\; 100\,(x_2 - x_1^2)^2 + (1 - x_1)^2
\quad\text{s.t.}\quad x_1 x_2 \ge 1,\; x_1 + x_2^2 \ge 0,\; x_1 \le 0.5 .
```

The constraints are nonlinear, so here the sign convention matters. We
leave `lagrangian_sign` at its default `"negative"` and therefore
**subtract** the `lambda` terms in the Hessian.

``` r

hs015 <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(0.5, Inf), sense = "minimize",

  obj  = function(x) 100 * (x[2] - x[1]^2)^2 + (1 - x[1])^2,
  grad = function(x) c(
    400 * x[1]^3 - 400 * x[1] * x[2] + 2 * x[1] - 2,
    200 * (x[2] - x[1]^2)
  ),

  m = 2L, cl = c(1, 0), cu = c(Inf, Inf),
  cons = function(x) c(x[1] * x[2], x[1] + x[2]^2),

  jac_rows = as.integer(c(1, 2, 1, 2)),
  jac_cols = as.integer(c(1, 1, 2, 2)),
  jac = function(x) c(x[2], 1, x[1], 2 * x[2]),

  hess_rows = as.integer(c(1, 2, 2)),
  hess_cols = as.integer(c(1, 1, 2)),
  hess = function(x, sigma, lambda) c(
    sigma * (1200 * x[1]^2 - 400 * x[2] + 2),   # (1,1): from the objective
    -400 * sigma * x[1] - lambda[1],            # (2,1): note the minus signs
    200 * sigma - 2 * lambda[2]                 # (2,2)
  ),

  x0 = c(-2, 1), preset = "ipopt", base_indexing = 1L, verbose = FALSE,
  options = quiet                                # lagrangian_sign = "negative" (default)
)

names(hs015$optimization_status)
#> [1] "SUCCESS"
hs015$objective                    # 306.5
#> [1] 306.5
hs015$primal                       # (0.5, 2)
#> [1] 0.5 2.0
```

## Example 3: Rosenbrock — unconstrained, with and without a Hessian

The Rosenbrock “banana” function is the classic unconstrained test
problem, with global minimum $`0`$ at $`(1, 1)`$. With no constraints
(`m = 0`) there is no Jacobian, and the Lagrangian Hessian reduces to
$`\sigma \nabla^2 f`$ (so `lambda` is unused).

``` r

rosen <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",

  obj  = function(x) (1 - x[1])^2 + 100 * (x[2] - x[1]^2)^2,
  grad = function(x) c(
    -2 * (1 - x[1]) - 400 * x[1] * (x[2] - x[1]^2),
    200 * (x[2] - x[1]^2)
  ),

  m = 0L, cl = numeric(), cu = numeric(), cons = function(x) numeric(),
  jac_rows = integer(), jac_cols = integer(), jac = function(x) numeric(),

  hess_rows = as.integer(c(1, 2, 2)),
  hess_cols = as.integer(c(1, 1, 2)),
  hess = function(x, sigma, lambda) sigma * c(
    2 - 400 * x[2] + 1200 * x[1]^2,   # (1,1)
    -400 * x[1],                      # (2,1)
    200                               # (2,2)
  ),

  x0 = c(-1.2, 1), preset = "ipopt", base_indexing = 1L, verbose = FALSE,
  options = quiet
)
rosen$primal
#> [1] 1 1
```

If coding an exact Hessian is inconvenient, pass `hess = NULL` (with
empty `hess_rows`/`hess_cols`); Uno then builds an L-BFGS approximation
from gradients. This is only available with the **`ipopt`** preset — the
HiGHS QP solver behind `filtersqp` requires an explicit Hessian.

``` r

rosen_lm <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj  = function(x) (1 - x[1])^2 + 100 * (x[2] - x[1]^2)^2,
  grad = function(x) c(
    -2 * (1 - x[1]) - 400 * x[1] * (x[2] - x[1]^2),
    200 * (x[2] - x[1]^2)
  ),
  m = 0L, cl = numeric(), cu = numeric(), cons = function(x) numeric(),
  jac_rows = integer(), jac_cols = integer(), jac = function(x) numeric(),
  hess_rows = integer(), hess_cols = integer(), hess = NULL,
  x0 = c(-1.2, 1), preset = "ipopt", base_indexing = 1L, verbose = FALSE,
  options = quiet
)
rosen_lm$primal
#> [1] 1 1
```

## Example 4: Maximum-entropy distribution — equality constraints

This example is a staple of statistics and information-theory courses:
among all probability distributions $`p`$ on $`\{1, \dots, K\}`$ with a
prescribed mean $`\mu`$, find the one of maximum entropy. Equivalently,
minimize the negative entropy $`\sum_i p_i \log p_i`$ subject to
$`\sum_i
p_i = 1`$ and $`\sum_i i\,p_i = \mu`$, $`p_i \ge 0`$.

Both constraints are **linear**, so their Hessians vanish — the
Lagrangian Hessian is just $`\sigma\,\mathrm{diag}(1/p_i)`$, a diagonal
matrix, and the sign convention is irrelevant.

``` r

K <- 5L; support <- 1:K; mu <- 2

ent <- uno_solve(
  n = K, lb = rep(1e-8, K), ub = rep(1, K), sense = "minimize",   # p_i > 0

  obj  = function(p) sum(p * log(p)),
  grad = function(p) log(p) + 1,

  m = 2L, cl = c(1, mu), cu = c(1, mu),                # two equalities
  cons = function(p) c(sum(p), sum(support * p)),
  jac_rows = rep(1:2, each = K),
  jac_cols = rep(seq_len(K), times = 2L),
  jac = function(p) c(rep(1, K), support),             # constant Jacobian

  hess_rows = seq_len(K), hess_cols = seq_len(K),      # diagonal only
  hess = function(p, sigma, lambda) sigma * (1 / p),

  x0 = rep(1 / K, K), preset = "ipopt", base_indexing = 1L, verbose = FALSE,
  options = quiet
)

round(ent$primal, 5)
#> [1] 0.45936 0.26079 0.14806 0.08406 0.04772
c(total = sum(ent$primal), mean = sum(support * ent$primal))
#> total  mean 
#>     1     2
```

Maximum-entropy theory says the answer is a discrete exponential
distribution $`p_i \propto e^{-\theta i}`$, with $`\theta`$ the
multiplier on the mean constraint — and `constraint_dual` recovers
exactly that:

``` r

theta <- ent$constraint_dual[2]
cf <- exp(-theta * support); cf <- cf / sum(cf)
round(cf, 5)                       # matches ent$primal
#> [1] 0.04772 0.08406 0.14806 0.26079 0.45936
```

## Example 5: a convex QP via the SQP (HiGHS) preset

The examples above all use the interior-point `ipopt` preset because
they are either nonconvex (HS015, Rosenbrock) or just convenient to
solve that way. For a **convex** problem the SQP preset `filtersqp`,
backed by HiGHS, applies. Here is a small convex QP,
$`\min (x_1-1)^2 + (x_2-2.5)^2`$ subject to $`x_1 + x_2 \le 3`$,
$`x \ge 0`$:

``` r

qp <- uno_solve(
  n = 2L, lb = c(0, 0), ub = c(Inf, Inf), sense = "minimize",
  obj  = function(x) (x[1] - 1)^2 + (x[2] - 2.5)^2,
  grad = function(x) c(2 * (x[1] - 1), 2 * (x[2] - 2.5)),
  m = 1L, cl = -Inf, cu = 3,
  cons = function(x) x[1] + x[2],
  jac_rows = as.integer(c(1, 1)), jac_cols = as.integer(c(1, 2)),
  jac = function(x) c(1, 1),
  hess_rows = as.integer(c(1, 2)), hess_cols = as.integer(c(1, 2)),
  hess = function(x, sigma, lambda) sigma * c(2, 2),
  x0 = c(0, 0), preset = "filtersqp", base_indexing = 1L, verbose = FALSE,
  options = quiet
)
qp$primal
#> [1] 0.75 2.25
qp$objective
#> [1] 0.125
```

## Choosing a preset

- **Convex** problems — including the smooth problems produced by CVXR’s
  DNLP reduction — work with either preset. `filtersqp` (HiGHS) is
  natural for convex QP-shaped subproblems; `ipopt` (MUMPS) also works.
  `filtersqp` always requires an explicit Hessian (HiGHS cannot use an
  L-BFGS approximation).
- **Nonconvex** problems (HS015, Rosenbrock) produce indefinite
  subproblems that HiGHS cannot solve. Use the interior-point `ipopt`
  preset, which copes with indefiniteness through inertia correction in
  MUMPS.

## Solver options

Any Uno option can be passed through `options`; values are coerced to
the option’s declared type and applied after the preset:

``` r

# cap the iteration count and tighten the tolerance
uno_solve(..., preset = "ipopt",
          options = list(max_iterations = 200L, tolerance = 1e-8))

# pick the linear solver explicitly, and silence output
uno_solve(..., preset = "ipopt",
          options = list(linear_solver = "MUMPS", logger = "SILENT"))
```

An unknown option name, or a value the option rejects, raises an error
rather than being silently ignored.

## Monitoring and early termination

[`uno_solve()`](https://bnaras.github.io/Uno/reference/uno_solve.md)
accepts an optional `iter_callback`, a `function(info)` that Uno calls
at each *acceptable iterate*. `info` is a named list carrying the
current `primals`, the duals (`lower_bound_dual`, `upper_bound_dual`,
`constraint_dual`), the `objective_multiplier`, and the KKT residuals
(`primal_feasibility`, `stationarity`, `complementarity`). The
callback’s return value controls the solve: return `FALSE` to continue,
or `TRUE` to **stop early** — in which case the `optimization_status` is
`USER_TERMINATION`.

Used as a pure monitor (always returning `FALSE`), it lets you watch
convergence. Here we record the stationarity residual at each iterate of
the Rosenbrock solve:

``` r

ros_obj  <- function(x) (1 - x[1])^2 + 100 * (x[2] - x[1]^2)^2
ros_grad <- function(x) c(-2 * (1 - x[1]) - 400 * x[1] * (x[2] - x[1]^2),
                          200 * (x[2] - x[1]^2))
ros_hess <- function(x, sigma, lambda)
  sigma * c(2 - 400 * x[2] + 1200 * x[1]^2, -400 * x[1], 200)

stationarity <- numeric(0)
mon <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj = ros_obj, grad = ros_grad,
  m = 0L, cl = numeric(), cu = numeric(), cons = function(x) numeric(),
  jac_rows = integer(), jac_cols = integer(), jac = function(x) numeric(),
  hess_rows = as.integer(c(1, 2, 2)), hess_cols = as.integer(c(1, 1, 2)), hess = ros_hess,
  x0 = c(-1.2, 1), preset = "ipopt", base_indexing = 1L, verbose = FALSE, options = quiet,
  iter_callback = function(info) {
    stationarity[[length(stationarity) + 1L]] <<- info$stationarity
    FALSE                                            # keep going
  }
)
names(mon$optimization_status)
#> [1] "SUCCESS"
length(stationarity)                                 # one entry per acceptable iterate
#> [1] 21
signif(range(stationarity), 3)                       # residual shrinks toward 0
#> [1] 3.73e-10 2.60e+01
```

Returning `TRUE` stops the solve. For example, to bail out after five
acceptable iterates — note the super-assignment `<<-`, needed so the
counter persists across calls rather than writing a local copy:

``` r

iter <- 0L
stopped <- uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj = ros_obj, grad = ros_grad,
  m = 0L, cl = numeric(), cu = numeric(), cons = function(x) numeric(),
  jac_rows = integer(), jac_cols = integer(), jac = function(x) numeric(),
  hess_rows = as.integer(c(1, 2, 2)), hess_cols = as.integer(c(1, 1, 2)), hess = ros_hess,
  x0 = c(-1.2, 1), preset = "ipopt", base_indexing = 1L, verbose = FALSE, options = quiet,
  iter_callback = function(info) { iter <<- iter + 1L; iter >= 5L }
)
iter                                 # stopped after the 5th acceptable iterate
#> [1] 5
names(stopped$optimization_status)   # "USER_TERMINATION"
#> [1] "USER_TERMINATION"
```

An error thrown inside the callback is caught and treated as “do not
terminate,” so a buggy monitor cannot crash the solve.

## Additional Notes

- Errors thrown inside a callback are caught and reported back to Uno as
  an evaluation error — they will not crash the R session. If this
  happens, please report the bug with a reproducible example.
- [`uno_solve()`](https://bnaras.github.io/Uno/reference/uno_solve.md)
  also accepts a `log_callback` (a sink for Uno’s output stream); see
  [`?uno_solve`](https://bnaras.github.io/Uno/reference/uno_solve.md)
  for the full argument list.
