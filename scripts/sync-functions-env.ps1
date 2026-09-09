<#!
.SYNOPSIS
Copies the repository's single local .env source into functions/.env for Firebase CLI.

.DESCRIPTION
Firebase Functions expects its deployment environment file inside functions/.env.
Do not edit that generated file manually; edit the repository root .env and rerun this script.
#>
[CmdletBinding()]
param()

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot '.env'
$destination = Join-Path $repoRoot 'functions/.env'

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "루트 .env가 없습니다. .env.example을 복사해 먼저 설정하세요."
}

Copy-Item -LiteralPath $source -Destination $destination -Force
Write-Output 'functions/.env를 루트 .env 기준으로 동기화했습니다. 값은 출력하지 않습니다.'
