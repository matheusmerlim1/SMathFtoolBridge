# SMathFtoolBridge

Plugin para o [SMath Studio](https://smath.com) que adiciona uma região "Ftool" na
planilha: ela mostra o diagrama de um modelo do [Ftool](https://www.tecgraf.puc-rio.br/ftool/)
e, com duplo clique, abre o Ftool com o arquivo `.ftl` vinculado para você ajustar o
modelo. Funciona e foi testado dentro do SMath e do Ftool de verdade (não é só teoria).

## Como funciona

1. Menu **Inserir > Ftool** — escolhe um arquivo `.ftl` e a região já entra vinculada
   a ele (ou clique direito numa região existente > **Vincular arquivo .ftl...**).
2. **Duplo clique** na região abre esse `.ftl` no Ftool (se já tiver uma janela do
   Ftool aberta com esse arquivo, ele só traz ela pra frente em vez de abrir outra).
3. Ajusta o modelo no Ftool normalmente.
4. De volta ao SMath, clique direito na região > **Sincronizar com o Ftool aberto** —
   isso tira um print da janela do Ftool (enquanto ela ainda estiver aberta), corta
   automaticamente só a área do desenho (sem menus/painéis) e atualiza o preview na
   planilha, sem precisar exportar nada nem escolher arquivo.
5. A região não pode ser redimensionada arrastando a borda (não é suportado pela API
   de região do SMath do jeito que foi implementada aqui). Use **Ftool: ampliar** /
   **Ftool: reduzir** no menu de contexto para isso. O tamanho escolhido é mantido
   entre sincronizações.
6. Se o corte automático (passo 4) deixar sobrar pedaço de menu/painel do Ftool, ou
   se você quiser focar só numa parte do diagrama, use **Ftool: cortar topo / base /
   esquerda / direita...** no menu de contexto — ele pergunta quantos % daquele lado
   cortar (padrão 25%, pode digitar outro valor) — e ajuste aos poucos: dá pra cortar
   várias vezes seguidas e usar **Ftool: desfazer último corte** para voltar só o
   último passo (não perde os cortes anteriores), ou **Ftool: desfazer todos os
   cortes** para voltar à imagem inteira de uma vez. Esse corte manual é salvo junto
   com o documento, mas some se você sincronizar de novo (a sincronização sempre
   recarrega a imagem inteira do zero).
7. A imagem sempre mantém a proporção original (nunca fica esticada/distorcida),
   mesmo redimensionando ou cortando de forma assimétrica — o desenho é encaixado
   ("letterbox") dentro do tamanho da região, com uma sobra vazia nas bordas se a
   proporção não bater exatamente.

Na primeira vez que você abrir o Ftool por essa região, o plugin pergunta onde está o
`Ftool.exe` e guarda esse caminho em `%AppData%\SMathFtoolBridge\ftool-path.txt`
(reconfigurável pelo menu **Serviço/Tools > Ftool: configurar caminho do
Ftool.exe...**).

Também existe **Atualizar preview (imagem exportada)...** no menu de contexto, como
alternativa manual: exporta uma imagem no Ftool (Arquivo > Export Model Screen) e
escolhe o arquivo gerado. Só é necessário se por algum motivo a sincronização
automática não achar a janela do Ftool aberta.

## Como a sincronização automática funciona (e por que não é mais simples)

A primeira tentativa foi mandar o Ftool executar o próprio comando de exportar
(`File > Export Model Screen > Clipboard`) via mensagem do Windows
(`WM_COMMAND`) — funcionava num modelo vazio de teste, mas não em modelos reais,
mesmo com a janela em foco e testando com esperas de até 60 segundos. A causa real
era mais simples do que parecia: a janela do Ftool estava **minimizada**, e nesse
estado o Ftool não tem uma imagem renderizada pra copiar.

A solução final é mais direta e não depende de nenhum comando interno do Ftool: o
plugin usa `PrintWindow` (API nativa do Windows) para tirar um print da janela do
Ftool inteira, restaurando-a primeiro se estiver minimizada. Isso é mais robusto
porque não depende da versão/idioma do menu do Ftool — só precisa que a janela exista
e não esteja minimizada.

O print inclui a janela inteira do Ftool (menus, barra de ferramentas, painel
lateral). Para não mostrar isso no SMath, o plugin corta automaticamente a imagem:
acha a cor de fundo predominante (o canvas do Ftool é sempre um bloco grande de cor
sólida — preto/branco/cinza, dependendo da opção de Display escolhida no Ftool, bem
diferente da cor dos painéis ao redor) e recorta para o maior bloco contínuo dessa
cor, tolerando pequenas interrupções (como a barra de mensagem no topo do canvas) para
não fatiar o desenho ao meio. Não é perfeito — pode sobrar um pouco de barra de
ferramentas nas bordas — mas fica bem mais limpo que a janela inteira. Se o corte
errar demais num caso específico, tem a opção **"Sincronizar (janela inteira, sem
cortar)"** no menu de contexto como saída de emergência.

Como a região não suporta redimensionar arrastando a borda, o zoom fica nos comandos
**Ftool: ampliar** / **Ftool: reduzir** do menu de contexto (multiplicam o tamanho
atual por 1.25x/0.8x). O tamanho escolhido não é resetado em sincronizações seguintes.

## Estrutura do projeto

```
dist/                          Pacote pronto para instalar
  SMathFtoolBridge-Setup.exe     Instalador de duplo clique (gerado por build/)
  SMathFtoolBridge-1.0.0.0.zip   Mesmo conteudo, em zip, para instalacao manual
  SMathFtoolBridge.dll           O plugin
  SMathFtoolBridge.dll.ini       Identificacao do plugin (GUID, versao, autor)
  metadata/                      Metadados lidos pelo SMath
  install.ps1 / uninstall.ps1    Scripts de instalacao
  Instalar.bat / Desinstalar.bat Atalhos que chamam os scripts sem bloqueio do PowerShell
  LEIAME.txt                     Passo a passo para o usuario final
build/
  make-installer.ps1           Gera o .exe e o .zip a partir de dist/
docs/
  architecture.md              Referencia da API do SMath usada, decisoes e armadilhas
                                 encontradas ao testar de verdade
index.html                     Pagina do projeto (GitHub Pages)
```

### Sobre o codigo-fonte

Este repositorio distribui o **plugin compilado** (`SMathFtoolBridge.dll`) mais a
documentacao tecnica. O codigo C# (`src/SMathFtoolBridge/`, com `FtoolRegion.cs`,
`FtoolRegionImpl.cs`, `FtoolAutomation.cs`, `FtoolLocator.cs` e `PluginLog.cs`)
ficou na maquina em que o plugin foi desenvolvido e ainda nao foi trazido para ca.

Enquanto isso, [`docs/architecture.md`](docs/architecture.md) e a referencia real do
projeto: ele documenta a API do SMath usada, por que cada decisao foi tomada e as
armadilhas que so apareceram testando dentro do SMath de verdade. Quem for retomar o
desenvolvimento deve comecar por ele.

## Compilar o plugin (precisa do codigo-fonte)

Requer o SMath Studio instalado localmente (o projeto referencia as DLLs da
instalação para compilar) e o .NET Framework 4.8 (ou o MSBuild clássico, que já vem
com o Windows em `C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe`).

```powershell
& "C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe" `
  src\SMathFtoolBridge\SMathFtoolBridge.csproj /p:Configuration=Release
```

Se o SMath estiver instalado em outro caminho, passe
`/p:SMathInstallDir="C:\caminho\para\SMath Studio"`.

## Instalar

Não precisa compilar nada: só ter o SMath Studio e o Ftool já instalados.

1. Feche o SMath Studio.
2. Dê dois cliques em **`dist/SMathFtoolBridge-Setup.exe`**.
3. Abra o SMath. Se aparecer **Serviço/Tools > "Ftool: configurar caminho do
   Ftool.exe..."**, o plugin carregou.

Não pede administrador — a instalação é só para o seu usuário, em
`%AppData%\SMath\extensions\plugins\<guid>\<versão>\`. Quem preferir ver os arquivos
pode usar o zip e rodar o `Instalar.bat`. Para desinstalar, `Desinstalar.bat`
(ou `uninstall.ps1`), que apaga a pasta do plugin inteira.

O instalador grava um log em `%TEMP%\SMathFtoolBridge-install.log`, útil quando a
janela fecha rápido demais para ler o erro.

## Gerar o instalador

```powershell
powershell -ExecutionPolicy Bypass -File build\make-installer.ps1
```

Isso regera **os dois** artefatos (`SMathFtoolBridge-Setup.exe` e o `.zip`) a partir
dos mesmos arquivos de `dist/`, então eles nunca ficam fora de sincronia. Antes de
empacotar, o script confere que a versão do assembly da DLL bate com a versão pedida.

O executável é montado com o **IExpress** (`iexpress.exe`), que já vem no Windows —
não há dependência externa nem necessidade de um compilador. Duas armadilhas do
IExpress que o script já contorna, documentadas nele:

- Ele lê o roteiro `.SED` em ANSI, então um caminho de projeto com acento (como
  `Sistema de Informação`) corrompe o destino e o build falha **sem mensagem
  nenhuma**. O script gera o `.exe` num caminho temporário sem acento e só depois
  copia para `dist/`.
- O programa em `AppLaunched` precisa ser **um dos arquivos empacotados**. Usar
  `cmd /c setup.cmd` faz o instalador abrir e fechar sem instalar nada e sem erro,
  porque o `cmd.exe` não está no pacote. O correto é `AppLaunched=setup.cmd`.

Como o IExpress não preserva subpastas, o `SMathFtoolBridge.en.json` entra "plano" no
pacote e o `install.ps1` recria a subpasta `metadata\` no destino — ele aceita os dois
layouts.

## Limitações conhecidas

- **A sincronização depende do Ftool estar aberto** com o arquivo no momento em que
  você clica "Sincronizar". Se ele estiver fechado, o plugin avisa e você pode abrir
  pelo duplo clique primeiro.
- **O corte automático não é perfeito.** Pode sobrar um pouco de barra de ferramentas
  nas bordas, dependendo do layout da janela do Ftool no momento (ver seção acima).
  Tem a opção de sincronizar sem cortar como saída de emergência.
- **Não dá para redimensionar arrastando a borda da região** — use os comandos
  Ampliar/Reduzir do menu de contexto.
- **Caminho do `.ftl` é absoluto.** Se você mover a pasta do documento SMath para outra
  máquina, o vínculo com o `.ftl` pode quebrar. Guardar o caminho relativo ao arquivo
  `.sm` é uma melhoria futura razoável (não implementada ainda porque não confirmei,
  pela API refletida, como obter o caminho do documento de dentro da região).
- O preview é uma imagem estática — não atualiza sozinho quando o modelo muda no
  Ftool, precisa clicar em "Sincronizar" de novo.

## Próximos passos sugeridos

- Implementar redimensionamento por arrastar a borda da região (hoje só dá pra usar
  os comandos de Ampliar/Reduzir do menu de contexto).
- Guardar o caminho do `.ftl` relativo ao documento `.sm`, se/quando for encontrada a
  forma de acessar o caminho do documento a partir da região.
- Opcional: sincronizar automaticamente quando o processo do Ftool que a região abriu
  é encerrado (hoje é só manual, pelo menu de contexto).
