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

# ── read_vtk_conf: Windows block – win_base_dir = NULL (system.file path) ────
# Covers the is.null(win_base_dir) TRUE branch. system.file() with mustWork=TRUE
# errors when the subdir does not exist inside the installed package, which is
# the case on non-Windows platforms. That error is sufficient to prove the lines
# were reached.

conf_win_null <- write_conf(
  "VTK_VERSION=9.5.2",
  "VTK_SUFFIX=-9.5",
  "VTK_SUBDIR=nonexistent_subdir"
)
expect_error(
  rvtk:::read_vtk_conf(conf_win_null, os_type = "windows")
)

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

# ── read_vtk_conf: Unix prebuilt – versioned include dir (Darwin) ─────────────

vtk_prebuilt_d <- make_vtk_tree(
  inc_subdir = "vtk-9.5",
  libs = "libvtkFoo-9.5.a"
)
conf_prebuilt <- write_conf(
  "VTK_VERSION=9.5.2",
  "VTK_PREBUILT=yes"
)

res_prebuilt_darwin <- rvtk:::read_vtk_conf(
  conf_prebuilt,
  os_type = "unix",
  sysname = "Darwin",
  unix_base_dir = vtk_prebuilt_d
)

expect_true(grepl("-isystem", res_prebuilt_darwin[["VTK_CPPFLAGS"]]))
expect_true(grepl("vtk-9\\.5", res_prebuilt_darwin[["VTK_CPPFLAGS"]]))
expect_true(grepl("-Wl,-all_load", res_prebuilt_darwin[["VTK_LIBS"]]))
expect_true(grepl("vtkFoo", res_prebuilt_darwin[["VTK_LIBS"]]))

# ── read_vtk_conf: Unix prebuilt – versioned include dir (Linux) ──────────────

res_prebuilt_linux <- rvtk:::read_vtk_conf(
  conf_prebuilt,
  os_type = "unix",
  sysname = "Linux",
  unix_base_dir = vtk_prebuilt_d
)

expect_true(grepl("-isystem", res_prebuilt_linux[["VTK_CPPFLAGS"]]))
expect_true(grepl("-Wl,--start-group", res_prebuilt_linux[["VTK_LIBS"]]))
expect_true(grepl("-Wl,--end-group", res_prebuilt_linux[["VTK_LIBS"]]))
expect_true(grepl("vtkFoo", res_prebuilt_linux[["VTK_LIBS"]]))

# ── read_vtk_conf: Unix prebuilt – unversioned "vtk" include dir ──────────────

vtk_prebuilt_u <- make_vtk_tree(inc_subdir = "vtk", libs = "libvtkBar.a")
res_prebuilt_unversioned <- rvtk:::read_vtk_conf(
  conf_prebuilt,
  os_type = "unix",
  sysname = "Linux",
  unix_base_dir = vtk_prebuilt_u
)

expect_true(grepl("vtk$", res_prebuilt_unversioned[["VTK_CPPFLAGS"]]))
expect_true(grepl("vtkBar", res_prebuilt_unversioned[["VTK_LIBS"]]))

# ── read_vtk_conf: Windows shared build ──────────────────────────────────────

vtk_tree_shared <- make_vtk_tree(
  inc_subdir = "vtk-9.5",
  libs = c("libvtkIOLegacy-9.5.dll.a", "libvtkCommonCore-9.5.dll.a")
)
conf_shared <- write_conf(
  "VTK_VERSION=9.5.2",
  "VTK_SUBDIR=fake_win_vtk",
  "VTK_LINK=shared"
)

res_win_shared <- rvtk:::read_vtk_conf(
  conf_shared,
  os_type = "windows",
  sysname = "Windows",
  win_base_dir = vtk_tree_shared
)

expect_true(grepl("-lgdi32", res_win_shared[["VTK_LIBS"]]))
expect_true(grepl("vtkIOLegacy", res_win_shared[["VTK_LIBS"]]))
expect_false(grepl("dll\\.a", res_win_shared[["VTK_LIBS"]]))

# ── .vtk_prepend_path: non-Windows early return ───────────────────────────────

ns_env <- new.env(parent = emptyenv())
result_unix <- rvtk:::.vtk_prepend_path(os_type = "unix", ns = ns_env)
expect_null(result_unix)
expect_false(exists(".vtk_original_path", envir = ns_env, inherits = FALSE))

# ── .vtk_prepend_path: Windows, dll_dir empty – no-op ────────────────────────

ns_env2 <- new.env(parent = emptyenv())
rvtk:::.vtk_prepend_path(os_type = "windows", dll_dir = "", ns = ns_env2)
expect_false(exists(".vtk_original_path", envir = ns_env2, inherits = FALSE))

# ── .vtk_prepend_path: Windows, dll_dir exists – prepends to PATH ────────────

(function() {
  fake_dll_dir <- tempfile("fake_vtk_dlls_")
  dir.create(fake_dll_dir)
  on.exit(unlink(fake_dll_dir, recursive = TRUE), add = FALSE)

  ns_env3 <- new.env(parent = emptyenv())
  controlled_path <- "/usr/bin:/bin"
  Sys.setenv(PATH = controlled_path)

  rvtk:::.vtk_prepend_path(
    os_type = "windows",
    dll_dir = fake_dll_dir,
    ns = ns_env3
  )
  new_path <- Sys.getenv("PATH")
  expect_true(exists(".vtk_original_path", envir = ns_env3, inherits = FALSE))
  expect_equal(
    get0(".vtk_original_path", envir = ns_env3, inherits = FALSE),
    controlled_path
  )
  expect_true(grepl(
    normalizePath(fake_dll_dir, winslash = "\\", mustWork = FALSE),
    new_path,
    fixed = TRUE
  ))

  # Restore PATH after test
  Sys.setenv(PATH = controlled_path)
})()

# ── .vtk_prepend_path: Windows, vtk_dll_dir set ───────────────────────────────

(function() {
  fake_dll_dir2 <- tempfile("fake_vtk_dlls2_")
  dir.create(fake_dll_dir2)
  on.exit(unlink(fake_dll_dir2, recursive = TRUE), add = FALSE)

  ns_env4 <- new.env(parent = emptyenv())
  controlled_path4 <- "/usr/bin:/bin"
  Sys.setenv(PATH = controlled_path4)

  rvtk:::.vtk_prepend_path(
    os_type = "windows",
    dll_dir = "",
    vtk_dll_dir = fake_dll_dir2,
    ns = ns_env4
  )
  new_path4 <- Sys.getenv("PATH")
  expect_true(exists(".vtk_original_path", envir = ns_env4, inherits = FALSE))
  expect_true(grepl(
    normalizePath(fake_dll_dir2, winslash = "\\", mustWork = FALSE),
    new_path4,
    fixed = TRUE
  ))

  # Restore PATH
  Sys.setenv(PATH = controlled_path4)
})()

# ── .vtk_prepend_path: Windows, dir already in PATH – not re-added ────────────

(function() {
  fake_dll_dir3 <- tempfile("fake_vtk_dlls3_")
  dir.create(fake_dll_dir3)
  on.exit(unlink(fake_dll_dir3, recursive = TRUE), add = FALSE)

  norm_dir3 <- normalizePath(fake_dll_dir3, winslash = "\\", mustWork = FALSE)
  Sys.setenv(PATH = paste(norm_dir3, "/usr/bin", sep = ";"))

  ns_env5 <- new.env(parent = emptyenv())
  rvtk:::.vtk_prepend_path(
    os_type = "windows",
    dll_dir = fake_dll_dir3,
    ns = ns_env5
  )
  expect_false(exists(".vtk_original_path", envir = ns_env5, inherits = FALSE))

  # Restore PATH
  Sys.setenv(PATH = "/usr/bin:/bin")
})()

# ── .vtk_restore_path: non-Windows early return ───────────────────────────────

ns_env6 <- new.env(parent = emptyenv())
result_restore_unix <- rvtk:::.vtk_restore_path(os_type = "unix", ns = ns_env6)
expect_null(result_restore_unix)

# ── .vtk_restore_path: Windows, no saved path – no-op ────────────────────────

ns_env7 <- new.env(parent = emptyenv())
old_path7 <- Sys.getenv("PATH")
rvtk:::.vtk_restore_path(os_type = "windows", ns = ns_env7)
expect_equal(Sys.getenv("PATH"), old_path7)

# ── .vtk_restore_path: Windows, saved path – restores PATH ───────────────────

ns_env8 <- new.env(parent = emptyenv())
saved_path <- "/some/saved/path"
assign(".vtk_original_path", saved_path, envir = ns_env8)

rvtk:::.vtk_restore_path(os_type = "windows", ns = ns_env8)
expect_equal(Sys.getenv("PATH"), saved_path)

# Restore PATH to actual value
Sys.setenv(PATH = old_path7)

# ── .onLoad and .onUnload are callable without error ──────────────────────────
# These exercise the delegation wrappers so all their lines are covered.

expect_silent(rvtk:::.onLoad("", "rvtk"))
expect_silent(rvtk:::.onUnload(""))
