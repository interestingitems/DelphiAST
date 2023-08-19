unit TestAppMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, System.Generics.Collections, AST.Pascal.Project,
  AST.Pascal.Parser, AST.Delphi.Classes, SynEdit, SynEditHighlighter, SynEditCodeFolding, SynHighlighterPas, AST.Delphi.Project,
  Vcl.ComCtrls, System.Types, Vcl.ExtCtrls, AST.Intf, AST.Parser.ProcessStatuses, Vcl.CheckLst, SynEditMiscClasses,
  SynEditSearch, AST.Parser.Messages, SynMemo;   // system

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
    tsNameSpace: TTabSheet;
    edAllItems: TSynEdit;
    Panel2: TPanel;
    Panel3: TPanel;
    Button3: TButton;
    Splitter1: TSplitter;
    lbFiles: TCheckListBox;
    Button4: TButton;
    chkbShowSysDecls: TCheckBox;
    chkbShowConstValues: TCheckBox;
    chkbShowAnonymous: TCheckBox;
    Splitter2: TSplitter;
    Panel4: TPanel;
    SynEditSearch1: TSynEditSearch;
    Panel5: TPanel;
    Button5: TButton;
    NSSearchEdit: TEdit;
    ErrMemo: TSynMemo;
    Panel6: TPanel;
    Label1: TLabel;
    edSrcRoot: TEdit;
    chkStopIfError: TCheckBox;
    chkCompileSsystemForASTParse: TCheckBox;
    chkParseAll: TCheckBox;
    Button1: TButton;
    Button2: TButton;
    chkShowWarnings: TCheckBox;
    procedure Button2Click(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure Button5Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    { Private declarations }
    //fPKG: INPPackage;
    fFiles: TStringDynArray;
    fSettings: IASTProjectSettings;
    FStartedAt: TDateTime;
    procedure OnProgress(const Module: IASTModule; Status: TASTProcessStatusClass);
    procedure ShowAllItems(const Project: IASTDelphiProject);
    procedure ShowResult(const Project: IASTDelphiProject);
    procedure CompilerMessagesToStrings(const Project: IASTDelphiProject);
  public
    { Public declarations }
    procedure IndexSources(const RootPath: string; Dict: TSourcesDict);
  end;

var
  frmTestAppMain: TfrmTestAppMain;

implementation

uses
  System.IOUtils,
  System.TypInfo,
  System.Rtti,
  AST.Delphi.System,
  AST.Delphi.Parser,
  AST.Classes,
  AST.Writer,
  AST.Targets,
  AST.Delphi.DataTypes, AST.Parser.Utils;

{$R *.dfm}

procedure TfrmTestAppMain.CompilerMessagesToStrings(const Project: IASTDelphiProject);
var
  I: Integer;
  Msg: TCompilerMessage;
begin
  ErrMemo.Lines.Add('===================================================================');
  for i := 0 to Project.Messages.Count - 1 do
  begin
    Msg := Project.Messages[i];
    if (Msg.MessageType >= cmtError) or chkShowWarnings.Checked then
    begin
      ErrMemo.Lines.AddStrings(Msg.AsString.Split([sLineBreak]));
      if (Msg.MessageType = cmtError) and (Msg.UnitName = 'TestUnit.XXX') then
      begin
        ErrMemo.CaretY := ErrMemo.Lines.Count;
        ErrMemo.CaretX := Length(Msg.AsString) + 1;
        edUnit.CaretX := Msg.Col;
        edUnit.CaretY := Msg.Row;
      end;
    end;
  end;
  if edUnit.CanFocus then
    edUnit.SetFocus;
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
      ErrMemo.Lines.Add(FileInfo.FullPath);
      ErrMemo.Lines.Add(Dict.Items[FileName].FullPath);
    end;
  end;
end;

function GetDeclName(const Decl: TASTDeclaration): string;
begin
  try
    if Decl.Name <> '' then
      Result := Decl.DisplayName
    else
      Result := '[Anonymous]' + Decl.DisplayName;

    var CastedDecl := (Decl as TIDDeclaration);
    case CastedDecl.ItemType of
      itVar, itConst: Result := Result + ' : '  + CastedDecl.DataType.DisplayName;
      itType: Result := Result + ' ['  + GetDataTypeName(TIDType(CastedDecl).DataTypeID) + ']';
    end;
  except
     on E: Exception do
       Result := E.Message;
  end;
end;

procedure TfrmTestAppMain.Button1Click(Sender: TObject);
var
  UN: TASTDelphiUnit;
  Prj: IASTDelphiProject;
begin
  ErrMemo.Clear;

  FStartedAt := Now;

  Prj := TASTDelphiProject.Create('test');
  Prj.AddUnitSearchPath(ExtractFilePath(Application.ExeName));
  if chkCompileSsystemForASTParse.Checked then
    Prj.AddUnitSearchPath(edSrcRoot.Text);
  Prj.Target := TWINX86_Target.TargetName;
  Prj.Defines.Add('CPUX86');
  Prj.Defines.Add('CPU386');
  Prj.Defines.Add('WIN32');
  Prj.Defines.Add('MSWINDOWS');
  Prj.Defines.Add('ASSEMBLER');
  Prj.Defines.Add('UNICODE');
  Prj.OnProgress := OnProgress;
  Prj.StopCompileIfError := chkStopIfError.Checked;
  Prj.OnConsoleWrite := procedure (const Module: IASTModule; Line: Integer; const Msg: string)
                        begin
                          ErrMemo.Lines.Add(format('#console: [%s: %d]: %s', [Module.Name, Line, Msg]));
                        end;

  UN := TASTDelphiUnit.Create(Prj, 'test', edUnit.Text);
  Prj.AddUnit(UN, nil);

  ShowResult(Prj);

  Prj.Clear;
end;

procedure TfrmTestAppMain.OnProgress(const Module: IASTModule; Status: TASTProcessStatusClass);
begin
  //if Status = TASTStatusParseSuccess then
    ErrMemo.Lines.Add(Module.Name + ' : ' + Status.Name);
end;

procedure TfrmTestAppMain.ShowAllItems(const Project: IASTDelphiProject);
begin
  edAllItems.BeginUpdate;
  try
    edAllItems.Clear;
    Project.EnumAllDeclarations(
      procedure(const Module: TASTModule; const Decl: TASTDeclaration)
      begin
        if not chkbShowAnonymous.Checked and (Decl.ID.Name = '') then
          Exit;

        if not chkbShowSysDecls.Checked and (Module.Name = 'system') then
          Exit;

        var Str := format('%s - %s.%s', [GetItemTypeName(TIDDeclaration(Decl).ItemType), Module.Name, GetDeclName(Decl)]);

        if chkbShowConstValues.Checked and (Decl is TIDConstant) then
          Str := Str + ' = ' + TIDConstant(Decl).AsString;

        edAllItems.Lines.Add(Str);
        Application.ProcessMessages;
      end);
  finally
    edAllItems.EndUpdate;
  end;
end;

procedure TfrmTestAppMain.ShowResult(const Project: IASTDelphiProject);
begin
  var Msg := TStringList.Create;
  try
    var CResult := Project.Compile;
    if CResult = CompileSuccess then
      Msg.Add('compile success')
    else
      Msg.Add('compile fail');

    Msg.Add(format('total units parsed: %d (interface only: %d)',
      [Project.TotalUnitsParsed, Project.TotalUnitsIntfOnlyParsed]));
    Msg.Add(format('total lines parsed: %d in %s', [Project.TotalLinesParsed,
                                                    FormatDateTime('nn:ss.zzz', Now - FStartedAt)]));

      //ASTToTreeView2(UN, tvAST);

    ShowAllItems(Project);
    CompilerMessagesToStrings(Project);

    ErrMemo.Lines.AddStrings(Msg);
  finally
    Msg.Free;
  end;
end;

procedure TfrmTestAppMain.Button2Click(Sender: TObject);

  procedure AddDelphiUnits(var AUsesList: string; const APath: string);
  begin
    var LRtlSources := GetDirectoryFiles(edSrcRoot.Text + APath, '*.pas');
    for var LPath in LRtlSources do
    begin
      var LUnitName := StringReplace(ExtractFileName(LPath), '.pas', '', [rfReplaceAll]);
      AUsesList := AddStringSegment(AUsesList, LUnitName, ',');
    end;

  end;

var
  UN: TASTDelphiUnit;
  Prj: IASTDelphiProject;
begin
  ErrMemo.Clear;

  FStartedAt := Now;

  Prj := TASTDelphiProject.Create('test');
  Prj.AddUnitSearchPath(edSrcRoot.Text);
  Prj.Target := TWINX86_Target.TargetName;
  Prj.Defines.Add('CPUX86');
  Prj.Defines.Add('CPU386');
  Prj.Defines.Add('WIN32');
  Prj.Defines.Add('MSWINDOWS');
  Prj.Defines.Add('ASSEMBLER');
  Prj.OnProgress := OnProgress;
  Prj.StopCompileIfError := chkStopIfError.Checked;
  Prj.CompileAll := chkParseAll.Checked;

  var LUsesUntis := '';
  AddDelphiUnits(LUsesUntis, 'rtl\sys');

  var RTLUsesSourceText :=
  'unit RTLParseTest; '#10#13 +
  'interface'#10#13 +
  'uses'#10#13 +
   LUsesUntis + ';'#10#13 +
  'implementation'#10#13 +
  'end.';

  UN := TASTDelphiUnit.Create(Prj, 'RTLParseTest', RTLUsesSourceText);
  Prj.AddUnit(UN, nil);

  ShowResult(Prj);
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
  ErrMemo.Clear;

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
          Application.ProcessMessages;
        end);
    finally
      edAllItems.EndUpdate;
    end;

    CompilerMessagesToStrings(Prj);

    ErrMemo.Lines.AddStrings(Msg);
  finally
    Msg.Free;
  end;
end;

procedure TfrmTestAppMain.Button5Click(Sender: TObject);
begin
  edAllItems.SearchReplace(NSSearchEdit.Text, '', []);
end;

procedure TfrmTestAppMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  TPooledObject.ClearPool;
end;

procedure TfrmTestAppMain.FormCreate(Sender: TObject);
begin
  fSettings := TPascalProjectSettings.Create;
end;

end.


