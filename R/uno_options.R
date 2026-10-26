# Introspection of the linked Uno: its options, status labels and the MUMPS it
# reaches through rmumps. The cpp11 entry points are in src/uno_binding.cpp.

#' Uno solver options
#'
#' Every option the linked Uno accepts in the `options` argument of
#' [uno_solve()], with its declared type (`"integer"`, `"double"`, `"bool"` or
#' `"string"`), as read from Uno's C API option iterator.
#'
#' @return A data frame with the columns `name` and `type`, one row per option,
#'   sorted by name.
#' @examples
#' opts <- uno_options()
#' head(opts)
#' opts[opts$name == "preset", ]
#' @export
uno_options <- function() {
  res <- uno_options_impl()
  out <- data.frame(name = res$name, type = res$type, stringsAsFactors = FALSE)
  out[order(out$name), , drop = FALSE]
}

#' Uno status labels
#'
#' The optimization and solution statuses of the linked Uno, as named integer
#' vectors: the names are the labels [uno_solve()] returns in
#' `optimization_status` and `solution_status`, the values are Uno's enum
#' codes. Generated from Uno's C API header at build time, so they follow the
#' bundled Uno exactly.
#'
#' @return A list with two named integer vectors, `optimization` and `solution`.
#' @examples
#' uno_status_labels()
#' @export
uno_status_labels <- function() {
  uno_status_labels_impl()
}

#' MUMPS version reached through rmumps
#'
#' The version of the MUMPS linear solver that Uno's interior-point preset uses,
#' as provided by the installed \pkg{rmumps} package, or `NA` for a build made
#' without MUMPS (`R_UNO_NO_MUMPS=1`).
#'
#' @return A character scalar such as `"5.9.1"`, or `NA_character_`.
#' @examples
#' uno_mumps_version()
#' @export
uno_mumps_version <- function() {
  info <- uno_rmumps_load()
  if (identical(info$mode, "none") || !nzchar(info$mumps_version)) {
    return(NA_character_)
  }
  info$mumps_version
}
