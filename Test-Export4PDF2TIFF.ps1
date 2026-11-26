#requires -Version 5.1
[CmdletBinding()]
param()
Clear-Host
$ErrorActionPreference = 'Stop'
function Log($Level,$Message) {
    foreach ($Line in ("$Message" -split '\r?\n')) {
        Write-Host ('[{0}] {1}: {2}' -f (Get-Date -Format 'yyMMdd HH:mm:ss'),$Level,$Line)
    }
}
function Assert($Condition,$Message) {
    if (-not $Condition) { throw $Message }
}
function Hash($Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}
Log INFO '=== REQUEST #6 / ACCEPTANCE TEST ==='
$Passed=0
try {
    # Weryfikacja interpreterow oraz narzedzi.
    $Project=$PSScriptRoot
    $PS51=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $PS7=(Get-Command pwsh.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $Magick=(Get-Command magick.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $Magick) { $Magick='C:\Program Files\ImageMagick\magick.exe' }
    foreach ($Exe in @($PS51,$PS7,$Magick)) {
        Assert (Test-Path -LiteralPath $Exe -PathType Leaf) "Missing executable: $Exe"
        Log PASS "FOUND=$Exe"
    }
    # Wylacznie nowe, izolowane dane testowe.
    $Root=Join-Path 'C:\Tools\Export4PDF2TIFF-Tests' ([Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($Root)
    Log INFO "TEST_DIRECTORY=$Root"
    $Master=Join-Path $Root 'master.pdf'
    $LF=[string][char]10
    $Objects=@('<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R 5 0 R 7 0 R] /Count 3 >>')
    $Sizes=@('144 216','216 144','144 144')
    $Drawings=@('0 g 10 10 40 80 re f','0 g 30 20 100 30 re f','0 g 50 50 40 40 re f')
    for ($i=0; $i -lt 3; $i++) {
        $Data=$Drawings[$i]+$LF
        $Objects+="<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $($Sizes[$i])] /Resources << >> /Contents $(4+2*$i) 0 R >>"
        $Objects+="<< /Length $($Data.Length) >>"+$LF+'stream'+$LF+$Data+'endstream'
    }
    $PDF='%PDF-1.4'+$LF
    $Offsets=@()
    for ($i=0; $i -lt $Objects.Count; $i++) {
        $Offsets+=$PDF.Length
        $PDF+="$($i+1) 0 obj"+$LF+$Objects[$i]+$LF+'endobj'+$LF
    }
    $Xref=$PDF.Length
    $PDF+='xref'+$LF+'0 9'+$LF+'0000000000 65535 f '+$LF
    foreach ($Offset in $Offsets) { $PDF+=('{0:D10} 00000 n ' -f $Offset)+$LF }
    $PDF+='trailer'+$LF+'<< /Size 9 /Root 1 0 R >>'+$LF+'startxref'+$LF+$Xref+$LF+'%%EOF'+$LF
    [IO.File]::WriteAllBytes($Master,[Text.Encoding]::ASCII.GetBytes($PDF))
    $MasterHash=Hash $Master
    foreach ($Engine in @($PS51,$PS7)) {
        $Name=if ($Engine -eq $PS51) {'PS51'} else {'PS7'}
        try {
            $Converter=Join-Path $Project "Export4PDF2TIFF-$Name.ps1"
            Assert (Test-Path -LiteralPath $Converter -PathType Leaf) "Missing script: $Converter"
            # Parser uruchamiany w docelowej wersji PowerShell.
            $ParseCommand='$t=$null; $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile('''+$Converter.Replace("'","''")+''',[ref]$t,[ref]$e); if ($e.Count) { $e | Out-String; throw ''Syntax error'' }; Write-Output ''SYNTAX_PASS'''
            $Parsed=@(& $Engine -NoLogo -NoProfile -NonInteractive -Command $ParseCommand)
            $ParseCode=$LASTEXITCODE
            $Parsed | ForEach-Object { Log DEBUG $_ }
            Assert ($ParseCode -eq 0 -and $Parsed -contains 'SYNTAX_PASS') "Syntax check failed: $Name"
            foreach ($Mode in @('KEEP','DELETE')) {
                $Folder=Join-Path $Root ($Name+'_'+$Mode)
                [void][IO.Directory]::CreateDirectory($Folder)
                $Source=Join-Path $Folder 'multi.pdf'
                $Target=Join-Path $Folder 'TIFF\multi.tif'
                Copy-Item -LiteralPath $Master -Destination $Source
                if ($Mode -eq 'DELETE') {
                    $Bad=Join-Path $Folder 'broken.pdf'
                    [IO.File]::WriteAllText($Bad,'Invalid PDF test')
                    $BadHash=Hash $Bad
                    $Collision=Join-Path $Folder 'collision.pdf'
                    $Existing=Join-Path $Folder 'TIFF\collision.tif'
                    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Existing))
                    Copy-Item -LiteralPath $Master -Destination $Collision
                    Copy-Item -LiteralPath (Join-Path $Root ($Name+'_KEEP\TIFF\multi.tif')) -Destination $Existing
                    $ExistingHash=Hash $Existing
                }
                $ArgsList=@('-NoLogo','-NoProfile','-NonInteractive','-File',$Converter)
                if ($Mode -eq 'KEEP') { $ArgsList+=@('-InputFolder',$Folder,'-KeepPdf') }
                Log INFO "TEST=$Name/$Mode; CWD=$Folder"
                # Osobny proces, jawny katalog roboczy i pliki diagnostyczne.
                $StdOut=Join-Path $Root ($Name+'_'+$Mode+'.stdout.log')
                $StdErr=Join-Path $Root ($Name+'_'+$Mode+'.stderr.log')
                $QuotedArgs=($ArgsList | ForEach-Object {'"'+$_+'"'}) -join ' '
                $Child=Start-Process -FilePath $Engine -ArgumentList $QuotedArgs -WorkingDirectory $Folder -RedirectStandardOutput $StdOut -RedirectStandardError $StdErr -NoNewWindow -PassThru
                try {
                    while (-not $Child.WaitForExit(5000)) { Log INFO "RUNNING=$Name/$Mode; PID=$($Child.Id)" }
                    $Child.WaitForExit()
                    $Code=$Child.ExitCode
                }
                finally { $Child.Dispose() }
                $Output=Get-Content -LiteralPath $StdOut -Raw
                Get-Content -LiteralPath $StdOut | ForEach-Object { Log DEBUG $_ }
                Get-Content -LiteralPath $StdErr | ForEach-Object { Log WARN $_ }
                Assert ($Code -eq 0) "Child PowerShell returned $Code"
                Assert (Test-Path -LiteralPath $Target -PathType Leaf) 'Output TIFF missing.'
                $Rows=@(& $Magick identify -regard-warnings -format '%w|%h|%z|%C|%x|%y|%U\n' $Target)
                Assert ($LASTEXITCODE -eq 0) 'TIFF verification failed.'
                $Expected=@('600|900|1|Group4|300|300|PixelsPerInch','900|600|1|Group4|300|300|PixelsPerInch','600|600|1|Group4|300|300|PixelsPerInch')
                Assert (($Rows -join ';') -eq ($Expected -join ';')) "Unexpected pages: $($Rows -join ';')"
                $Rows | ForEach-Object { Log DEBUG $_ }
                if ($Mode -eq 'KEEP') {
                    Assert ((Hash $Source) -eq $MasterHash) 'KeepPdf failed.'
                    Assert ($Output -match 'PDF_SUCCESS=1; PDF_SKIPPED=0; PDF_FAILED=0; TIFF_PAGES=3; PDF_DELETED=0') 'Unexpected KEEP summary.'
                }
                if ($Mode -eq 'DELETE') {
                    Assert (-not (Test-Path -LiteralPath $Source)) 'Source not deleted.'
                    Assert ((Hash $Bad) -eq $BadHash) 'Broken PDF not preserved.'
                    Assert ((Hash $Collision) -eq $MasterHash) 'Collision PDF not preserved.'
                    Assert ((Hash $Existing) -eq $ExistingHash) 'Existing TIFF overwritten.'
                    Assert (-not (Test-Path -LiteralPath (Join-Path $Folder 'TIFF\broken.tif'))) 'Invalid TIFF published.'
                    Assert ($Output -match 'PDF_SUCCESS=1; PDF_SKIPPED=1; PDF_FAILED=1; TIFF_PAGES=3; PDF_DELETED=1') 'Unexpected DELETE summary.'
                }
                $Passed++
                Log PASS "$Name/$Mode"
            }
        }
        catch { Log ERROR "$Name : $($_.Exception.Message)"; Log DEBUG $_.ScriptStackTrace }
    }
    Assert ((Hash $Master) -eq $MasterHash) 'Master PDF changed.'
    Log INFO "PASSED=$Passed/4; TEST_DIRECTORY=$Root"
    Assert ($Passed -eq 4) 'Acceptance tests failed.'
    Log PASS 'RESULT=ACCEPTANCE_TEST_PASS'
}
catch { Log ERROR $_.Exception.Message; Log ERROR 'RESULT=ACCEPTANCE_TEST_FAILED' }
Log INFO '=== REQUEST #6 / FINISHED ==='
