unit TestAppMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, System.Generics.Collections, AST.Pascal.Project,
  AST.Pascal.Parser, AST.Delphi.Classes, SynEdit, SynEditHighlighter, SynEditCodeFolding, SynHighlighterPas, AST.Delphi.Project,
  Vcl.ComCtrls, System.Types, Vcl.ExtCtrls, AST.Intf, AST.Parser.ProcessStatuses, Vcl.CheckLst;   // system

type
  TSourceFileInfo = record
    FullPath: string;
    DateModify: TDateTime;
  end;

  TSourcesDict = TDictionary<string, TSourceFileInfo>;


  TfrmTestAppMain = class(TForm)
    SynPasSyn1: TSynPasSyn;
    PageControl1: TPageControl;
    tsSource: TTabSheet;
    edUnit: TSynEdit;
    tsAST: TTabSheet;
    tvAST: TTreeView;
    Panel1: TPanel;
    Label1: TLabel;
    edSrcRoot: TEdit;
    Button1: TButton;
    Button2: TButton;
    Memo1: TMemo;
    tsNameSpace: TTabSheet;
    edAllItems: TSynEdit;
    Panel2: TPanel;
    Panel3: TPanel;
    Button3: TButton;
    Splitter1: TSplitter;
    lbFiles: TCheckListBox;
    Button4: TButton;
    procedure Button2Click(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }
    //fPKG: INPPackage;
    fFiles: TStringDynArray;
    fSettings: IASTProjectSettings;
    procedure OnProgress(const Module: IASTModule; Status: TASTProcessStatusClass);
  public
    { Public declarations }
    procedure IndexSources(const RootPath: string; Dict: TSourcesDict);
  end;

var
  frmTestAppMain: TfrmTestAppMain;

implementation

uses
  System.IOUtils,
  AST.Delphi.System,
  AST.Delphi.Parser,
  AST.Classes,
  AST.Parser.Messages,
  AST.Writer,
  AST.Targets,
  AST.Delphi.DataTypes;

{$R *.dfm}

procedure CompilerMessagesToStrings(const Messages: ICompilerMessages; Strings: TStrings);
var
  I: Integer;
  Msg: TCompilerMessage;
begin
  for i := 0 to Messages.Count - 1 do
  begin
    Msg := Messages[i];
    Strings.Add(Msg.AsString);
  end;
end;

procedure ASTToTreeView2(ASTUnit: TASTDelphiUnit; TreeView: TTreeView);
var
  WR: TASTWriter<TTreeView, TTreeNode>;
begin
  TreeView.Items.Clear;
  WR := TASTWriter<TTreeView, TTreeNode>.Create(TreeView, ASTUnit,
    function (const Container: TTreeView; const RootNode: TTreeNode; const NodeText: string): TTreeNode
    begin
      Result := Container.Items.AddChild(RootNode, NodeText);
    end,
    procedure (const Node: TTreeNode; const ASTItem: TASTItem)
    begin
      Node.Text := ASTItem.DisplayName;
    end);
  try
    WR.Write(nil);
  finally
    WR.Free;
  end;
  TreeView.FullExpand;
end;

const ExcludePath = 'C:\Program Files (x86)\Embarcadero\Studio\19.0\source\DUnit\examples\';

procedure TfrmTestAppMain.IndexSources(const RootPath: string; Dict: TSourcesDict);
var
  Files: TStringDynArray;
  i: Integer;
  FileName: string;
  FilePath: string;
  FileInfo: TSourceFileInfo;
begin
  Files := TDirectory.GetFiles(RootPath, '*.inc', TSearchOption.soAllDirectories);
  for i := 0 to Length(Files) -1 do
  begin
    FilePath := ExtractFilePath(Files[i]);
    if Pos(ExcludePath, FilePath) >= Low(string) then
      Continue;
    FileInfo.FullPath := Files[i];
    FileName := ExtractFileName(FileInfo.FullPath);
    try
      Dict.Add(FileName, FileInfo);
    except
      Memo1.Lines.Add(FileInfo.FullPath);
      Memo1.Lines.Add(Dict.Items[FileName].FullPath);
    end;
  end;
end;

function GetDeclName(const Decl: TASTDeclaration): string;
begin
  if Decl.Name <> '' then
    Result := Decl.DisplayName
  else
    Result := '[Anonymous]' + Decl.DisplayName;

  var CastedDecl := (Decl as TIDDeclaration);
  case CastedDecl.ItemType of
    itVar, itConst: Result := Result + ' : '  + CastedDecl.DataType.DisplayName;
    itType: Result := Result + ' ['  + GetDataTypeName(TIDType(CastedDecl).DataTypeID) + ']';
  end;
end;

procedure TfrmTestAppMain.Button1Click(Sender: TObject);
var
  UN: TASTDelphiUnit;
  Msg: TStrings;
  Prj: IASTDelphiProject;
  CResult: TCompilerResult;
  a: UInt32;
begin
  Memo1.Clear;
  Prj := TASTDelphiProject.Create('test');
  Prj.AddUnitSearchPath(ExtractFilePath(Application.ExeName));
  Prj.Target := 'WIN-X86';
  Prj.Defines.Add('CPUX86');
  Prj.Defines.Add('MSWINDOWS');

  UN := TASTDelphiUnit.Create(Prj, 'test', edUnit.Text);
  Prj.AddUnit(UN, nil);

  Msg := TStringList.Create;
  try
    Msg.Add('===================================================================');
    CResult := Prj.Compile;
    if CResult = CompileSuccess then
      Msg.Add('compile success')
    else
      Msg.Add('compile fail');

    ASTToTreeView2(UN, tvAST);

    edAllItems.BeginUpdate;
    try
      edAllItems.Clear;
      Prj.EnumIntfDeclarations(
        procedure(const Module: TASTModule; const Decl: TASTDeclaration)
        begin
          edAllItems.Lines.Add(format('%s - %s.%s', [GetItemTypeName(TIDDeclaration(Decl).ItemType), Module.Name, GetDeclName(Decl)]));
        end);
    finally
      edAllItems.EndUpdate;
    end;

    CompilerMessagesToStrings(Prj.Messages, Msg);

    Memo1.Lines := Msg;
  finally
    Msg.Free;
  end;
end;

const cRTLUsesSource =
'unit RTLParseTest; '#10#13 +
'interface'#10#13 +
'uses System.UITypes;'#10#13 +
'implementation'#10#13 +
'end.';


procedure TfrmTestAppMain.OnProgress(const Module: IASTModule; Status: TASTProcessStatusClass);
begin
  //if Status = TASTStatusParseSuccess then
    Memo1.Lines.Add(Module.Name + ' : ' + Status.Name);
end;

procedure TfrmTestAppMain.Button2Click(Sender: TObject);
var
  UN: TASTDelphiUnit;
  Msg: TStrings;
  Prj: IASTDelphiProject;
  CResult: TCompilerResult;
begin
  Memo1.Clear;

  Prj := TASTDelphiProject.Create('test');
  Prj.AddUnitSearchPath(edSrcRoot.Text);
  Prj.Target := TWINX86_Target.TargetName;
  Prj.Defines.Add('CPUX86');
  Prj.Defines.Add('CPU386');
  Prj.Defines.Add('MSWINDOWS');
  Prj.Defines.Add('ASSEMBLER');

  UN := TASTDelphiUnit.Create(Prj, 'RTLParseTest', cRTLUsesSource);
  Prj.AddUnit(UN, nil);

  Msg := TStringList.Create;
  try
    Msg.Add('===================================================================');
    CResult := Prj.Compile;
    if CResult = CompileSuccess then
      Msg.Add('compile success')
    else
      Msg.Add('compile fail');

    ASTToTreeView2(UN, tvAST);

    edAllItems.BeginUpdate;
    try
      edAllItems.Clear;
      Prj.EnumIntfDeclarations(
        procedure(const Module: TASTModule; const Decl: TASTDeclaration)
        begin
          edAllItems.Lines.Add(format('%s - %s.%s', [GetItemTypeName(TIDDeclaration(Decl).ItemType), Module.Name, GetDeclName(Decl)]));
        end);
    finally
      edAllItems.EndUpdate;
    end;

    CompilerMessagesToStrings(Prj.Messages, Msg);

    Memo1.Lines := Msg;
  finally
    Msg.Free;
  end;
end;

procedure TfrmTestAppMain.Button3Click(Sender: TObject);
begin
  fFiles := TDirectory.GetFiles(edSrcRoot.Text, '*.pas', TSearchOption.soAllDirectories);
  lbFiles.Clear;
  lbFiles.Items.BeginUpdate;
  try
    for var i := 0 to Length(fFiles) - 1 do
      lbFiles.AddItem(ExtractRelativePath(edSrcRoot.Text, fFiles[i]), nil);
    lbFiles.CheckAll(cbChecked);
  finally
    lbFiles.Items.EndUpdate;
  end;
end;

procedure TfrmTestAppMain.Button4Click(Sender: TObject);
var
  Msg: TStrings;
  Prj: IASTDelphiProject;
  CResult: TCompilerResult;
begin
  Memo1.Clear;

  Prj := TASTDelphiProject.Create('test');
  Prj.AddUnitSearchPath(edSrcRoot.Text);
  Prj.Target := TWINX86_Target.TargetName;
  Prj.Defines.Add('CPUX86');
  Prj.Defines.Add('CPU386');
  Prj.Defines.Add('MSWINDOWS');
  Prj.Defines.Add('ASSEMBLER');
  Prj.OnProgress := OnProgress;

  for var f in fFiles do
    Prj.AddUnit(f);

  Msg := TStringList.Create;
  try
    Msg.Add('===================================================================');
    CResult := Prj.Compile;
    if CResult = CompileSuccess then
      Msg.Add('compile success')
    else
      Msg.Add('compile fail');

    //ASTToTreeView2(UN, tvAST);

    edAllItems.BeginUpdate;
    try
      edAllItems.Clear;
      Prj.EnumIntfDeclarations(
        procedure(const Module: TASTModule; const Decl: TASTDeclaration)
        begin
          edAllItems.Lines.Add(format('%s - %s.%s', [GetItemTypeName(TIDDeclaration(Decl).ItemType), Module.Name, GetDeclName(Decl)]));
        end);
    finally
      edAllItems.EndUpdate;
    end;

    CompilerMessagesToStrings(Prj.Messages, Msg);

    Memo1.Lines.AddStrings(Msg);
  finally
    Msg.Free;
  end;
end;

procedure TfrmTestAppMain.FormCreate(Sender: TObject);
begin
  fSettings := TPascalProjectSettings.Create;
end;

end.


