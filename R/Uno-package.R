#' Uno: R interface to the Uno nonlinear optimization solver
#'
#' R bindings to \href{https://github.com/cvanaret/Uno}{Uno} (Unifying Nonlinear
#' Optimization), a C++ solver for nonlinearly constrained optimization, via
#' Uno's C API. The HiGHS QP/LP subproblem solver is built from source for the
#' SQP presets; the MUMPS linear solver used by the interior-point preset is
#' reached at run time through the \pkg{rmumps} package (bound when the
#' namespace loads; see \code{\link{uno_mumps_version}}). Intended as a
#' nonlinear (DNLP) backend for \pkg{CVXR}; this is the R analog of the
#' \code{unopy} Python package.
#'
#' @seealso \code{\link{uno_solve}} to solve a nonlinear program,
#'   \code{\link{uno_version}} for the linked Uno version,
#'   \code{\link{uno_options}} and \code{\link{uno_status_labels}} for what the
#'   linked Uno accepts and returns.
#' @keywords internal
"_PACKAGE"

#' Linked Uno version
#'
#' Returns the version string of the Uno C++ library this package is built
#' against.
#'
#' @return A character scalar, e.g. \code{"2.9.2"}.
#' @examples
#' uno_version()
#' @name uno_version
NULL
