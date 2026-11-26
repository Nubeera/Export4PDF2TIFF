#requires -Version 7.0
[CmdletBinding()]
param([string]$InputFolder,[string]$OutputFolder,[ValidateRange(72,1200)][int]$Dpi=300,[switch]$KeepPdf)

# Czyszczenie tylko przy dostepnej konsoli interaktywnej.
try {
    if (-not [Console]::IsOutputRedirected -and -not [Console]::IsErrorRedirected) {
        Clear-Host -ErrorAction Stop
    }
}
catch {
    Write-Host ('[{0}] WARN: Console clear unavailable: {1}' -f (Get-Date -Format 'yyMMdd HH:mm:ss'),$_.Exception.Message)
}
$ErrorActionPreference = 'Stop'
function Log {
    param([string]$Level,[string]$Message)
    $Color = switch ($Level) {
        ERROR { 'Red' }
        WARN { 'Yellow' }
        PASS { 'Green' }
        DEBUG { 'Gray' }
        default { 'Cyan' }
    }
    foreach ($Line in ($Message -split '\r?\n')) {
        $Stamp = [DateTime]::Now.ToString('yyMMdd HH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
        Write-Host ('[{0}] {1}: {2}' -f $Stamp,$Level,$Line) -ForegroundColor $Color
    }
}
function Run-Native {
    param([string]$Exe,[string[]]$Arguments,[string]$WorkingDirectory,[switch]$QuietStdOut)
    # Oba strumienie odczytywane rownolegle, logowane po zakonczeniu.
    $Quoted = foreach ($Arg in $Arguments) {
        if ($Arg.Contains('"')) { throw 'Unsupported quote in native argument.' }
        '"' + ($Arg -replace '(\\+)$','$1$1') + '"'
    }
    $Info = New-Object Diagnostics.ProcessStartInfo
    $Info.FileName = $Exe
    $Info.Arguments = $Quoted -join ' '
    $Info.WorkingDirectory = $WorkingDirectory
    $Info.UseShellExecute = $false
    $Info.RedirectStandardOutput = $true
    $Info.RedirectStandardError = $true
    $Info.CreateNoWindow = $true
    Log DEBUG "CWD=$WorkingDirectory; COMMAND=$Exe $($Info.Arguments)"
    $Proc = New-Object Diagnostics.Process
    $Proc.StartInfo = $Info
    $Watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $Proc.Start()) { throw 'Unable to start native process.' }
        $OutTask = $Proc.StandardOutput.ReadToEndAsync()
        $ErrTask = $Proc.StandardError.ReadToEndAsync()
        while (-not $Proc.WaitForExit(5000)) { Log INFO "NATIVE_RUNNING: PID=$($Proc.Id); ELAPSED_MS=$($Watch.ElapsedMilliseconds)" }
        $Proc.WaitForExit()
        $StdOut = $OutTask.GetAwaiter().GetResult()
        $StdErr = $ErrTask.GetAwaiter().GetResult()
        $Code = $Proc.ExitCode
        if (-not $QuietStdOut -or $Code -ne 0) {
            foreach ($Line in ($StdOut -split '\r?\n')) { if ($Line) { Log DEBUG "STDOUT: $Line" } }
        }
        foreach ($Line in ($StdErr -split '\r?\n')) { if ($Line) { Log WARN "STDERR: $Line" } }
        Log DEBUG "PROCESS_CODE=$Code; ELAPSED_MS=$($Watch.ElapsedMilliseconds)"
        if ($Code -ne 0) { throw "Native process failed: $Code" }
        if (-not [string]::IsNullOrWhiteSpace($StdErr)) { throw 'Native diagnostic on stderr; refusing destructive processing.' }
        return ($StdOut -split '\r?\n' | Where-Object { $_ })
    }
    finally { $Proc.Dispose() }
}
function Find-Exe {
    param([string]$Name,[string[]]$Candidates)
    $Command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Command) { return $Command.Source }
    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) { return $Candidate }
    }
    throw "Required software not found: $Name"
}
function Hash-File {
    param([string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}
$OK=0; $Skipped=0; $Failed=0; $Pages=0; $Deleted=0; $Fatal=$false
$BatchWatch=[Diagnostics.Stopwatch]::StartNew()
Log INFO '=== EXPORT4PDF2TIFF / START ==='
try {
    if ($PSVersionTable.PSVersion.Major -ne 7 -or -not $IsWindows) { throw 'Use PowerShell 7 on Windows.' }
    Log INFO "PowerShell=$($PSVersionTable.PSVersion); Computer=$env:COMPUTERNAME; DPI=$Dpi; KeepPdf=$KeepPdf"
    # Sprawdzenie zaleznosci przed przetwarzaniem.
    $MC=@(); $GC=@()
    foreach ($Base in (@($env:ProgramFiles,$env:ProgramW6432,$env:LOCALAPPDATA) | Where-Object { $_ } | Select-Object -Unique)) {
        $MC += (Join-Path $Base 'ImageMagick\magick.exe')
        $GSRoot=Join-Path $Base 'gs'
        if (Test-Path -LiteralPath $GSRoot -PathType Container) {
            $GC += @(Get-ChildItem -LiteralPath $GSRoot -Directory -ErrorAction Stop |
                Where-Object { $_.Name -match '^gs\d+(\.\d+)+$' } |
                Sort-Object { [version]($_.Name.Substring(2)) } -Descending |
                ForEach-Object { Join-Path $_.FullName 'bin\gswin64c.exe' })
        }
    }
    $Magick=Find-Exe 'magick.exe' $MC
    $GS=Find-Exe 'gswin64c.exe' $GC
    $Temp=[IO.Path]::GetTempPath()
    Log INFO "ImageMagick=$Magick; Ghostscript=$GS"
    $MV=@(Run-Native $Magick @('-version') $Temp)
    if (($MV -join ' ') -notmatch 'ImageMagick 7\.') { throw 'ImageMagick 7 required.' }
    $GV=@(Run-Native $GS @('--version') $Temp)
    if (($GV -join '') -notmatch '^\d+\.\d+(\.\d+)?$') { throw 'Invalid Ghostscript version.' }
    # ImageMagick moze wyswietlac dodatkowa kolumne Module.
    $Formats=@(Run-Native $Magick @('-list','format') $Temp -QuietStdOut)
    $PdfFormats=@($Formats | Where-Object { $_ -match '^\s*PDF\*?\s+(?:\S+\s+)?r[w-][+-]\s' })
    $TiffFormats=@($Formats | Where-Object { $_ -match '^\s*TIFF\*?\s+(?:\S+\s+)?[r-]w\+\s' })
    $MiffFormats=@($Formats | Where-Object { $_ -match '^\s*MIFF\*?\s+(?:\S+\s+)?rw\+\s' })
    foreach ($Row in $MiffFormats) { Log PASS "MIFF: $($Row.Trim())" }
    Log DEBUG "FORMAT_ROWS=$($Formats.Count)"
    foreach ($Row in $PdfFormats) { Log PASS "PDF: $($Row.Trim())" }
    foreach ($Row in $TiffFormats) { Log PASS "TIFF: $($Row.Trim())" }
    if ($PdfFormats.Count -ne 1 -or $TiffFormats.Count -ne 1 -or $MiffFormats.Count -ne 1) {
        foreach ($Row in $Formats) { Log DEBUG "FORMAT: $Row" }
        throw 'PDF read, multipage MIFF read/write or multipage TIFF write support unavailable.'
    }
    Log PASS 'Dependency checks passed.'
    # Brak argumentu oznacza biezacy katalog, bez pytania.
    if ([string]::IsNullOrWhiteSpace($InputFolder)) { $InputFolder=(Get-Location).Path; Log INFO 'Using current directory.' }
    $InputDir=Get-Item -LiteralPath $InputFolder -ErrorAction Stop
    if (-not $InputDir.PSIsContainer -or $InputDir.PSProvider.Name -ne 'FileSystem') { throw 'Input must be a filesystem directory.' }
    $Files=@(Get-ChildItem -LiteralPath $InputDir.FullName -File -Filter '*.pdf' -ErrorAction Stop | Sort-Object Name)
    Log INFO "INPUT=$($InputDir.FullName); PDF_COUNT=$($Files.Count)"
    if ($Files.Count -eq 0) { Log INFO 'No PDFs found.' }
    if ($Files.Count -gt 0) {
        if ([string]::IsNullOrWhiteSpace($OutputFolder)) { $OutputFolder=Join-Path $InputDir.FullName 'TIFF' }
        $OutDir=[IO.Directory]::CreateDirectory($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)).FullName
        Log INFO "OUTPUT=$OutDir"
        if (-not $KeepPdf) { Log WARN 'Verified source PDFs will be permanently deleted.' }
        $Index=0
        foreach ($Pdf in $Files) {
            $Index++; $Stage=$null; $Stream=$null; $Published=$false; $Verified=$false
            $Watch=[Diagnostics.Stopwatch]::StartNew()
            Log INFO ('[{0}/{1}; {2:P0}] {3}' -f $Index,$Files.Count,($Index/$Files.Count),$Pdf.FullName)
            try {
                if (($Pdf.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse-point PDF not processed.' }
                $Target=Join-Path $OutDir ($Pdf.BaseName+'.tif')
                Log DEBUG "SOURCE_BYTES=$($Pdf.Length); TARGET=$Target"
                if (Test-Path -LiteralPath $Target) { $Skipped++; Log WARN 'Existing TIFF; PDF retained, no overwrite.'; continue }
                # Kopia robocza z blokada zapisu pliku zrodlowego.
                $Stage=Join-Path $OutDir ('.pdf2tiff-'+[Guid]::NewGuid().ToString('N'))
                [void][IO.Directory]::CreateDirectory($Stage)
                $StagePdf=Join-Path $Stage 'input.pdf'
                $StageTif=Join-Path $Stage 'result.tif'
                $Stream=[IO.File]::Open($Pdf.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
                $SourceHash=(Get-FileHash -InputStream $Stream -Algorithm SHA256 -ErrorAction Stop).Hash
                $Stream.Position=0
                $Copy=[IO.File]::Open($StagePdf,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                try { $Stream.CopyTo($Copy); $Copy.Flush() } finally { $Copy.Dispose() }
                if ((Hash-File $StagePdf) -ne $SourceHash) { throw 'Staging copy checksum mismatch.' }
                Log DEBUG "PDF_SHA256=$SourceHash"
                # Niezalezna liczba stron PDF.
                $Code='(input.pdf) (r) file runpdfbegin pdfpagecount (PAGES=) print = runpdfend'
                $Count=@(Run-Native $GS @('-q','-dSAFER','-dPDFSTOPONERROR','-dPDFSTOPONWARNING','-dNODISPLAY','-dBATCH','-dNOPAUSE','--permit-file-read=input.pdf','-c',$Code) $Stage | Where-Object { $_ -match '^PAGES=\d+$' })
                if ($Count.Count -ne 1) { throw 'Cannot establish PDF page count.' }
                $Expected=[int]($Count[0].Substring(6))
                if ($Expected -lt 1) { throw 'PDF has no pages.' }
                Log PASS "PDF_PAGES=$Expected"
                # Bezstratny wielostronicowy MIFF; osobny odczyt podpisow wszystkich stron.
                Log INFO 'STAGE=RENDER_PDF_TO_MIFF'
                $Render=@('-regard-warnings','-density',"$Dpi",'-define','pdf:use-cropbox=false','input.pdf','-background','white','-alpha','remove','-alpha','off','-colorspace','gray','-threshold','50%','-type','bilevel','-units','PixelsPerInch','-density',"$Dpi",'-depth','1','-compress','Zip','-adjoin','render.miff')
                Run-Native $Magick $Render $Stage | Out-Null
                $Pixels=@(Run-Native $Magick @('identify','-regard-warnings','-format','PIX=%w|%h|%#\n','render.miff') $Stage | Where-Object { $_ -match '^PIX=\d+\|\d+\|[0-9a-fA-F]{64}
                # Pelne dekodowanie i porownanie kazdej strony.
                $Check=@(Run-Native $Magick @('identify','-regard-warnings','-format','PAGE=%m|%z|%C|%x|%y|%U|%w|%h|%#\n','result.tif') $Stage | Where-Object { $_ -match '^PAGE=' })
                if ($Check.Count -ne $Expected) { throw 'TIFF page count mismatch.' }
                for ($N=0; $N -lt $Expected; $N++) {
                    $Wanted="PAGE=TIFF|1|Group4|$Dpi|$Dpi|PixelsPerInch|"+$Pixels[$N].Substring(4)
                    if ($Check[$N] -ne $Wanted) { throw "Page $($N+1) properties or pixels differ." }
                    Log PASS "PAGE $($N+1)/$Expected verified: $($Check[$N])"
                }
                $TiffHash=Hash-File $StageTif
                # Publikacja bez nadpisywania i weryfikacja pliku docelowego.
                [IO.File]::Move($StageTif,$Target)
                $Published=$true
                if ((Hash-File $Target) -ne $TiffHash) { throw 'Published TIFF checksum mismatch.' }
                $Verified=$true
                Log PASS "TIFF_SHA256=$TiffHash; TIFF_BYTES=$((Get-Item -LiteralPath $Target -ErrorAction Stop).Length)"
                $Stream.Dispose(); $Stream=$null
                # Usuniecie tylko po pelnej weryfikacji i ponownym sprawdzeniu sum.
                if (-not $KeepPdf) {
                    if ((Hash-File $Pdf.FullName) -ne $SourceHash) { throw 'Source changed; deletion cancelled.' }
                    if ((Hash-File $Target) -ne $TiffHash) { throw 'Output changed; deletion cancelled.' }
                    Remove-Item -LiteralPath $Pdf.FullName -ErrorAction Stop
                    if (Test-Path -LiteralPath $Pdf.FullName) { throw 'Source still exists after deletion.' }
                    $Deleted++; Log PASS "PDF_DELETED=$($Pdf.FullName)"
                }
                if ($KeepPdf) { Log INFO 'KeepPdf enabled; source retained.' }
                $OK++; $Pages+=$Expected
                Log PASS "CONVERTED=$Target; PAGES=$Expected"
            }
            catch {
                $Failed++; Log ERROR "$($Pdf.Name): $($_.Exception.Message)"
                Log DEBUG "$($_.ScriptStackTrace)"
                if ($Published) { Log WARN 'Published TIFF retained; review before retry.' }
                if (Test-Path -LiteralPath $Pdf.FullName) { Log INFO 'Source PDF retained.' }
            }
            finally {
                if ($Stream) { $Stream.Dispose() }
                if ($Stage -and (Test-Path -LiteralPath $Stage -PathType Container)) {
                    if ($Verified) {
                        try { Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction Stop }
                        catch { Log WARN "Staging cleanup failed: $Stage" }
                    }
                    if (Test-Path -LiteralPath $Stage -PathType Container) { Log WARN "Staging files retained: $Stage" }
                }
                Log DEBUG "FILE_ELAPSED_MS=$($Watch.ElapsedMilliseconds)"
            }
        }
    }
}
catch { $Fatal=$true; Log ERROR $_.Exception.Message; Log DEBUG "$($_.ScriptStackTrace)" }
finally {
    Log INFO "PDF_SUCCESS=$OK; PDF_SKIPPED=$Skipped; PDF_FAILED=$Failed; TIFF_PAGES=$Pages; PDF_DELETED=$Deleted"
    Log INFO "TOTAL_ELAPSED_MS=$($BatchWatch.ElapsedMilliseconds)"
    if ($Fatal -or $Failed -gt 0) { Log ERROR 'RESULT=COMPLETED_WITH_ERRORS' }
    if (-not $Fatal -and $Failed -eq 0) { Log PASS 'RESULT=COMPLETED' }
    Log INFO '=== EXPORT4PDF2TIFF / FINISHED ==='
}
 })
                if ($Pixels.Count -ne $Expected) { throw "Rendered page count mismatch: expected $Expected, found $($Pixels.Count)." }
                Log PASS "RENDERED_PAGES=$($Pixels.Count)"
                Log INFO 'STAGE=ENCODE_MULTIPAGE_TIFF'
                Run-Native $Magick @('-regard-warnings','render.miff','-type','bilevel','-depth','1','-units','PixelsPerInch','-density',"$Dpi",'-compress','Group4','-adjoin','result.tif') $Stage | Out-Null
                Log INFO 'STAGE=VERIFY_MULTIPAGE_TIFF'
                # Pelne dekodowanie i porownanie kazdej strony.
                $Check=@(Run-Native $Magick @('identify','-regard-warnings','-format','PAGE=%m|%z|%C|%x|%y|%U|%w|%h|%#\n','result.tif') $Stage | Where-Object { $_ -match '^PAGE=' })
                if ($Check.Count -ne $Expected) { throw 'TIFF page count mismatch.' }
                for ($N=0; $N -lt $Expected; $N++) {
                    $Wanted="PAGE=TIFF|1|Group4|$Dpi|$Dpi|PixelsPerInch|"+$Pixels[$N].Substring(4)
                    if ($Check[$N] -ne $Wanted) { throw "Page $($N+1) properties or pixels differ." }
                    Log PASS "PAGE $($N+1)/$Expected verified: $($Check[$N])"
                }
                $TiffHash=Hash-File $StageTif
                # Publikacja bez nadpisywania i weryfikacja pliku docelowego.
                [IO.File]::Move($StageTif,$Target)
                $Published=$true
                if ((Hash-File $Target) -ne $TiffHash) { throw 'Published TIFF checksum mismatch.' }
                $Verified=$true
                Log PASS "TIFF_SHA256=$TiffHash; TIFF_BYTES=$((Get-Item -LiteralPath $Target -ErrorAction Stop).Length)"
                $Stream.Dispose(); $Stream=$null
                # Usuniecie tylko po pelnej weryfikacji i ponownym sprawdzeniu sum.
                if (-not $KeepPdf) {
                    if ((Hash-File $Pdf.FullName) -ne $SourceHash) { throw 'Source changed; deletion cancelled.' }
                    if ((Hash-File $Target) -ne $TiffHash) { throw 'Output changed; deletion cancelled.' }
                    Remove-Item -LiteralPath $Pdf.FullName -ErrorAction Stop
                    if (Test-Path -LiteralPath $Pdf.FullName) { throw 'Source still exists after deletion.' }
                    $Deleted++; Log PASS "PDF_DELETED=$($Pdf.FullName)"
                }
                if ($KeepPdf) { Log INFO 'KeepPdf enabled; source retained.' }
                $OK++; $Pages+=$Expected
                Log PASS "CONVERTED=$Target; PAGES=$Expected"
            }
            catch {
                $Failed++; Log ERROR "$($Pdf.Name): $($_.Exception.Message)"
                Log DEBUG "$($_.ScriptStackTrace)"
                if ($Published) { Log WARN 'Published TIFF retained; review before retry.' }
                if (Test-Path -LiteralPath $Pdf.FullName) { Log INFO 'Source PDF retained.' }
            }
            finally {
                if ($Stream) { $Stream.Dispose() }
                if ($Stage -and (Test-Path -LiteralPath $Stage -PathType Container)) {
                    if ($Verified) {
                        try { Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction Stop }
                        catch { Log WARN "Staging cleanup failed: $Stage" }
                    }
                    if (Test-Path -LiteralPath $Stage -PathType Container) { Log WARN "Staging files retained: $Stage" }
                }
                Log DEBUG "FILE_ELAPSED_MS=$($Watch.ElapsedMilliseconds)"
            }
        }
    }
}
catch { $Fatal=$true; Log ERROR $_.Exception.Message; Log DEBUG "$($_.ScriptStackTrace)" }
finally {
    Log INFO "PDF_SUCCESS=$OK; PDF_SKIPPED=$Skipped; PDF_FAILED=$Failed; TIFF_PAGES=$Pages; PDF_DELETED=$Deleted"
    Log INFO "TOTAL_ELAPSED_MS=$($BatchWatch.ElapsedMilliseconds)"
    if ($Fatal -or $Failed -gt 0) { Log ERROR 'RESULT=COMPLETED_WITH_ERRORS' }
    if (-not $Fatal -and $Failed -eq 0) { Log PASS 'RESULT=COMPLETED' }
    Log INFO '=== EXPORT4PDF2TIFF / FINISHED ==='
}
