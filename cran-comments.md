## Submission

This release fixes the installation failure reported on
`r-devel-linux-x86_64-fedora-clang` after that check flavor moved to LLVM 23.1.0
on 2026-08-25.

LLVM 23's libc++ dropped a large number of transitive includes in all language
modes. The bundled Uno C++ solver's `linear_algebra/VectorView.hpp` used
`std::fill` while including only `<cstddef>`, so it no longer compiled:

```
VectorView.hpp:247:10: error: no member named 'fill' in namespace 'std';
                              did you mean simply 'fill'?
```

Because that header is reached from `linear_algebra/Vector.hpp`, 28 translation
units failed. The header now includes `<algorithm>` directly. There is no
user-visible change and no change to the R code or the package API.

## Test environments

* Local reproduction of the reporting check flavor, in a container built to match
  it: Fedora 44, x86_64, clang 23.1.0 and flang 23.1.0 installed at
  `/usr/local/clang23`, R-devel (2026-08-25 r90448) configured from the published
  `config.site` for that flavor (`--without-lapack`), with the documented
  `_R_CHECK_*` environment set.

Before this change `R CMD INSTALL` fails as above; after it, the package installs
cleanly and `R CMD check --as-cran` completes with no errors or warnings.

## R CMD check results

0 errors | 0 warnings | 1 note

The note is `checking HTML version of manual`, reporting that `tidy` and the `V8`
package were unavailable in the container used for the check, so HTML validation
and math rendering were skipped. It reflects the checking environment, not the
package.

## Downstream dependencies

None on CRAN.
