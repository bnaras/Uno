# Uno 2.9.2-1

* Updated the bundled Uno C++ solver from 2.7.4 to upstream release 2.9.2. Uno
  2.9 adds the `auto` preset (chosen by problem size), function scaling for all
  methods, a Ctrl-C handler that stops a solve cleanly with the new
  `USER_INTERRUPTION` status, and two solution statuses: `DIVERGING_ITERATE`
  and `UNBOUNDED_OBJECTIVE` (which replaces `UNBOUNDED`). The R-packaging patch
  set was rebased onto v2.9.2.

* The status labels `uno_solve()` returns are now generated from Uno's C API
  header at install time, so they follow the bundled Uno exactly;
  `uno_status_labels()` lists them.

* MUMPS through `rmumps`, two generations: with `rmumps` 5.2.1-44 or later the
  package binds to the versioned C interface `<rmumps/rmumps_api.h>`, whose
  entry points are named after the MUMPS structure layout they were built for,
  so a mismatch between the `rmumps` a binary was built against and the one
  installed is a clear error when the package loads rather than memory
  corruption; `rmumps` 5.9.1-1 brings MUMPS 5.9.1 this way. With `rmumps`
  5.2.1-43 the legacy `dmumps_c` entry point is used as before. The binding
  happens in `.onLoad`. `uno_mumps_version()` reports the MUMPS reached.

* New: `uno_options()` lists every Uno option with its type; `uno_solve()`
  gains a `name` argument (the model name in Uno's log) and validates the
  preset; without a `log_callback`, Uno's output now goes to the R console
  through an explicit logger sink.

* Build: Uno is configured with `-DUSE_OPENMP=OFF` (Uno 2.7.5 made OpenMP the
  default, which its CMake requires whenever MUMPS is present). The bundled
  Uno's CMake gains a `FORTRAN_MANGLING_UNDERSCORE` option, which the package
  turns on: BLAS/LAPACK symbol names are spelled with the gfortran convention
  R uses everywhere instead of being discovered by compiling and linking a
  Fortran probe, so installing no longer needs a working Fortran link step
  (nothing in the build is Fortran; R supplies BLAS, LAPACK and the Fortran
  runtime at link time). The bundled
  Uno's `DynamicLoader.cpp` includes `<cstdlib>` for `std::getenv`, which
  LLVM 23's libc++ no longer provides transitively (CRAN's
  `r-devel-linux-x86_64-fedora-clang`); the 2.7.4-1 fix of `VectorView.hpp` is
  moot, that file is gone upstream.

* Fixed an installation failure on glibc 2.36 and older (Debian 12, Ubuntu
  22.04 LTS, RHEL 9), where the bundled HiGHS build stopped.

# Uno 2.7.4-1

* Fixed a compilation failure with LLVM 23's libc++, reported by CRAN's
  `r-devel-linux-x86_64-fedora-clang` check. libc++ 23 dropped many transitive
  includes in all language modes, so the bundled Uno solver's `VectorView.hpp`
  no longer saw `<algorithm>` and its use of `std::fill` failed to compile,
  taking 28 translation units with it. The header now includes `<algorithm>`
  directly. No user-visible change.

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
