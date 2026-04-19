#' Compiler flags for packages linking against VTK
#'
#' Returns the C pre-processor flags (`-I` paths) required to compile C++ code
#' that includes VTK headers.  Intended to be called from a downstream
#' package's `src/Makevars` or `src/Makevars.win`:
#'
#' ```makefile
#' PKG_CPPFLAGS = $(shell "$(R_HOME)/bin$(R_ARCH_BIN)/Rscript" -e "rvtk::CppFlags()")
#' ```
#'
#' @return A single character string of compiler flags, printed to stdout (so
#'   that it can be captured by `$(shell ...)` in a `Makefile`).
#' @export
CppFlags <- function() {
  cat(read_vtk_conf()[["VTK_CPPFLAGS"]])
}

#' Linker flags for packages linking against VTK
#'
#' Returns the linker flags (`-L` paths and `-l` library names) required to
#' link C++ code against VTK.  Intended to be called from a downstream
#' package's `src/Makevars` or `src/Makevars.win`:
#'
#' ```makefile
#' PKG_LIBS = $(shell "$(R_HOME)/bin$(R_ARCH_BIN)/Rscript" -e "rvtk::LdFlags()")
#' ```
#'
#' @return A single character string of linker flags, printed to stdout (so
#'   that it can be captured by `$(shell ...)` in a `Makefile`).
#' @export
LdFlags <- function() {
  cat(read_vtk_conf()[["VTK_LIBS"]])
}

#' VTK version used by this package
#'
#' @return A character string with the VTK version, e.g. `"9.3.1"`.
#' @export
VtkVersion <- function() {
  read_vtk_conf()[["VTK_VERSION"]]
}

# Internal helper -------------------------------------------------------

read_vtk_conf <- function(path = NULL) {
  if (is.null(path)) {
    path <- system.file("vtk.conf", package = "rvtk", mustWork = TRUE)
  }
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(trimws(lines)) & !startsWith(trimws(lines), "#")]
  parsed <- strsplit(lines, "=", fixed = TRUE)
  vals <- vapply(parsed, function(x) paste(x[-1], collapse = "="), character(1))
  keys <- vapply(parsed, `[[`, character(1), 1)
  conf <- stats::setNames(as.list(vals), keys)

  ## On Windows the VTK headers and libs live under inst/windows/ inside the
  ## installed package.  Resolve them at runtime so the paths are always valid
  ## regardless of where the package was installed.
  if (.Platform$OS.type == "windows" && !is.null(conf[["VTK_SUBDIR"]])) {
    subdir <- conf[["VTK_SUBDIR"]]
    lib_sfx <- conf[["VTK_SUFFIX"]]
    base_dir <- system.file(
      file.path("windows", subdir),
      package = "rvtk",
      mustWork = TRUE
    )
    base_dir <- normalizePath(base_dir, winslash = "/")

    ## Look for a versioned include sub-directory (e.g. vtk-9.5)
    inc_root <- file.path(base_dir, "include")
    vdirs <- list.dirs(inc_root, recursive = FALSE, full.names = FALSE)
    vdirs <- grep("^vtk-[0-9]", vdirs, value = TRUE)
    if (length(vdirs) > 0L) {
      inc_dir <- file.path(inc_root, vdirs[length(vdirs)])
    } else {
      inc_dir <- file.path(inc_root, "vtk")
    }

    lib_dir <- file.path(base_dir, "lib")
    conf[["VTK_CPPFLAGS"]] <- sprintf('-I"%s"', inc_dir)
    ## Discover every .a present and wrap in a linker group so that the
    ## linker resolves all transitive dependencies regardless of ordering.
    all_libs <- list.files(lib_dir, pattern = "\\.a$", full.names = FALSE)
    lib_flags <- paste(
      sprintf("-l%s", sub("\\.a$", "", sub("^lib", "", all_libs))),
      collapse = " "
    )
    ## GNU ld (Linux) and MinGW (Windows) support --start-group/--end-group.
    ## Apple ld (macOS) does not; use -all_load instead.
    if (Sys.info()[["sysname"]] == "Darwin") {
      conf[["VTK_LIBS"]] <- paste(
        sprintf('-L"%s"', lib_dir),
        paste0("-Wl,-all_load ", lib_flags)
      )
    } else {
      conf[["VTK_LIBS"]] <- paste(
        sprintf('-L"%s"', lib_dir),
        "-Wl,--start-group",
        lib_flags,
        "-Wl,--end-group"
      )
    }
  }

  conf
}
