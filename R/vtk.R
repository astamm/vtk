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

#' Write VTK linker flags to a response file
#'
#' On Windows the full set of VTK linker flags can exceed the 8 191-character
#' Windows command-line limit, causing the linker to drop flags at the end of
#' the list.  This function writes the flags to a plain-text response file that
#' the linker reads via the `@file` syntax, keeping the command line short.
#'
#' Intended to be called from a downstream package's `configure` script:
#'
#' ```sh
#' VTK_LIBS="$("${R_HOME}/bin/Rscript" --vanilla -e \
#'   "rvtk::LdFlagsFile('src/vtk_libs.rsp')")"
#' # VTK_LIBS is now the short string "@src/vtk_libs.rsp"
#' sed -e "s|@VTK_LIBS@|${VTK_LIBS}|g" src/Makevars.in > src/Makevars
#' ```
#'
#' On non-Windows platforms the flags are still written to `path` (so the
#' workflow is identical on all platforms), and the returned `@path` string
#' is equally valid because GCC/Clang also support response files.
#'
#' @param path Path (relative to the package source root, i.e. where
#'   `configure` runs) to the response file to write, e.g.
#'   `"src/vtk_libs.rsp"`.
#'
#' @return Invisibly, the string to embed in `Makevars` (either `@path` on
#'   Windows or the raw flags on other platforms).  The string is also printed
#'   to stdout so that shell command substitution captures it.
#' @export
LdFlagsFile <- function(path) {
  flags <- read_vtk_conf()[["VTK_LIBS"]]
  if (.Platform$OS.type == "windows") {
    ## On Windows the flags string can exceed the 8191-char cmd.exe limit.
    ## Write them to a response file and return the short @file reference.
    ## configure writes the file relative to the package root (e.g.
    ## "src/vtk_libs.rsp"), but the linker runs from src/, so the @reference
    ## must use only the basename.
    writeLines(flags, path)
    result <- paste0("@", basename(path))
  } else {
    ## On macOS/Linux Apple ld and GNU ld do not reliably support @file at the
    ## compiler-driver level; return the flags directly (no length problem here).
    result <- flags
  }
  cat(result)
  invisible(result)
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
    } else if (Sys.info()[["sysname"]] == "Windows") {
      conf[["VTK_LIBS"]] <- paste(
        sprintf('-L"%s"', lib_dir),
        "-Wl,--start-group",
        lib_flags,
        ## Windows / Rtools45 static.posix system libraries required by VTK:
        ## gdi32      - GDI functions (vtkWin32OutputWindow)
        ## winpthread - nanosleep64 / POSIX threads (vtkloguru)
        ##              must be inside the group for circular dep resolution
        ## compat     - ftime64 POSIX wrapper (vtkCommonSystem, Rtools45 UCRT)
        ## mingwex    - additional POSIX wrappers (mingw-w64)
        ## ucrt       - __imp_fseeko64, __imp_ftello64 (vtkpugixml, UCRT import)
        ## oleaut32, ole32, ws2_32 - COM/sockets used by some VTK modules
        "-lgdi32 -lwinpthread -lcompat -lmingwex -lucrt -loleaut32 -lole32 -lws2_32",
        "-Wl,--end-group"
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
