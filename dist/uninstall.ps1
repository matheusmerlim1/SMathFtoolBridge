<#
    Remove o plugin SMathFtoolBridge do SMath Studio do usuario atual.
#>

$ErrorActionPreference = 'Stop'

$pluginGuid = 'c1aba7a7-e39c-49ea-a6d1-7fe7d842b374'
$targetDir = Join-Path $env:APPDATA "SMath\extensions\plugins\$pluginGuid"

if (Test-Path $targetDir) {
    Remove-Item $targetDir -Recurse -Force
    Write-Host "Plugin removido: $targetDir" -ForegroundColor Green
} else {
    Write-Host "Plugin nao estava instalado ($targetDir nao existe)." -ForegroundColor Yellow
}

Write-Host "Reabra o SMath Studio para aplicar."
