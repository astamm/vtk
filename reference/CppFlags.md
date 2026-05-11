# Compiler flags for packages linking against VTK

Returns the C pre-processor flags (`-I` paths) required to compile C++
code that includes VTK headers. Intended to be called from a downstream
package's `configure` or `configure.win` script:

## Usage

``` r
CppFlags()
```

## Value

A single character string of compiler flags, written to stdout (so that
it can be captured by shell command substitution in `configure`) and
returned invisibly.

## Details

    VTK_CPPFLAGS="$("${R_HOME}/bin/Rscript" --vanilla -e "rvtk::CppFlags()")"

## Examples

``` r
flags <- CppFlags()
#> -isystem/home/runner/work/_temp/Library/rvtk/prebuilt/include/vtk-9.5
```
