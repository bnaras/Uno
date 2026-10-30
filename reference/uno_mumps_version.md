# MUMPS version reached through rmumps

The version of the MUMPS linear solver that Uno's interior-point preset
uses, as provided by the installed rmumps package, or \`NA\` for a build
made without MUMPS (\`R_UNO_NO_MUMPS=1\`).

## Usage

``` r
uno_mumps_version()
```

## Value

A character scalar such as \`"5.9.1"\`, or \`NA_character\_\`.

## Examples

``` r
uno_mumps_version()
#> [1] "5.2.1"
```
