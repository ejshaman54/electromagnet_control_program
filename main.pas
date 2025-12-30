unit main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  StdCtrls, ExtCtrls, ComCtrls, TAGraph, TASeries;

type

  { TEMForm }

  TEMForm = class(TForm)
    BSetEdit: TEdit;
    FieldChart: TChart;
    EStopButton: TButton;
    EnableCheckBox: TCheckBox;
    BSetLabel: TLabel;
    SetFieldSeries: TLineSeries;
    MeasuredFieldSeries: TLineSeries;
    FieldLabel: TLabel;
    HallVoltageLabel: TLabel;
    OutputVoltageLabel: TLabel;
    StatusBar: TStatusBar;
    ControlTimer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure EnableCheckBoxChange(Sender: TObject);
    procedure EStopButtonClick(Sender: TObject);
    procedure ControlTimerTimer(Sender: TObject);

  private
    FEnabled: Boolean;
    FSetField: Double;

    procedure UpdateReadouts;
    procedure UpdatePlot;

  public
  end;

var
  EMForm: TEMForm;

implementation

{$R *.lfm}

procedure TEMForm.FormCreate(Sender: TObject);
begin
  FEnabled := False;
  FSetField := 0.0;

  EnableCheckBox.Checked := False;
  StatusBar.SimpleText := 'Idle';

  ControlTimer.Interval := 50;
  ControlTimer.Enabled := True;

  MeasuredFieldSeries.Clear;
  SetFieldSeries.Clear;
end;

procedure TEMForm.FormDestroy(Sender: TObject);
begin
end;

procedure TEMForm.EnableCheckBoxChange(Sender: TObject);
begin
  FEnabled := EnableCheckBox.Checked;

  if FEnabled then
    StatusBar.SimpleText := 'Output ENABLED'
  else
    StatusBar.SimpleText := 'Output disabled';

end;

procedure TEMForm.EStopButtonClick(Sender: TObject);
begin
  FEnabled := False;
  EnableCheckBox.Checked := False;
  StatusBar.SimpleText := 'EMERGENCY STOP';

end;

procedure TEMForm.ControlTimerTimer(Sender: TObject);
begin

  UpdateReadouts;
  UpdatePlot;
end;

procedure TEMForm.UpdateReadouts;
begin
  // Placeholder values for now
  HallVoltageLabel.Caption := 'Hall V: ---.--- V';
  FieldLabel.Caption := 'B: ---.--- T';
  OutputVoltageLabel.Caption := 'Vout: ---.--- V';

end;

procedure TEMForm.UpdatePlot;
begin
  // Placeholder plot update

end;

end.

