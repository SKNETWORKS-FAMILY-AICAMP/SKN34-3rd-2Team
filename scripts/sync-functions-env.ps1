<#
.SYNOPSIS
Copies the repository's single local .env source into functions/.env for Firebase CLI.

.DESCRIPTION
Firebase Functions expects its deployment environment file inside functions/.env.
Do not edit that generated file manually; edit the repository root .env and rerun this script.

Firebase CLI rejects keys starting with reserved prefixes:
X_GOOGLE_ / FIREBASE_ / EXT_ / KIT_
#>
[CmdletBinding()]
param()

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot '.env'
$destination = Join-Path $repoRoot 'functions/.env'

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "루트 .env가 없습니다. .env.example을 복사해 먼저 설정하세요."
}

$reserved = [regex]'^\s*(export\s+)?(X_GOOGLE_|FIREBASE_|EXT_|KIT_)'
$lines = Get-Content -LiteralPath $source -Encoding UTF8
$filtered = foreach ($line in $lines) {
    if ($line -match $reserved) { continue }
    $line
}
Set-Content -LiteralPath $destination -Value $filtered -Encoding UTF8
Write-Output 'functions/.env를 루트 .env 기준으로 동기화했습니다(예약 prefix 키 제외). 값은 출력하지 않습니다.'
