unit main;

interface

uses
   SysUtils, Classes, Contnrs,

   {$I dbisamvr.inc}

   SyncObjs, SvcMgr, Windows, Messages, Forms, Graphics, Controls,
   Dialogs, StdCtrls, Menus, ExtCtrls, ComCtrls, ImgList,
   dbisamtb, dbisamlb, dbisamut, System.ImageList,
   System.Variants, System.IOUtils, System.Generics.Collections,
   System.JSON, IdHTTP, IdSSLOpenSSL;

const

   DS_INITIALIZE = (WM_USER+1);
   DS_TRAYICON = (DS_INITIALIZE+1);
   DS_SQLPERFTHREADSTART = (DS_INITIALIZE+2);
   DS_SQLPERFTHREADABORT = (DS_INITIALIZE+3);
   DS_SQLPERF = (DS_INITIALIZE+4);

   SQLPERF_START = 1;
   SQLPERF_STOP = 2;
   SQLPERF_ABORT = 3;
   SQLPERF_ERROR = 4;

   CR = #13;
   LF = #10;
   CRLF = CR+LF;
   CRLF_LITERAL = '<#CR#><#LF#>';

   MIN_SQLPERF_EXECUTION_TIME = 30;
   SQLPERF_SEPARATOR = '|';
   MAX_SQLPERFFILE_SIZE = ((High(Word)+1)*2048);
   MAX_SQLPERFFILE_AUTOINC = 64;

   LOG_EXT = '.log';
   LOG_BACKUP_EXT = '.lgb';

   PARAMS_SECTION = 'Server Parameters';

   SERVER_NAME_PARAM = 'SN';
   SERVER_DESC_PARAM = 'SD';
   SERVER_ADDRESS_PARAM = 'SA';
   SERVER_PORT_PARAM = 'SP';
   SERVER_THREAD_PARAM = 'ST';
   ADMIN_ADDRESS_PARAM = 'AA';
   ADMIN_PORT_PARAM = 'AP';
   ADMIN_THREAD_PARAM = 'AT';
   CONFIG_FILE_PARAM = 'CF';
   CONFIG_PASSWORD_PARAM = 'CP';
   ENCRYPTED_PARAM = 'EN';
   ENCRYPT_PASSWORD_PARAM = 'EP';
   APPENDLOG_PARAM = 'AL';

type

   TSessionItem = class(TObject)
      private
         FConnected: Boolean;
         FEncrypted: Boolean;
         FUserName: ShortString;
         FAddress: ShortString;
         FCreatedOn: TDateTime;
         FListItem: TListItem;
      public
         property Connected: Boolean read FConnected write FConnected;
         property Encrypted: Boolean read FEncrypted write FEncrypted;
         property UserName: ShortString read FUserName write FUserName;
         property Address: ShortString read FAddress write FAddress;
         property CreatedOn: TDateTime read FCreatedOn write FCreatedOn;
         property ListItem: TListItem read FListItem write FListItem;
      end;

   TDisplayActionType = (atConnect,atDisconnect,atReconnect,atLogin,atLogout);

   TSessionDisplayItem = class(TObject)
      private
         FActionType: TDisplayActionType;
         FNewEncrypted: Boolean;
         FNewUserName: ShortString;
         FNewAddress: ShortString;
         FNewCreatedOn: TDateTime;
         FSessionItem: TSessionItem;
      public
         property ActionType: TDisplayActionType read FActionType write FActionType;
         property NewEncrypted: Boolean read FNewEncrypted write FNewEncrypted;
         property NewUserName: ShortString read FNewUserName write FNewUserName;
         property NewAddress: ShortString read FNewAddress write FNewAddress;
         property NewCreatedOn: TDateTime read FNewCreatedOn write FNewCreatedOn;
         property SessionItem: TSessionItem read FSessionItem write FSessionItem;
      end;

   TDatabaseService = class(TService)
      protected
         procedure ServiceStart(Sender: TService; var Started: Boolean);
         procedure ServiceStop(Sender: TService; var Stopped: Boolean);
         procedure ServiceAfterInstall(Sender: TService);
      public
         function GetServiceController: TServiceController; override;
         constructor CreateNew(AOwner: TComponent; Dummy: Integer=0); override;
      end;

   TServerSQLPerfEntry = class(TDBISAMBaseObject)
      private
         FUserName: String;
         FDatabase: String;
         FDateTime: TDateTime;
         FStatementType: TSQLStatementType;
         FSQL: String;
         FExecutionTime: Double;
         FRowsAffected: Integer;
      public
         property UserName: String read FUserName write FUserName;
         property Database: String read FDatabase write FDatabase;
         property DateTime: TDateTime read FDateTime write FDateTime;
         property StatementType: TSQLStatementType read FStatementType
                                                   write FStatementType;
         property SQL: String read FSQL write FSQL;
         property ExecutionTime: Double read FExecutionTime write FExecutionTime;
         property RowsAffected: Integer read FRowsAffected write FRowsAffected;
      end;

   TServerSQLPerfEntryArray = array of TServerSQLPerfEntry;

   TServerSQLPerfPool = class(TDBISAMBaseObject)
      private
         FStack: TDBISAMObjectStack;
         FSection: TDBISAMCriticalSection;
         procedure Lock;
         procedure Unlock;
      public
         constructor Create; virtual;
         destructor Destroy; override;
         function Get: TServerSQLPerfEntry;
         procedure Put(Value: TServerSQLPerfEntry); overload;
         procedure Put(Value: TServerSQLPerfEntryArray); overload;
      end;

   TServerSQLPerfQueue = class(TDBISAMBaseObject)
      private
         FQueue: TDBISAMObjectQueue;
         FSection: TDBISAMCriticalSection;
         procedure Lock;
         procedure Unlock;
      public
         constructor Create; virtual;
         destructor Destroy; override;
         procedure Enqueue(Value: TServerSQLPerfEntry); overload;
         procedure Enqueue(Value: TServerSQLPerfEntryArray); overload;
         function Dequeue: TServerSQLPerfEntry;
         function DequeueAll: TServerSQLPerfEntryArray;
      end;

   TServerSQLPerfThread = class(TDBISAMThread)
      private
         FEvent: TDBISAMEvent;
         FSQLPerfFile: TFileStream;
         FSQLPerfFileName: String;
         FSQLPerfFileAutoIncrement: Boolean;
         FMaxSQLPerfFileAutoIncrement: Integer;
         FSQLPerfFileNumber: Integer;
         FMaxSQLPerfFileSize: Int64;
         FRunning: Boolean;
         FLastException: TObject;
         procedure CreateSQLPerfFile(const AFileName: String);
         procedure NotifyThreadStart;
         procedure NotifyThreadStop;
         procedure NotifyThreadAbort;
         procedure NotifyThreadException;
         procedure ProcessQueue;
      protected
         procedure Execute; override;
      public
         constructor Create(const SQLPerfFileName: String;
                            MaxSQLPerfFileSize: Int64=MAX_SQLPERFFILE_SIZE;
                            SQLPerfFileAutoIncrement: Boolean=False;
                            MaxSQLPerfFileAutoIncrement: Integer=MAX_SQLPERFFILE_AUTOINC); reintroduce; virtual;
         destructor Destroy; override;
         property Running: Boolean read FRunning;
         property LastException: TObject read FLastException;
         procedure Start; virtual;
         procedure CheckAbort;
         procedure Abort; virtual;
         procedure Terminate; override;
         procedure ReleaseException;
      end;

   TIconState = (isNoChange,isStarted,isStopped);

  TMainForm = class(TForm)
    Pages: TPageControl;
    CloseButton: TButton;
    ServerSessionsSheet: TTabSheet;
    TrayMenu: TPopupMenu;
    OpenItem: TMenuItem;
    N2: TMenuItem;
    SessionsGroupBox: TGroupBox;
    ServerOnIcon: TImage;
    ServerOffIcon: TImage;
    StopItem: TMenuItem;
    AboutButton: TButton;
    Label1: TLabel;
    TotalSessionsEdit: TEdit;
    Label2: TLabel;
    TotalConnectedSessionsEdit: TEdit;
    StartItem: TMenuItem;
    N1: TMenuItem;
    ExitItem: TMenuItem;
    HelpPopup: TPopupMenu;
    WhatsThisItem: TMenuItem;
    ServerEngine: TDBISAMEngine;
    ServerStatusSheet: TTabSheet;
    ServerGroupBox: TGroupBox;
    Label11: TLabel;
    Label14: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    UpTimeEdit: TEdit;
    EngineVersionEdit: TEdit;
    StopButton: TButton;
    StartButton: TButton;
    MainPortEdit: TEdit;
    AdminPortEdit: TEdit;
    MainAddressEdit: TEdit;
    AdminAddressEdit: TEdit;
    SessionsListView: TListView;
    UserImageList: TImageList;
    IconTimer: TTimer;
    SystemTimer: TTimer;
    Bevel1: TBevel;
    procedure FormCreate(Sender: TObject);
    procedure SystemTimerTimer(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure OpenItemClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure CloseButtonClick(Sender: TObject);
    procedure FormHide(Sender: TObject);
    procedure AboutButtonClick(Sender: TObject);
    procedure ExitItemClick(Sender: TObject);
    procedure StopButtonClick(Sender: TObject);
    procedure StartButtonClick(Sender: TObject);
    procedure WhatsThisItemClick(Sender: TObject);
    procedure IconTimerTimer(Sender: TObject);
    procedure ServerEngineServerConnect(Sender: TObject;
      IsEncrypted: Boolean; const ConnectAddress: String;
      var UserData: TObject);
    procedure ServerEngineServerDisconnect(Sender, UserData: TObject;
      const LastConnectAddress: String);
    procedure ServerEngineServerReconnect(Sender: TObject;
      IsEncrypted: Boolean; const ConnectAddress: String;
      UserData: TObject);
    procedure ServerEngineServerLogin(Sender: TObject;
      const UserName: String; UserData: TObject);
    procedure ServerEngineServerLogout(Sender: TObject;
      var UserData: TObject);
    procedure ServerEngineServerStart(Sender: TObject);
    procedure ServerEngineServerStop(Sender: TObject);
    procedure ServerEngineServerLogEvent(Sender: TObject;
      LogRecord: TLogRecord);
    procedure ServerEngineServerLogCount(Sender: TObject;
      var LogCount: Integer);
    procedure ServerEngineServerLogRecord(Sender: TObject; Number: Integer;
      var LogRecord: TLogRecord);
    procedure SessionsListViewData(Sender: TObject; Item: TListItem);
    procedure ApplicationIdle(Sender: TObject; var Done: Boolean);
    procedure ServerEngineSQLTrigger(Sender: TObject;
      TriggerSession: TDBISAMSession; TriggerDatabase: TDBISAMDatabase;
      StatementType: TSQLStatementType; const SQL: String;
      ExecutionTime: Double; RowsAffected: Integer);
    procedure ServerEngineAfterUpdateTrigger(Sender: TObject;
      TriggerSession: TDBISAMSession; TriggerDatabase: TDBISAMDatabase;
      const TableName: string; CurrentRecord: TDBISAMRecord);
    procedure ServerEngineAfterInsertTrigger(Sender: TObject;
      TriggerSession: TDBISAMSession; TriggerDatabase: TDBISAMDatabase;
      const TableName: string; CurrentRecord: TDBISAMRecord);
   private
    SessionsList: TObjectList;
    TotalSessions: Integer;
    TotalConnectedSessions: Integer;
    DisplayQueue: TObjectList;
    DisplayQueueSection: TCriticalSection;
    FromService: Boolean;
    NoUI: Boolean;
    AppendToLog: Boolean;
    IconSection: TCriticalSection;
    IconHint: string;
    IconVisible: Boolean;
    LogFileHandle: Integer;
    LogBuffer: pAnsiChar;
    LogBufferSize: Integer;
    SQLPerfTracking: Boolean;
    SQLPerfMinExecutionTime: Double;
    SQLPerfFileName: String;
    MaxSQLPerfFileSize: Int64;
    SQLPerfFileAutoIncrement: Boolean;
    MaxSQLPerfFileAutoIncrement: Integer;
    SQLPerfPool: TServerSQLPerfPool;
    SQLPerfQueue: TServerSQLPerfQueue;
    SQLPerfThread: TServerSQLPerfThread;
    FTableKeys: TDictionary<string,string>;
    // dictionary for table distinction (table mapping)
    procedure RegisterTables;
    // move on
    procedure UpdateFormPosition;
    procedure UpdateTrayIcon;
    procedure RemoveTrayIcon;
    function GetStartedHint: string;
    function GetStoppedHint: string;
    procedure UpdateFixedSystemInfo;
    procedure UpdateVariableSystemInfo;
    procedure UpdateSessionInfo;
    procedure ProcessDisplayQueue;
    procedure AddToDisplayQueue(Value: TSessionDisplayItem);
    procedure UpdateListItem(SessionItem: TSessionItem);
    procedure ApplicationMessage(var Msg: TMsg; var Handled: Boolean);
    procedure ApplicationMinimize(Sender: TObject);
    procedure AddSQLPerfEntry(ASQLPerfEntry: TServerSQLPerfEntry);
    procedure AddSQLPerfEntries(ASQLPerfEntries: TServerSQLPerfEntryArray);
    procedure StartSQLPerfTracking;
    procedure StopSQLPerfTracking;
    procedure SQLPerfThreadStart(AThread: TServerSQLPerfThread);
    procedure SQLPerfThreadStop(AThread: TServerSQLPerfThread);
    procedure SQLPerfThreadAbort(AThread: TServerSQLPerfThread);
    procedure SQLPerfThreadException(AThread: TServerSQLPerfThread);
   protected
    procedure DSInitialize(var Msg: TMessage); message DS_INITIALIZE;
    procedure DSTrayIcon(var Msg: TMessage); message DS_TRAYICON;
    procedure DSSQLPerf(var Msg: TMessage); message DS_SQLPERF;
   public
    AppDirectory: string;
    AppVersionInformation: TVersionInfo;
    procedure Initialize(Service: TService);
    // related functions for table mapping
    function GetPrimaryKeyField(const TableName: string): string;
    function SerializeRecordToJson(CurrentRecord: TDBISAMRecord): string;
   end;

var
   MainForm: TMainForm;
   DatabaseService: TDatabaseService;
   ServerName: ShortString;
   ServerDescription: ShortString;

implementation

uses DB, Registry, ShellAPI, IniFiles, about, dbisamcn;

{$R *.dfm}

{ TServerSQLPerfPool }

constructor TServerSQLPerfPool.Create;
begin
   inherited Create;
   FStack:=TDBISAMObjectStack.Create;
   FSection:=TDBISAMCriticalSection.Create;
end;

destructor TServerSQLPerfPool.Destroy;
begin
   FreeAndNilObject(FStack);
   FreeAndNilObject(FSection);
   inherited Destroy;
end;

procedure TServerSQLPerfPool.Lock;
begin
   FSection.Enter;
end;

procedure TServerSQLPerfPool.Unlock;
begin
   FSection.Leave;
end;

function TServerSQLPerfPool.Get: TServerSQLPerfEntry;
begin
   Lock;
   try
      Result:=TServerSQLPerfEntry(FStack.Pop);
      if (not Assigned(Result)) then
         Result:=TServerSQLPerfEntry.Create;
   finally
      Unlock;
   end;
end;

procedure TServerSQLPerfPool.Put(Value: TServerSQLPerfEntry);
begin
   Lock;
   try
      FStack.Push(Value);
   finally
      Unlock;
   end;
end;

procedure TServerSQLPerfPool.Put(Value: TServerSQLPerfEntryArray);
begin
   Lock;
   try
      FStack.Push(TDBISAMObjectsArray(Value));
   finally
      Unlock;
   end;
end;

{ TServerSQLPerfQueue }

constructor TServerSQLPerfQueue.Create;
begin
   inherited Create;
   FQueue:=TDBISAMObjectQueue.Create;
   FSection:=TDBISAMCriticalSection.Create;
end;

destructor TServerSQLPerfQueue.Destroy;
begin
   FreeAndNilObject(FQueue);
   FreeAndNilObject(FSection);
   inherited Destroy;
end;

procedure TServerSQLPerfQueue.Lock;
begin
   FSection.Enter;
end;

procedure TServerSQLPerfQueue.Unlock;
begin
   FSection.Leave;
end;

procedure TServerSQLPerfQueue.Enqueue(Value: TServerSQLPerfEntry);
begin
   Lock;
   try
      FQueue.Enqueue(Value);
   finally
      Unlock;
   end;
end;

procedure TServerSQLPerfQueue.Enqueue(Value: TServerSQLPerfEntryArray);
begin
   Lock;
   try
      FQueue.Enqueue(TDBISAMObjectsArray(Value));
   finally
      Unlock;
   end;
end;

function TServerSQLPerfQueue.Dequeue: TServerSQLPerfEntry;
begin
   Lock;
   try
      Result:=TServerSQLPerfEntry(FQueue.Dequeue);
   finally
      Unlock;
   end;
end;

function TServerSQLPerfQueue.DequeueAll: TServerSQLPerfEntryArray;
begin
   Lock;
   try
      Result:=TServerSQLPerfEntryArray(FQueue.DequeueAll);
   finally
      Unlock;
   end;
end;

{ TServerSQLPerfThread }

constructor TServerSQLPerfThread.Create(const SQLPerfFileName: String;
                                        MaxSQLPerfFileSize: Int64=MAX_SQLPERFFILE_SIZE;
                                        SQLPerfFileAutoIncrement: Boolean=False;
                                        MaxSQLPerfFileAutoIncrement: Integer=MAX_SQLPERFFILE_AUTOINC);
begin
   FreeOnTerminate:=False;
   FEvent:=TDBISAMEvent.Create;
   FSQLPerfFileName:=SQLPerfFileName;
   if (FSQLPerfFileName <> '') then
      begin
      CreateSQLPerfFile(FSQLPerfFileName);
      FMaxSQLPerfFileSize:=MaxSQLPerfFileSize;
      FSQLPerfFileAutoIncrement:=SQLPerfFileAutoIncrement;
      FMaxSQLPerfFileAutoIncrement:=MaxSQLPerfFileAutoIncrement;
      FSQLPerfFileNumber:=0;
      end;
   inherited Create(tpLower);
   { Wait for initial signal after establishing message queue !!! }
   FEvent.WaitFor(INFINITE);
end;

destructor TServerSQLPerfThread.Destroy;
begin
   inherited Destroy;
   FreeAndNil(FSQLPerfFile);
   FreeAndNilObject(FEvent);
end;

procedure TServerSQLPerfThread.CreateSQLPerfFile(const AFileName: String);
{$IFDEF UNICODE}
var
   TempBuffer: array[0..1] of Byte;
{$ENDIF}
begin
   if FileExists(AFileName) then
      FSQLPerfFile:=TFileStream.Create(AFileName,fmOpenReadWrite)
   else
      FSQLPerfFile:=TFileStream.Create(AFileName,fmCreate);
   {$IFDEF UNICODE}
   { Be sure to write out Unicode prefix bytes !!! }
   TempBuffer[0]:=$FF;
   TempBuffer[1]:=$FE;
   FSQLPerfFile.Write(TempBuffer[0],2);
   {$ENDIF}
end;

procedure TServerSQLPerfThread.NotifyThreadStart;
begin
   FRunning:=True;
   if (MainForm.Handle <> 0) then
      PostMessage(MainForm.Handle,DS_SQLPERF,TDBISAMIntPtr(Self),SQLPERF_START);
end;

procedure TServerSQLPerfThread.NotifyThreadStop;
begin
   FRunning:=False;
   if (MainForm.Handle <> 0) then
      PostMessage(MainForm.Handle,DS_SQLPERF,TDBISAMIntPtr(Self),SQLPERF_STOP);
end;

procedure TServerSQLPerfThread.NotifyThreadAbort;
begin
   FRunning:=False;
   if (MainForm.Handle <> 0) then
      PostMessage(MainForm.Handle,DS_SQLPERF,TDBISAMIntPtr(Self),SQLPERF_ABORT);
end;

procedure TServerSQLPerfThread.NotifyThreadException;
begin
   FRunning:=False;
   if (MainForm.Handle <> 0) then
      PostMessage(MainForm.Handle,DS_SQLPERF,TDBISAMIntPtr(Self),SQLPERF_ERROR);
end;

procedure TServerSQLPerfThread.Execute;
var
   TempMsg: TMsg;
begin
   { Create message queue for thread }
   PeekMessage(TempMsg,0,WM_USER,WM_USER,PM_NOREMOVE);
   FEvent.Signal;
   while (not Terminated) and GetMessage(TempMsg,0,0,0) do
      begin
      case TempMsg.Message of
         DS_SQLPERFTHREADSTART:
            begin
            NotifyThreadStart;
            try
               ProcessQueue;
               NotifyThreadStop;
            except
               on E: Exception do
                  begin
                  if (E is EAbort) then
                     NotifyThreadAbort
                  else
                     begin
                     FLastException:=AcquireExceptionObject;
                     NotifyThreadException;
                     end;
                  end;
            end;
            end;
         DS_SQLPERFTHREADABORT:
            ; // Do nothing
         end;
      end;
end;

procedure TServerSQLPerfThread.ReleaseException;
begin
   FreeAndNil(FLastException);
end;

procedure TServerSQLPerfThread.Start;
begin
   PostThreadMessage(ThreadID,DS_SQLPERFTHREADSTART,0,0);
end;

procedure TServerSQLPerfThread.Abort;
begin
   PostThreadMessage(ThreadID,DS_SQLPERFTHREADABORT,0,0);
end;

procedure TServerSQLPerfThread.Terminate;
begin
   inherited Terminate;
   Abort;
end;

procedure TServerSQLPerfThread.CheckAbort;
var
   TempMsg: TMsg;
begin
   if PeekMessage(TempMsg,0,DS_SQLPERFTHREADABORT,DS_SQLPERFTHREADABORT,PM_NOREMOVE) then
      RaiseAbortException('SQL performance thread '+IntToString(ThreadID)+' terminated');
end;

procedure TServerSQLPerfThread.ProcessQueue;
var
   TempArray: TServerSQLPerfEntryArray;
   I: Integer;
   TempBuffer: String;
   TempFileName: String;

   function BuildLine(DateTime: TDateTime;
                      const UserName: String;
                      const DatabaseName: String;
                      StatementType: TSQLStatementType;
                      const SQL: String;
                      ExecutionTime: Double;
                      RowsAffected: Integer): String;
   begin
      Result:=DateTimeToStr(DateTime)+SQLPERF_SEPARATOR+
              UserName+SQLPERF_SEPARATOR+
              DatabaseName+SQLPERF_SEPARATOR+
              StatementTypeToString(StatementType)+SQLPERF_SEPARATOR+
              FloatToStr(ExecutionTime)+SQLPERF_SEPARATOR+
              IntToStr(RowsAffected)+SQLPERF_SEPARATOR+
              StringReplace(StringReplace(SQL,CRLF,CRLF_LITERAL,[rfReplaceAll]),LF,CRLF_LITERAL,[rfReplaceAll]);
   end;

begin
   TempArray:=MainForm.SQLPerfQueue.DequeueAll;
   if (Length(TempArray) > 0) then
      begin
      try
         if (FSQLPerfFile <> nil) then
            begin
            for I:=0 to Length(TempArray)-1 do
               begin
               with TempArray[I] do
                  TempBuffer:=TempBuffer+BuildLine(DateTime,UserName,Database,StatementType,SQL,
                                                   ExecutionTime,RowsAffected)+CRLF;
               end;
            if (FSQLPerfFile.Size >= FMaxSQLPerfFileSize) then
               begin
               FreeAndNil(FSQLPerfFile);
               if FSQLPerfFileAutoIncrement then
                  begin
                  Inc(FSQLPerfFileNumber);
                  if (FSQLPerfFileNumber > FMaxSQLPerfFileAutoIncrement) then
                     FSQLPerfFileNumber:=1;
                  TempFileName:=ExtractFileRoot(FSQLPerfFileName,ExtractFileExt(FSQLPerfFileName))+
                                IntToString(FSQLPerfFileNumber)+
                                ExtractFileExt(FSQLPerfFileName);
                  end
               else
                  TempFileName:=ExtractFileRoot(FSQLPerfFileName,ExtractFileExt(FSQLPerfFileName))+'.bak';
               if FileExists(TempFileName) then
                  SysUtils.DeleteFile(TempFileName);
               RenameFile(FSQLPerfFileName,TempFileName);
               CreateSQLPerfFile(FSQLPerfFileName);
               end;
            FSQLPerfFile.Write(TempBuffer[1],(Length(TempBuffer)*SizeOf(Char)));
            end
         else
            begin
            for I:=0 to Length(TempArray)-1 do
               begin
               with TempArray[I] do
                  OutputDebugString(pChar(BuildLine(DateTime,UserName,Database,StatementType,SQL,
                                                    ExecutionTime,RowsAffected)));
               end;
            end;
      finally
         MainForm.SQLPerfPool.Put(TempArray);
      end;
      end;
end;

{ Service code }

procedure ServiceController(CtrlCode: DWORD); stdcall;
begin
   DatabaseService.Controller(CtrlCode);
end;

function TDatabaseService.GetServiceController: TServiceController;
begin
   Result:=ServiceController;
end;

constructor TDatabaseService.CreateNew(AOwner: TComponent; Dummy: integer);
begin
   inherited CreateNew(AOwner,Dummy);
   AllowStop:=True;
   AllowPause:=False;
   Interactive:=Boolean(Dummy);
   DisplayName:=ServerDescription;
   Name:=ServerName;
   OnStart:=ServiceStart;
   OnStop:=ServiceStop;
   AfterInstall:=ServiceAfterInstall;
end;

procedure TDatabaseService.ServiceStart(Sender: TService; var Started: Boolean);
begin
   PostMessage(MainForm.Handle,DS_INITIALIZE,TDBISAMIntPtr(Self),0);
   Started:=True;
end;

procedure TDatabaseService.ServiceStop(Sender: TService; var Stopped: Boolean);
begin
   PostMessage(MainForm.Handle,WM_QUIT,0,0);
   Stopped:=True;
end;

procedure TDatabaseService.ServiceAfterInstall(Sender: TService);
var
   TempRegistry: TRegistry;
begin
   TempRegistry:=TRegistry.Create;
   try
      with TempRegistry do
         begin
         RootKey:=HKEY_LOCAL_MACHINE;
         if OpenKey('\SYSTEM\CurrentControlSet\Services\'+ServerName,False) then
            WriteExpandString('ImagePath','"'+ParamStr(0)+'"')
         else
            raise Exception.Create('Error installing service '+ServerName+': error updating registry');
         end;
   finally
      FreeAndNil(TempRegistry);
   end;
end;

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
   SessionsList:=TObjectList.Create;
   DisplayQueueSection:=TCriticalSection.Create;
   DisplayQueue:=TObjectList.Create;
   SQLPerfPool:=TServerSQLPerfPool.Create;
   SQLPerfQueue:=TServerSQLPerfQueue.Create;
   ReadVersionInformation(AppVersionInformation);
   // starting the mapping
   RegisterTables;
   with AppVersionInformation do
      begin
      with Application do
         begin
         OnIdle:=ApplicationIdle;
         OnMessage:=ApplicationMessage;
         OnMinimize:=ApplicationMinimize;
         AppDirectory:=AddBS(ExtractFilePath(ExeName));
         Caption:=ProductName;
         Title:=ProductName;
         HelpFile:=AppDirectory+StripFilePathAndExtension(ExeName,'.exe')+'.hlp';
         end;
      end;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
   if (not InstallingService) then
      begin
      if (not NoUI) then
         IconTimer.Enabled:=False;
      try
         ServerEngine.Active:=False;
      except
      end;
      DeAllocMem(LogBuffer);
      FileClose(LogFileHandle);
      LogFileHandle:=0;
      if (not NoUI) then
         begin
         RemoveTrayIcon;
         FreeAndNil(IconSection);
         end;
      end;
   FreeAndNilObject(SQLPerfQueue);
   FreeAndNilObject(SQLPerfPool);
   FreeAndNil(DisplayQueue);
   FreeAndNil(DisplayQueueSection);
   FreeAndNil(SessionsList);
   // free mapping
   FTableKeys.Free;
end;

procedure TMainForm.Initialize(Service: TService);
var
   I: Integer;
   TempParams: TStrings;
   TempParam: AnsiString;
   TempIniFile: TIniFile;
begin
   { Force the current working directory to the same as the .exe }
   ChDir(AppDirectory);
   FromService:=(Service <> nil);
   NoUI:=FromService;
   AppendToLog:=False;
   ServerEngine.ServerName:=ServerName;
   ServerEngine.ServerDescription:=ServerDescription;
   { Check for an INI file with parameters }
   if FileExists(AppDirectory+StripFilePathAndExtension(Application.ExeName,'.exe')+'.ini') then
      begin
      TempIniFile:=TIniFile.Create(AppDirectory+StripFilePathAndExtension(Application.ExeName,'.exe')+'.ini');
      try
         with TempIniFile do
            begin
            ServerEngine.ServerName:=ReadString(PARAMS_SECTION,'Server Name',
                           ServerEngine.ServerName);
            ServerEngine.ServerDescription:=ReadString(PARAMS_SECTION,'Server Description',
                           ServerEngine.ServerDescription);
            ServerEngine.ServerMainAddress:=ReadString(PARAMS_SECTION,'Server Address',
                           ServerEngine.ServerMainAddress);
            ServerEngine.ServerMainPort:=ReadInteger(PARAMS_SECTION,'Server Port',
                           ServerEngine.ServerMainPort);
            ServerEngine.ServerMainThreadCacheSize:=ReadInteger(PARAMS_SECTION,'Server Thread Cache Size',
                           ServerEngine.ServerMainThreadCacheSize);
            ServerEngine.ServerAdminAddress:=ReadString(PARAMS_SECTION,'Administration Address',
                           ServerEngine.ServerAdminAddress);
            ServerEngine.ServerAdminPort:=ReadInteger(PARAMS_SECTION,'Administration Port',
                           ServerEngine.ServerAdminPort);
            ServerEngine.ServerAdminThreadCacheSize:=ReadInteger(PARAMS_SECTION,'Administration Thread Cache Size',
                           ServerEngine.ServerAdminThreadCacheSize);
            ServerEngine.ServerConfigFileName:=ReadString(PARAMS_SECTION,'Configuration File',
                           ServerEngine.ServerConfigFileName);
            ServerEngine.ServerConfigPassword:=ReadString(PARAMS_SECTION,'Configuration Password',
                           ServerEngine.ServerConfigPassword);
            ServerEngine.ServerEncryptedOnly:=ReadBool(PARAMS_SECTION,'Encrypted Only',
                           ServerEngine.ServerEncryptedOnly);
            ServerEngine.ServerEncryptionPassword:=ReadString(PARAMS_SECTION,'Encryption Password',
                           ServerEngine.ServerEncryptionPassword);
            ServerEngine.EngineSignature:=ReadString(PARAMS_SECTION,'Signature',
                           ServerEngine.EngineSignature);
            AppendToLog:=ReadBool(PARAMS_SECTION,'Append To Log',False);
            SQLPerfTracking:=ReadBool(PARAMS_SECTION,'SQL Performance Tracking',SQLPerfTracking);
            SQLPerfMinExecutionTime:=ReadFloat(PARAMS_SECTION,'Min SQL Performance Execution Time',MIN_SQLPERF_EXECUTION_TIME);
            SQLPerfFileName:=ReadString(PARAMS_SECTION,'SQL Performance File Name','');
            MaxSQLPerfFileSize:=ReadInteger(PARAMS_SECTION,'Max SQL Performance File Size',MAX_SQLPERFFILE_SIZE);
            SQLPerfFileAutoIncrement:=ReadBool(PARAMS_SECTION,'Auto-Increment SQL Performance File Name',False);
            MaxSQLPerfFileAutoIncrement:=ReadInteger(PARAMS_SECTION,'Max Auto-Increment SQL Performance File Name',MAX_SQLPERFFILE_AUTOINC);
            ServerEngine.TableDataExtension:=ReadString(PARAMS_SECTION,'Table Data Extension',
                                                        ServerEngine.TableDataExtension);
            ServerEngine.TableIndexExtension:=ReadString(PARAMS_SECTION,'Table Index Extension',
                                                         ServerEngine.TableIndexExtension);
            ServerEngine.TableBlobExtension:=ReadString(PARAMS_SECTION,'Table Blob Extension',
                                                        ServerEngine.TableBlobExtension);
            ServerEngine.TableDataBackupExtension:=ReadString(PARAMS_SECTION,'Backup Table Data Extension',
                                                              ServerEngine.TableDataBackupExtension);
            ServerEngine.TableIndexBackupExtension:=ReadString(PARAMS_SECTION,'Backup Table Index Extension',
                                                               ServerEngine.TableIndexBackupExtension);
            ServerEngine.TableBlobBackupExtension:=ReadString(PARAMS_SECTION,'Backup Table Blob Extension',
                                                              ServerEngine.TableBlobBackupExtension);
            ServerEngine.TableDataUpgradeExtension:=ReadString(PARAMS_SECTION,'Upgrade Table Data Extension',
                                                               ServerEngine.TableDataUpgradeExtension);
            ServerEngine.TableIndexUpgradeExtension:=ReadString(PARAMS_SECTION,'Upgrade Table Index Extension',
                                                                ServerEngine.TableIndexUpgradeExtension);
            ServerEngine.TableBlobUpgradeExtension:=ReadString(PARAMS_SECTION,'Upgrade Table Blob Extension',
                                                               ServerEngine.TableBlobUpgradeExtension);
            ServerEngine.TableDataTempExtension:=ReadString(PARAMS_SECTION,'Temp Table Data Extension',
                                                            ServerEngine.TableDataTempExtension);
            ServerEngine.TableIndexTempExtension:=ReadString(PARAMS_SECTION,'Temp Table Index Extension',
                                                             ServerEngine.TableIndexTempExtension);
            ServerEngine.TableBlobTempExtension:=ReadString(PARAMS_SECTION,'Temp Table Blob Extension',
                                                            ServerEngine.TableBlobTempExtension);
            end;
      finally
         TempIniFile.Free;
      end;
      end;
   TempParams:=TStringList.Create;
   try
      if FromService then
         begin
         AboutButton.Visible:=False;
         N1.Visible:=False;
         ExitItem.Visible:=False;
         with Service do
            begin
            for I:=0 to ParamCount-1 do
               TempParams.Add(Param[I]);
            end;
         end
      else
         begin
         AboutButton.Visible:=True;
         for I:=1 to ParamCount do
            TempParams.Add(ParamStr(I));
         end;
      for I:=0 to TempParams.Count-1 do
         begin
         if GetParam(TempParams[I],SERVER_NAME_PARAM,TempParam) then
            ServerEngine.ServerName:=TempParam
         else if GetParam(TempParams[I],SERVER_DESC_PARAM,TempParam) then
            ServerEngine.ServerDescription:=TempParam
         else if GetParam(TempParams[I],SERVER_ADDRESS_PARAM,TempParam) then
            ServerEngine.ServerMainAddress:=TempParam
         else if GetParam(TempParams[I],SERVER_PORT_PARAM,TempParam) then
            begin
            try
               ServerEngine.ServerMainPort:=StrToInt(TempParam);
            except
            end;
            end
         else if GetParam(TempParams[I],SERVER_THREAD_PARAM,TempParam) then
            begin
            try
               ServerEngine.ServerMainThreadCacheSize:=StrToInt(TempParam);
            except
            end;
            end
         else if GetParam(TempParams[I],ADMIN_ADDRESS_PARAM,TempParam) then
            ServerEngine.ServerAdminAddress:=TempParam
         else if GetParam(TempParams[I],ADMIN_PORT_PARAM,TempParam) then
            begin
            try
               ServerEngine.ServerAdminPort:=StrToInt(TempParam);
            except
            end;
            end
         else if GetParam(TempParams[I],ADMIN_THREAD_PARAM,TempParam) then
            begin
            try
               ServerEngine.ServerAdminThreadCacheSize:=StrToInt(TempParam);
            except
            end;
            end
         else if GetParam(TempParams[I],CONFIG_FILE_PARAM,TempParam) then
            ServerEngine.ServerConfigFileName:=TempParam
         else if GetParam(TempParams[I],CONFIG_PASSWORD_PARAM,TempParam) then
            ServerEngine.ServerConfigPassword:=TempParam
         else if GetParam(TempParams[I],ENCRYPTED_PARAM,TempParam) then
            ServerEngine.ServerEncryptedOnly:=True
         else if GetParam(TempParams[I],ENCRYPT_PASSWORD_PARAM,TempParam) then
            ServerEngine.ServerEncryptionPassword:=TempParam
         else if GetParam(TempParams[I],APPENDLOG_PARAM,TempParam) then
            AppendToLog:=True;
         end;
      Caption:=ServerEngine.ServerDescription;
   finally
      TempParams.Free;
   end;
   if FileExists(AppDirectory+LowerCase(ServerEngine.ServerName)+LOG_EXT) and AppendToLog then
      LogFileHandle:=FileOpen(AppDirectory+LowerCase(ServerEngine.ServerName)+LOG_EXT,(fmOpenReadWrite or fmShareExclusive))
   else
      begin
      if (not AppendToLog) then
         CopyDiskFile(AppDirectory+LowerCase(ServerEngine.ServerName)+LOG_EXT,
                      AppDirectory+LowerCase(ServerEngine.ServerName)+LOG_BACKUP_EXT);
      LogFileHandle:=FileCreate(AppDirectory+LowerCase(ServerEngine.ServerName)+LOG_EXT);
      end;
   if (LogFileHandle < 0) then
      raise Exception.Create('Cannot open or create log file '+AppDirectory+ServerEngine.ServerName+LOG_EXT+
                             ' for database server');
   if (not NoUI) then
      begin
      UpdateFixedSystemInfo;
      IconSection:=TCriticalSection.Create;
      IconTimer.Enabled:=True;
      end;
   try
      ServerEngine.Active:=True;
   except
   end;
end;

procedure TMainForm.DSInitialize(var Msg: TMessage);
begin
   Initialize(TService(Msg.WParam));
end;

procedure TMainForm.DSTrayIcon(var Msg: TMessage);
var
   Point: TPoint;
begin
   if (not Visible) then
      begin
      with Msg do
         begin
         case LParam of
            WM_RBUTTONDOWN:
               begin
               GetCursorPos(Point);
               SetForegroundWindow(Handle);
               TrayMenu.Popup(Point.X,Point.Y);
               end;
            WM_LBUTTONDBLCLK:
               TrayMenu.Items[0].Click;
            end;
         end;
      end;
end;

procedure TMainForm.UpdateTrayIcon;
var
   IconData: TNotifyIconData;
begin
   if NoUI then Exit;
   IconSection.Enter;
   try
      IconData.cbSize:=SizeOf(IconData);
      IconData.Wnd:=Handle;
      IconData.uID:=Tag;
      IconData.uFlags:=(NIF_ICON or NIF_TIP or NIF_MESSAGE);
      IconData.uCallbackMessage:=DS_TRAYICON;
      StrPCopy(IconData.szTip,IconHint);
      if ServerEngine.Active and (ServerEngine.GetServerUpTime >= 0) then
         IconData.hIcon:=ServerOnIcon.Picture.Icon.Handle
      else
         IconData.hIcon:=ServerOffIcon.Picture.Icon.Handle;
      if IconVisible then
         begin
         if (not Shell_NotifyIcon(NIM_MODIFY,@IconData)) then
            Shell_NotifyIcon(NIM_ADD,@IconData);
         end
      else
         begin
         if Shell_NotifyIcon(NIM_ADD,@IconData) then
            IconVisible:=True;
         end;
   finally
      IconSection.Leave;
   end;
end;

procedure TMainForm.RemoveTrayIcon;
var
   IconData: TNotifyIconData;
begin
   IconSection.Enter;
   try
      IconData.cbSize:=SizeOf(IconData);
      IconData.Wnd:=Handle;
      IconData.uID:=Tag;
      IconData.uFlags:=(NIF_ICON or NIF_TIP or NIF_MESSAGE);
      IconData.uCallbackMessage:=DS_TRAYICON;
      if Shell_NotifyIcon(NIM_DELETE,@IconData) then
         IconVisible:=False;
   finally
      IconSection.Leave;
   end;
end;

procedure TMainForm.SystemTimerTimer(Sender: TObject);
begin
   UpdateVariableSystemInfo;
end;

procedure TMainForm.UpdateFixedSystemInfo;
begin
   if NoUI then Exit;
   EngineVersionEdit.Text:='DBISAM Version '+ServerEngine.EngineVersion;
   if (ServerEngine.ServerMainAddress <> '') then
      MainAddressEdit.Text:=ServerEngine.ServerMainAddress
   else
      MainAddressEdit.Text:='All Addresses';
   MainPortEdit.Text:=IntToStr(ServerEngine.ServerMainPort);
   if (ServerEngine.ServerAdminAddress <> '') then
      AdminAddressEdit.Text:=ServerEngine.ServerAdminAddress
   else
      AdminAddressEdit.Text:='All Addresses';
   AdminPortEdit.Text:=IntToStr(ServerEngine.ServerAdminPort);
end;

procedure TMainForm.UpdateVariableSystemInfo;
begin
   if NoUI then Exit;
   if (ServerEngine.GetServerUpTime >= 0) then
      UpTimeEdit.Text:=TextTimeInterval(ServerEngine.GetServerUpTime)
   else
      UpTimeEdit.Text:='Stopped';
end;

procedure TMainForm.UpdateSessionInfo;
begin
   if NoUI then Exit;
   TotalSessionsEdit.Text:=IntToStr(TotalSessions);
   TotalConnectedSessionsEdit.Text:=IntToStr(TotalConnectedSessions);
end;

procedure TMainForm.OpenItemClick(Sender: TObject);
begin
   Show;
   Application.Restore;
end;

procedure TMainForm.UpdateFormPosition;
var
   Rect: TRect;
begin
   SystemParametersInfo(SPI_GETWORKAREA,0,@Rect,0);
   Left:=(Rect.Right-Width-10);
   Top:=(Rect.Bottom-Height-10);
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
   SessionsListView.Items.Count:=TotalSessions;
   SessionsListView.Repaint;
   UpdateVariableSystemInfo;
   UpdateSessionInfo;
   SystemTimer.Enabled:=True;
   UpdateFormPosition;
   ActiveControl:=CloseButton;
end;

procedure TMainForm.CloseButtonClick(Sender: TObject);
begin
   Hide;
end;

procedure TMainForm.FormHide(Sender: TObject);
begin
   SessionsListView.Items.Count:=0;
   SystemTimer.Enabled:=False;
end;

procedure TMainForm.AboutButtonClick(Sender: TObject);
begin
   AboutBox.ShowModal;
end;

procedure TMainForm.ExitItemClick(Sender: TObject);
begin
   StopButtonClick(nil);
   Close;
end;

function TMainForm.GetStartedHint: string;
begin
   if (ServerEngine.ServerMainAddress <> '') then
      Result:='Running on address '+
              ServerEngine.ServerMainAddress+' and port '+
              IntToStr(ServerEngine.ServerMainPort)
   else
      Result:='Running on all addresses '+
              'and port '+IntToStr(ServerEngine.ServerMainPort);
end;

function TMainForm.GetStoppedHint: string;
begin
   if (ServerEngine.ServerMainAddress <> '') then
      Result:='Stopped on address '+
              ServerEngine.ServerMainAddress+' and port '+
              IntToStr(ServerEngine.ServerMainPort)
   else
      Result:='Stopped on all addresses '+
              'and port '+IntToStr(ServerEngine.ServerMainPort);
end;

// mapping functions (mapping table name) against the table keys
function TMainForm.GetPrimaryKeyField(
  const TableName: string): string;
begin
  if not FTableKeys.TryGetValue(TableName, Result) then
    Result := '';
end;

// mapping functions for JSON serialization
function TMainForm.SerializeRecordToJson(
  CurrentRecord: TDBISAMRecord): string;
var
  Obj: TJSONObject;
  I: Integer;
begin
  Obj := TJSONObject.Create;
  try

    for I := 0 to CurrentRecord.FieldCount - 1 do
    begin
      Obj.AddPair(
        CurrentRecord.Fields[I].FieldName,
        VarToStr(CurrentRecord.Fields[I].Value)
      );
    end;

    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

// custom mapping for tables
procedure TMainForm.RegisterTables;
begin
  FTableKeys := TDictionary<string,string>.Create;
  // keys
  FTableKeys.Add('Sinventario', 'FI_CODIGO');
  FTableKeys.Add('SinvDep', 'FT_CODIGOPRODUCTO');
  FTableKeys.Add('a2InvCostosPrecios', 'FIC_CODEITEM');
end;

procedure TMainForm.StartButtonClick(Sender: TObject);
begin
   try
      StartButton.Enabled:=False;
      StartItem.Enabled:=False;
      IconHint:='Starting';
      UpdateTrayIcon;
      ServerEngine.StartMainServer;
   except
      StartButton.Enabled:=True;
      StartItem.Enabled:=True;
      StopButton.Enabled:=False;
      StopItem.Enabled:=False;
      IconHint:=GetStoppedHint;
      UpdateTrayIcon;
      raise;
   end;
end;

procedure TMainForm.StopButtonClick(Sender: TObject);
var
   ContinueStopping: Boolean;
begin
   ContinueStopping:=True;
   if (ServerEngine.GetServerConnectedSessionCount > 0) then
      begin
      if (MessageDlg('There are active sessions currently connected and stopping '+
                     'the server will disconnect these active sessions, are you '+
                     'sure you want to stop the server ?',mtConfirmation,[mbYes,mbNo],0)=mrNo) then
         ContinueStopping:=False;
      end;
   if ContinueStopping then
      begin
      try
         IconHint:='Stopping';
         UpdateTrayIcon;
         StopButton.Enabled:=False;
         StopItem.Enabled:=False;
         ServerEngine.StopMainServer;
      except
         StartButton.Enabled:=False;
         StartItem.Enabled:=False;
         StopButton.Enabled:=True;
         StopItem.Enabled:=True;
         IconHint:=GetStartedHint;
         UpdateTrayIcon;
         raise;
      end;
      end
   else
      Abort;
end;

procedure TMainForm.WhatsThisItemClick(Sender: TObject);
begin
   if (HelpPopup.PopupComponent is TControl) then
      Application.HelpCommand(HELP_CONTEXTPOPUP,
                  TControl(HelpPopup.PopupComponent).Tag);
end;

procedure TMainForm.ApplicationMessage(var Msg: TMsg; var Handled: Boolean);
begin
   Handled:=False;
   if (Msg.Message=WM_CLOSE) then
      begin
      Hide;
      Close;
      end;
end;

procedure TMainForm.ApplicationMinimize(Sender: TObject);
begin
   Hide;
end;

procedure TMainForm.IconTimerTimer(Sender: TObject);
begin
   UpdateTrayIcon;
end;

procedure TMainForm.ApplicationIdle(Sender: TObject; var Done: Boolean);
begin
   ProcessDisplayQueue;
   Done:=True;
end;

procedure TMainForm.ProcessDisplayQueue;
var
   ItemPos: Integer;
begin
   DisplayQueueSection.Enter;
   try
      while (DisplayQueue.Count > 0) do
         begin
         with TSessionDisplayItem(DisplayQueue[0]) do
            begin
            case ActionType of
               atConnect:
                  begin
                  SessionItem.Connected:=True;
                  SessionItem.Encrypted:=NewEncrypted;
                  SessionItem.UserName:='';
                  SessionItem.Address:=NewAddress;
                  SessionItem.CreatedOn:=NewCreatedOn;
                  SessionsList.Add(SessionItem);
                  Inc(TotalSessions);
                  Inc(TotalConnectedSessions);
                  if Visible then
                     begin
                     SessionsListView.Items.Count:=TotalSessions;
                     SessionsListView.UpdateItems(TotalSessions-1,TotalSessions-1);
                     UpdateSessionInfo;
                     end;
                  end;
               atDisconnect:
                  begin
                  SessionItem.Connected:=False;
                  SessionItem.Address:=NewAddress;
                  Dec(TotalConnectedSessions);
                  if Visible then
                     begin
                     ItemPos:=SessionsList.IndexOf(SessionItem);
                     if (ItemPos <> -1) then
                        SessionsListView.UpdateItems(ItemPos,ItemPos);
                     UpdateSessionInfo;
                     end;
                  end;
               atReconnect:
                  begin
                  SessionItem.Connected:=True;
                  SessionItem.Encrypted:=NewEncrypted;
                  SessionItem.Address:=NewAddress;
                  Inc(TotalConnectedSessions);
                  if Visible then
                     begin
                     ItemPos:=SessionsList.IndexOf(SessionItem);
                     if (ItemPos <> -1) then
                        SessionsListView.UpdateItems(ItemPos,ItemPos);
                     UpdateSessionInfo;
                     end;
                  end;
               atLogin:
                  begin
                  SessionItem.UserName:=NewUserName;
                  if Visible then
                     begin
                     ItemPos:=SessionsList.IndexOf(SessionItem);
                     if (ItemPos <> -1) then
                        SessionsListView.UpdateItems(ItemPos,ItemPos);
                     end;
                  end;
               atLogout:
                  begin
                  ItemPos:=SessionsList.IndexOf(SessionItem);
                  if (ItemPos <> -1) then
                     begin
                     Dec(TotalSessions);
                     if SessionItem.Connected then
                        Dec(TotalConnectedSessions);
                     SessionsList.Delete(ItemPos);
                     if Visible then
                        begin
                        SessionsListView.UpdateItems(ItemPos,TotalSessions);
                        UpdateSessionInfo;
                        end;
                     end;
                  end;
               end;
            end;
         DisplayQueue.Delete(0);
         end;
   finally
      DisplayQueueSection.Leave;
   end;
end;

procedure TMainForm.AddToDisplayQueue(Value: TSessionDisplayItem);
begin
   DisplayQueueSection.Enter;
   try
      DisplayQueue.Add(Value);
   finally
      DisplayQueueSection.Leave;
      Application.ProcessMessages;
   end;
end;

// sending event to Aggregation server
procedure SendEvent (
  const TableName: string;
  const KeyField: string;
  const KeyValue: string;
  const Payload: string;
  const operation: string
);
var
  HTTP: TIdHTTP;
  Body: TStringStream;
  Json: TJSONObject;
begin
  // create
  HTTP := TIdHTTP.Create(nil);
  try
    // timeout settings
    HTTP.ConnectTimeout := 3000;
    HTTP.ReadTimeout := 3000;
    HTTP.Request.ContentType := 'application/json';
    // JSON
    Json := TJSONObject.Create;
    // try
    try
      Json.AddPair('timestamp', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Now));
      Json.AddPair('operation', operation);
      Json.AddPair('table', TableName);
      Json.AddPair('keyField', KeyField);
      Json.AddPair('keyValue', KeyValue);
      Json.AddPair('data', TJSONObject.ParseJSONValue(Payload));
      // stream object of JSON
      Body := TStringStream.Create(
        Json.ToJSON,
        TEncoding.UTF8
      );
      // sending request
      try
        HTTP.Post('http://127.0.0.1:3000/api/db-trigger', Body);
      finally
        Body.Free;
      end;

    finally
      Json.Free;
    end;

  finally
    HTTP.Free;
  end;

end;

// INSERT TRIGGER (FROM SERVICE ENGINE)
procedure TMainForm.ServerEngineAfterInsertTrigger(Sender: TObject;
  TriggerSession: TDBISAMSession; TriggerDatabase: TDBISAMDatabase;
  const TableName: string; CurrentRecord: TDBISAMRecord);
var
  KeyField: string;
  KeyValue: string;
  Payload: string;
begin
  KeyField := GetPrimaryKeyField(TableName);
    if KeyField = '' then
      Exit;
    KeyValue := VarToStr(CurrentRecord.FieldByName(KeyField).Value);
    Payload := SerializeRecordToJson(CurrentRecord);
    // sending request
    SendEvent(TableName, KeyField, KeyValue, Payload, 'INSERT');
end;

// UPDATE TRIGGER (FROM SERVICE ENGINE)
procedure TMainForm.ServerEngineAfterUpdateTrigger(Sender: TObject;
  TriggerSession: TDBISAMSession; TriggerDatabase: TDBISAMDatabase;
  const TableName: string; CurrentRecord: TDBISAMRecord);
var
  KeyField: string;
  KeyValue: string;
  Payload: string;
begin
try
    KeyField := GetPrimaryKeyField(TableName);
    if KeyField = '' then
      Exit;
    KeyValue := VarToStr(CurrentRecord.FieldByName(KeyField).Value);
    Payload := SerializeRecordToJson(CurrentRecord);
    // sending request
    SendEvent(TableName, KeyField, KeyValue, Payload, 'UPDATE');
except
  on E: Exception do
  begin
    TFile.AppendAllText('C:\dbisam-errors.txt', E.Message + sLineBreak, TEncoding.UTF8);
  end;
end;
end;

procedure TMainForm.ServerEngineServerConnect(Sender: TObject;
  IsEncrypted: Boolean; const ConnectAddress: String;
  var UserData: TObject);
var
   DisplayItem: TSessionDisplayItem;
begin
   UserData:=nil;
   if NoUI then Exit;
   UserData:=TSessionItem.Create;
   DisplayItem:=TSessionDisplayItem.Create;
   with DisplayItem do
      begin
      ActionType:=atConnect;
      NewEncrypted:=IsEncrypted;
      NewUserName:='';
      NewAddress:=ConnectAddress;
      NewCreatedOn:=Now;
      SessionItem:=TSessionItem(UserData);
      end;
   AddToDisplayQueue(DisplayItem);
end;

procedure TMainForm.ServerEngineServerDisconnect(Sender, UserData: TObject;
  const LastConnectAddress: String);
var
   DisplayItem: TSessionDisplayItem;
begin
   if NoUI then Exit;
   if (UserData <> nil) then
      begin
      DisplayItem:=TSessionDisplayItem.Create;
      with DisplayItem do
         begin
         ActionType:=atDisconnect;
         NewAddress:=LastConnectAddress;
         SessionItem:=TSessionItem(UserData);
         end;
      AddToDisplayQueue(DisplayItem);
      end;
end;

procedure TMainForm.ServerEngineServerReconnect(Sender: TObject;
  IsEncrypted: Boolean; const ConnectAddress: String; UserData: TObject);
var
   DisplayItem: TSessionDisplayItem;
begin
   if NoUI then Exit;
   if (UserData <> nil) then
      begin
      DisplayItem:=TSessionDisplayItem.Create;
      with DisplayItem do
         begin
         ActionType:=atReconnect;
         NewEncrypted:=IsEncrypted;
         NewAddress:=ConnectAddress;
         SessionItem:=TSessionItem(UserData);
         end;
      AddToDisplayQueue(DisplayItem);
      end;
end;

procedure TMainForm.ServerEngineServerLogin(Sender: TObject;
  const UserName: String; UserData: TObject);
var
   DisplayItem: TSessionDisplayItem;
begin
   if NoUI then Exit;
   if (UserData <> nil) then
      begin
      DisplayItem:=TSessionDisplayItem.Create;
      with DisplayItem do
         begin
         ActionType:=atLogin;
         NewUserName:=UserName;
         SessionItem:=TSessionItem(UserData);
         end;
      AddToDisplayQueue(DisplayItem);
      end;
end;

procedure TMainForm.ServerEngineServerLogout(Sender: TObject;
  var UserData: TObject);
var
   DisplayItem: TSessionDisplayItem;
begin
   if NoUI then Exit;
   if (UserData <> nil) then
      begin
      DisplayItem:=TSessionDisplayItem.Create;
      with DisplayItem do
         begin
         ActionType:=atLogout;
         SessionItem:=TSessionItem(UserData);
         end;
      AddToDisplayQueue(DisplayItem);
      end;
end;

procedure TMainForm.ServerEngineServerStart(Sender: TObject);
begin
   StartSQLPerfTracking;
   StartButton.Enabled:=False;
   StartItem.Enabled:=False;
   StopButton.Enabled:=True;
   StopItem.Enabled:=True;
   IconHint:=GetStartedHint;
   UpdateTrayIcon;
   UpdateVariableSystemInfo;
end;

procedure TMainForm.ServerEngineServerStop(Sender: TObject);
begin
   StopSQLPerfTracking;
   StartButton.Enabled:=True;
   StartItem.Enabled:=True;
   StopButton.Enabled:=False;
   StopItem.Enabled:=False;
   IconHint:=GetStoppedHint;
   UpdateTrayIcon;
   UpdateVariableSystemInfo;
end;

procedure TMainForm.ServerEngineServerLogEvent(Sender: TObject;
  LogRecord: TLogRecord);
begin
   FileSeek(LogFileHandle,0,2);
   FileWrite(LogFileHandle,LogRecord,SizeOf(TLogRecord));
end;

procedure TMainForm.ServerEngineServerLogCount(Sender: TObject;
  var LogCount: Integer);
var
   TotalLogSize: Int64;
begin
   TotalLogSize:=FileSeek(LogFileHandle,0,2);
   if (TotalLogSize > High(Integer)) then
      TotalLogSize:=High(Integer);
   LogCount:=(TotalLogSize div SizeOf(TLogRecord));
   if (TotalLogSize <> LogBufferSize) then
      begin
      DeAllocMem(LogBuffer);
      LogBuffer:=AllocMem(TotalLogSize);
      LogBufferSize:=TotalLogSize;
      FileSeek(LogFileHandle,0,0);
      FileRead(LogFileHandle,LogBuffer^,LogBufferSize);
      end;
end;

procedure TMainForm.ServerEngineServerLogRecord(Sender: TObject;
  Number: Integer; var LogRecord: TLogRecord);
var
   TempOffset: Integer;
begin
   TempOffset:=((Number-1)*SizeOf(TLogRecord));
   if (TempOffset <= (LogBufferSize-SizeOf(TLogRecord))) then
      Move((LogBuffer+TempOffset)^,LogRecord,SizeOf(TLogRecord));
end;

procedure TMainForm.UpdateListItem(SessionItem: TSessionItem);
begin
   with SessionItem do
      begin
      if (UserName <> '') then
         ListItem.Caption:=UserName
      else
         ListItem.Caption:='N/A';
      if Connected then
         begin
         if Encrypted then
            ListItem.ImageIndex:=1
         else
            ListItem.ImageIndex:=0;
         if (ListItem.SubItems.Count=0) then
            ListItem.SubItems.Add(Address)
         else
            ListItem.SubItems[0]:=Address;
         end
      else
         begin
         ListItem.ImageIndex:=2;
         if (ListItem.SubItems.Count=0) then
            ListItem.SubItems.Add('Disconnected ('+Address+')')
         else
            ListItem.SubItems[0]:='Disconnected ('+Address+')';
         end;
      if (ListItem.SubItems.Count=1) then
         ListItem.SubItems.Add(DateTimeToStr(CreatedOn))
      else
         ListItem.SubItems[1]:=DateTimeToStr(CreatedOn);
      end;
end;

procedure TMainForm.SessionsListViewData(Sender: TObject; Item: TListItem);
begin
   if (Item.Index >= TotalSessions) then
      Exit;
   TSessionItem(SessionsList[Item.Index]).ListItem:=Item;
   UpdateListItem(TSessionItem(SessionsList[Item.Index]));
end;

procedure TMainForm.SQLPerfThreadStart(AThread: TServerSQLPerfThread);
begin
end;

procedure TMainForm.SQLPerfThreadStop(AThread: TServerSQLPerfThread);
begin
end;

procedure TMainForm.SQLPerfThreadAbort(AThread: TServerSQLPerfThread);
begin
end;

procedure TMainForm.SQLPerfThreadException(AThread: TServerSQLPerfThread);
begin
end;

procedure TMainForm.DSSQLPerf(var Msg: TMessage);
var
   TempThread: TServerSQLPerfThread;
begin
   try
      TempThread:=TServerSQLPerfThread(Msg.wParam);
      case Msg.Msg of
         SQLPERF_START:
            SQLPerfThreadStart(TempThread);
         SQLPERF_STOP:
            SQLPerfThreadStop(TempThread);
         SQLPERF_ABORT:
            SQLPerfThreadAbort(TempThread);
         SQLPERF_ERROR:
            begin
            try
               SQLPerfThreadException(TempThread);
            finally
               TempThread.ReleaseException;
            end;
            end;
         end;
   except
      raise;
   end;
end;

procedure TMainForm.StartSQLPerfTracking;
begin
   SQLPerfThread:=TServerSQLPerfThread.Create(SQLPerfFileName,MaxSQLPerfFileSize,
                                              SQLPerfFileAutoIncrement,
                                              MaxSQLPerfFileAutoIncrement);
end;

procedure TMainForm.StopSQLPerfTracking;
begin
   SQLPerfThread.Terminate;
   SQLPerfThread.WaitFor;
   FreeAndNilObject(SQLPerfThread);
end;

procedure TMainForm.AddSQLPerfEntry(ASQLPerfEntry: TServerSQLPerfEntry);
begin
   SQLPerfQueue.Enqueue(ASQLPerfEntry);
   SQLPerfThread.Start;
end;

procedure TMainForm.AddSQLPerfEntries(ASQLPerfEntries: TServerSQLPerfEntryArray);
begin
   SQLPerfQueue.Enqueue(ASQLPerfEntries);
   SQLPerfThread.Start;
end;

procedure TMainForm.ServerEngineSQLTrigger(Sender: TObject;
  TriggerSession: TDBISAMSession; TriggerDatabase: TDBISAMDatabase;
  StatementType: TSQLStatementType; const SQL: String;
  ExecutionTime: Double; RowsAffected: Integer);
var
   SQLPerfEntry: TServerSQLPerfEntry;
begin
   if (ExecutionTime >= SQLPerfMinExecutionTime) then
      begin
      SQLPerfEntry:=SQLPerfPool.Get;
      SQLPerfEntry.DateTime:=Now;
      SQLPerfEntry.UserName:=TriggerSession.CurrentServerUser;
      SQLPerfEntry.Database:=TriggerDatabase.DatabaseName;
      SQLPerfEntry.StatementType:=StatementType;
      SQLPerfEntry.SQL:=SQL;
      SQLPerfEntry.ExecutionTime:=ExecutionTime;
      SQLPerfEntry.RowsAffected:=RowsAffected;
      AddSQLPerfEntry(SQLPerfEntry)
      end;
end;

end.

