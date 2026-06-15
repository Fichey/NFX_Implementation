# =====================================================================
# NFX – Spakowanie paczki oddawczej (<= 50 MB, BEZ danych zrodlowych)
# Tworzy NFX_Deliverable.zip w katalogu nadrzednym.
# Wyklucza: pelny ekstrakt produkt×kraj (26 MB, odtwarzalny), surowe CSV, cache.
# =====================================================================
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$zip  = Join-Path (Split-Path $root -Parent) "NFX_Deliverable.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

$exclude = @(
    "*\05_data_profiling\nike_product_country.csv",  # derywat zrodla (odtwarzalny profilerem)
    "*\__pycache__\*",
    "*.pyc"
)
$items = Get-ChildItem -Path $root -Recurse -File | Where-Object {
    $p = $_.FullName
    -not ($exclude | Where-Object { $p -like $_ })
}
Write-Host "Pakowanie $($items.Count) plikow..." -ForegroundColor Cyan
Compress-Archive -Path $items.FullName -DestinationPath $zip -CompressionLevel Optimal
$sizeMB = [math]::Round((Get-Item $zip).Length / 1MB, 2)
Write-Host "Utworzono: $zip  ($sizeMB MB)" -ForegroundColor Green
if ($sizeMB -gt 50) { Write-Warning "Paczka > 50 MB! Usun wieksze artefakty." }
