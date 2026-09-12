<#
    Instala o plugin SMathFtoolBridge no SMath Studio do usuario atual.

    Aceita os dois layouts em que o pacote e distribuido:
      - pasta/zip:  metadata\SMathFtoolBridge.en.json  (em subpasta)
      - instalador: SMathFtoolBridge.en.json           (plano, ao lado do script)

    Uso:
      - instalador SMathFtoolBridge-Setup.exe (chama este script sozinho)
      - Instalar.bat
      - powershell -ExecutionPolicy Bypass -File .\install.ps1

    Script sem acentos de proposito: o console do Windows roda em code page
    850/437 e acento vira caractere quebrado nas mensagens.
#>

param(
    # Usado pelo instalador .exe: nao espera Enter no fim.
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'

$pluginGuid = 'c1aba7a7-e39c-49ea-a6d1-7fe7d842b374'
$pluginVersion = '1.0.0.0'

function Pause-AndExit([int]$code) {
    Write-Host ""
    if (-not $Silent) { Read-Host "Pressione Enter para fechar" | Out-Null }
    exit $code
}

function Fail([string]$mensagem) {
    Write-Host "ERRO: $mensagem" -ForegroundColor Red
    Pause-AndExit 1
}

<#
    Localiza TODAS as instalacoes do SMath Studio da maquina.

    A primeira versao deste script so olhava em Program Files e Program Files
    (x86) e falhava em instalacao fora dali (ex.: 'E:\smath'). Agora procura,
    nesta ordem: registro de desinstalacao, atalhos do Menu Iniciar e os
    caminhos padrao.
#>
function Find-SMathInstalls {
    $candidatos = New-Object System.Collections.ArrayList

    # 1) Registro de desinstalacao. InstallLocation as vezes e a raiz do drive
    #    (instalador do SMath aceita isso), entao testamos subpastas comuns.
    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $entradas = Get-ItemProperty $chaves -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match 'SMath' }
    foreach ($entrada in $entradas) {
        if (-not $entrada.InstallLocation) { continue }
        $local = $entrada.InstallLocation.TrimEnd('\')
        [void]$candidatos.Add((Join-Path $local 'Solver.exe'))
        [void]$candidatos.Add((Join-Path $local 'smath\Solver.exe'))
        [void]$candidatos.Add((Join-Path $local 'SMath Studio\Solver.exe'))
    }

    # 2) Atalhos do Menu Iniciar e da area de trabalho
    $pastasAtalho = @(
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
        [Environment]::GetFolderPath('Desktop')
    )
    $shell = $null
    foreach ($pasta in $pastasAtalho) {
        if (-not (Test-Path $pasta)) { continue }
        $atalhos = Get-ChildItem $pasta -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match 'SMath|Solver' }
        foreach ($atalho in $atalhos) {
            try {
                if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
                $alvo = $shell.CreateShortcut($atalho.FullName).TargetPath
                if ($alvo) { [void]$candidatos.Add($alvo) }
            } catch { }
        }
    }

    # 3) Caminhos padrao
    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($pf86) { [void]$candidatos.Add((Join-Path $pf86 'SMath Studio\Solver.exe')) }
    [void]$candidatos.Add((Join-Path $env:ProgramFiles 'SMath Studio\Solver.exe'))

    $achados = @{}
    foreach ($caminho in $candidatos) {
        if ([string]::IsNullOrWhiteSpace($caminho)) { continue }
        if ($caminho -notmatch '\.exe$') { continue }
        if (-not (Test-Path $caminho)) { continue }
        $completo = (Resolve-Path $caminho).Path
        $chave = $completo.ToLower()
        if ($achados.ContainsKey($chave)) { continue }
        $versao = (Get-Item $completo).VersionInfo.FileVersion
        if (-not $versao) { continue }
        $achados[$chave] = [PSCustomObject]@{
            Exe     = $completo
            Version = $versao
            Tag     = ($versao -replace '\.', '_')
        }
    }
    return @($achados.Values)
}

# ------------------------------------------------------------ arquivos de origem

$raiz = $PSScriptRoot
if (-not $raiz) { $raiz = Split-Path -Parent $MyInvocation.MyCommand.Path }

$origemDll = Join-Path $raiz 'SMathFtoolBridge.dll'
$origemIni = Join-Path $raiz 'SMathFtoolBridge.dll.ini'
$origemMetaDir  = Join-Path $raiz 'metadata'
$origemMetaFlat = Join-Path $raiz 'SMathFtoolBridge.en.json'

Write-Host ""
Write-Host "SMathFtoolBridge $pluginVersion - instalacao" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $origemDll)) { Fail "SMathFtoolBridge.dll nao foi encontrado ao lado deste script (esperado em $origemDll)." }
if (-not (Test-Path $origemIni)) { Fail "SMathFtoolBridge.dll.ini nao foi encontrado ao lado deste script (esperado em $origemIni)." }

# ------------------------------------------------------------ pre-condicoes

if (Get-Process -Name 'SMathStudio_Desktop', 'Solver' -ErrorAction SilentlyContinue) {
    Write-Host "O SMath Studio esta aberto. Feche o programa e rode este instalador de novo." -ForegroundColor Yellow
    Pause-AndExit 1
}

# @(...) garante array mesmo com um unico resultado: um PSCustomObject solto
# nao expoe .Count de forma confiavel no PowerShell 5.1.
$instalacoes = @(Find-SMathInstalls)
if ($instalacoes.Count -eq 0) {
    Fail "Nao encontrei o SMath Studio (procurei no registro, nos atalhos do Menu Iniciar e em Program Files). Instale o SMath Studio antes."
}

Write-Host "SMath Studio encontrado:" -ForegroundColor Green
foreach ($instalacao in $instalacoes) {
    Write-Host ("  versao {0}  -  {1}" -f $instalacao.Version, $instalacao.Exe)
}
Write-Host ""

# ------------------------------------------------------------ copia dos arquivos

$pastaRaizPlugin = Join-Path $env:APPDATA "SMath\extensions\plugins\$pluginGuid"
$pastaDestino    = Join-Path $pastaRaizPlugin $pluginVersion

New-Item -ItemType Directory -Force -Path $pastaDestino | Out-Null
Copy-Item $origemDll $pastaDestino -Force
Copy-Item $origemIni $pastaDestino -Force

if (Test-Path $origemMetaDir) {
    Copy-Item $origemMetaDir $pastaDestino -Recurse -Force
} elseif (Test-Path $origemMetaFlat) {
    $destinoMeta = Join-Path $pastaDestino 'metadata'
    New-Item -ItemType Directory -Force -Path $destinoMeta | Out-Null
    Copy-Item $origemMetaFlat $destinoMeta -Force
} else {
    Fail "Os metadados (metadata\SMathFtoolBridge.en.json) nao foram encontrados ao lado deste script."
}

<#
    Arquivo "marcador" que registra o plugin para uma versao especifica do
    SMath. Sem ele o SMath simplesmente nao lista o plugin na inicializacao, e
    nao mostra erro nenhum. Nao e documentado: foi descoberto comparando com
    plugins de terceiros ja instalados (ver docs/architecture.md).

    Geramos um marcador para CADA versao encontrada, porque a mesma pasta de
    plugins do perfil do usuario atende todas as instalacoes do SMath.
#>
foreach ($instalacao in $instalacoes) {
    $arquivoConfig = Join-Path $pastaRaizPlugin ("config.{0}.ini" -f $instalacao.Tag)
    @($pluginVersion, "0", "SMathFtoolBridge.dll") | Set-Content -Path $arquivoConfig -Encoding ASCII
    Write-Host ("Registrado para o SMath {0}  ->  {1}" -f $instalacao.Version, (Split-Path -Leaf $arquivoConfig))
}

Write-Host ""
Write-Host "Plugin instalado em:" -ForegroundColor Green
Write-Host "  $pastaDestino"
Write-Host ""
Write-Host "Abra o SMath Studio. No menu Servico (ou Tools, dependendo do idioma)" -ForegroundColor Green
Write-Host "deve aparecer 'Ftool: configurar caminho do Ftool.exe...' - isso confirma"
Write-Host "que o plugin carregou. Tambem da para conferir em Servico/Tools >"
Write-Host "Complementos (Add-ins)."

Pause-AndExit 0
