# Builds web-sized copies of the originals and writes galleries.js.
# Originals in originales/ are only read, never modified.
# Usage (from PowerShell, in this folder):
#   .\build-images.ps1                                  all sections, only new files
#   .\build-images.ps1 -Sections WORLDBUILDING,ABOUT    some sections
#   .\build-images.ps1 -Force                           regenerate everything
#   .\build-images.ps1 -Sections HOME                   only refresh the Home selection (home.txt)
# If scripts are blocked: powershell -ExecutionPolicy Bypass -Command "& .\build-images.ps1"
param(
  [string[]]$Sections = @('WORLDBUILDING','CHARACTERS','ADVERTISING','WOLFBOY','HOUSEBROKEN','ABOUT','HEADER'),
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = $PSScriptRoot
$src  = Join-Path $root 'originales'
$out  = Join-Path $root 'images'

# Folder in originales -> id used by the site
$IDS = [ordered]@{ WORLDBUILDING='world-building'; CHARACTERS='characters'; ADVERTISING='advertising'; WOLFBOY='wolfboy'; HOUSEBROKEN='house-broken' }
# Output sizes: sm = slot thumbnail (short side), md = side panel / phone (long side), full = lightbox (long side)
$SM_SHORT = 320; $MD_LONG = 1100; $FULL_LONG = 2400

$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
function Save-Resized($img, [int]$w, [int]$h, [string]$path, [bool]$png, [int]$quality = 84) {
  if ((Test-Path $path) -and -not $Force) { return }
  $bmp = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'; $g.CompositingQuality = 'HighQuality'
  if (-not $png) { $g.Clear([System.Drawing.Color]::White) }
  $attr = New-Object System.Drawing.Imaging.ImageAttributes
  $attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $w, $h), 0, 0, $img.Width, $img.Height, 'Pixel', $attr)
  $g.Dispose()
  if ($png) { $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png) }
  else {
    $ep = New-Object System.Drawing.Imaging.EncoderParameters 1
    $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([long]$quality)
    $bmp.Save($path, $jpegCodec, $ep)
  }
  $bmp.Dispose()
}
function Save-Icon($img, [int]$size, [string]$path, $bg, [double]$pad, [string]$tint = '#b8873a') {
  if ((Test-Path $path) -and -not $Force) { return }
  $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'
  if ($bg) { $g.Clear([System.Drawing.ColorTranslator]::FromHtml($bg)) } else { $g.Clear([System.Drawing.Color]::Transparent) }
  $inner = $size * (1 - 2 * $pad); $k = $inner / [math]::Max($img.Width, $img.Height)
  $w = $img.Width * $k; $h = $img.Height * $k
  # Repaint the mark in one flat colour (keeps the original alpha, so the brush texture stays)
  $c = [System.Drawing.ColorTranslator]::FromHtml($tint)
  $cm = New-Object System.Drawing.Imaging.ColorMatrix
  $cm.Matrix00 = 0; $cm.Matrix11 = 0; $cm.Matrix22 = 0; $cm.Matrix33 = 1
  $cm.Matrix40 = $c.R / 255; $cm.Matrix41 = $c.G / 255; $cm.Matrix42 = $c.B / 255
  $attr = New-Object System.Drawing.Imaging.ImageAttributes; $attr.SetColorMatrix($cm)
  $x = [int](($size - $w) / 2); $y = [int](($size - $h) / 2)
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle $x, $y, ([int]$w), ([int]$h)), 0, 0, $img.Width, $img.Height, 'Pixel', $attr)
  $g.Dispose(); $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
# Crop a transparent image to the box of its visible pixels (alpha > 8), plus a 2% margin
function Trim-Transparent($img) {
  $b = New-Object System.Drawing.Bitmap $img
  $rect = New-Object System.Drawing.Rectangle 0, 0, $b.Width, $b.Height
  $d = $b.LockBits($rect, 'ReadOnly', ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb))
  $bytes = New-Object byte[] ($d.Stride * $b.Height)
  [System.Runtime.InteropServices.Marshal]::Copy($d.Scan0, $bytes, 0, $bytes.Length); $b.UnlockBits($d)
  $minX = $b.Width; $minY = $b.Height; $maxX = -1; $maxY = -1; $st = $d.Stride
  for ($y = 0; $y -lt $b.Height; $y++) { $row = $y * $st
    for ($x = 0; $x -lt $b.Width; $x++) { if ($bytes[$row + $x * 4 + 3] -gt 8) {
      if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }; if ($y -lt $minY) { $minY = $y }; $maxY = $y } } }
  if ($maxX -lt 0) { $b.Dispose(); return $img }
  $m = [int]([math]::Max($maxX - $minX, $maxY - $minY) * 0.02)
  $minX = [math]::Max(0, $minX - $m); $minY = [math]::Max(0, $minY - $m)
  $maxX = [math]::Min($b.Width - 1, $maxX + $m); $maxY = [math]::Min($b.Height - 1, $maxY + $m)
  $crop = $b.Clone((New-Object System.Drawing.Rectangle $minX, $minY, ($maxX - $minX + 1), ($maxY - $minY + 1)), $b.PixelFormat)
  $b.Dispose(); return $crop
}
function Fit([int]$w, [int]$h, [int]$long) { $s = [math]::Min(1.0, $long / [math]::Max($w, $h)); return @([int][math]::Round($w * $s), [int][math]::Round($h * $s)) }
function Slug([string]$name) { ($name.ToLower() -replace '[^a-z0-9]+', '-').Trim('-') }
function HasAlpha($img) {
  if (-not [System.Drawing.Image]::IsAlphaPixelFormat($img.PixelFormat)) { return $false }
  $b = New-Object System.Drawing.Bitmap $img
  $sx = [math]::Max(1, [int]($b.Width / 30)); $sy = [math]::Max(1, [int]($b.Height / 30))
  for ($y = 0; $y -lt $b.Height; $y += $sy) { for ($x = 0; $x -lt $b.Width; $x += $sx) { if ($b.GetPixel($x, $y).A -lt 250) { $b.Dispose(); return $true } } }
  $b.Dispose(); return $false
}
# Order: if orden/<SECTION>.txt exists, files listed there come first in that order; the rest follow in natural name order.
function Files($dir) {
  $list = Get-ChildItem $dir -File | Where-Object { $_.Extension -match '^\.(png|jpe?g)$' }
  $orderFile = Join-Path $root ("orden\" + (Split-Path $dir -Leaf) + '.txt')
  $rank = @{}
  if (Test-Path $orderFile) {
    $n = 0
    foreach ($l in Get-Content $orderFile -Encoding UTF8) { $t = $l.Trim(); if ($t -and -not $t.StartsWith('#')) { $rank[$t.ToLower()] = $n++ } }
  }
  $list | Sort-Object @{ Expression = { if ($rank.ContainsKey($_.Name.ToLower())) { $rank[$_.Name.ToLower()] } else { 100000 } } },
                      @{ Expression = { [regex]::Replace($_.Name, '\d+', { $args[0].Value.PadLeft(8, '0') }) } }
}

# Existing galleries.js data is kept for sections not rebuilt this run
$data = @{}
$jsPath = Join-Path $root 'galleries.js'
$cachePath = Join-Path $out 'manifest.json'
if (Test-Path $cachePath) { (Get-Content $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $data[$_.Name] = $_.Value } }

foreach ($sec in $Sections) {
  if ($sec -eq 'HOME') { continue }   # handled after the sections, from home.txt
  if ($sec -eq 'HEADER') {
    # Wide image = site title (transparent PNG, 200px tall). Square-ish image = favicon / app icons.
    $o = Join-Path $out 'header'; New-Item -ItemType Directory -Force $o | Out-Null
    foreach ($f in Files (Join-Path $src $sec)) {
      $img = [System.Drawing.Image]::FromFile($f.FullName)
      if ($img.Width / $img.Height -gt 1.5) {
        $h = [math]::Min(200, $img.Height); $w = [int][math]::Round($img.Width * $h / $img.Height)
        Save-Resized $img $w $h (Join-Path $o 'title.png') $true
        $data['header'] = [pscustomobject]@{ src = 'images/header/title.png'; w = $w; h = $h }
        Write-Host "HEADER title  $($f.Name)"
      } else {
        $io = Join-Path $out 'icons'; New-Item -ItemType Directory -Force $io | Out-Null
        foreach ($s in 16, 32, 48) { Save-Icon $img $s (Join-Path $io "favicon-$s.png") $null 0 }
        # Home-screen icons can't be transparent on iOS: ochre mark on the header's dark grey, with margin
        Save-Icon $img 180 (Join-Path $io 'apple-touch-icon.png') '#36342f' 0.14
        foreach ($s in 192, 512) { Save-Icon $img $s (Join-Path $io "icon-$s.png") '#36342f' 0.14 }
        Write-Host "HEADER icon   $($f.Name)"
      }
      $img.Dispose()
    }
    continue
  }
  $dir = Join-Path $src $sec
  if (-not (Test-Path $dir)) { Write-Warning "Missing $dir"; continue }
  if ($sec -eq 'ABOUT') {
    $o = Join-Path $out 'about'; New-Item -ItemType Directory -Force $o | Out-Null
    $logos = @(); $photo = $null
    foreach ($f in Files $dir) {
      $img = [System.Drawing.Image]::FromFile($f.FullName)
      $slug = Slug $f.BaseName
      if (HasAlpha $img) {
        $trim = Trim-Transparent $img          # drop the empty margin around the logo
        $s = Fit $trim.Width $trim.Height 360
        Save-Resized $trim $s[0] $s[1] (Join-Path $o "logo-$slug.png") $true
        if ($trim -ne $img) { $trim.Dispose() }
        $logos += "images/about/logo-$slug.png"
      } else {
        $s = Fit $img.Width $img.Height 900
        Save-Resized $img $s[0] $s[1] (Join-Path $o 'photo.jpg') $false 88
        $photo = 'images/about/photo.jpg'
      }
      $img.Dispose(); Write-Host "ABOUT  $($f.Name)"
    }
    $data['about'] = [pscustomobject]@{ photo = $photo; logos = $logos }
    continue
  }
  $id = $IDS[$sec]; $o = Join-Path $out $id
  New-Item -ItemType Directory -Force $o | Out-Null
  $list = @()
  foreach ($f in Files $dir) {
    $img = [System.Drawing.Image]::FromFile($f.FullName)
    $slug = Slug $f.BaseName
    $full = Fit $img.Width $img.Height $FULL_LONG
    $md = Fit $img.Width $img.Height $MD_LONG
    $k = [math]::Min(1.0, $SM_SHORT / [math]::Min($img.Width, $img.Height))
    Save-Resized $img $full[0] $full[1] (Join-Path $o "$slug.jpg") $false 84
    Save-Resized $img $md[0] $md[1] (Join-Path $o "$slug-md.jpg") $false 82
    Save-Resized $img ([int]($img.Width * $k)) ([int]($img.Height * $k)) (Join-Path $o "$slug-sm.jpg") $false 80
    $list += [pscustomobject]@{ src = "images/$id/$slug"; w = $img.Width; h = $img.Height; title = '' }
    $img.Dispose(); Write-Host "$sec  $($f.Name)"
  }
  $data[$id] = $list
}

# Home: a curated list (home.txt) of artworks already built in their sections
$homeTxt = Join-Path $root 'home.txt'
if (Test-Path $homeTxt) {
  $homeList = @()
  foreach ($line in Get-Content $homeTxt -Encoding UTF8) {
    $name = $line.Trim()
    if (-not $name -or $name.StartsWith('#')) { continue }
    $slug = Slug ([IO.Path]::GetFileNameWithoutExtension($name))
    $hit = $null
    foreach ($k in $IDS.Values) { if ($data[$k]) { $hit = @($data[$k]) | Where-Object { $_.src -eq "images/$k/$slug" } | Select-Object -First 1 }; if ($hit) { break } }
    if ($hit) { $homeList += $hit } else { Write-Warning "home.txt: '$name' not found in any built section" }
  }
  $data['home'] = $homeList
  Write-Host "Home: $($homeList.Count) artworks"
}

New-Item -ItemType Directory -Force $out | Out-Null
$json = $data | ConvertTo-Json -Depth 5
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($cachePath, $json, $utf8)
[IO.File]::WriteAllText($jsPath, "/* Generated by build-images.ps1. Do not edit by hand. */`nwindow.GALLERIES = $json;`n", $utf8)
Write-Host "Wrote galleries.js"
