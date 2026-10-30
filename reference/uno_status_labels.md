# Uno status labels

The optimization and solution statuses of the linked Uno, as named
integer vectors: the names are the labels \[uno_solve()\] returns in
\`optimization_status\` and \`solution_status\`, the values are Uno's
enum codes. Generated from Uno's C API header at build time, so they
follow the bundled Uno exactly.

## Usage

``` r
uno_status_labels()
```

## Value

A list with two named integer vectors, \`optimization\` and
\`solution\`.

## Examples

``` r
uno_status_labels()
#> $optimization
#>           SUCCESS   ITERATION_LIMIT        TIME_LIMIT  EVALUATION_ERROR 
#>                 0                 1                 2                 3 
#> ALGORITHMIC_ERROR  USER_TERMINATION USER_INTERRUPTION 
#>                 4                 5                 6 
#> 
#> $solution
#>                 NOT_OPTIMAL          FEASIBLE_KKT_POINT 
#>                           0                           1 
#>           FEASIBLE_FJ_POINT INFEASIBLE_STATIONARY_POINT 
#>                           2                           3 
#>         FEASIBLE_SMALL_STEP       INFEASIBLE_SMALL_STEP 
#>                           4                           5 
#>           DIVERGING_ITERATE         UNBOUNDED_OBJECTIVE 
#>                           6                           7 
#> 
```
