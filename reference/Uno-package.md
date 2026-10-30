# Uno: R interface to the Uno nonlinear optimization solver

R bindings to [Uno](https://github.com/cvanaret/Uno) (Unifying Nonlinear
Optimization), a C++ solver for nonlinearly constrained optimization,
via Uno's C API. The HiGHS QP/LP subproblem solver is built from source
for the SQP presets; the MUMPS linear solver used by the interior-point
preset is reached at run time through the rmumps package (bound when the
namespace loads; see
[`uno_mumps_version`](https://bnaras.github.io/Uno/reference/uno_mumps_version.md)).
Intended as a nonlinear (DNLP) backend for CVXR; this is the R analog of
the `unopy` Python package.

## See also

[`uno_solve`](https://bnaras.github.io/Uno/reference/uno_solve.md) to
solve a nonlinear program,
[`uno_version`](https://bnaras.github.io/Uno/reference/uno_version.md)
for the linked Uno version,
[`uno_options`](https://bnaras.github.io/Uno/reference/uno_options.md)
and
[`uno_status_labels`](https://bnaras.github.io/Uno/reference/uno_status_labels.md)
for what the linked Uno accepts and returns.

## Author

**Maintainer**: Balasubramanian Narasimhan <naras@stanford.edu>

Authors:

- Balasubramanian Narasimhan <naras@stanford.edu>

- Charlie Vanaret (Designed and implemented Uno) \[copyright holder\]

- Sven Leyffer (Co-developed the Uno framework) \[copyright holder\]

Other contributors:

- HiGHS development team (Bundled HiGHS LP/QP/MIP solver (MIT); see
  inst/COPYRIGHTS) \[copyright holder\]
