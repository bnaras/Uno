## Generate the Uno hex sticker.
##
## Source of truth = THIS script: the saddle-surface ("optimization landscape")
## wireframe is generated in R, so colour, view and density are fully under our
## control and the mesh is contained inside the hex (no leak). Renders
## man/figures/logo.png (+ logo@2x.png for Retina) and refreshes the pkgdown
## favicons. Run from the package root:
##
##   Rscript tools/build-logo.R
##
## tools/ is .Rbuildignore'd, so this script is not shipped in the tarball.
##
## Palette (sampled from the upstream Uno brand, docs/figures/logo.png):
##   Hex fill ...... #5171a5  slate blue (upstream background)
##   Hex border .... #324f80  darker slate
##   Mesh .......... #d4e6fb  pale periwinkle wireframe
##   Wordmark ...... #ffffff  white "Uno"

suppressMessages({library(hexSticker); library(grDevices)})

SLATE  <- "#5171a5"
BORDER <- "#324f80"
MESH   <- "#d4e6fb"
WORD   <- "#ffffff"

## Saddle (hyperbolic-paraboloid z = x^2 - y^2) wireframe -> transparent PNG.
mesh_png <- function(file, col = MESH, lwd = 1.0, theta = 35, phi = 28, n = 28) {
  x <- seq(-1, 1, length.out = n); y <- seq(-1, 1, length.out = n)
  z <- outer(x, y, function(x, y) x^2 - y^2)
  grDevices::png(file, width = 1100, height = 1100, bg = "transparent")
  op <- par(mar = c(0, 0, 0, 0))
  persp(x, y, z, theta = theta, phi = phi, col = NA, border = col, lwd = lwd,
        box = FALSE, axes = FALSE, scale = FALSE, expand = 0.55, r = 3, d = 2)
  par(op); grDevices::dev.off(); file
}

build <- function(out, dpi) {
  m <- mesh_png(tempfile(fileext = ".png"))
  sticker(
    # mesh in the lower-centre; large all-caps wordmark up top
    subplot = m, s_x = 1.0, s_y = 0.80, s_width = 0.66, s_height = 0.66,
    package = "UNO", p_x = 1.0, p_y = 1.46, p_size = 26, p_color = WORD,
    p_family = "sans", p_fontface = "plain",
    h_fill = SLATE, h_color = BORDER, h_size = 1.4,
    dpi = dpi, filename = out
  )
  cat("wrote", out, "\n")
}

build("man/figures/logo.png",    320)   # standard
build("man/figures/logo@2x.png", 640)   # Retina

if (requireNamespace("pkgdown", quietly = TRUE)) {
  cat("Rebuilding pkgdown favicons...\n")
  try(pkgdown::build_favicons(overwrite = TRUE), silent = TRUE)
}
