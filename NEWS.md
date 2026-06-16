# Uno 2.7.4

* Fixed the interior-point ("ipopt") preset on Windows, which failed with "The
  linear solver MUMPS is unknown". The shim now resolves rmumps' `dmumps_c` via
  `R_GetCCallable` (works on Windows) instead of `R_FindSymbol` (did not), and
  `configure.win` builds with MUMPS enabled. Requires `rmumps >= 5.2.1-43`.

* Updated the bundled Uno C++ solver to upstream release 2.7.4. The R-packaging
  patch set rebased cleanly; the C API is backward-compatible and the R binding
  is unchanged.

* Build: forward the HiGHS include root into the bundled Uno compile, fixing a
  "'highs/Highs.h' file not found" error from Uno 2.7.4's prefixed include.

* Keep the bundled HiGHS/Uno source trees out of the *installed* package via a
  top-level `.Rinstignore`, as CRAN requested; the static libraries are still
  built from the bundled sources at configure time.

* Fixed an undefined-behavior report from CRAN's gcc-SAN / clang-SAN checks
  (`uno_binding.cpp`, `make_x`): a length-0 `memcpy` received a NULL source. The
  copy is now guarded; no user-visible behavior change.

# Uno 2.7.3-1

* Fixed the bundled HiGHS/Uno source build on non-shlib R (CRAN fedora-gcc/clang,
  musl): use `R.home("include")` for R's header path, and normalize a `lib64/`
  `libuno.a` install to `lib/`.

# Uno 2.7.3

* Updated the bundled Uno C++ solver to upstream release 2.7.3. The R-packaging
  patch set was rebased onto v2.7.3; the C API is backward-compatible (the
  binding is unchanged). One internal fix: Uno 2.7.3 relocated
  `Options::dump_default_options()`, so its console output is re-routed through
  the R-output mechanism (`UNO_COUT`) to keep the compiled library free of raw
  `std::cout` for the CRAN compiled-code check.

* Added `inst/COPYRIGHTS` documenting the copyright holders and licenses of the
  bundled third-party libraries: the Uno C++ solver and HiGHS, including the
  components HiGHS itself bundles (AMD, METIS, pdqsort, zstr, rcm, filereaderlp,
  Catch2, and CLI11). All are permissive and MIT-compatible
  (MIT / BSD-3-Clause / Apache-2.0 / zlib / Boost Software License 1.0); none is
  copyleft. A `Copyright: file inst/COPYRIGHTS` field and a `cph` entry for the
  HiGHS development team record this in the package metadata. Because the file
  lives under `inst/`, the attribution survives installation. MUMPS (reached at
  run time through the GPL-licensed `rmumps` package) and BQPD are not bundled.
