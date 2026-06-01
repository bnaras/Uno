#!/usr/bin/env Rscript
## tools/shorten_paths.R -- keep the bundled Uno source under the CRAN 100-byte
## tarball-path limit, declaratively.
##
## WHY: `R CMD check` flags any file whose tarball path ("Uno/<relpath>") exceeds
## 100 bytes (a tar/ustar portability limit). The vendored Uno C++ tree is deeply
## nested (inst/uno/uno/ingredients/...), so several files sit at/near the limit.
## Rather than carry hand-applied directory renames as source patches -- which
## conflict on every upstream rebase and reveal the *next* long path only after a
## slow build -- this script:
##   * applies a declarative segment-rename MAP (tools/path_shortenings.csv) to
##     the vendored tree, and
##   * CHECKS that no shipped path exceeds the limit, failing loudly (CI guard)
##     with a suggested fix when one does.
##
## USAGE (from the package root):
##   Rscript tools/shorten_paths.R check     # exit 1 if any tarball path > LIMIT
##   Rscript tools/shorten_paths.R suggest    # propose segments to shorten
##   Rscript tools/shorten_paths.R apply      # git-mv + rewrite refs per the map
##
## DESIGN NOTES (see also the discussion this was distilled from):
##   * The map stores only {long_segment -> short_segment}. The files that
##     reference a segment are DISCOVERED at apply time (grep), never stored, so
##     the map can't drift behind upstream restructuring.
##   * Only "<segment>/" (a segment followed by a slash = a path use) is
##     rewritten, so identifiers such as the option name "quasi_newton_memory_size"
##     (segment followed by "_") are never touched.
##   * `check` is the immediately-useful piece (run it in CI / before build).
##     `apply` supports the longer-term "keep upstream pristine, transform at
##     prep time" model; today the renames are still committed in the r-pkg
##     branch, so `apply` is idempotent (a no-op once applied).

LIMIT <- 100L
PKG   <- "Uno"                                   # tarball top dir (= Package)
ROOT  <- "inst/uno"                              # vendored subtree
MAP   <- "tools/path_shortenings.csv"
EXTS  <- c("cpp", "hpp", "h", "txt", "cmake", "in")  # ref-rewrite targets

nb <- function(x) nchar(x, type = "bytes")

read_map <- function() {
  if (!file.exists(MAP)) stop("map not found: ", MAP, call. = FALSE)
  m <- utils::read.csv(MAP, comment.char = "#", strip.white = TRUE,
                       stringsAsFactors = FALSE)
  stopifnot(all(c("long_segment", "short_segment") %in% names(m)))
  m[nzchar(m$long_segment) & nzchar(m$short_segment), , drop = FALSE]
}

## Files R CMD build would ship: present files minus build artifacts and the
## simple directory prefixes in .Rbuildignore. This is an EARLY-WARNING
## approximation; the authoritative gate is R CMD check's portable-paths check.
tarball_files <- function() {
  all <- list.files(".", recursive = TRUE, all.files = FALSE, no.. = TRUE)
  drop <- "(^|/)(\\.git|highs_build|uno_build|highslib|unolib)(/|$)|\\.(o|so|a)$"
  keep <- !grepl(drop, all)
  if (file.exists(".Rbuildignore")) {
    pats <- readLines(".Rbuildignore", warn = FALSE)
    pats <- sub("\\$$", "", sub("^\\^", "", pats[nzchar(pats)]))
    for (p in pats) if (nzchar(p)) keep <- keep & !startsWith(all, p)
  }
  all[keep]
}

check_paths <- function() {
  paths <- file.path(PKG, tarball_files())
  over <- paths[nb(paths) > LIMIT]
  if (length(over)) {
    message(sprintf("FAIL: %d shipped path(s) exceed %d bytes:", length(over), LIMIT))
    for (p in over[order(-nb(over))]) message(sprintf("  %3d  %s", nb(p), p))
    message("\nRun `Rscript tools/shorten_paths.R suggest`, add a row to ", MAP,
            ", then `apply`.")
    quit(status = 1L, save = "no")
  }
  message(sprintf("OK: all %d shipped paths <= %d bytes (longest = %d).",
                  length(paths), LIMIT, max(nb(paths))))
}

## propose a directory segment to shorten for each path near/over the limit
suggest <- function() {
  files <- tarball_files()
  near  <- files[nb(file.path(PKG, files)) > LIMIT - 8L]
  if (!length(near)) { message("Nothing within 8 bytes of the limit."); return(invisible()) }
  map_long <- if (file.exists(MAP)) read_map()$long_segment else character()
  for (f in near[order(-nb(file.path(PKG, near)))]) {
    segs <- strsplit(f, "/", fixed = TRUE)[[1]]
    cand <- setdiff(unique(segs[nb(segs) >= 12]), map_long)  # unmapped, long segments
    message(sprintf("%3d  Uno/%s", nb(file.path(PKG, f)), f))
    if (length(cand)) message("       candidates to shorten: ", paste(cand, collapse = ", "))
  }
}

## rename dirs + rewrite "<long>/" path refs for every map row
apply_map <- function() {
  m <- read_map()
  ref_files <- list.files(ROOT, recursive = TRUE, full.names = TRUE,
                          pattern = paste0("\\.(", paste(EXTS, collapse = "|"), ")$"))
  for (i in seq_len(nrow(m))) {
    long <- m$long_segment[i]; short <- m$short_segment[i]
    dirs <- list.dirs(ROOT, recursive = TRUE, full.names = TRUE)
    dirs <- dirs[basename(dirs) == long]
    dirs <- dirs[order(-nchar(dirs))]            # deepest first
    for (d in dirs) {
      nd <- file.path(dirname(d), short)
      if (dir.exists(d) && !dir.exists(nd))
        system2("git", c("mv", shQuote(d), shQuote(nd)))
    }
    for (f in ref_files) {
      if (!file.exists(f)) next                  # may have been renamed
      txt <- readLines(f, warn = FALSE)
      new <- gsub(paste0(long, "/"), paste0(short, "/"), txt, fixed = TRUE)  # path use only
      if (!identical(txt, new)) writeLines(new, f)
    }
  }
  message("Applied ", nrow(m), " segment shortenings; now run `check`.")
}

mode <- { a <- commandArgs(trailingOnly = TRUE); if (length(a)) a[[1]] else "check" }
switch(mode,
       check   = check_paths(),
       suggest = suggest(),
       apply   = apply_map(),
       stop("usage: shorten_paths.R [check|suggest|apply]", call. = FALSE))
