; Nox 1.0 for Windows: Inno Setup 7 script.
; Build:  ISCC.exe /DAppVersion=1.0.6 /DDist=..\dist installer\nox.iss
; Dist layout (made by CI, see .github/workflows/windows.yml):
;   dist\app\   Flutter Release folder (Nox.exe, flutter_windows.dll, plugins, data\) + VC++ runtime DLLs
;   dist\core\  noxd.exe, sing-box.exe, libcronet.dll, qwdtt.exe, xray.exe, *.srs, LICENSES.txt
; The UI runs as the normal user. Only the installer needs admin: it registers the
; "Nox" service (LocalSystem), which owns TUN, routes and SSTP. No OpenVPN.
; Silent update (from the service): Setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART

#ifndef AppVersion
  #define AppVersion "1.0.6"
#endif
#ifndef Dist
  #define Dist "..\dist"
#endif
#ifndef OutDir
  #define OutDir "..\out"
#endif

[Setup]
AppId={{6E0F3B8C-2D4A-4C1E-9B57-0A9D1F4E7C21}
AppName=Nox
AppVersion={#AppVersion}
AppVerName=Nox {#AppVersion}
AppPublisher=Nox
VersionInfoVersion={#AppVersion}
VersionInfoProductName=Nox
VersionInfoDescription=Nox VPN Setup
DefaultDirName={autopf}\Nox
DefaultGroupName=Nox
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=admin
SetupArchitecture=x64
MinVersion=10.0
OutputDir={#OutDir}
OutputBaseFilename=Nox-Setup-{#AppVersion}
SetupIconFile={#Dist}\app\data\flutter_assets\assets\icon.ico
UninstallDisplayIcon={app}\Nox.exe
UninstallDisplayName=Nox
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
; Restart Manager closes Nox.exe (UI) before files are replaced; the service is
; stopped explicitly in PrepareToInstall. Never ask to reboot.
CloseApplications=force
RestartApplications=no
RestartIfNeededByRun=no
; SignTool=nox $f   ; enable when a code-signing certificate is available (see README)

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
ru.DeskIcon=Ярлык на рабочем столе
en.DeskIcon=Desktop shortcut
ru.RunNox=Запустить Nox
en.RunNox=Launch Nox
ru.SvcFail=Не удалось установить службу Nox (код %1). Подробности: %2
en.SvcFail=Could not install the Nox service (code %1). Details: %2
ru.DelData=Удалить также подписки и настройки Nox?
en.DelData=Also delete Nox subscriptions and settings?
ru.Uninst=Удалить Nox
en.Uninst=Uninstall Nox

[Tasks]
Name: "desktopicon"; Description: "{cm:DeskIcon}"

[Files]
Source: "{#Dist}\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#Dist}\core\*"; DestDir: "{app}\core"; Flags: ignoreversion recursesubdirs createallsubdirs

[Dirs]
; data dir of the service; ipc.json inside gets its own ACL from noxd
Name: "{commonappdata}\Nox"

[Icons]
Name: "{group}\Nox"; Filename: "{app}\Nox.exe"
Name: "{group}\{cm:Uninst}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Nox"; Filename: "{app}\Nox.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\core\noxd.exe"; Parameters: "install"; Flags: runhidden waituntilterminated; StatusMsg: "Nox service…"; AfterInstall: CheckSvc
Filename: "{app}\core\noxd.exe"; Parameters: "start"; Flags: runhidden waituntilterminated
Filename: "{app}\Nox.exe"; Description: "{cm:RunNox}"; Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallRun]
Filename: "{app}\core\noxd.exe"; Parameters: "stop"; Flags: runhidden waituntilterminated; RunOnceId: "NoxStop"
Filename: "{app}\core\noxd.exe"; Parameters: "uninstall"; Flags: runhidden waituntilterminated; RunOnceId: "NoxUninstall"
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM Nox.exe"; Flags: runhidden waituntilterminated; RunOnceId: "NoxKillUI"

[UninstallDelete]
Type: files; Name: "{commonappdata}\Nox\ipc.json"
Type: files; Name: "{commonappdata}\Nox\noxd.log"
Type: dirifempty; Name: "{app}\core"
Type: dirifempty; Name: "{app}"

[Code]
const
  OldKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\Nox'; // Nox 0.8.x (NSIS)
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  InetKey = 'Software\Microsoft\Windows\CurrentVersion\Internet Settings';

procedure Run(const Exe, Params: String);
var Code: Integer;
begin
  Exec(Exe, Params, '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

// Nox 0.8.x (Wails + NSIS) and the even older VPS app: stop them and remove the old
// program files. User data in %LOCALAPPDATA%\Nox and \VPS stays; the new UI imports
// it into the service on first start (OpenVPN servers are dropped).
procedure RemoveNox08;
var Un, Dir: String;
begin
  Run(ExpandConstant('{sys}\schtasks.exe'), '/Delete /F /TN Nox');
  Run(ExpandConstant('{sys}\schtasks.exe'), '/Delete /F /TN VPS');
  if not RegQueryStringValue(HKLM64, OldKey, 'InstallLocation', Dir) then exit;
  Un := AddBackslash(Dir) + 'Uninstall.exe';
  if FileExists(Un) then begin
    Log('Removing Nox 0.8.x from ' + Dir);
    Run(Un, '/S _?=' + Dir); // NSIS silent: keeps user data
    DeleteFile(Un);
  end;
  RegDeleteKeyIncludingSubkeys(HKLM64, OldKey);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Svc: String;
begin
  Result := '';
  Svc := ExpandConstant('{app}\core\noxd.exe');
  if FileExists(Svc) then
    Run(Svc, 'stop');  // upgrade: release core binaries; VPN reconnects after start
  Run(ExpandConstant('{sys}\taskkill.exe'), '/F /IM Nox.exe');
  Run(ExpandConstant('{sys}\taskkill.exe'), '/F /IM sing-box.exe');
  Run(ExpandConstant('{sys}\taskkill.exe'), '/F /IM qwdtt.exe');
  Run(ExpandConstant('{sys}\taskkill.exe'), '/F /IM xray.exe');
  RemoveNox08;
end;

procedure CheckSvc;
var Code: Integer; LogPath: String;
begin
  // noxd install is idempotent; verify the service exists
  if not Exec(ExpandConstant('{sys}\sc.exe'), 'query Nox', '', SW_HIDE, ewWaitUntilTerminated, Code) or (Code <> 0) then begin
    LogPath := ExpandConstant('{commonappdata}\Nox\noxd.log');
    SuppressibleMsgBox(FmtMessage(CustomMessage('SvcFail'), [IntToStr(Code), LogPath]), mbError, MB_OK, IDOK);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var P: String;
begin
  if CurUninstallStep = usUninstall then begin
    // per-user bits written by the UI: autostart and a system proxy left pointing at us
    RegDeleteValue(HKCU, RunKey, 'Nox');
    if RegQueryStringValue(HKCU, InetKey, 'ProxyServer', P) and (Pos('127.0.0.1:', P) = 1) then
      RegWriteDWordValue(HKCU, InetKey, 'ProxyEnable', 0);
  end;
  if (CurUninstallStep = usPostUninstall) and not UninstallSilent then
    if MsgBox(CustomMessage('DelData'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then begin
      DelTree(ExpandConstant('{commonappdata}\Nox'), True, True, True);
      DelTree(ExpandConstant('{localappdata}\Nox'), True, True, True);
    end;
end;
