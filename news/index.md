# Changelog

## Uno 2.7.3

- Updated the bundled Uno C++ solver to upstream release 2.7.3. The
  R-packaging patch set was rebased onto v2.7.3; the C API is
  backward-compatible (the binding is unchanged). One internal fix: Uno
  2.7.3 relocated `Options::dump_default_options()`, so its console
  output is re-routed through the R-output mechanism (`UNO_COUT`) to
  keep the compiled library free of raw `std::cout` for the CRAN
  compiled-code check.

- Added `inst/COPYRIGHTS` documenting the copyright holders and licenses
  of the bundled third-party libraries: the Uno C++ solver and HiGHS,
  including the components HiGHS itself bundles (AMD, METIS, pdqsort,
  zstr, rcm, filereaderlp, Catch2, and CLI11). All are permissive and
  MIT-compatible (MIT / BSD-3-Clause / Apache-2.0 / zlib / Boost
  Software License 1.0); none is copyleft. A
  `Copyright: file inst/COPYRIGHTS` field and a `cph` entry for the
  HiGHS development team record this in the package metadata. Because
  the file lives under `inst/`, the attribution survives installation.
  MUMPS (reached at run time through the GPL-licensed `rmumps` package)
  and BQPD are not bundled.
