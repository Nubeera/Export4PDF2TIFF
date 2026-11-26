# Export4PDF2TIFF

Two standalone Windows scripts: Export4PDF2TIFF-PS51.ps1 (Windows PowerShell 5.1) and Export4PDF2TIFF-PS7.ps1 (PowerShell 7). Both use the same conversion logic with distinct runtime checks.

Requires ImageMagick 7 and Ghostscript x64. Startup checks executables, versions and PDF/TIFF support. Reference workstation: ImageMagick 7.1.2-36 and Ghostscript 10.08.0. No Poppler or Python needed.

Run the appropriate script in the corresponding shell. Default input is the current PowerShell filesystem directory, not the script directory; optionally pass -InputFolder. Default output is the TIFF subdirectory; optionally pass -OutputFolder. Default DPI is 300; optionally pass -Dpi. Non-recursive.

**Source PDFs are permanently deleted by default after verification.** Use -KeepPdf for a non-destructive test. Test only on copies first. Existing target TIFFs cause the corresponding PDF to be skipped and retained; previous separate-page TIFFs are not changed. Do not concurrently modify input/output folders. Final hash checks and deletion are separate filesystem operations.

One PDF = one multipage TIFF, same basename, original page order, mixed page dimensions, 1-bit monochrome, CCITT Group 4. Color/grayscale are intentionally thresholded; not a universal archival replacement for PDF text, annotations, signatures, metadata or attachments.

Safety: read-locked staging copy with SHA256 check, independent Ghostscript page count, signatures before encoding, full TIFF decoding and comparison of page count, pixel signatures, dimensions, DPI, depth and compression. Publish without overwrite and verify SHA256; check source and target hash again before removing original. Native stderr diagnostics stop processing conservatively. Failed staging directories may retain PDF copies for diagnosis; verified published TIFF is retained if deletion fails. No automatic installations or execution policy changes.

Console: local time [yyMMdd HH:mm:ss] on each application log line, English INFO/DEBUG/PASS/WARN/ERROR, progress, commands, buffered native stdout/stderr after each process, checksums and timings. Polish comments, CRLF checkout.

Validation: original single-page Windows output quality accepted by user. Multipage pipeline, independent count and pixel signature verification tested on 9 sample PDFs in Linux (ImageMagick 7.1.2-1, Ghostscript 10.05.1); full batch test interrupted by time limit. Both Windows wrappers and destructive operation await acceptance testing. No user PDFs or TIFFs included in public repo.
