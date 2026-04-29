.onLoad <- function(libname, pkgname) {
  if (.Platform$OS.type == "windows") {
    conf <- read_vtk_conf()

    ## 1. VTK DLLs from a system install (populated by configure.win)
    vtk_bin_dir <- conf[["VTK_BIN_DIR"]]
    if (
      !is.null(vtk_bin_dir) && nzchar(vtk_bin_dir) && file.exists(vtk_bin_dir)
    ) {
      Sys.setenv(PATH = paste(vtk_bin_dir, Sys.getenv("PATH"), sep = ";"))
    }

    ## 2. VTK DLLs bundled inside this package (pre-built / winlibs.R path)
    pkg_lib_dir <- system.file(
      "libs",
      .Platform$r_arch,
      package = pkgname,
      lib.loc = libname
    )
    if (nzchar(pkg_lib_dir) && file.exists(pkg_lib_dir)) {
      Sys.setenv(PATH = paste(pkg_lib_dir, Sys.getenv("PATH"), sep = ";"))
    }
  }
}
