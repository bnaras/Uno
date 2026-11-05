## Windows debug: the filtersqp (HiGHS via the highs registry) path through Uno,
## with unbuffered markers so a crash shows where it happened.
mark <- function(...) { message("MARK ", ...); flush(stderr()) }
library(Uno)
mark("Uno loaded: ", uno_version(), " mumps ", uno_mumps_version())
print(getLoadedDLLs()[c("Uno", "highs", "rmumps")])
obj  <- function(x) (x[1] - 1)^2 + (x[2] - 2)^2
grad <- function(x) c(2 * (x[1] - 1), 2 * (x[2] - 2))
cons <- function(x) x[1] + x[2]
jac  <- function(x) c(1, 1)
hess <- function(x, sigma, lambda) c(2 * sigma, 2 * sigma)
solve_once <- function(verbose) uno_solve(
  n = 2L, lb = c(-Inf, -Inf), ub = c(Inf, Inf), sense = "minimize",
  obj = obj, grad = grad, m = 1L, cl = -Inf, cu = 10, cons = cons,
  jac_rows = c(0L, 0L), jac_cols = c(0L, 1L), jac = jac,
  hess_rows = c(0L, 1L), hess_cols = c(0L, 1L), hess = hess,
  x0 = c(0, 0), preset = "filtersqp", base_indexing = 0L, verbose = verbose,
  log_callback = function(txt) { message(txt, appendLF = FALSE); flush(stderr()); invisible(NULL) })
mark("calling uno_solve (filtersqp)")
res <- solve_once(TRUE)
mark("uno_solve returned: ", names(res$optimization_status), " objective ", format(res$objective))
invisible(gc()); mark("after gc")
res2 <- solve_once(FALSE)
mark("second uno_solve returned: ", names(res2$optimization_status))
mark("exiting R normally")
