# Uno solver options

Every option the linked Uno accepts in the \`options\` argument of
\[uno_solve()\], with its declared type (\`"integer"\`, \`"double"\`,
\`"bool"\` or \`"string"\`), as read from Uno's C API option iterator.

## Usage

``` r
uno_options()
```

## Value

A data frame with the columns \`name\` and \`type\`, one row per option,
sorted by name.

## Examples

``` r
opts <- uno_options()
head(opts)
#>                                name    type
#> 5               BQPD_kmax_heuristic  string
#> 32     LBFGS_max_skips_before_reset integer
#> 97                        LP_solver  string
#> 31         LSR1_pivot_max_magnitude  double
#> 114           LS_backtracking_ratio  double
#> 82  LS_scale_duals_with_step_length    bool
opts[opts$name == "preset", ]
#>      name   type
#> 69 preset string
```
