## Windows debug: HiGHS' C API through the highs registry WITHOUT Uno.
## Compiles tools/windebug/ccall_bench.c (same file as the macOS A/B) against
## highs_ccallable.h and exercises create/destroy and tiny QP solves, with
## unbuffered markers so a crash shows where it happened.
mark <- function(...) { message("MARK ", ...); flush(stderr()) }
inc <- system.file("include", package = "highs")
mark("highs include: ", inc)
loadNamespace("highs")
mark("highs namespace loaded; DLL: ", getLoadedDLLs()[["highs"]][["path"]])
dir.create("wdbg", showWarnings = FALSE)
file.copy("tools/windebug/ccall_bench.c", "wdbg/ccall_bench.c", overwrite = TRUE)
Sys.setenv(PKG_CPPFLAGS = paste0("-DVIA_REGISTRY -I", shQuote(inc)))
owd <- setwd("wdbg")
st <- system2(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", "-o", "ccall_reg.dll", "ccall_bench.c"),
              stdout = TRUE, stderr = TRUE)
setwd(owd)
cat(st, sep = "\n")
mark("SHLIB done")
dll <- dyn.load(file.path("wdbg", "ccall_reg.dll"))
mark("dll loaded")
run <- function(fn, n) {
  t <- .Call(getNativeSymbolInfo(fn, dll), as.integer(n))
  mark(fn, "(", n, ") ok: ", signif(1e6 * t / n, 4), " us/iter")
  invisible(t)
}
run("bench_version", 1000L)
run("bench_create", 1L)          # one create + destroy (destroy resets the global scheduler)
run("bench_create", 3L)
run("bench_tiny_reuse", 3L)      # pass/run on one instance, destroyed once at the end
run("bench_tiny", 1L)            # create / solve / destroy, as Uno does
run("bench_tiny", 3L)
run("bench_tiny_t1", 3L)         # same with threads = 1
mark("all C API calls done; exiting R normally")
