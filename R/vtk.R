#' Compiler flags for packages linking against VTK
#'
#' Returns the C pre-processor flags (`-I` paths) required to compile C++ code
#' that includes VTK headers.  Intended to be called from a downstream
#' package's `configure` or `configure.win` script:
#'
#' ```sh
#' VTK_CPPFLAGS="$("${R_HOME}/bin/Rscript" --vanilla -e "rvtk::CppFlags()")"
#' ```
#'
#' @return A single character string of compiler flags, written to stdout (so
#'   that it can be captured by shell command substitution in `configure`) and
#'   returned invisibly.
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
#' package's `configure` or `configure.win` script:
#'
#' ```sh
#' VTK_LIBS="$("${R_HOME}/bin/Rscript" --vanilla -e "rvtk::LdFlags()")"
#' ```
#'
#' On Windows the full set of VTK linker flags can exceed the 8 191-character
#' command-line limit.  Prefer `LdFlagsFile()` on Windows to write the flags
#' to a response file instead.
#'
#' @param modules A character vector of VTK module names to link against,
#'   e.g. `c("vtkIOLegacy", "vtkCommonCore")`.  When `NULL` (the default) all
#'   available modules are included.  When non-`NULL`, only the requested
#'   modules are linked, which avoids pulling in unneeded symbols (such as
#'   AppKit/Cocoa symbols from rendering modules when using the pre-built
#'   static bundle).
#'
#' @return A single character string of linker flags, written to stdout (so
#'   that it can be captured by shell command substitution in `configure`) and
#'   returned invisibly.
#' @examples
#' flags <- LdFlags()
#' @export
LdFlags <- function(modules = NULL) {
  flags <- read_vtk_conf(modules = modules)[["VTK_LIBS"]]
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
#' Intended to be called from a downstream package's `configure` or
#' `configure.win` script:
#'
#' ```sh
#' VTK_LIBS="$("${R_HOME}/bin/Rscript" --vanilla -e \
#'   "rvtk::LdFlagsFile('src/vtk_libs.rsp')")"
#' # VTK_LIBS is now the short string "@src/vtk_libs.rsp" on Windows,
#' # or the raw flags on macOS/Linux.
#' ```
#'
#' On Windows the flags are written to `path` and the function returns the
#' `@basename(path)` token for the linker.  On macOS and Linux, `ld` does not
#' reliably support `@file` response files at the compiler-driver level, so
#' no file is written and the raw flags are returned directly.
#'
#' @param path Path (relative to the package source root, i.e. where
#'   `configure` runs) to the response file to write on Windows, e.g.
#'   `"src/vtk_libs.rsp"`.  Ignored on non-Windows platforms.
#' @param modules A character vector of VTK module names to link against,
#'   e.g. `c("vtkIOLegacy", "vtkCommonCore")`.  When `NULL` (the default) all
#'   available modules are included.  When non-`NULL`, only the requested
#'   modules are linked, which avoids pulling in unneeded symbols (such as
#'   AppKit/Cocoa symbols from rendering modules when using the pre-built
#'   static bundle).
#' @param os_type A string identifying the operating-system type, defaulting to
#'   `.Platform$OS.type`.  Override to `"windows"` or `"unix"` in tests to
#'   exercise the Windows response-file branch without needing a Windows
#'   environment.
#'
#' @return Invisibly, the string to embed in `configure` (either
#'   `@basename(path)` on Windows or the raw flags on other platforms).  The
#'   string is also written to stdout so that shell command substitution
#'   captures it.
#' @examples
#' rsp <- file.path(tempdir(), "vtk_libs.rsp")
#' ref <- LdFlagsFile(rsp)
#' @export
LdFlagsFile <- function(path, modules = NULL, os_type = .Platform$OS.type) {
  flags <- read_vtk_conf(modules = modules)[["VTK_LIBS"]]
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
  modules = NULL,
  os_type = .Platform$OS.type,
  sysname = Sys.info()[["sysname"]],
  win_base_dir = NULL,
  unix_base_dir = NULL
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

  ## On Unix with pre-built static libraries, headers and libs live under
  ## inst/prebuilt/ inside the installed package.  Resolve them at runtime.
  if (os_type != "windows" && identical(conf[["VTK_PREBUILT"]], "yes")) {
    if (is.null(unix_base_dir)) {
      base_dir <- system.file("prebuilt", package = "rvtk", mustWork = TRUE)
    } else {
      base_dir <- unix_base_dir
    }
    base_dir <- normalizePath(base_dir, winslash = "/")

    inc_root <- file.path(base_dir, "include")
    vdirs <- list.dirs(inc_root, recursive = FALSE, full.names = FALSE)
    vdirs <- grep("^vtk-[0-9]", vdirs, value = TRUE)
    if (length(vdirs) > 0L) {
      inc_dir <- file.path(inc_root, vdirs[length(vdirs)])
    } else {
      inc_dir <- file.path(inc_root, "vtk")
    }

    lib_dir <- file.path(base_dir, "lib")
    conf[["VTK_CPPFLAGS"]] <- sprintf("-isystem%s", inc_dir)

    all_libs_full <- list.files(lib_dir, pattern = "\\.a$", full.names = TRUE)
    all_libs_full <- filter_libs(all_libs_full, modules)
    lib_args <- paste(all_libs_full, collapse = " ")
    if (sysname == "Darwin") {
      conf[["VTK_LIBS"]] <- paste("-Wl,-all_load", lib_args)
    } else {
      conf[["VTK_LIBS"]] <- paste(
        "-Wl,--start-group",
        lib_args,
        "-Wl,--end-group"
      )
    }
  }

  ## On Windows the VTK headers and libs live under inst/windows/ inside the
  ## installed package.  Resolve them at runtime so the paths are always valid
  ## regardless of where the package was installed.
  if (os_type == "windows" && !is.null(conf[["VTK_SUBDIR"]])) {
    subdir <- conf[["VTK_SUBDIR"]]
    link_type <- if (!is.null(conf[["VTK_LINK"]])) {
      conf[["VTK_LINK"]]
    } else {
      "static"
    }
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

    if (identical(link_type, "shared")) {
      ## Shared build: link against .dll.a import libs.  The VTK DLLs live in
      ## inst/vtk-dlls/ and are prepended to PATH by .onLoad() so downstream
      ## packages do not need to do anything special.
      all_libs <- list.files(
        lib_dir,
        pattern = "\\.dll\\.a$",
        full.names = FALSE
      )
      all_libs <- filter_libs(all_libs, modules)
      lib_flags <- paste(
        sprintf("-l%s", sub("\\.dll\\.a$", "", sub("^lib", "", all_libs))),
        collapse = " "
      )
      conf[["VTK_LIBS"]] <- paste(
        sprintf('-L"%s"', lib_dir),
        lib_flags,
        "-lgdi32"
      )
    } else {
      ## Static build: wrap in a linker group to resolve circular dependencies.
      ## Exclude any .dll.a import libs that might co-exist with .a archives.
      all_libs <- list.files(lib_dir, pattern = "\\.a$", full.names = FALSE)
      all_libs <- all_libs[!grepl("\\.dll\\.a$", all_libs)]
      all_libs <- filter_libs(all_libs, modules)
      lib_flags <- paste(
        sprintf("-l%s", sub("\\.a$", "", sub("^lib", "", all_libs))),
        collapse = " "
      )
      if (sysname == "Darwin") {
        ## Cross-compiling on macOS: use -all_load (Apple ld syntax) and omit
        ## the Windows-only -lgdi32.
        conf[["VTK_LIBS"]] <- paste(
          sprintf('-L"%s"', lib_dir),
          "-Wl,-all_load",
          lib_flags
        )
      } else {
        ## Native Windows or Linux cross-compile: use GNU ld group syntax.
        ## -lgdi32 is only needed when the actual target linker is MinGW (i.e.
        ## building on or for Windows).  On Linux cross-builds the Windows
        ## system libs are resolved by the cross toolchain automatically.
        gdi_flag <- if (sysname == "Windows") "-lgdi32" else ""
        conf[["VTK_LIBS"]] <- trimws(paste(
          sprintf('-L"%s"', lib_dir),
          "-Wl,--start-group",
          lib_flags,
          gdi_flag,
          "-Wl,--end-group"
        ))
      }
    }
  }

  conf
}

## Filter a vector of library filenames (basenames or full paths) to only
## those whose basename matches at least one of the requested module names.
## If modules is NULL, all libraries are returned unchanged.
filter_libs <- function(libs, modules) {
  if (is.null(modules)) {
    return(libs)
  }
  # Always keep bundled third-party libs (not prefixed with "vtk")
  # e.g. libvtkexpat, libvtkzlib, libvtklz4, libvtklzma, libvtkloguru...
  # These lack the vtk<ModuleName> convention but are needed as transitive deps.
  basenames <- sub(".*/", "", libs)
  is_third_party <- !grepl("^libvtk[A-Z]", basenames) # vtk<UpperCase> = VTK module

  pattern <- paste0(
    "(^|/)(lib)?(",
    paste(modules, collapse = "|"),
    ")(-[0-9]|\\.).*"
  )
  is_module <- grepl(pattern, libs, perl = TRUE)

  libs[is_module | is_third_party]
}
