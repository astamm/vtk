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
#' @return A single character string of compiler flags, written to stdout (so
#'   that it can be captured by `$(shell ...)` in a `Makefile`) and returned
#'   invisibly.
#' @examples
#' flags <- CppFlags()
#' @export
CppFlags <- function() {
  flags <- read_vtk_conf()[["VTK_CPPFLAGS"]]
  writeLines(flags)
  invisible(flags)
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
#' @return A single character string of linker flags, written to stdout (so
#'   that it can be captured by `$(shell ...)` in a `Makefile`) and returned
#'   invisibly.
#' @examples
#' flags <- LdFlags()
#' @export
LdFlags <- function() {
  flags <- read_vtk_conf()[["VTK_LIBS"]]
  writeLines(flags)
  invisible(flags)
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
#' @param os_type A string identifying the operating-system type, defaulting to
#'   `.Platform$OS.type`.  Override to `"windows"` or `"unix"` in tests to
#'   exercise the Windows response-file branch without needing a Windows
#'   environment.
#'
#' @return Invisibly, the string to embed in `Makevars` (either `@path` on
#'   Windows or the raw flags on other platforms).  The string is also written
#'   to stdout so that shell command substitution captures it.
#' @examples
#' rsp <- file.path(tempdir(), "vtk_libs.rsp")
#' ref <- LdFlagsFile(rsp)
#' @export
LdFlagsFile <- function(path, os_type = .Platform$OS.type) {
  flags <- read_vtk_conf()[["VTK_LIBS"]]
  if (os_type == "windows") {
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
  writeLines(result)
  invisible(result)
}

#' VTK version used by this package
#'
#' @return A character string with the VTK version, e.g. `"9.3.1"`.
#' @examples
#' VtkVersion()
#' @export
VtkVersion <- function() {
  read_vtk_conf()[["VTK_VERSION"]]
}

# Internal helper -------------------------------------------------------

read_vtk_conf <- function(
  path = NULL,
  os_type = .Platform$OS.type,
  sysname = Sys.info()[["sysname"]],
  win_base_dir = NULL
) {
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
  if (os_type == "windows" && !is.null(conf[["VTK_SUBDIR"]])) {
    subdir <- conf[["VTK_SUBDIR"]]
    lib_sfx <- conf[["VTK_SUFFIX"]]
    if (is.null(win_base_dir)) {
      base_dir <- system.file(
        file.path("windows", subdir),
        package = "rvtk",
        mustWork = TRUE
      )
    } else {
      base_dir <- win_base_dir
    }
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
    if (sysname == "Darwin") {
      conf[["VTK_LIBS"]] <- paste(
        sprintf('-L"%s"', lib_dir),
        paste0("-Wl,-all_load ", lib_flags)
      )
    } else if (sysname == "Windows") {
      conf[["VTK_LIBS"]] <- paste(
        sprintf('-L"%s"', lib_dir),
        "-Wl,--start-group",
        lib_flags,
        ## Windows system libraries required by VTK (static.posix build):
        ## gdi32 - GDI functions used by vtkWin32OutputWindow.
        ## POSIX threading / libc symbols (nanosleep, ftime64, fseeko64, ...)
        ## are resolved automatically by the x86_64-w64-mingw32.static.posix
        ## toolchain's default link libraries; no extra -l flags needed.
        "-lgdi32",
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
