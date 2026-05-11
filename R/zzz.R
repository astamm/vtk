# Package hooks --------------------------------------------------------

## Saved PATH value before rvtk prepended the vtk-dlls directory.
## Used by .onUnload to restore PATH cleanly.
.vtk_original_path <- NULL

.onLoad <- function(libname, pkgname) {
  ## On Windows, if rvtk was installed against a shared VTK build, the VTK
  ## DLLs are staged in inst/vtk-dlls/.  Prepend that directory to PATH so
  ## that the Windows DLL loader can find the VTK DLLs when downstream
  ## packages that link against them are loaded.
  ##
  ## For system VTK installs (e.g. pacman ucrt64), also prepend VTK_DLL_DIR
  ## (the original bin/ of the system VTK, e.g. C:/rtools45/ucrt64/bin) so
  ## that transitive dependencies of the VTK DLLs (libtbb, libgcc_s, etc.)
  ## which live there can also be found by the Windows DLL loader.
  ##
  ## R's own library.dynam() uses the same Sys.setenv(PATH=...) mechanism
  ## (see src/library/base/R/library.R), and the dyn.load() help page
  ## documents this as the standard approach.  The Windows DLL loader
  ## searches PATH as part of its resolution chain; R's newer
  ## SetDllDirectory / AddDllDirectory calls are not exposed at the R level.
  ##
  ## We save the original PATH so that .onUnload() can restore it, which
  ## satisfies CRAN's requirement that packages not leave persistent side
  ## effects after being unloaded.
  conf <- tryCatch(read_vtk_conf(), error = function(e) NULL)
  dll_dir <- system.file("vtk-dlls", package = pkgname, lib.loc = libname)
  vtk_dll_dir <- if (!is.null(conf)) conf[["VTK_DLL_DIR"]] else NULL
  ns <- environment(sys.function())
  .vtk_prepend_path(
    os_type = .Platform$OS.type,
    dll_dir = dll_dir,
    vtk_dll_dir = vtk_dll_dir,
    ns = ns
  )
}

.onUnload <- function(libpath) {
  ## Restore PATH to the value it had before .onLoad prepended vtk-dlls,
  ## so that unloading rvtk leaves no persistent side effects.
  ns <- asNamespace("rvtk")
  .vtk_restore_path(os_type = .Platform$OS.type, ns = ns)
}

# Internal helpers (extracted for testability) -------------------------

## Prepend VTK DLL directories to PATH on Windows.
## `dll_dir`     – path to the staged vtk-dlls directory (may be "")
## `vtk_dll_dir` – system VTK bin/ directory from vtk.conf (may be NULL/"")
## `ns`          – the namespace environment used to persist the saved PATH
.vtk_prepend_path <- function(
  os_type = .Platform$OS.type,
  dll_dir = "",
  vtk_dll_dir = NULL,
  ns = asNamespace("rvtk")
) {
  if (os_type != "windows") {
    return(invisible(NULL))
  }

  dirs_to_add <- character(0L)
  if (nzchar(dll_dir) && dir.exists(dll_dir)) {
    dirs_to_add <- c(
      normalizePath(dll_dir, winslash = "\\", mustWork = FALSE),
      dirs_to_add
    )
  }
  if (!is.null(vtk_dll_dir) && nzchar(vtk_dll_dir)) {
    dirs_to_add <- c(
      dirs_to_add,
      normalizePath(vtk_dll_dir, winslash = "\\", mustWork = FALSE)
    )
  }

  if (length(dirs_to_add) > 0L) {
    old_path <- Sys.getenv("PATH")
    new_dirs <- dirs_to_add[
      !vapply(
        dirs_to_add,
        function(d) grepl(d, old_path, fixed = TRUE),
        logical(1L)
      )
    ]
    if (length(new_dirs) > 0L) {
      assign(".vtk_original_path", old_path, envir = ns)
      Sys.setenv(
        PATH = paste(
          paste(new_dirs, collapse = ";"),
          old_path,
          sep = ";"
        )
      )
    }
  }

  invisible(NULL)
}

## Restore PATH to the value saved by .vtk_prepend_path.
.vtk_restore_path <- function(
  os_type = .Platform$OS.type,
  ns = asNamespace("rvtk")
) {
  if (os_type != "windows") {
    return(invisible(NULL))
  }
  saved <- get0(".vtk_original_path", envir = ns, inherits = FALSE)
  if (!is.null(saved)) {
    Sys.setenv(PATH = saved)
  }
  invisible(NULL)
}
