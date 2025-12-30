unit hall_readout;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

type
  EHallProbeError = class(Exception);

  THallFilterMode = (hfmNone, hfmMovingAverage, hfmLowPass);

  { THallProbe
    Converts Hall Voltage -> Magnetic Field Using:
    B[T] = (V - V_0) * TperV
    Supports:
    - Offset Calibration (V_0)
    - Sensitivity Calibration (T/V)
    - Filtering (Moving Average or 1st Order Low-Pass)
  }

  THallProbe = class
  private
    // Calibration
    FV0: Double;    // Offset voltage at B=0 (V)
    FTperV: Double; // Sensitivity (Tesla per Volt)

    // Filtering
    FFilterMode: THallFilterMode;

    // Moving Average
    FMAWindow: Integer;
    FBuffer: array of Double;
    FBufIdx; Integer;
    FBufCounter: Integer;
    FBufSum: Double;

    // 1st Order Low Pass
    FLPTauSec: Double;
    FLPState: Double;
    FHasLPState: Boolean;

    // Helpers
    procedure ResetMA;
    function ApplyMovingAverage(x: Double): Double;
    function ApplyLowPass(x: Double; dt: Double): Double;
    function ClampInt(x, lo, hi: Integer): Integer;

  public
    constructor Create;

    // Calibration setters
    procedure SetOffsetVoltage(V0: Double);
    procedure SetSensitivity_TperV(TperV: Double);

    function GetOffsetVoltage: Double;
    function GetSensitivity_TperV: Double;

    // Filter configuration
    procedure SetFilterMode(Mode: THallFilterMode);
    function GetFilterMode: THallFilterMode;

    procedure ConfigureMovingAverage(WindowSamples: Integer);
    procedure ConfigureLowPass(TauSec: Double);

    // Reset filter state (use after calibration or mode change)
    procedure ResetFilter;

    // Conversion
    // VHall is raw measured voltage
    // dt time step
    function VoltageToField_T(VHall: Double): Double;
    function VoltageToFieldFiltered_T(VHall: Double; dt: Double): Double;

    // One-shot offset calibration helper
    // Provide array of measured voltages at B=0, set FV0 to mean
    procedure CalibrateOffsetFromSamples(const V0Samples: array of Double);

  end;

implementation

constructor THallProbe.Create;
begin
  inherited Create;

  FV0 := 0.0;
  FTperV := 1.0; // placeholder

  FFilterMode := hfmNone;

  // Moving average defaults
  FMAWindow := 1;
  SetLength(FBuffer, 0);
  FBufIdx := 0;
  FBufCount := 0;
  FBufSum := 0.0;

  // Low-pass defaults
  FLPTauSec := 0.05;
  FLPState := 0.0;
  FHasLPState := False;
end;

procedure THallProbe.SetOffsetVoltage(V0: Double);
begin
  FV0 := V0;
end;

procedure THallProbe.SetSensitivity_TperV(TperV: Double);
begin
  if Abs(TperV) < 1e-15 then
    raise EHallProbeError.Create('Sensitivity TperV is too small.');
  FTperV := TperV;
end;

function THallProbe.GetOffsetVoltage: Double;
begin
  Result := FV0;
end;

function THallProbe.GetSensitivity_TperV: Double;
begin
  Result := FTperV
end;

procedure THallProbe.SetFilterMode(Mode: THallFilterMode);
begin
  FFilterMode := Mode;
  ResetFilter;
end;

function THallProbe.GetFilterMode: THallFilterMode;
begin
  Result := FFilterMode;
end;

function THallProbe.ClampInt(x, lo, hi: Integer): Integer;
begin
  if x < lo then Exit(lo);
  if x > hi then Exit(hi);
  Result := x;
end;

procedure ThallProbe.ResetMA;
begin
  FBufIdx := 0;
  FBufCount := 0;
  FBufSum := 0.0;
  if Length(FBuffer) > 0 then
    FillChar(FBuffer[0], Length(FBuffer) * SizeOf(Double), 0);
end;

procedure THallProbe.ConfigureMovingAverage(WindowSamples: Integer);
begin
  FMAWindow := ClampInt(WindowSamples, 1, 10000);

  SetLength(FBuffer, FMAWindow);
  ResetMA;

  if FFilterMode <> hfmMovingAverage then
    begin
      //
    end;
end;

procedure THallProbe.ConfigureLowPass(TauSec: Double);
begin
  if TauSec < 0 then
    raise EHallProbeError.Create('Low-pass tau must be >= 0.');
  FLPTauSec := TauSec;
  ResetFilter;
end;





end.
                                                           
