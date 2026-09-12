# Arquitetura e referência de API verificada

Tudo abaixo foi confirmado por reflexão sobre as DLLs da instalação local do SMath
Studio (`C:\Program Files (x86)\SMath Studio`), não só por documentação — a
documentação pública do SDK do SMath é escassa e não cobre esses detalhes.

## Empacotamento de plugin

- Cada plugin é uma DLL cujo assembly tem `[assembly: Guid("...")]`.
- Plugins de terceiros ficam em
  `%AppData%\SMath\extensions\plugins\<mesmo GUID do assembly>\<versão>\<dll>`.
  Confirmado observando plugins reais instalados no perfil do usuário (ex.:
  `ExcelIOCom.dll` em
  `...\extensions\plugins\0370e95d-cfdf-4f76-96cb-468d63d765c0\1.1.8225.33532\`).
- Plugins nativos do SMath seguem o mesmo padrão dentro da própria instalação, em
  `plugins\<guid>\<dll>` (ex.: `PictureRegion.dll` em
  `plugins\06b5df04-393e-4be7-9107-305196fcb861\`).
- Não há manifesto XML separado — o próprio `GuidAttribute` do assembly é o
  identificador usado pelo carregador de plugins.

## API de região customizada

`SMath.Controls.IPluginCustomRegion` (implementada pela classe "Impl" do plugin,
`FtoolRegionImpl` no nosso caso):

```
string TagName { get; }
Type RegionType { get; }
MenuButton[] GetMenuItems(SessionProfile);
DragAndDropFileType[] DragAndDropFileTypes { get; }
string[] SupportedClipboardFormats { get; }
RegionBase CreateNew(SessionProfile);
MenuButton[] GetContextMenuItems(MenuContext);
```

Junto com `SMath.Manager.IPlugin` (`void Initialize()`) e `IDisposable`.

`SMath.Controls.RegionBase` (classe base de toda região da planilha) só tem **um**
membro realmente abstrato: `RegionBase Clone()`. Tudo mais relevante é `virtual`,
inclusive:

```
void OnMouseDown(MouseEventOptions)
void OnMouseUp(MouseEventOptions)
void OnMouseMove(MouseEventOptions)
void OnPaint(PaintEventOptions)
void ToXml(StorageWriter, FileParsingContext)
void FromXml(StorageReader, FileParsingContext)
void InitLayout()
```

`MouseEventOptions.Clicks` é um `int` (igual ao `MouseEventArgs.Clicks` do WinForms) —
duplo clique é simplesmente `e.Clicks >= 2`.

## Por que herdar de `PictureRegion` em vez de `RegionBase`

`SMath.Controls.PictureRegion` (a região nativa "Picture", em
`plugins\06b5df04-393e-4be7-9107-305196fcb861\PictureRegion.dll`) é `public` e não
`sealed`, e todos os métodos acima são `virtual` nela também. Ela já resolve:

- Desenho do preview (`OnPaint`) e do cursor/seleção.
- Carregar uma imagem de um arquivo: `void LoadImage(string path)`.
- Serialização da imagem em `ToXml`/`FromXml`.

Herdando dela (`FtoolRegion : PictureRegion`), só precisamos adicionar o campo
`FtoolFilePath`, o duplo clique para abrir o Ftool, e persistir esse campo extra —
sem reimplementar rasterização nem o formato de arquivo do SMath.

## Persistência de dados extras (`FtoolFilePath`)

`StorageWriter`/`StorageReader` expõem `GetXmlWriter()`/`GetXmlReader()` (haveria risco
de mexer na ordem/posição do `XmlWriter`/`XmlReader` compartilhado com a classe base
sem decompilar o código que os chama), mas também expõem uma propriedade `Properties`
do tipo `PropertiesWriter`/`PropertiesReader` com um bag de chave-valor tipado
(`SetString`/`GetString`, `SetInt32`/`GetInt32`, etc.) — claramente feito para plugins
guardarem dados próprios sem tocar no XML cru. É isso que `FtoolRegion.ToXml`/`FromXml`
usa:

```csharp
public override void ToXml(StorageWriter writer, FileParsingContext context)
{
    base.ToXml(writer, context);
    writer.Properties.SetString("ftoolFile", FtoolFilePath ?? string.Empty);
}

public override void FromXml(StorageReader reader, FileParsingContext context)
{
    base.FromXml(reader, context);
    FtoolFilePath = reader.Properties.GetString("ftoolFile", string.Empty);
}
```

## Menu de contexto e diálogo de arquivo

`MenuButton` tem `OpenFileFilter`/`SaveFileFilter`. Quando preenchidos, é o próprio
SMath que mostra o diálogo de arquivo do Windows antes de invocar o `ButtonAction`, e
entrega o caminho escolhido em `MenuButtonArgs.DialogPath`. Não precisamos abrir
`OpenFileDialog` manualmente para "vincular .ftl" nem para "atualizar preview" — só
para localizar o `Ftool.exe` na primeira vez (isso é global ao plugin, não amarrado a
uma região, então fica em `FtoolLocator` usando `System.Windows.Forms.OpenFileDialog`
diretamente).

## Duas armadilhas reais encontradas ao testar a instalação de verdade

Estas duas só apareceram testando dentro do SMath de verdade (a instalação falhava
sem nenhuma mensagem de erro útil na UI):

1. **Nunca referencie a DLL de outro plugin como dependência de compilação.** A
   primeira versão de `FtoolRegion` herdava de `SMath.Controls.PictureRegion`, que
   vive em `PictureRegion.dll` — a DLL de um plugin nativo diferente, não uma
   biblioteca do núcleo. Quando o SMath carrega o nosso plugin isoladamente (para
   inspecionar seus tipos via reflexão), ele não resolve `PictureRegion.dll` porque
   ela não está ao lado do nosso `.dll` nem necessariamente já carregada no
   AppDomain. Isso foi confirmado reproduzindo o carregamento manualmente:
   `Assembly.LoadFrom(nossaDll).GetTypes()` lançava `ReflectionTypeLoadException`
   com `FileNotFoundException: PictureRegion, Version=...`. Testado também o
   contrário: pré-carregando só as DLLs do núcleo (`SMath.Manager.dll`,
   `SMath.Controls.dll`, `SMath.Drawing.dll` — que ficam na pasta raiz da
   instalação, não em `plugins\<guid>\`) antes de carregar nossa DLL, o
   `GetTypes()` funciona. Por isso `FtoolRegion` agora herda direto de
   `SMath.Controls.RegionBase` e desenha a própria imagem com `SMath.Drawing`
   (`IGraphics`, `DesktopBitmap`) em vez de reaproveitar a região "Picture".

2. **Falta um arquivo `config.<versão>.ini` na pasta do plugin.** Além da pasta
   `plugins\<guid>\<versão>\` com a DLL, o `.dll.ini` e `metadata\*.json`, os
   plugins de terceiros reais também têm um arquivo
   `plugins\<guid>\config.<versão-do-SMath-com-underscore>.ini` (ex.:
   `config.1_5_0_9678.ini` para o SMath 1.5.0.9678), com três linhas: versão do
   plugin, um `0`, e o nome do arquivo `.dll` principal. Sem esse arquivo, o SMath
   simplesmente não lista o plugin em Serviço/Tools > Complementos na
   inicialização — não aparece erro nenhum, ele só não aparece. Isso não está
   documentado em lugar nenhum que eu tenha achado; foi descoberto comparando a
   pasta do nosso plugin com as pastas de plugins de terceiros já instalados no
   perfil do usuário. `install.ps1` gera esse arquivo automaticamente, detectando a
   versão do SMath instalado.

## Compatibilidade entre versões do SMath

Testado numa segunda máquina com uma versão mais antiga do SMath Studio
(`SMath.Manager` reportando `Version=1.73.9126.0`, contra `1.75.9678.0` na máquina de
desenvolvimento) e o plugin falhou ao carregar com
`Não foi possível carregar o tipo SMath.Manager.AlertLevel`. O tipo `AlertLevel`
(usado só para `SessionProfile.UserInformer.ShowAlert(string, AlertLevel)`) não existe
nessa versão mais antiga — foi adicionado depois. Como `SMath.Manager.dll` não é
assinada (`PublicKeyToken=null`), o binding de assembly é por nome simples, então o
plugin carrega contra QUALQUER versão do SMath instalada na máquina, não a que foi
usada para compilar — mas se o código referenciar um tipo/membro que não existe
naquela versão especificamente, a carga do plugin inteiro falha (não é uma falha
graciosa por método).

Correção: parei de usar `UserInformer`/`AlertLevel` e troquei por
`System.Windows.Forms.MessageBox.Show(...)` (WinForms puro, sem depender de nada do
SMath) em todos os avisos do plugin. Isso é uma licao geral: qualquer API do SMath
usada no plugin é um risco de compatibilidade coisas mais "de conveniência"/recentes
tendem a não existir em instalações mais antigas. Prefira sempre a API mínima
necessária (RegionBase, IGraphics, MenuButton) e evite membros que pareçam ter sido
adicionados recentemente, especialmente se não aparecerem usados pelos plugins nativos
mais antigos (ex.: `PictureRegion.dll`, que tampouco usa `UserInformer`).

## O que não foi possível confirmar por reflexão (fica para quando testar dentro do SMath)

- Onde exatamente `GetMenuItems` (ao contrário de `GetContextMenuItems`) aparece na
  UI — só temos a assinatura, não o comportamento. Só um teste real dentro do SMath
  confirma.
- Se existe alguma forma de a região saber o caminho do arquivo `.sm` que a contém
  (para guardar o `.ftl` com caminho relativo em vez de absoluto).
- Comportamento exato de `Draw`/`RegionExport` ao imprimir/exportar o documento SMath
  para PDF — assumimos que herdar de `PictureRegion` já cobre isso, mas não foi testado
  visualmente.

## Ftool: o que existe e o que não existe

- Confirmado (manual oficial): arquivos `.ftl`, `Arquivo > Abrir/Salvar`,
  `Arquivo > Exportar tela` (imagem) e `Exportar resultados de linha` (texto),
  `Importar propriedades` de outro `.ftl`.
- Não documentado nem encontrado: linha de comando além de "abrir arquivo", API,
  automação COM/.NET, ou qualquer forma de extrair resultados programaticamente.
  Por isso o fluxo de atualização do preview é manual.
