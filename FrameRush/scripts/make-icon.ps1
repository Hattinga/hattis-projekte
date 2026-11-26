# Draws the FrameRush icon and writes
#   assets\framerush.ico   16-64 px as 32-bit bitmaps, 256 px as PNG
#   assets\framerush.png   256 x 256 preview
#
# Each size is drawn on its own (not scaled down from 256), so the small
# ones stay sharp: below 48 px the glow and the live dot are left out, at
# 16 px the frame corners too.
#
# Usage (from the FrameRush folder):
#   powershell -ExecutionPolicy Bypass -File scripts\make-icon.ps1
#
# The .ico is checked in; run this only after changing the design.
# scripts\package.ps1 embeds the .ico into FrameRush.exe.
param(
    [string]$OutDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets'),
    [int[]]$Sizes = @(16, 20, 24, 32, 40, 48, 64, 256)
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function New-Argb([int]$a, [string]$hex) {
    $rgb = [Convert]::ToInt32($hex.TrimStart('#'), 16)
    [System.Drawing.Color]::FromArgb($a, ($rgb -shr 16) -band 255, ($rgb -shr 8) -band 255, $rgb -band 255)
}

function New-RoundedRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $d = 2 * $r
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    $p
}

function New-Points([float[]]$xy) {
    $points = New-Object 'System.Drawing.PointF[]' ($xy.Length / 2)
    for ($i = 0; $i -lt $points.Length; $i++) {
        $points[$i] = New-Object System.Drawing.PointF($xy[2 * $i], $xy[2 * $i + 1])
    }
    , $points
}

# Draws the icon at $size x $size pixels. All coordinates below are in a
# 256 x 256 design space; the graphics transform scales them.
function New-IconBitmap([int]$size) {
    $s = $size / 256.0
    $px = 1.0 / $s   # one device pixel in design units
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.ScaleTransform($s, $s)

    # Tile: deep indigo to night blue, with a violet glow in the middle.
    $margin = [Math]::Max(8, 0.5 * $px)
    $tile = New-RoundedRect $margin $margin (256 - 2 * $margin) (256 - 2 * $margin) 54
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF(0, 0)), (New-Object System.Drawing.PointF(256, 256)),
        (New-Argb 255 '#33206E'), (New-Argb 255 '#070C24'))
    $g.FillPath($bg, $tile)
    $g.SetClip($tile)
    $glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $glowPath.AddEllipse(8, 18, 240, 220)
    $glow = New-Object System.Drawing.Drawing2D.PathGradientBrush($glowPath)
    $glow.CenterColor = New-Argb 120 '#7C3AED'
    $glow.SurroundColors = @((New-Argb 0 '#7C3AED'))
    $g.FillPath($glow, $glowPath)
    # Soft sheen on the upper half.
    $sheen = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF(0, -2)), (New-Object System.Drawing.PointF(0, 136)),
        (New-Argb 34 '#FFFFFF'), (New-Argb 0 '#FFFFFF'))
    $g.FillRectangle($sheen, 0, 0, 256, 130)
    $g.ResetClip()
    $rim = New-Object System.Drawing.Pen((New-Argb 60 '#A5B4FC'), [Math]::Max(3, $px))
    $g.DrawPath($rim, $tile)

    # Capture frame: four viewfinder corners, cyan to violet.
    if ($size -gt 16) {
        $l = 34; $t = 74; $r = 222; $b = 182
        $arm = 36
        $width = [Math]::Max(15, 2 * $px)
        $frameBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.PointF(($l - 12), ($t - 12))), (New-Object System.Drawing.PointF(($r + 12), ($b + 12))),
            (New-Argb 255 '#2EE6FF'), (New-Argb 255 '#A78BFA'))
        $pen = New-Object System.Drawing.Pen($frameBrush, $width)
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        foreach ($corner in @(
                @($l, ($t + $arm), $l, $t, ($l + $arm), $t),
                @(($r - $arm), $t, $r, $t, $r, ($t + $arm)),
                @($r, ($b - $arm), $r, $b, ($r - $arm), $b),
                @(($l + $arm), $b, $l, $b, $l, ($b - $arm)))) {
            $g.DrawLines($pen, (New-Points $corner))
        }

        # Live dot, top left inside the frame.
        if ($size -ge 48) {
            $dotGlow = New-Object System.Drawing.SolidBrush((New-Argb 70 '#FF3D71'))
            $g.FillEllipse($dotGlow, 50, 90, 26, 26)
            $dot = New-Object System.Drawing.SolidBrush((New-Argb 255 '#FF3D71'))
            $g.FillEllipse($dot, 55, 95, 16, 16)
        }
    }

    # Lightning bolt breaking out of the frame: yellow to orange to pink.
    $bolt = New-Object System.Drawing.Drawing2D.GraphicsPath
    if ($size -le 16) {
        # Bigger and simpler, fills the tile.
        $bolt.AddPolygon((New-Points @(138, 26, 196, 26, 156, 104, 204, 104, 92, 232, 120, 140, 64, 140)))
    } else {
        $bolt.AddPolygon((New-Points @(134, 38, 182, 38, 150, 106, 190, 106, 102, 220, 124, 138, 76, 138)))
    }
    if ($size -ge 48) {
        foreach ($halo in @(@(34, 22), @(22, 40), @(12, 70))) {
            $haloPen = New-Object System.Drawing.Pen((New-Argb $halo[1] '#FF8A3D'), $halo[0])
            $haloPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
            $g.DrawPath($haloPen, $bolt)
        }
    }
    $boltBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF(0, 18)), (New-Object System.Drawing.PointF(0, 242)),
        (New-Argb 255 '#FFE45C'), (New-Argb 255 '#FF4D6D'))
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend(3)
    $blend.Colors = @((New-Argb 255 '#FFF27A'), (New-Argb 255 '#FF9A3C'), (New-Argb 255 '#FF4D6D'))
    $blend.Positions = @(0.0, 0.55, 1.0)
    $boltBrush.InterpolationColors = $blend
    $g.FillPath($boltBrush, $bolt)
    # Thin light edge so the bolt reads on the dark tile at small sizes.
    $edge = New-Object System.Drawing.Pen((New-Argb 150 '#FFF7C2'), [Math]::Max(3, 0.6 * $px))
    $edge.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawPath($edge, $bolt)

    $g.Dispose()
    $bmp
}

function ConvertTo-PngBytes([System.Drawing.Bitmap]$bmp) {
    $stream = New-Object System.IO.MemoryStream
    $bmp.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    , $stream.ToArray()
}

# Classic icon image: BITMAPINFOHEADER (height counts color + mask), 32-bit
# BGRA rows bottom-up, then the 1-bit AND mask (set where fully
# transparent). Readable by every icon consumer, unlike PNG entries.
function ConvertTo-DibBytes([System.Drawing.Bitmap]$bmp) {
    $n = $bmp.Width
    $rect = New-Object System.Drawing.Rectangle(0, 0, $n, $n)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $pixels = New-Object byte[] ($n * $n * 4)
    try {
        # Stride is $n * 4 for 32-bit pixels; rows are top-down.
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
    } finally {
        $bmp.UnlockBits($data)
    }
    $maskStride = [int]([Math]::Ceiling($n / 32.0) * 4)
    $mask = New-Object byte[] ($maskStride * $n)
    $out = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter($out)
    $w.Write([uint32]40); $w.Write([int32]$n); $w.Write([int32](2 * $n))
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]0)
    $w.Write([uint32]($pixels.Length + $mask.Length))
    $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
    for ($row = $n - 1; $row -ge 0; $row--) {
        $w.Write($pixels, $row * $n * 4, $n * 4)
        $maskRow = ($n - 1 - $row) * $maskStride
        for ($x = 0; $x -lt $n; $x++) {
            if ($pixels[($row * $n + $x) * 4 + 3] -eq 0) {
                $mask[$maskRow + ($x -shr 3)] = $mask[$maskRow + ($x -shr 3)] -bor (0x80 -shr ($x -band 7))
            }
        }
    }
    $w.Write($mask)
    $w.Flush()
    , $out.ToArray()
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$images = foreach ($size in $Sizes) {
    $bmp = New-IconBitmap $size
    if ($size -eq 256) {
        $bmp.Save((Join-Path $OutDir 'framerush.png'), [System.Drawing.Imaging.ImageFormat]::Png)
        $bytes = ConvertTo-PngBytes $bmp   # 256 px: PNG, as Windows expects
    } else {
        $bytes = ConvertTo-DibBytes $bmp
    }
    [pscustomobject]@{ Size = $size; Data = $bytes }
    $bmp.Dispose()
}

# ICO container: ICONDIR, one ICONDIRENTRY per image, then the PNG data.
$out = New-Object System.IO.MemoryStream
$w = New-Object System.IO.BinaryWriter($out)
$w.Write([uint16]0)              # reserved
$w.Write([uint16]1)              # type: icon
$w.Write([uint16]$images.Count)
$offset = 6 + 16 * $images.Count
foreach ($img in $images) {
    $dim = if ($img.Size -ge 256) { 0 } else { $img.Size }   # 0 means 256
    $w.Write([byte]$dim)         # width
    $w.Write([byte]$dim)         # height
    $w.Write([byte]0)            # palette colors
    $w.Write([byte]0)            # reserved
    $w.Write([uint16]1)          # color planes
    $w.Write([uint16]32)         # bits per pixel
    $w.Write([uint32]$img.Data.Length)
    $w.Write([uint32]$offset)
    $offset += $img.Data.Length
}
foreach ($img in $images) { $w.Write($img.Data) }
$w.Flush()
$ico = Join-Path $OutDir 'framerush.ico'
[System.IO.File]::WriteAllBytes($ico, $out.ToArray())
Write-Host ("{0}  {1} sizes, {2:N1} KB" -f $ico, $images.Count, ($out.Length / 1KB))
