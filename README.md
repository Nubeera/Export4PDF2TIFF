# Export4PDF2TIFF

Two standalone Windows scripts: Export4PDF2TIFF-PS51.ps1 (Windows PowerShell 5.1) and Export4PDF2TIFF-PS7.ps1 (PowerShell 7). Both use the same conversion logic with distinct runtime checks.

Requires ImageMagick 7 and Ghostscript x64. Startup checks executables, versions and PDF/TIFF support. Reference workstation: ImageMagick 7.1.2-36 and Ghostscript 10.08.0. No Poppler or Python needed.

Run the appropriate script in the corresponding shell. Default input is the current PowerShell filesystem directory, not the script directory; optionally pass -InputFolder. Default output is the TIFF subdirectory; optionally pass -OutputFolder. Default DPI is 300; optionally pass -Dpi. Non-recursive.

**Source PDFs are permanently deleted by default after verification.** Use -KeepPdf for a non-destructive test. Test only on copies first. Existing target TIFFs cause the corresponding PDF to be skipped and retained; previous separate-page TIFFs are not changed. Do not concurrently modify input/output folders. Final hash checks and deletion are separate filesystem operations.

One PDF = one multipage TIFF, same basename, original page order, mixed page dimensions, 1-bit monochrome, CCITT Group 4. Color/grayscale are intentionally thresholded; not a universal archival replacement for PDF text, annotations, signatures, metadata or attachments.

Safety: read-locked staging copy with SHA256 check, independent Ghostscript page count, signatures before encoding, full TIFF decoding and comparison of page count, pixel signatures, dimensions, DPI, depth and compression. Publish without overwrite and verify SHA256; check source and target hash again before removing original. Native stderr diagnostics stop processing conservatively. Failed staging directories may retain PDF copies for diagnosis; verified published TIFF is retained if deletion fails. No automatic installations or execution policy changes.

Console: local time [yyMMdd HH:mm:ss] on each application log line, English INFO/DEBUG/PASS/WARN/ERROR, progress, commands, buffered native stdout/stderr after each process, checksums and timings. Polish comments, CRLF checkout.

Validation: original single-page Windows output quality accepted by user. Multipage pipeline, independent count and pixel signature verification tested on 9 sample PDFs in Linux (ImageMagick 7.1.2-1, Ghostscript 10.05.1); full batch test interrupted by time limit. Both Windows wrappers and destructive operation await acceptance testing. No user PDFs or TIFFs included in public repo.

## Windows acceptance tests
Run `& 'C:\Tools\Export4PDF2TIFF\Test-Export4PDF2TIFF.ps1'` in PowerShell 7 after synchronizing main. The test generates isolated PDFs under C:\Tools\Export4PDF2TIFF-Tests, checks syntax in each target interpreter, and verifies four scenarios (KEEP and DELETE for each runtime), including page properties, corrupt input retention and output collision protection. Logs and fixtures remain for inspection. A heartbeat is shown every five seconds while child processes run. Windows execution has not yet been verified.

### Windows validation 2026-11-26
First acceptance run: 0/4; PDF/TIFF startup check rejected valid ImageMagick 7 output containing the Module column. No PDFs processed. The capability check now accepts both table layouts and requires multipage TIFF write support; successful startup logs only the relevant format rows. Console clearing is skipped when output is redirected; child timestamps are preserved. Windows retest pending.

### Windows retest: 16:40
Dependencies and format checks passed on PowerShell 7.7.0. Windows PowerShell 5.1 parsed successfully but execution policy blocked loading the unsigned script. No execution policy changes are made by this project. The Windows ImageMagick build emitted only one page signature for `-write info:` despite Ghostscript counting three pages. The converter now renders a lossless multipage MIFF, reads every signature with a separate identify invocation, encodes one Group4 TIFF, then compares all signatures and TIFF properties. The revised native pipeline passed on four original sample PDFs (10 pages) with Linux ImageMagick 7.1.2-1 / Ghostscript 10.05.1. Windows retest required. Additional temporary disk space is needed for the MIFF. Use `-EngineName PS7` on the test script for a two-scenario subset while PS5.1 policy remains unresolved; this is not full acceptance. No source PDF was deleted in the reported failed tests.

### Windows retest: 16:42
The previous commit accidentally duplicated the converter tail inside a quoted regex during a text replacement, causing parser errors before processing. Both converters were repaired using literal string slicing; verification/deletion logic was compared byte-for-byte (LF normalized) with the previously parsed version. A fresh Linux native-pipeline test on a synthetic 3-page PDF passed all three pixel signatures and TIFF properties. Windows parser and execution retests are required. PS5.1 policy scopes are all Undefined on the reference workstation; PS7 LocalMachine is RemoteSigned. No policy changes were made. Do not bypass domain or local policies without authorization.

### Windows retest: 16:47
PowerShell 7 parsed and executed the revised converter, but ImageMagick PDF-to-MIFF still yielded only one reported page out of three. Source retained. The next implementation renders numbered PNG pages directly with Ghostscript, checks the exact count and every expected filename, prepares a single-page lossless MIFF and signature for each page, and assembles one TIFF in explicit numeric order. Existing final TIFF verification and deletion guards are unchanged. Native pipeline tested on two original PDFs (five pages) under Linux; all TIFF properties and signatures passed and decoded pixels matched the previous reference TIFFs. A third test timed out and is not counted. Temporary disk usage increases; overly long Windows native argument lists fail safely. Windows acceptance and PS5.1 execution policy remain pending.
