# Uno: R interface to the Uno nonlinear optimization solver

R bindings to [Uno](https://github.com/cvanaret/Uno) (Unifying Nonlinear
Optimization), a C++ solver for nonlinearly constrained optimization,
via Uno's C API. The HiGHS QP/LP subproblem solver is built from source
for the SQP presets; the MUMPS linear solver used by the interior-point
preset is reached at runtime through the rmumps package. Intended as a
nonlinear (DNLP) backend for CVXR; this is the R analog of the `unopy`
Python package.

## See also

[`uno_solve`](https://bnaras.github.io/Uno/reference/uno_solve.md) to
solve a nonlinear program,
[`uno_version`](https://bnaras.github.io/Uno/reference/uno_version.md)
for the linked Uno version.

## Author

**Maintainer**: Balasubramanian Narasimhan <naras@stanford.edu>

Authors:

- Charlie Vanaret (Designed and implemented Uno) \[copyright holder\]

- Sven Leyffer (Co-developed the Uno framework) \[copyright holder\]
