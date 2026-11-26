#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$InputFolder,
    [string]$OutputFolder,
    [ValidateRange(72,1200)][int]$Dpi = 300
)

Clear-Host
Write-Host "=== EXPORT4PDF2TIFF ===" -ForegroundColor Cyan

try {
    # Weryfikacja katalogu i narzedzi
    if ([string]::IsNullOrWhiteSpace($InputFolder)) {
        $InputFolder = (Read-Host "Enter PDF folder path").Trim().Trim('"')
    }
    if ([string]::IsNullOrWhiteSpace($InputFolder)) {
        throw "Input folder is required."
    }
    $InputDir = Get-Item -LiteralPath $InputFolder -ErrorAction Stop
    if (-not $InputDir.PSIsContainer -or $InputDir.PSProvider.Name -ne 'FileSystem') {
        throw "Input must be a filesystem directory."
    }
    $Magick = Get-Command magick.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $MagickExe = 'C:\Program Files\ImageMagick\magick.exe'
    if ($Magick) { $MagickExe = $Magick.Source }
    if (-not (Test-Path -LiteralPath $MagickExe -PathType Leaf)) {
        throw "ImageMagick executable not found."
    }
    $Files = @(Get-ChildItem -LiteralPath $InputDir.FullName -File -Filter '*.pdf' -ErrorAction Stop | Sort-Object Name)
    if ($Files.Count -eq 0) { throw "No PDF files found." }
    if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
        $OutputFolder = Join-Path $InputDir.FullName 'TIFF'
    }
    $OutDir = [System.IO.Directory]::CreateDirectory($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)).FullName

    $Success = 0
    $Skipped = 0
    $Failed = 0
    $Pages = 0
    $Index = 0

    foreach ($Pdf in $Files) {
        $Index++
        Write-Host "[$Index/$($Files.Count)] $($Pdf.Name)" -ForegroundColor Cyan
        $Stage = $null
        $Published = [System.Collections.Generic.List[string]]::new()
        try {
            # Brak nadpisywania poprzednich wynikow
            $Prefix = $Pdf.BaseName + '_'
            $Existing = @(Get-ChildItem -LiteralPath $OutDir -File -ErrorAction Stop | Where-Object {
                $_.Name.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase) -and
                $_.Name.Substring($Prefix.Length) -match '^\d{6}\.tif$'
            })
            if ($Existing.Count -gt 0) {
                $Skipped++
                Write-Host "SKIP: Existing output; no files overwritten." -ForegroundColor Yellow
                continue
            }

            # Izolowany katalog roboczy; bez zmian pliku zrodlowego
            $Stage = Join-Path $OutDir ('.pdf2tiff-' + [Guid]::NewGuid().ToString('N'))
            [void][System.IO.Directory]::CreateDirectory($Stage)
            Copy-Item -LiteralPath $Pdf.FullName -Destination (Join-Path $Stage 'input.pdf') -ErrorAction Stop
            Push-Location -LiteralPath $Stage -ErrorAction Stop
            try {
                & $MagickExe -density $Dpi -define 'pdf:use-cropbox=false' 'input.pdf' -background white -alpha remove -alpha off -colorspace gray -threshold '50%' -type bilevel -units PixelsPerInch -density $Dpi -compress Group4 +adjoin 'page-%06d.tif'
                if ($LASTEXITCODE -ne 0) { throw "PDF conversion failed (code $LASTEXITCODE)." }
                $Generated = @(Get-ChildItem -LiteralPath $Stage -File -Filter 'page-*.tif' -ErrorAction Stop | Sort-Object Name)
                if ($Generated.Count -eq 0) { throw "No TIFF files generated." }

                # Weryfikacja formatu i parametrow kazdej strony
                for ($N = 0; $N -lt $Generated.Count; $N++) {
                    $Expected = 'page-{0:D6}.tif' -f $N
                    if ($Generated[$N].Name -ne $Expected) { throw "Unexpected page numbering." }
                    $Info = @(& $MagickExe identify -format '%m|%z|%C|%x|%y|%U\n' $Expected)
                    if ($LASTEXITCODE -ne 0 -or $Info.Count -ne 1) { throw "TIFF verification failed: $Expected" }
                    $Parts = $Info[0].Split('|')
                    if ($Parts.Count -ne 6 -or $Parts[0] -ne 'TIFF' -or $Parts[1] -ne '1' -or $Parts[2] -ne 'Group4' -or $Parts[3] -ne "$Dpi" -or $Parts[4] -ne "$Dpi" -or $Parts[5] -ne 'PixelsPerInch') {
                        throw "Unexpected TIFF properties: $($Info -join ' ')"
                    }
                }
            }
            finally { Pop-Location }

            # Publikacja po weryfikacji; File.Move nie nadpisuje plikow
            for ($N = 0; $N -lt $Generated.Count; $N++) {
                $Target = Join-Path $OutDir ($Pdf.BaseName + ('_{0:D6}.tif' -f ($N + 1)))
                [System.IO.File]::Move($Generated[$N].FullName, $Target)
                $Published.Add($Target)
            }
            $Success++
            $Pages += $Generated.Count
            Write-Host "PASS: $($Generated.Count) TIFF page(s)." -ForegroundColor Green
        }
        catch {
            $Failed++
            Write-Host "ERROR: $($Pdf.Name): $($_.Exception.Message)" -ForegroundColor Red
            # Zachowanie opublikowanych plikow i katalogu roboczego do diagnostyki
            if ($Published.Count -gt 0) { Write-Host "WARNING: Partial output retained; inspect before retrying." -ForegroundColor Yellow }
        }
        finally {
            if ($Stage -and (Test-Path -LiteralPath $Stage -PathType Container)) {
                if ($Published.Count -gt 0 -and $Published.Count -eq $Generated.Count) {
                    try { Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction Stop }
                    catch { Write-Host "WARNING: Temporary folder retained: $Stage" -ForegroundColor Yellow }
                }
                if (Test-Path -LiteralPath $Stage -PathType Container) {
                    Write-Host "INFO: Working folder retained: $Stage" -ForegroundColor Yellow
                }
            }
        }
    }
    Write-Host ""
    Write-Host "PDF SUCCESS: $Success / $($Files.Count)"
    Write-Host "PDF SKIPPED: $Skipped"
    Write-Host "PDF FAILED:  $Failed"
    Write-Host "TIFF PAGES:  $Pages"
    Write-Host "OUTPUT: $OutDir"
    if ($Failed -eq 0) { Write-Host "RESULT: COMPLETED" -ForegroundColor Green }
    if ($Failed -gt 0) { Write-Host "RESULT: COMPLETED_WITH_ERRORS" -ForegroundColor Red }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "=== EXPORT4PDF2TIFF / FINISHED ===" -ForegroundColor Cyan
