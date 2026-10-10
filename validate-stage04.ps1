# Stage 04 validation for Windows PowerShell, Prisma ORM 7.x.
# Run from the project root. This script does not create schema/migration files.
# Preconditions: prisma/schema.prisma and prisma/migrations/00000000000000_init/migration.sql
# must already exist; DATABASE_URL and SHADOW_DATABASE_URL must be set in .env/config.

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Invoke-Stage04Command {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string[]]$Args
    )
    Write-Host "`n== $Label ==" -ForegroundColor Cyan
    & $Exe @Args
    if ($LASTEXITCODE -ne 0) {
        throw "FAILED ($LASTEXITCODE): $Exe $($Args -join ' ')"
    }
}

$requiredPaths = @(
    'prisma.config.ts',
    'prisma/schema.prisma',
    'prisma/migrations/00000000000000_init/migration.sql',
    'db/audit-stage04.sql'
)
foreach ($path in $requiredPaths) {
    if (-not (Test-Path $path)) {
        throw "Required file not found: $path. Create/copy the corrected Stage 04 artifacts first; do not run migrations yet."
    }
}

if (-not (Test-Path '.env')) {
    Write-Warning '.env was not found at the project root. Confirm prisma.config.ts gets DATABASE_URL and SHADOW_DATABASE_URL from a valid environment source.'
}

Invoke-Stage04Command '1. Toolchain' 'npx' @('prisma', '--version')
Invoke-Stage04Command '2. Format schema' 'npx' @('prisma', 'format')
Invoke-Stage04Command '3. Validate schema' 'npx' @('prisma', 'validate')

Write-Host "`n== 4. Apply migration to development database ==" -ForegroundColor Cyan
Write-Warning 'If Prisma asks you to create a NEW migration, press Ctrl+C. Do not accept a newly proposed migration until the diff has been reviewed.'
& npx prisma migrate dev
if ($LASTEXITCODE -ne 0) { throw "FAILED ($LASTEXITCODE): npx prisma migrate dev" }

Invoke-Stage04Command '5. Migration status' 'npx' @('prisma', 'migrate', 'status')

Write-Host "`n== 6. PostgreSQL catalog audit ==" -ForegroundColor Cyan
# psql accepts a libpq connection URI. DATABASE_URL must be in this PowerShell session.
$dbUrl = $env:DATABASE_URL
if ([string]::IsNullOrWhiteSpace($dbUrl)) {
    throw 'DATABASE_URL is not set in the PowerShell process. Ensure prisma.config.ts loads .env, and set $env:DATABASE_URL before running the audit, or run psql manually with the URL.'
}
& psql $dbUrl '-v' 'ON_ERROR_STOP=1' '-f' 'db/audit-stage04.sql'
if ($LASTEXITCODE -ne 0) { throw "FAILED ($LASTEXITCODE): psql catalog audit" }

Write-Host "`n== 7. Prisma migration/schema diff (Prisma 7 syntax) ==" -ForegroundColor Cyan
$diffPath = Join-Path $env:TEMP 'stage04-diff.sql'
& npx prisma migrate diff '--from-migrations' 'prisma/migrations' '--to-config-datasource' '--script' '--output' $diffPath '--config' 'prisma.config.ts'
if ($LASTEXITCODE -ne 0) { throw "FAILED ($LASTEXITCODE): prisma migrate diff" }
if ((Test-Path $diffPath) -and ((Get-Item $diffPath).Length -gt 0)) {
    Write-Host "DIFF IS NON-EMPTY. Review this file; do not apply it automatically: $diffPath" -ForegroundColor Yellow
    Get-Content $diffPath
} else {
    Write-Host 'DIFF EMPTY — Prisma-visible schema and migration history agree. PostgreSQL-specific features still require the catalog audit above.' -ForegroundColor Green
}

Write-Host "`nDONE. Save the full terminal output and the catalog audit results for review." -ForegroundColor Green
