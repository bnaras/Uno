# Bind Uno's MUMPS calls to the installed 'rmumps' when the namespace loads, so
# a mismatch between the rmumps this build was compiled against and the one now
# installed is a clear error here, not memory corruption inside a solve. The
# binding itself lives in src/dmumps_shim.c; it is a no-op for builds made with
# R_UNO_NO_MUMPS=1.
.onLoad <- function(libname, pkgname) {
  info <- tryCatch(uno_rmumps_load(), error = function(e) e)
  if (inherits(info, "error")) {
    stop(sprintf(paste0(
      "Uno cannot bind to the MUMPS solver of the installed 'rmumps' package: %s\n",
      "This build of Uno was compiled against a different 'rmumps'; reinstall ",
      "Uno from source (install.packages(\"Uno\", type = \"source\")) or update ",
      "'rmumps'."), conditionMessage(info)), call. = FALSE)
  }
  invisible()
}
