# Uno 2.7.3-3

* Keep the bundled HiGHS/Uno source trees out of the *installed* package via a
  top-level `.Rinstignore` (patterns `/HiGHS`, `/uno`, and `/build_.*\.sh$`)
  rather than deleting them in `configure` / `configure.win` during a tarball
  install. This is the documented R mechanism (Writing R Extensions,
  ".Rinstignore"), it never touches a developer's submodule checkout during an
  in-place `R CMD INSTALL .`, and it is what CRAN requested. The static
  libraries are still built from the bundled sources at configure time; only the
  *installed* copy omits the third-party source trees.

# Uno 2.7.3-2

* Fixed an undefined-behavior report from CRAN's gcc-SAN / clang-SAN checks
  (`uno_binding.cpp`, `make_x`): for an unconstrained iterate the progress
  callback passes a null constraint-multiplier pointer with length 0, and the
  subsequent `memcpy` received a NULL source, which `-fsanitize=nonnull-attribute`
  flags as undefined behavior even at length 0. The copy is now guarded. No
  user-visible behavior change; verified under `clang -fsanitize=undefined` that
  the report is present before the guard and gone after.

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
