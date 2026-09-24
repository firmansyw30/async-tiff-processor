import sys
import os
import time
import numpy as np
from osgeo import gdal

gdal.UseExceptions()

from osgeo import osr

_proj_dir = os.path.join(sys.prefix, "Library", "share", "proj")
if os.path.exists(os.path.join(_proj_dir, "proj.db")):
    osr.SetPROJSearchPaths([_proj_dir])

# Cache GDAL 1 GB (adjust according to RAM). Helps if input is a strip.
gdal.SetCacheMax(1024 * 1024 * 1024)
gdal.SetConfigOption("GDAL_NUM_THREADS", "ALL_CPUS")

# Windows size read/write (pixels). 2048x2048 ~ 16 MB per RGBA window.
BLOCK = 2048

# Output options. ZLEVEL=1 is much faster than default (6) with not much difference in file size. If your GDAL supports ZSTD, change to:
# COMPRESS=ZSTD, ZSTD_LEVEL=1
CREATE_OPTIONS = [
    "TILED=YES",
    "BLOCKXSIZE=512",
    "BLOCKYSIZE=512",
    "COMPRESS=DEFLATE",
    "ZLEVEL=1",
    "PREDICTOR=2",
    "NUM_THREADS=ALL_CPUS",   # Multi-thread compression
    "BIGTIFF=IF_SAFER",       # Required for output > 4 GB
    "PHOTOMETRIC=RGB",
    "ALPHA=YES",
]


def build_palette_lut(band, ct, transparent_color):
    """Lookup table (N x 4) dari color table: index -> RGBA."""
    n = 256 if band.DataType == gdal.GDT_Byte else 65536
    lut = np.zeros((n, 4), dtype=np.uint8)

    for i in range(min(ct.GetCount(), n)):
        lut[i] = ct.GetColorEntry(i)

    # Entry palette which color = transparent_color -> alpha 0
    tr, tg, tb = transparent_color
    white = (lut[:, 0] == tr) & (lut[:, 1] == tg) & (lut[:, 2] == tb)
    lut[white, 3] = 0

    print(f"Palette entries transparan: {np.flatnonzero(white).tolist()}")

    # One array per channel for fast indexing
    return [np.ascontiguousarray(lut[:, k]) for k in range(4)]


def make_transparent(src, dst=None, transparent_color=(255, 255, 255), block=BLOCK):
    t0 = time.time()
    ds = gdal.Open(src)

    if dst is None:
        base, _ = os.path.splitext(src)
        dst = f"{base}_transparent.tif"

    print(f"Input  : {src}")
    print(f"Output : {dst}")

    xsize, ysize = ds.RasterXSize, ds.RasterYSize
    nbands = ds.RasterCount
    band1 = ds.GetRasterBand(1)
    ct = band1.GetColorTable()

    if ct is not None:
        print("Type   : Palette")
        lut = build_palette_lut(band1, ct, transparent_color)
    elif nbands >= 3:
        print(f"Type   : {'RGBA' if nbands >= 4 else 'RGB'}")
        in_bands = [ds.GetRasterBand(i) for i in (1, 2, 3)]
        alpha_band = ds.GetRasterBand(4) if nbands >= 4 else None
    else:
        raise RuntimeError("Raster not Pallete and not RGB/RGBA.")

    print(f"Size   : {xsize:,} x {ysize:,} px")

    driver = gdal.GetDriverByName("GTiff")
    out = driver.Create(dst, xsize, ysize, 4, gdal.GDT_Byte, options=CREATE_OPTIONS)
    out.SetGeoTransform(ds.GetGeoTransform())
    out.SetProjection(ds.GetProjection())

    out_bands = [out.GetRasterBand(i) for i in (1, 2, 3, 4)]
    for b, ci in zip(out_bands, (gdal.GCI_RedBand, gdal.GCI_GreenBand,
                                 gdal.GCI_BlueBand, gdal.GCI_AlphaBand)):
        b.SetColorInterpretation(ci)

    tr, tg, tb = transparent_color
    n_white = 0
    total = ((ysize + block - 1) // block) * ((xsize + block - 1) // block)
    done = 0

    for yoff in range(0, ysize, block):
        ys = min(block, ysize - yoff)

        for xoff in range(0, xsize, block):
            xs = min(block, xsize - xoff)

            if ct is not None:
                # ---------- PALETTE: lookup only, without loop each color entry ----------
                idx = band1.ReadAsArray(xoff, yoff, xs, ys)
                for k in range(4):
                    out_bands[k].WriteArray(lut[k][idx], xoff, yoff)
            else:
                # ---------- RGB / RGBA ----------
                r = in_bands[0].ReadAsArray(xoff, yoff, xs, ys)
                g = in_bands[1].ReadAsArray(xoff, yoff, xs, ys)
                b = in_bands[2].ReadAsArray(xoff, yoff, xs, ys)

                white = (r == tr) & (g == tg) & (b == tb)
                n_white += int(np.count_nonzero(white))

                if alpha_band is not None:
                    a = alpha_band.ReadAsArray(xoff, yoff, xs, ys)
                    a[white] = 0
                else:
                    a = np.where(white, 0, 255).astype(np.uint8)

                out_bands[0].WriteArray(r, xoff, yoff)
                out_bands[1].WriteArray(g, xoff, yoff)
                out_bands[2].WriteArray(b, xoff, yoff)
                out_bands[3].WriteArray(a, xoff, yoff)

            done += 1
            gdal.TermProgress_nocb(done / total)

    if ct is None:
        print(f"White pixels: {n_white:,}")

    out.FlushCache()
    out = None
    ds = None

    print(f"Completed in {time.time() - t0:.1f} seconds.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print('  python make_transparent.py "input.tif" ["output.tif"]')
        sys.exit(1)

    make_transparent(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)