# Solve a nonlinear program with Uno

Solve a nonlinear program with Uno

## Usage

``` r
uno_solve(
  n,
  lb,
  ub,
  sense,
  obj,
  grad,
  m,
  cl,
  cu,
  cons,
  jac_rows,
  jac_cols,
  jac,
  hess_rows,
  hess_cols,
  hess,
  x0,
  preset,
  base_indexing,
  verbose,
  options = list()
)
```

## Arguments

- n:

  number of variables.

- lb, ub:

  variable lower/upper bounds (length \`n\`; use \`-Inf\`/\`Inf\`).

- sense:

  \`"minimize"\` or \`"maximize"\`.

- obj, grad:

  objective \`function(x)\` and its gradient \`function(x)\`.

- m:

  number of constraints (0 for unconstrained).

- cl, cu:

  constraint lower/upper bounds (length \`m\`).

- cons:

  constraint \`function(x)\` returning a length-\`m\` vector.

- jac_rows, jac_cols:

  COO row/column indices of the Jacobian nonzeros.

- jac:

  Jacobian \`function(x)\` returning the nonzero values.

- hess_rows, hess_cols:

  COO indices of the lower-triangular Hessian.

- hess:

  Lagrangian Hessian \`function(x, sigma, lambda)\` returning the
  lower-triangular nonzero values, or \`NULL\` (Uno then uses an L-BFGS
  approximation, which the HiGHS subproblem solver cannot use).

- x0:

  initial primal iterate (length \`n\`).

- preset:

  Uno preset, e.g. \`"filtersqp"\` (SQP) or \`"ipopt"\` (interior point,
  using MUMPS as the linear solver).

- base_indexing:

  0 for C-style or 1 for Fortran-style COO indices.

- verbose:

  if \`FALSE\`, suppress Uno's solution printout.

- options:

  a named list of Uno solver options applied AFTER the preset (so they
  override it), e.g. \`list(max_iterations = 200L, tolerance = 1e-8,
  linear_solver = "MUMPS")\`. Each value is coerced to the option's
  declared Uno type; an unknown option name or an unacceptable value
  raises an error.

## Value

a named list with the optimization/solution status, objective, primal
and dual solutions, KKT residuals, and per-callback evaluation counters.
