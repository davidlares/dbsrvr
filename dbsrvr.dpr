program dbsrvr;

uses
  {$I dbisamvr.inc }

  {$IFDEF MSWINDOWS}
  {$IFDEF D7UP}
  {$SetPEFlags $20}
  {$ENDIF}

  {$IFNDEF D11UP}
  FastMM4,
  {$ENDIF}
  {$ENDIF}

  SysUtils,

  {$IFDEF MSWINDOWS}
  WinSvc,
  SvcMgr,
  Windows,
  Forms,
  {$ENDIF}

  dbisamcn,
  dbisamlb,
  dbisamut,
  main in 'main.pas' {MainForm},
  about in 'about.pas' {AboutBox};

{$R *.res}

{$IFDEF MSWINDOWS}
function StartingService(var Interactive: Boolean): Boolean;
var
   Manager: Integer;
   Service: Integer;
   ServiceStatus: TServiceStatus;
   ConfigBytes: DWORD;
   {$IFDEF D15UP}
   ServiceConfig: LPQUERY_SERVICE_CONFIGA;
   {$ELSE}
   ServiceConfig: pQueryServiceConfigA;
   {$ENDIF}
begin
   Result:=False;
   Interactive:=False;
   Manager:=OpenSCManagerA(nil,nil,SC_MANAGER_ALL_ACCESS);
   if (Manager <> 0) then
      begin
      try
         Service:=OpenServiceA(Manager,pAnsiChar(AnsiString(ServerName)),SERVICE_ALL_ACCESS);
         Result:=(Service <> 0);
         if Result then
            begin
            try
               if QueryServiceStatus(Service,ServiceStatus) then
                  begin
                  if (ServiceStatus.dwCurrentState=SERVICE_START_PENDING) then
                     begin
                     Result:=True;
                     QueryServiceConfigA(Service,nil,0,ConfigBytes);
                     ServiceConfig:=AllocMem(ConfigBytes);
                     try
                        if QueryServiceConfigA(Service,ServiceConfig,ConfigBytes,
                                               ConfigBytes) then
                           Interactive:=((ServiceConfig^.dwServiceType and
                                          SERVICE_INTERACTIVE_PROCESS)=SERVICE_INTERACTIVE_PROCESS);
                     finally
                        DeAllocMem(ServiceConfig);
                     end;
                     end
                  else
                     Result:=False;
                  end
               else
                  Result:=False;
            finally
               CloseServiceHandle(Service);
            end;
            end;
      finally
         CloseServiceHandle(Manager);
      end;
      end;
end;

var
   Mutex: THandle;
   MutexName: array [0..MAX_PATH] of AnsiChar;
   IsInteractive: Boolean;
begin
   StrPCopy(@MutexName,AnsiString(AnsiLowerCase(StringReplace(ParamStr(0),OSBackSlash,
                                                              OSForwardSlash,[rfReplaceAll]))));
   Mutex:=CreateMutexA(nil,True,@MutexName);
   if (Mutex <> 0) and (GetLastError=0) then
      begin
      ServerName:=AnsiUpperCase(StripFilePathAndExtension(ParamStr(0),'.exe'));
      IsInteractive:=False;
      if (InstallingService or StartingService(IsInteractive)) then
         begin
         ServerDescription:=DEFAULT_SERVER_DESC+' - '+ServerName+' (Service)';
         SvcMgr.Application.Initialize;
         if InstallingService then
            DatabaseService:=TDatabaseService.CreateNew(SvcMgr.Application,
                                                        Integer(InteractiveService))
         else
            DatabaseService:=TDatabaseService.CreateNew(SvcMgr.Application,
                                                        Integer(IsInteractive));
         SvcMgr.Application.CreateForm(TMainForm, MainForm);
         SvcMgr.Application.Run;
         end
      else
         begin
         ServerDescription:=DEFAULT_SERVER_DESC+' - '+ServerName+' (Application)';
         Forms.Application.ShowMainForm:=False;
         Forms.Application.UpdateFormatSettings:=False;
         Forms.Application.Initialize;
         Forms.Application.CreateForm(TMainForm,MainForm);
         Forms.Application.Icon:=MainForm.Icon;
         MainForm.Initialize(nil);
         Forms.Application.CreateForm(TAboutBox,AboutBox);
         Forms.Application.Run;
         end;
      CloseHandle(Mutex);
      end;
{$ENDIF}
end.
