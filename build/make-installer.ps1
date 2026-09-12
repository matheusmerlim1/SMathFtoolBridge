<#
    Gera os dois artefatos de distribuicao a partir do conteudo de dist\:

      dist\SMathFtoolBridge-Setup.exe    instalador de duplo clique
      dist\SMathFtoolBridge-1.0.0.0.zip  pacote manual (mesmos arquivos)

    Uso:
      powershell -ExecutionPolicy Bypass -File build\make-installer.ps1

    Por que IExpress e nao um compilador: este projeto nao tem codigo C# para
    compilar aqui - a DLL ja vem pronta. O que falta e so um empacotador que
    junte DLL + metadados + script e rode a instalacao num duplo clique. O
    IExpress (iexpress.exe) ja vem no Windows e faz exatamente isso, sem
    dependencia externa nenhuma.

    Limitacao do IExpress: ele nao guarda estrutura de pastas, os arquivos sao
    extraidos todos no mesmo diretorio temporario. Por isso o
    SMathFtoolBridge.en.json entra "plano" no pacote e o install.ps1 recria a
    subpasta metadata\ no destino (ele aceita os dois layouts).

    Script sem acentos de proposito (mensagens de console do Windows).
#>

param(
    [string]$Versao = '1.0.0.0'
)

$ErrorActionPreference = 'Stop'

$raizProjeto = Split-Path -Parent $PSScriptRoot
$pastaDist   = Join-Path $raizProjeto 'dist'
$exeSaida    = Join-Path $pastaDist 'SMathFtoolBridge-Setup.exe'
$zipSaida    = Join-Path $pastaDist "SMathFtoolBridge-$Versao.zip"

function Passo([string]$texto) { Write-Host "==> $texto" -ForegroundColor Cyan }

# ------------------------------------------------------------ conferencia da origem

Passo "Conferindo os arquivos de origem em dist\"

$obrigatorios = @{
    'SMathFtoolBridge.dll'                  = Join-Path $pastaDist 'SMathFtoolBridge.dll'
    'SMathFtoolBridge.dll.ini'              = Join-Path $pastaDist 'SMathFtoolBridge.dll.ini'
    'metadata\SMathFtoolBridge.en.json'     = Join-Path $pastaDist 'metadata\SMathFtoolBridge.en.json'
    'install.ps1'                           = Join-Path $pastaDist 'install.ps1'
    'uninstall.ps1'                         = Join-Path $pastaDist 'uninstall.ps1'
    'Instalar.bat'                          = Join-Path $pastaDist 'Instalar.bat'
    'Desinstalar.bat'                       = Join-Path $pastaDist 'Desinstalar.bat'
    'LEIAME.txt'                            = Join-Path $pastaDist 'LEIAME.txt'
}
foreach ($nome in $obrigatorios.Keys) {
    if (-not (Test-Path $obrigatorios[$nome])) {
        throw "Arquivo obrigatorio ausente em dist\: $nome"
    }
}

# Confere que a DLL e mesmo o assembly esperado, para nao empacotar lixo.
$assembly = [System.Reflection.AssemblyName]::GetAssemblyName($obrigatorios['SMathFtoolBridge.dll'])
if ($assembly.Version.ToString() -ne $Versao) {
    throw "A versao da DLL ($($assembly.Version)) nao bate com a versao pedida ($Versao)."
}
Write-Host "    DLL conferida: $($assembly.FullName)"

$iexpress = Join-Path $env:WINDIR 'System32\iexpress.exe'
if (-not (Test-Path $iexpress)) { throw "iexpress.exe nao encontrado em $iexpress." }

# ------------------------------------------------------------ area de montagem

Passo "Montando a area temporaria"

$montagem = Join-Path ([IO.Path]::GetTempPath()) ("SMathFtoolBridge-build-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $montagem | Out-Null

try {
    # Layout plano exigido pelo IExpress.
    Copy-Item $obrigatorios['SMathFtoolBridge.dll']              $montagem
    Copy-Item $obrigatorios['SMathFtoolBridge.dll.ini']          $montagem
    Copy-Item $obrigatorios['metadata\SMathFtoolBridge.en.json'] $montagem
    Copy-Item $obrigatorios['install.ps1']                       $montagem
    Copy-Item $obrigatorios['uninstall.ps1']                     $montagem
    Copy-Item $obrigatorios['LEIAME.txt']                        $montagem

    <#
        Ponte .cmd: o IExpress so sabe executar um comando, e o PowerShell
        precisa de -ExecutionPolicy Bypass para nao ser bloqueado.

        'cd /d "%~dp0"' e obrigatorio: o IExpress extrai os arquivos numa pasta
        temporaria, mas o diretorio de trabalho do comando nao e garantido que
        seja ela. Sem o cd, o install.ps1 nao e encontrado e o instalador fecha
        na hora, sem instalar nada e sem mostrar erro.

        O log em %TEMP% serve para diagnosticar justamente esse tipo de falha
        silenciosa, em que a janela fecha rapido demais para ler.
    #>
    $setupCmd = @(
        '@echo off',
        'cd /d "%~dp0"',
        'set "SFB_LOG=%TEMP%\SMathFtoolBridge-install.log"',
        'echo [%DATE% %TIME%] iniciando em "%CD%" > "%SFB_LOG%"',
        'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"',
        'echo [%DATE% %TIME%] install.ps1 terminou com codigo %ERRORLEVEL% >> "%SFB_LOG%"'
    ) -join "`r`n"
    [IO.File]::WriteAllText((Join-Path $montagem 'setup.cmd'), $setupCmd + "`r`n", [Text.Encoding]::ASCII)

    $arquivosPacote = @(
        'SMathFtoolBridge.dll',
        'SMathFtoolBridge.dll.ini',
        'SMathFtoolBridge.en.json',
        'install.ps1',
        'uninstall.ps1',
        'LEIAME.txt',
        'setup.cmd'
    )

    # -------------------------------------------------------- arquivo .SED

    Passo "Gerando o roteiro .SED do IExpress"

    $linhasArquivos = @()
    for ($i = 0; $i -lt $arquivosPacote.Count; $i++) {
        $linhasArquivos += ('FILE{0}="{1}"' -f $i, $arquivosPacote[$i])
    }
    $linhasSource = @()
    for ($i = 0; $i -lt $arquivosPacote.Count; $i++) {
        $linhasSource += ('%FILE{0}%=' -f $i)
    }

    $sed = @()
    $sed += '[Version]'
    $sed += 'Class=IEXPRESS'
    $sed += 'SEDVersion=3'
    $sed += '[Options]'
    $sed += 'PackagePurpose=InstallApp'
    $sed += 'ShowInstallProgramWindow=1'   # deixa a janela visivel: o usuario le o resultado
    $sed += 'HideExtractAnimation=1'
    $sed += 'UseLongFileName=1'
    $sed += 'InsideCompressed=0'
    $sed += 'CAB_FixedSize=0'
    $sed += 'CAB_ResvCodeSigning=0'
    $sed += 'RebootMode=N'
    $sed += 'InstallPrompt=%InstallPrompt%'
    $sed += 'DisplayLicense=%DisplayLicense%'
    $sed += 'FinishMessage=%FinishMessage%'
    $sed += 'TargetName=%TargetName%'
    $sed += 'FriendlyName=%FriendlyName%'
    $sed += 'AppLaunched=%AppLaunched%'
    $sed += 'PostInstallCmd=%PostInstallCmd%'
    $sed += 'AdminQuietInstCmd=%AdminQuietInstCmd%'
    $sed += 'UserQuietInstCmd=%UserQuietInstCmd%'
    $sed += 'SourceFiles=SourceFiles'
    $sed += '[Strings]'
    $sed += 'InstallPrompt='
    $sed += 'DisplayLicense='
    $sed += 'FinishMessage='
    # O IExpress grava direto num caminho temporario ASCII e so depois movemos o
    # .exe para dist\. Motivo: o .SED e lido em ANSI e o caminho real do projeto
    # pode ter acento (ex.: "Sistema de Informacao"), o que corrompe o destino e
    # faz o IExpress falhar sem mensagem nenhuma.
    $exeTemporario = Join-Path $montagem 'SMathFtoolBridge-Setup.exe'
    $sed += ('TargetName=' + $exeTemporario)
    $sed += ('FriendlyName=SMathFtoolBridge ' + $Versao + ' - instalador')
    # AppLaunched precisa ser um dos arquivos empacotados. Usar 'cmd /c setup.cmd'
    # aqui faz o IExpress nao executar nada (o cmd.exe nao esta no pacote) e o
    # instalador fecha sem instalar, sem erro nenhum.
    $sed += 'AppLaunched=setup.cmd'
    $sed += 'PostInstallCmd=<None>'
    $sed += 'AdminQuietInstCmd='
    $sed += 'UserQuietInstCmd='
    $sed += $linhasArquivos
    $sed += '[SourceFiles]'
    $sed += ('SourceFiles0=' + $montagem + '\')
    $sed += '[SourceFiles0]'
    $sed += $linhasSource

    $arquivoSed = Join-Path $montagem 'SMathFtoolBridge.sed'
    # IExpress le o .SED em ANSI; ASCII puro evita qualquer surpresa de encoding.
    [IO.File]::WriteAllText($arquivoSed, (($sed -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

    # -------------------------------------------------------- build do .exe

    Passo "Chamando o IExpress"

    if (Test-Path $exeSaida) { Remove-Item $exeSaida -Force }
    & $iexpress /N /Q $arquivoSed | Out-Null

    if (-not (Test-Path $exeTemporario)) {
        throw "O IExpress terminou mas nao gerou o executavel em $exeTemporario."
    }
    Copy-Item $exeTemporario $exeSaida -Force

    if (-not (Test-Path $exeSaida)) {
        throw "Nao foi possivel copiar o executavel para $exeSaida."
    }
    $tamanhoExe = (Get-Item $exeSaida).Length
    Write-Host ("    OK: SMathFtoolBridge-Setup.exe ({0:N0} bytes)" -f $tamanhoExe) -ForegroundColor Green

    # -------------------------------------------------------- zip (mesma origem)

    Passo "Regerando o zip a partir dos mesmos arquivos"

    $montagemZip = Join-Path $montagem '_zip'
    New-Item -ItemType Directory -Force -Path (Join-Path $montagemZip 'metadata') | Out-Null
    foreach ($nome in @('SMathFtoolBridge.dll','SMathFtoolBridge.dll.ini','install.ps1','uninstall.ps1','Instalar.bat','Desinstalar.bat','LEIAME.txt')) {
        Copy-Item (Join-Path $pastaDist $nome) $montagemZip
    }
    Copy-Item $obrigatorios['metadata\SMathFtoolBridge.en.json'] (Join-Path $montagemZip 'metadata')

    if (Test-Path $zipSaida) { Remove-Item $zipSaida -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($montagemZip, $zipSaida)
    Write-Host ("    OK: $(Split-Path -Leaf $zipSaida) ({0:N0} bytes)" -f (Get-Item $zipSaida).Length) -ForegroundColor Green
}
finally {
    if (Test-Path $montagem) { Remove-Item $montagem -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
Write-Host "Pronto. Artefatos em dist\:" -ForegroundColor Green
Write-Host "  SMathFtoolBridge-Setup.exe     (duplo clique instala)"
Write-Host "  SMathFtoolBridge-$Versao.zip   (pacote manual)"
