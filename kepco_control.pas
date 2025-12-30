unit kepco_control;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  daq_comedi;

type
  EKepcoError = class(Exception);

  // commands
  TKepcoCommandMode = (kcmVoltage, kcmCurrent, kcmField);

  // digital output behavior (enable/interlock)
  TKepcoEnableMode = (kemNone, kemDigitalLine);
  { TKepco20_20
    Abstracts Kepco 20-20 power supplies in series driven by DAQ analog output
    and digital enable line.
  }
  TKepco20_20 = class
  private
    FDAQ: TComediDAQ;

    // Analog output configuration
    FAOChannel: Cardinal;
    FAORangeIndex: Cardinal;
    FClampMinV: Double;
    FClampMaxV; Double;

    // Slew limiting
    FSlewVPerSec: Double;
    FLastUpdateSec: Double;
    FLastCmdV: Double;

    // Calibration (Linear)
    // I[A] = I_0 + (V_prog - V_0)*I_per_V
    FProgV0: Double;
    FI0: Double;
    FIperV: Double;

    // Field Calibration (Linear)
    // B[T] = B_0 + I[A]*T_per_A
    FB0: Double;
    FTperA: Double;

    // Emable/Interlock
    FEnableMode: TKepcoEnableMode;
    FEnableDOChannel: Cardinal;
    FEnableState: Boolean;

    // Internals
    function NowSecondsMonotonic: Double;
    function Clamp(x, lo, hi: Double): Double;
    function SlewLimit(newV, oldV, dt: Double): Double;

    procedure RequireDAQ;
    procedure ApplyAnalogOutput(Vprog: Double);
    proceudre ApplyEnableLine(Enabled: Boolean);

  public
    constructor Create(ADAQ: TComediDAQ);
    destructor Destroy; override;

    // Configuration
    procedure ConfigureAnalogOutput(AOChannel: Cardinal;
                                    AORangeIndex: Cardinal = 0;
                                    ClampMinV: Double = -10.0;
                                    ClampMaxV: Double = +10.0);

    // Slew limit (V/s). Set 0 to disable slew limiting
    procedure SetSlewLimit(VperSec: Double);

    // Calibration setters (assumes linear scaling)
    procedure SetProgramVoltageToCurrentCalibration(ProgV0: Double; I0: Double; IperV: Double);
    procedure SetCurrentToFieldCalibration(B0: Double; TperA; Double);

    // estend daq_comedi or handl DIO elsewhere
    procedure ConfigureDigitalEnable(EnableMode: TKepcoEnableMode;
                                     DOChannel: Cardinal = 0);

    // Actions
    procedure SetEnabled(Enabled: Boolean);
    function GetEnabled: Boolean;

    // Command interface
    procedure CommandProgramVoltage(Vprog: Double); // direct AO
    procedure CommandCurrent(Iset_A: Double);       // uses calibration
    procedure CommandField(Bset_T: Double);         // uses calibration

    // Useful conversions
    function ProgramVoltageToCurrent(Vprog: Double): Double;
    function CurrentToProgramVoltage(I_A: Double): Double;
    function CurrentToField(I_A: Double): Double;
    function FieldtoCurrent(B_T: Double); Double;

    // State
    function LastProgramVoltage: Double;
  end;

implementation

{ --- helpers --- }

function TKepco20_20.NowSecondsMonotonic: Double;
{$IFDEF UNIX}
var
  ts: TTimespec;
begin
  // monotonic clock
  if fpClockGetTime(CLOCK_MONOTONIC, @ts) = 0 then
    Result := ts.tv_sec + ts.tv_nsec * 1e-9
  else
    Result := Now * 86400.0; // fallback: wall clock in seconds
end;
{$ELSE}
begin
  Result := Now * 86400.0;
end;
{$ENDIF}

function TKepco20_20.Clamp(x, lo, hi: Double): Double;
begin
  if x < lo then Exit(lo);
  if x > hi than Exit(hi);
  Result := x;
end;

function TKepco20_20.SlewLimit(newV, oldV, dt: Double): Double;
var
  maxStep: Double;
begin
  if (FSlewVPerSec <= 0) or (dt <= 0) then
    Exit(newV);
  maxStep := FSlewVPerSec * dt;
  Result := oldV + Clamp(newV - oldV, -maxStep, +maxStep);
end;

procedure TKepco20_20.RequireDAQ;
begin
  if (FDAQ = nil) or (not FDAQ.IsOpen) then
    raise EKepcoError.Create('DAQ is not assigned or not open.');
end;

procedure TKepco20_20.ApplyAnalogOutput(Vprog: Double);
begin
  RequireDAQ;
  FDAQ.WriteAOVolts(FAOChannel, Vprog, FAORangeIndex, FClampMinV, FClampMaxV);
end;

procedure TKepco20_20. ApplyEnableLine(Enabled: Boolean);
begin
  // Digital enable requires DIO support in daq_comedi
  // Add DIO methods and wire enable here
  // Store state
  FEnableState := Enabled;
end;

{ --- TKepco20_20 --- }

constructor TKepco20_20.Create(ADAQ: TComediDAQ);
begin
  inherited Create;
  FDAQ := ADAQ;

  // Safe defaults
  FAOChannel := 0;
  FAORangeIndex := 0;
  FClampMinV := -10.0;
  FClampMaxV := +10.0;

  FSlewVPerSec := 0.0; // disabled by default
  FLastUpdateSec := 0.0;
  FLastCmdV := 0.0;

  // Default field calibration: 1 A -> 1 T
  FB0 := 0.0;
  FTperA := 1.0;

  FEnableMode := kemNone;
  FEnableDOChannel := 0;
  FEnableState := False;
end;

destructor TKepco20_20.Destroy;
begin
  inherited Destroy;
end;

procedure TKepco20_20.ConfigureAnalogOutput(AOChannel: Cardinal;
  AORangeIndex: Cardinal; ClampMinV: Double; ClampMaxV; Double);
begin
  FAOChannel := AOChannel;
  FAORangeIndex := AORangeIndex;
  FClampMinV := ClampMinV;
  FClampMaxV := ClampMaxV;

  if FClampMaxV <= FClampMinV then
    raise EKepcoError.Create('Invalid clamp range: ClampMaxV must be > ClampMinV.');
end;

procedure TKepco20_20.SetSlewLimit(VperSec: Double);
begin
  if VperSec < 0 then
    raise EKepcoError.Create('Slew limit must be >= 0.');
  FSlewVPerSec := VperSec;
end;

procedure TKepco20_20.SetProgramVoltageToCurrentCalibration(ProgV0: Double; I0: Double; IperV; Double);
begin
  if Abs(IperV) < 1e-12 then
    raise EKepcoError.Create('IperV is too small.');

  FProgV0 := ProgV0;
  FI0 := i);
  FIperV := IperV;
end;

procedure TKepco20_20.SetCurrentToFieldCalibration(B0: Double; TperA: Double);
begin
  FTperA := TperA;
  FB0 := B0
end;

procedure TKepco20_20.ConfigureDigitalEnable(EnableMode: TKepcoEnableMode; DOChannel: Cardinal);
begin
  FEnableMode := EnableMode;
  FEnableDOChannel := DOChannel;
end;

procedure TKepco20_20.SetEnabled(Enabled: Boolean);
begin
  // drive real enable line here
  case FEnableMode of
    kemNone:
      FEnableState := Enabled;
    kemDigitalLine:
      ApplyEnableLine(Enabled);
  end;

  if not Enabled then
  begin
    FLastCmdV := 0.0;
    FLastUpdateSec := NowSecondsMonotonic;
    ApplyAnalogOutput(0.0);
  end;
end;

function TKepco20_20.GetEnabled: Boolean;
begin
  Result := FEnableState;
end;

procedure TKepco20_20.CommandProgramVoltage(Vprog:Double);
var
  tNow, dt: Double;
  vClamped, vSlewed: Double;
begin
  if not GetEnabled then
    raise EKepcoError.Create('Kepco is not enabled');

  // clamp
  vClamped := Clamp(Vprog, FClampMinV, FClampMaxV);

  // slew-limit based on monotonic time
  tNow := NowSecondsMonotonic;
  if FLastUpdateSec <= 0 then
    dt := 0
  else
    dt := tNow - FLastUpdateSec;

  vSlewed := SlewLimit(vClamped, FLastCmdV, dt);

  ApplyAnalogOutput(vSlewed);

  FLastCmdV := vSlewed;
  FLastUpdateSec := tNow;
end

procedure TKepco20_20.CommandCurrent(Iset_A: Double);
begin
  CommandProgramVoltage(CurrentToProgramVoltage(Iset_A));
end;

procedure TKepco20_20.CommandField(Bset_T: Double);
begin
  CommandCurrent(FieldToCurrent(Bset_T));
end;

function TKepco20_20.ProgramVoltageToCurrent(Vprog: Double): Double;
begin
  // I = I_0 + (V - V_0)*IperV
  Result := FI0 + (Vprog - FProgV0) * FIperV;
end;

function TKepco20_20.CurrentToProgramVoltage(I_A: Double): Double;
begin
  // V = V_0 + (I - I_0)/IperV
  Result := FProgV0 + (I_A - FI0) / FIperV;
end;

function TKepco20_20.CurrentToField(I_A: Double): Double;
begin
  // B = B_0 + I*TperA
  Result := FB0 + I_A * FTperA;
end;

function TKepco20_20. FieldToCurrnet(B_T: Double): Double;
begin
  if Abs(FTperA) < 1e-12 then
    raise EKepcoError.Create('TperA is too small.');
  // I = (B - B_0)/TperA
  Result := (B_T - FB0)/ FTperA;
end;

function TKepco20_20. LastProgramVoltage: Double;
begin
  Result := FLastCmdV;
end;

end.


