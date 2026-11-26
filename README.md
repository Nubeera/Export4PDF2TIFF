# Export4PDF2TIFF

Batch conversion of scanned PDF engineering drawings to monochrome TIFF on Windows.

## Requirements
- Windows PowerShell 5.1 or PowerShell 7.
- ImageMagick 7 (Q16 x64 installed on the reference workstation).
- Ghostscript x64, installed and discoverable by ImageMagick.
- Reference workstation versions: ImageMagick 7.1.2-36, Ghostscript 10.08.0 (installation verified 2026-11-26).
- No Poppler or Python required for runtime.

## Installation and usage
Clone to `C:\Tools\Export4PDF2TIFF`.

```powershell
& 'C:\Tools\Export4PDF2TIFF\Export4PDF2TIFF.ps1'
```

Enter the folder containing PDF files. Alternatively specify `-InputFolder`, `-OutputFolder` and optionally `-Dpi` (default 300).

## Output
- Non-recursive batch of PDF files from the selected folder.
- Default output: `TIFF` subfolder.
- One TIFF per page, e.g. `Drawing_000001.tif`.
- 1-bit monochrome, CCITT Group 4 compression, 300 DPI by default.
- PDF page dimensions retained at selected rendering density. Color and grayscale are deliberately thresholded at 50%; this is intended for monochrome scans, not general preservation of arbitrary PDF images.
- Original PDF files remain unchanged. Existing numbered output files for a PDF cause it to be skipped.
- Temporary copies and intermediate TIFFs use a unique staging directory. Successful staging directories are removed; failed ones are retained for diagnosis. If publication fails partway through, partial output is retained and subsequent runs skip the affected PDF until the operator resolves it.
- Per-file progress, validation of TIFF properties, and summary counters.
- No automatic installations, registry changes, or elevation.

## Validation
On 2026-11-26 the ImageMagick/Ghostscript conversion pipeline was tested on 18 sample scanned PDFs (46 pages) using Linux ImageMagick 7.1.2-1 and Ghostscript 10.05.1. All 46 output pages matched the pixel dimensions and pixel values of the extracted reference images and had 1-bit depth, 300 DPI and CCITT Group 4 compression. This is a sample-specific result, not a guarantee for arbitrary PDFs. The PowerShell wrapper itself has been reviewed but has not yet been executed on Windows; Windows acceptance testing is pending. Source PDFs and converted test images are not committed to this public repository.
