# Tests for the rvtk R package
# Uses fixture conf files and synthetic directory trees to exercise every
# branch of read_vtk_conf() and LdFlagsFile(), achieving 100% line coverage
# on every platform.

library(rvtk)

# ── Fixture helpers ──────────────────────────────────────────────────────────

write_conf <- function(...) {
  path <- tempfile(fileext = ".conf")
  writeLines(c(...), path)
  path
}

## Build a minimal fake VTK tree under a temp dir and return its root.
## Layout: <root>/include/<inc_subdir>/ and <root>/lib/libvtkFoo<sfx>.a
make_vtk_tree <- function(inc_subdir = "vtk-9.5", libs = "libvtkFoo-9.5.a") {
  root <- tempfile("rvtk_test_")
  dir.create(file.path(root, "include", inc_subdir), recursive = TRUE)
  dir.create(file.path(root, "lib"), recursive = TRUE)
  for (lib in libs) {
    file.create(file.path(root, "lib", lib))
  }
  root
}

# ── read_vtk_conf: normal parsing ────────────────────────────────────────────

conf <- write_conf(
  "VTK_VERSION=9.5.2",
  "VTK_CPPFLAGS=-isystem/opt/vtk/include/vtk-9.5",
  "VTK_LIBS=-L/opt/vtk/lib -lvtkIOLegacy-9.5",
  "VTK_INCLUDE_DIR=/opt/vtk/include/vtk-9.5"
)

result <- rvtk:::read_vtk_conf(conf)

expect_equal(result[["VTK_VERSION"]], "9.5.2")
expect_equal(result[["VTK_CPPFLAGS"]], "-isystem/opt/vtk/include/vtk-9.5")
expect_equal(result[["VTK_LIBS"]], "-L/opt/vtk/lib -lvtkIOLegacy-9.5")
expect_equal(result[["VTK_INCLUDE_DIR"]], "/opt/vtk/include/vtk-9.5")
expect_true(is.list(result))
expect_equal(length(result), 4L)

# ── read_vtk_conf: values containing '=' are preserved intact ────────────────

conf_eq <- write_conf("KEY=a=b=c")
expect_equal(rvtk:::read_vtk_conf(conf_eq)[["KEY"]], "a=b=c")

# ── read_vtk_conf: blank lines are ignored ───────────────────────────────────

conf_blank <- write_conf(
  "",
  "   ",
  "VTK_VERSION=1.2.3",
  ""
)
res_blank <- rvtk:::read_vtk_conf(conf_blank)
expect_equal(length(res_blank), 1L)
expect_equal(res_blank[["VTK_VERSION"]], "1.2.3")

# ── read_vtk_conf: comment lines are ignored ─────────────────────────────────

conf_comment <- write_conf(
  "# This is a comment",
  "  # indented comment",
  "VTK_VERSION=3.2.1"
)
res_comment <- rvtk:::read_vtk_conf(conf_comment)
expect_equal(length(res_comment), 1L)
expect_equal(res_comment[["VTK_VERSION"]], "3.2.1")

# ── read_vtk_conf: default path uses installed vtk.conf ──────────────────────

res_default <- rvtk:::read_vtk_conf()
expect_true(is.list(res_default))
expect_true("VTK_VERSION" %in% names(res_default))
expect_true("VTK_CPPFLAGS" %in% names(res_default))
expect_true("VTK_LIBS" %in% names(res_default))

# ── read_vtk_conf: Windows block – versioned include dir (sysname Darwin) ────
# Exercises: os_type="windows" branch, versioned vdirs path, Darwin lib flags.

vtk_tree_d <- make_vtk_tree(inc_subdir = "vtk-9.5", libs = "libvtkFoo-9.5.a")
conf_win <- write_conf(
  "VTK_VERSION=9.5.2",
  "VTK_SUFFIX=-9.5",
  "VTK_SUBDIR=fake_win_vtk"
)

res_win_darwin <- rvtk:::read_vtk_conf(
  conf_win,
  os_type = "windows",
  sysname = "Darwin",
  win_base_dir = vtk_tree_d
)

expect_true(grepl("-I", res_win_darwin[["VTK_CPPFLAGS"]]))
expect_true(grepl("vtk-9\\.5", res_win_darwin[["VTK_CPPFLAGS"]]))
expect_true(grepl("-Wl,-all_load", res_win_darwin[["VTK_LIBS"]]))
expect_true(grepl("vtkFoo", res_win_darwin[["VTK_LIBS"]]))

# ── read_vtk_conf: Windows block – versioned include dir (sysname Windows) ───

res_win_windows <- rvtk:::read_vtk_conf(
  conf_win,
  os_type = "windows",
  sysname = "Windows",
  win_base_dir = vtk_tree_d
)

expect_true(grepl("-Wl,--start-group", res_win_windows[["VTK_LIBS"]]))
expect_true(grepl("-lgdi32", res_win_windows[["VTK_LIBS"]]))
expect_true(grepl("-Wl,--end-group", res_win_windows[["VTK_LIBS"]]))

# ── read_vtk_conf: Windows block – versioned include dir (sysname Linux) ─────

res_win_linux <- rvtk:::read_vtk_conf(
  conf_win,
  os_type = "windows",
  sysname = "Linux",
  win_base_dir = vtk_tree_d
)

expect_true(grepl("-Wl,--start-group", res_win_linux[["VTK_LIBS"]]))
expect_false(grepl("-lgdi32", res_win_linux[["VTK_LIBS"]]))
expect_true(grepl("-Wl,--end-group", res_win_linux[["VTK_LIBS"]]))

# ── read_vtk_conf: Windows block – unversioned "vtk" include dir ─────────────
# Exercises the `else` branch when no vtk-X.Y directory is found.

vtk_tree_u <- make_vtk_tree(inc_subdir = "vtk", libs = "libvtkBar.a")
res_win_unversioned <- rvtk:::read_vtk_conf(
  conf_win,
  os_type = "windows",
  sysname = "Linux",
  win_base_dir = vtk_tree_u
)

expect_true(grepl("vtk\"", res_win_unversioned[["VTK_CPPFLAGS"]]))
expect_true(grepl("vtkBar", res_win_unversioned[["VTK_LIBS"]]))

# ── VtkVersion ───────────────────────────────────────────────────────────────

ver <- VtkVersion()
expect_true(is.character(ver))
expect_equal(length(ver), 1L)
expect_true(grepl("^[0-9]+\\.[0-9]+", ver))

# ── CppFlags ─────────────────────────────────────────────────────────────────

cpp_out <- capture.output(cpp_val <- CppFlags())
expect_true(is.character(cpp_val))
expect_true(nchar(cpp_val) > 0L)
expect_equal(cpp_out, cpp_val)

# ── LdFlags ──────────────────────────────────────────────────────────────────

ld_out <- capture.output(ld_val <- LdFlags())
expect_true(is.character(ld_val))
expect_true(nchar(ld_val) > 0L)
expect_equal(ld_out, ld_val)

# ── LdFlagsFile: non-Windows branch ──────────────────────────────────────────

rsp_path <- file.path(tempdir(), "vtk_libs.rsp")
on.exit(unlink(rsp_path), add = TRUE)

ldff_out <- capture.output(ldff_val <- LdFlagsFile(rsp_path, os_type = "unix"))
expect_equal(ldff_val, ld_val)
expect_equal(ldff_out, ldff_val)
expect_false(file.exists(rsp_path))

# ── LdFlagsFile: Windows branch ──────────────────────────────────────────────

rsp_win <- file.path(tempdir(), "vtk_libs_win.rsp")
on.exit(unlink(rsp_win), add = TRUE)

ldff_win_out <- capture.output(
  ldff_win_val <- LdFlagsFile(rsp_win, os_type = "windows")
)
expect_equal(ldff_win_val, paste0("@", basename(rsp_win)))
expect_true(file.exists(rsp_win))
expect_equal(readLines(rsp_win), ld_val)
expect_equal(ldff_win_out, ldff_win_val)
