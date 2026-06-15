# =====================================================================
# NFX - Wdrozenie calego schematu hurtowni do SQL Server
# Uruchom z dowolnego katalogu:  powershell -File deploy_all.ps1
# Parametry opcjonalne: -Server localhost  -Reset (usuwa baze przed wdrozeniem)
# =====================================================================
param(
    [string]$Server = "localhost",
    [switch]$Reset
)
$ErrorActionPreference = "Stop"
$env:PATH += ";C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn"
$base = $PSScriptRoot

if ($Reset) {
    Write-Host "=== RESET: DROP DATABASE NFX_DW ===" -ForegroundColor Yellow
    sqlcmd -S $Server -E -C -b -Q "IF DB_ID('NFX_DW') IS NOT NULL BEGIN ALTER DATABASE NFX_DW SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE NFX_DW; END"
}

$files = @(
    "01_create_database.sql",
    "02_dim_tables.sql",
    "03_fact_tables.sql",
    "04_staging_tables.sql",
    "05_populate_dim_date.sql",
    "06_seed_dim_geography.sql",
    "07_etl_procedures.sql"
)
foreach ($f in $files) {
    Write-Host "=== Deploying $f ===" -ForegroundColor Cyan
    sqlcmd -S $Server -E -C -b -i (Join-Path $base $f)
    if ($LASTEXITCODE -ne 0) { throw "FAILED on $f (exit $LASTEXITCODE)" }
}
# widoki BI (jesli plik istnieje)
$views = Join-Path $base "08_analytical_views.sql"
if (Test-Path $views) {
    Write-Host "=== Deploying 08_analytical_views.sql ===" -ForegroundColor Cyan
    sqlcmd -S $Server -E -C -b -i $views
    if ($LASTEXITCODE -ne 0) { throw "FAILED on 08_analytical_views.sql" }
}
Write-Host "=== Wdrozenie zakonczone OK ===" -ForegroundColor Green
