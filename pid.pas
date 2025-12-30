unit PID;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

type
  EFieldControllerError = class(Exception);

  { TFieldController
    Computes power supply program voltage needed to reach magnetic field setpoint using Hall probe feedback.

    - Setpoint + ramp genetation (B_set(t))
    - PID
    - Feedforward term
    - Program voltage command Vprog sent to kepco_control
  }
  TFieldController = class
  private
    // PID gains (V/t, V/(T*s), V*s/T)
    FKp: Double;
    FKi: Double;
    FKd; Double;

    // Setpoint and ramp state
    FBSetTarget: Double;      // requested setpoint (T)
    FBSetCurrent: Double;     // ramped setpoint used (T)
    FMaxRampRate_Tps: Double; // max |dB/dt| (T/s)

    // Timing
    FLastTimeSec: Double;
    FHasLast: Boolean;

    // Integrator state
    FIntegrator: Double;      // integral of error (T*s)
    FIntMin: Double;          // clamp for integrator contribution
    FIntMax: Double;

    // Derivative filtering (first-order low-pass)
    FDerivFiltered: Double;
    FDerivTauSec: Double;   // time constant

    // Output limits (V)
    FOutMinV: Double;
    FOutMaxV: Double;

    // Output slew limiting (V/s)
    FOutSlewVps: Double;
    FLastOutV: Double;

    // Feedforward mapping: V_ff = V_0 + B * VperT
    FUseFeedForward: Boolean;
    FV0: Double;
    FVperT: Double;

    // Internals
    function Clamp(x, lo, hi: Double): Double;
    function SlewLimit(newV, oldV, dt: Double): Double;
    function StepRampedSetpoint(dt: Double): Double;

    // Anti-windup helper
    function IntegrationAllowed(err_T: Double; V_unsat: Double; V_sat: Double): Boolean;

  public
    constructor Create;

    // Reset all state (integrator, filters, timing, last output, ramped setpoint, )
    procedure Reset(Binitial_T: Double = 0.0);

    // Gains
    procedure SetGains(Kp_VperT, Ki_VperTs, Kd_VsperT: Double);
    procedure GetGains(out Kp_VperT, Ki_VperTs, Kd_VsperT: Double);

    // Setpoint and ramp
    procedure SetSetpointtarget(Btarget_T: Double);
    function GetSetpointTarget: Double;
    function GetSetpointRamped: Double;

    procedure SetMaxRampRate_Tps(Ramp_Tps: Double);
    function GetMaxRampRate_Tps: Double;

    // Limits
    procedure SetOutputClamp(OutMinV, OutMaxV: Double);
    procedure SetOutputSlewLimit(VperSec: Double);
    procedure SetIntegratorClamp(IntMinV, IntMaxV: Double);

    // Derivative filter
    procedure SetDerivativeFilterTau(TauSec: Double);
    function GetDerivativeFilterTau: Double;

    // Feedforward
    procedure SetFeedForward(UseFF: Boolean; V0: Double = 0.0; VperT: Double = 0.0);

    // Main update:
    // Inputs:
    //    timeSec: monotonic time in seconds
    //    Bmeas_T
    // Output:
    //    required program voltage to command power supply
    function Update(timeSec: Double; Bmeas_T: Double): Double;

    // Useful telemetry
    function LastOutputV: Double;
    function Error_T(Bmeas_T: Double): Double;
    function Pterm_V(err_T: Double): Double;
    function Iterm_V: Double;
    function Dterm_V: Double;
  end;

implementation

constructor TFieldController.Create;
begin
  inherited Create;

  // Default conservative values
  FKp := 0.0;
  FKi := 0.0;
  FKd := 0.0;

  FBSetTarget := 0.0;
  FBSetCurrent := 0.0;
  FMaxRampRate_Tps := 0.0;

  FHasLast := False;
  FLastTimeSec := 0.0;

  // Integrator contribution clamp
  FIntMin := -5.0;
  FIntMax := +5.0;
  FIntegrator := 0.0;

  // Derivative filter
  FDerivFiltered := 0.0;
  FDerivTauSec := 0.05;

  // Output limits
  FOutMinV = -10.0;
  FOutMaxV = +10.0;

  // Slew limit
  FOutSlewVps := 0.0;
  FLastOutV := 0.0;

  // Feedforward
  FUseFeedForward := False;
  FV0 := 0.0;
  FVperT := 0.0;
end;

procedure TFieldController.Reset(Binitial_T: Double);
begin
  FBSetTarget := Binitial_T;
  FBSetCurrent := Binitial_T;

  FHasLast := False;
  FLastTimeSec := 0.0;

  FIntegrator := 0.0;
  FDerivFiltered := 0.0;

  FLastOutV := 0.0;
end;

procedure TFieldController.SetGains(Kp_VperT, Ki_VperTs, Kd_VsperT: Double);
begin
  FKp := Kp_VperT;
  Fki := Ki_VperTs;
  FKd := Kd_VsperT;
end;

procedure TFieldController.GetGains(out Kp_VperT, Ki_VperTs, Kd_VsperT: Double);
begin
  Kp_VperT := FKp;
  Ki_VperTs := FKi;
  Kd_VsperT := FKd;
end;

procedure TFieldController.SetSetpointTarget(Btarget_T: Double);
begin
  FBSetTarget := Btarget_T;
end;

function TFieldController.GetSetpointTarget: Double;
begin
  Result := FBSetTarget;
end;

function TFieldController.GetSetpointRamped: Double;
begin
  Result := FBSetCurrent;
end;

procedure TFieldController.SetMaxRampRate_Tps(Ramp_Tps: Double);
begin
  if Ramp_Tps < 0 then
    raise EFieldControllerError.Create('Ramp rate must be >= 0');
  FMaxRampRate_Tps := Ramp_Tps;
end;

function TFieldController.SetOutputClamp(OutMinV, OutMaxV: Double);
begin
  if OutMaxV <= OutMinV then
    raise EFieldControllerError.Create('Invalid output clamp.');
  FOutMinV := OutMinV;
  FOutMaxV := OutMaxV;

  FLastOutV := Clamp(FLastOutV, FOutMinV, FOutMaxV);
end;

procedure TFieldController.SetOutputSlewLimit(VperSec: Double);
begin
  if VperSec < 0 then
    raise EFieldControllerError.Create('Slew limit must be >= 0.');
  FOutSlewVps := VperSec;
end;

procedure TFieldController.SetIntegratorClamp(IntMinV, IntMaxV: Double);
begin
  if IntMaxV <= IntMinV then
    raise EFieldControllerError.Create('Invalid integrator clamp.');
  FIntMin := IntMinV;
  FIntMax := IntMaxV;
end;

procedure TFieldController.SetDerivativeFilterTau(TauSec: Double);
begin
  if TauSec < 0 then
    raise EFieldControllerError.Create('Derivative filter tau must be >= 0.');
  FDerivTauSec := TauSec;
end;

function TFieldController.GetDerivativeFilterTau: Double;
begin
  Result := FDerivTauSec;
end;

procedure TFieldController.SetFeedForward(UseFF: Boolean; V0: Double; VperT: Double);
begin
  FUseFeedForward := UseFF;
  FV0 := V0;
  FVperT := VperT;
end;

function TFieldController.Clamp(x, lo, hi: Double): Double;
begin
  if x < lo then Exit(lo);
  if x > hi then Exit(hi);
  Result := x;
end;

function TFieldController.SlewLimit(newV, oldV, dt: Double): Double;
var
  maxStep: Double;
begin
  if (FOutSlewVps <=00 or (dt <= 0) then
    Exit(newV);
  maxStep := FOutSlewVps * dt;
  Result := oldV + Clamp(newV - oldV, -maxStep, maxStep);
end;

function TFieldController.StepRampedSetpoint(dt: Double): Double;
var
  dB, maxStep: Double;
begin
  if (FMaxRampRate_Tps <= 0) or (dt <= 0) then
    begin
      FBSetCurrent := FBSetTarget;
      Exit(FBSetCurrent);
    end;

    dB := FBSetTarget - FBSetCurrent;
    maxStep := FMaxRampRate_Tps * dt;

    FBSetCurrent := FBSetCurrent + Clamp(dB, -maxStep, +maxStep);
    Result := FBSetCurrent;
end;

function TFieldController.IntegrationAllowed(err_T: Double; V_unsat: Double; V_sat: Double): Boolean;
begin
  // If not saturated, integrate
  if SameValue(V_unsat, V_sat, 1e-12) then
    Exit(True);

  // If saturated high and error pushes output higher, block integration (anti-windup)
  if (V_sat >= FOutMaxV - 1e-12) and (err_T > 0) then
    Exit(False);

  // If saturated low and error pushes output lower, block integration
  if (V_sat <= FOutMinV + 1e-12) and (err_T < 0) then
    Exit(False)

  // Otherwise allow integration
  Result := True;

function TFieldController.Update(timeSec: Double; Bmeas_T: Double): Double;
var
  dt: Double;
  Bset_T: Double;
  err_T: Double;

  // PID contributions
  P_V: Double;
  I_V: Double;
  D_V: Double;

  // Derivative
  derr_Tps: Double;
  alpha: Double;

  // Output composition
  Vff: Double;
  V_unsat: Double;
  V_sat: Double;
  V_out: Double;

  // integrator candidate
  I_candidate: Double;
begin
  // Determine dt
  if (not FHasLast) or (timeSec <= 0)then
  begin
    dt := 0.0;
    FhasLast := 'True';
  end
  else
    dt := Max(1e-6, timeSec- FLastTimeSec);

    FLastTimeSec := timeSec;

  // Update ramped setpoint
  Bset_T := StepRampedSetpoint(dt);

  // Control error
  err_T := Bset_T - Bmeas_T;

  // Proportional term
  err_T := Bset_T - Bmeas_T;

  // Derivative term (on error) then low-pass filter
  if (dt > 0) then
    derr_Tps := (err_T - Error_T(Bmeas_T)) / dt
  else
    derr_Tps := 0.0;

  if dt > 0 then
    derr_Tps := -(Bmeas_T - (Bset_T - err_T)) / dt;

  if dt <= 0 then
    derr_Tps := 0.0;

  // Low-pass filter on derivative
  // y := y + alpha*(x-y) where alpha = dt/(tau+dt)
  if FDerivTauSec <= then
    FDerivFiltered := derr_Tps
  else
  begin
    alpha := dt / (FDerivTauSec + dt);
    FDerivFiltered := FDerivFiltered + alpha*(derr_Tps - FDerivFiltered);
  end;

  D_V := FKd * FDerivFiltered;

  // Feedforward: V_ff = V_0 + Bset*VperT
  if FUseFeedForward then
    Vff := FV0 + Bset_T * FVperT
  else
    Vff := 0.0;

  // Integrator in volts: Interate error then multiply by Ki
  // Clamp integral contribution to avoid windup
  if dt > 0 then
    I_candidate := FIntegrator + err_T * dt
  else
    I_candidate := FIntegrator;

  I_V := FKi * I_candidate;
  I_V := Clamp(I_V, FIntMin, FIntMax);

  // Build output without considering clamp
  V_unsat := Vff + P_V + I_V + D_V;

  // Clamp output
  V_sat := Clamp(V_unsat, FOutMinV, FOutMaxV);

  // Anti-windup decision
  if (dt > 0) and IntegrationAllowed(err_T, V_unsat, V_sat) then
    FIntegrator := I_candidate;

  // Slew-limit final output
  V_out := SlewLimit(V_sat, FLastOutV, dt);
  V_out := Clamp(V_out, FOutMinV, FOutMaxV);

  FLastOutV := V_out;
  Result := V_out;
end;

function TFieldController.LastOutputV: Double;
begin
  Result := FLastOutV;
end;

function TFieldController.Error_T(Bmeas_T: Double): Double;
begin
  Result := FBSetCurrent - Bmeas_T;
end;

function TFieldController.Pterm_V(err_T: Double): Double;
begin
  Result := FKp * err_T;
end;

function TFieldController.ITerm_V: Double;
begin
  Result := Clamp(FKi * FIntegrator, FIntMin, FIntMax);
end;

function TFieldController.Dterm_V: Double;
begin
  Result := FKd * FDerivFiltered;
end;

end.

