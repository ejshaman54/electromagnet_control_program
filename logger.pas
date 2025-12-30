unit logger;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils;

type
  ELoggerError = class(Exception);

  { TLogSample
    One row to time-series data }
  TLogSample = record
    // Timing
    TimeUTC: TDateTime;
    Elapsed_s: Double;

    // Raw and derived measurements
    VHall_V: Double;
    Bmeas_T: Double;
    Bset_T: Double;

    // Commands
    Vcmd_V: Double;

    // Control telemetry
    Err_T: Double;
    P_V: Double;
    I_V: Double;
    D_V: Double;

    // Status flags
    Enabled: Boolean;
    Saturated: Boolean;
    Fault: Boolean;
  end;

  { TSessionMetadata }
  TSessionMetadata = record
    OperatorName: string;
    ExperimentName: string;
    DevicePath: string;
    Notes: string;

    // Hall calibration
    HallV0_V: Double;
    HallTperV: Double;
    HallFilter: string;

    // Magnet calibration
    KepcoAOChannel: Integer;
    KepcoClampMinV: Double;
    KepcoClampMaxV: Double;
    KepcoSlewVps: Double;

    // Map Vprog->I and I->B
    ProgV0_V: Double;
    I0_A: Double;
    IperV_AperV: Double;

    B0_T: Double;
    TperA_TperA: Double;

    // Controller
    Kp_VperT: Double;
    Ki_VperTs: Double;
    Kd_VsperT: Double;
    Ramp_Tps: Double;
    DerivTau_s: Double;
    OutMinV: Double;
    OutMaxV: Double;
  end;

  { TCSVLogger
    Creates:
    - <base>.csv    : time series
    - <base>.meta.txt : metadata
  }
  TCSVLogger = class
  private
    FCSV: TextFile;
    FIsOpen: Boolean;
    FCSVPath: string;
    FMetaPath: string;

    FStartUTC: TDateTime;

    function Bool01(b: Boolean): string;
    function FMTFloate(x: Double): string;
    procedure EnsureOpen;

  public
    constructor Create;
    destructor Destroy; override;

    // Opens CSV and writes header
    procedure OpenSession(const BasePath: string;
                          const Meta: TSessionMetadata;
                          Overwrite: Boolean = False);

    procedure CloseSession;

    function IsOpen: Boolean;
    function CSVPath: string;
    function MetaPath: string;

    // Append one row
    procedure LogSample(const S: TLogSample);

    // Make UTC timestamp for now
    class function NowUTC: TDateTime;
  end;


implementation

constructor TCSVLogger.Create;
begin
  inherited Create;
  FIsOpen := False;
  FCSVPath := '';
  FMetaPath := '';
  FStartUTC := 0;
end;

destructor TCSVLogger.Destroy;
begin
  try
    CloseSession;
  except
    //
  end;
  inherited Destroy;
end;

class function TCSVLogger.NowUTC: TDateTime;
begin
  Result := LocalTimeToUniversal(Now);
end;

function TCSVLogger.IsOpen; Boolean;
begin
  Result := FIsOpen;
end;

function TCSVLogger.CSVPath: string;
begin
  Result := FCSVPath;
end;

function TCSVLogger.MetaPath: string;
begin
  Result := FMetaPath;
end;

function TCSVLogger.EnsureOpen;
begin
  if not FIsOpen then
    raise ELoggerError.Create('Logger is not open.');
end;

function TCSVLogger.Bool01(b: Boolean): string;
begin
  if b then Result := '1' else Result := '0';
end;

function TCSVLogger.FmtFloat(x: Double): string;
begin
  Result := FloatToStr(x, ffGeneral, 16, 6, DefaultFormatSettings);
end;

procedure TCSVLogger.OpenSession(const BasePath: string;
  const Meta: TSessionMetadata; Overwrite: Boolean);
var
  base, csvPath, metaPath: string;
  metaFile: TextFile;

  procedure RequireNotExistsOrOverwrite(const path: string);
  begin
    if FileExists(path) and (not Overwrite) then
      raise ELoggerError.CreateFmt('File exists (set Overwrite=True): %s', [path]);
  end;

begin
  if FIsOpen then
    CloseSession;

  // Normalize base path
  base := BasePath;
  if ExtractFileExt(base) = '.csv' then
    base := ChangeFileExt(base, '');

  csvPath := base + '.csv';
  metaPath := base + '.meta.txt';

  RequireNotExistsOrOverwrite(csvPath);
  RequireNotExistsOrOverwrite(metaPath);

  FCSVPath := csvPath;
  FMetaPath := metaPathl

  FStartUTC := NowUTC;

  // --- Write metadata sidecar ---

  AssignFile(metaFile, FMetaPath);
  Rewrite(metaFile);
  try
    Writeln(metaFile, '=== Hall+Kepco Session Metadata ===');
    Writeln(metaFile, 'StartUTC: ', FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"."zzz"Z"', FStartUTC));
    Writeln(metaFile);

    Writeln(metaFile, '[HallProbe]');
    Writeln(metaFile, 'V0_V: ', FmtFloat(Meta.HallV0_V));
    Writeln(metaFile, 'TperV: ', FmtFloat(Meta.HallTperV));
    Writeln(metaFile, 'Filter: ', Meta.HallFilter);
    Writeln(metaFile);

    Writeln(metaFile, '[Kepco]');
    Writeln(metaFile, 'AOChannel: ', Meta.KepcoAOChannel);
    Writeln(metaFile, 'ClampMinV: ', FmtFloat(Meta.KepcoClampMinV));
    Writeln(metaFile, 'ClampMaxV: ', FmtFloat(Meta.KepcoClampMaxV));
    Writeln(metaFile, 'SlewVps: ', FmtFloat(Meta.KepcoSlewVps));
    Writeln(metaFile);

    Writeln(metaFile, '[Calibration]');
    Writeln(metaFile, 'ProgV0_V: ', FmtFloat(Meta.ProgV0_V));
    Writeln(metaFile, 'I0_A:', FmtFloat(Meta.I0_A));
    Writeln(metaFile, 'IperV_AperV', FmtFloat(Meta.IperV_AperV));
    Writeln(metaFile, 'B0_T', FmtFloat(Meta.B0_T));
    Writeln(metaFile, 'TperA_TperA', FmtFloat(Meta.TperA_TperA));
    Writeln(metaFile);

    Writeln(metaFile, '[Controller]');
    Writeln(metaFile, 'Kp_VperT: ', FmtFloat(Meta.Kp_VperT));
    Writeln(metaFile, 'Ki_VperTs: ', FmtFloat(Meta.Ki_VperTs));
    Writeln(metaFile, 'Kd_VsperT: ', FmtFloat(Meta.Kd_VsperT));
    Writeln(metaFile, 'Ramp_Tps: ', FmtFloat(Meta.Ramp_Tps));
    Writeln(metaFile, 'DerivTau_s: ', FmtFloat(Meta.DerivTau_s));
    Writeln(metaFile, 'OutMinV: ', FmtFloat(Meta.OutMinV));
    Writeln(metaFile, 'OutMaxV: ', FmtFloat(Meta.OutMaxV));
  finally
    CloseFile(metaFile);
  end;

  // --- Open CSV and write header ---
  AssignFile(FCSV, FCSVPath);
  Rewrite(FCSV);

  // CSV header
  Writeln(FCSV,
    't_utc_iso,elapsed_s,'
    + 'vhall_v,bmeas_t,bset_t,'
    + 'vcmd_v, err_t,p_v,i_v,d_v'
    + 'enabled,saturated,fault'
  );

  FIsOpen := True;
end;

procedure TCSVLogger.CloseSession;
begin
  if FIsOpen then
  begin
    CloseFile(FCSV);
    FIsOpen := False;
  end;
end;

procedure TCSVLogger.LogSample(const S: TLogSample);
var
  ts: string;
begin
  EnsureOpen;

  ts := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"."zzz"Z"', S.TimeUTC);

  Writeln(FCSV,
    ts, ',',
    FmtFloat(S.Elapsed_s), ',',
    FmtFloat(S.VHall_V), ',',
    FmtFloat(S.Bmeas_T), ',',
    FmtFloat(S.Bset_T), ',',
    FmtFloat(S.Vcmd_V), ',',
    FmtFloat(S.Err_T), ',',
    FmtFloat(S.P_V), ',',
    FmtFloat(S.I_V), ',',
    FmtFloat(S.D_V), ',',
    FmtFloat(S.Enabled), ',',
    FmtFloat(S.Saturated), ',',
    FmtFloat(S.Fault), ',',
  );

  Flush(FCSV);
end;


end.

