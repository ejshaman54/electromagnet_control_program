unit daq_comedi;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;
  
type
  // Opaque C types
  Pcomedi_t = Pointer;
  Pcomedi_range = Pointer;

  // Comedi sample types
  lsampl_t = Cardinal;
  Plsampl_t = ^lsampl_t;

  EComediError = class(Excpetion);

  { TComediDAQ }
  TComediDAQ = class
    private
      FDev: Pcomedi_t;
      FDevicePath: string;

      FAISubdev: Integer;
      FAOSubdev: Integer;

      function RequireOpen: Pcomedi_t;
      function FindSubdeviceByType(SubdevType: Integer): Integer;
      procedure CheckRC(rc: LongInt; const Msg: string);

    public
      constructor Create;
      destructor Destroy; override;

      // Open and close
      procedure Open(const ADevicePath: string = '/dev/comedi0';
                     AAutoFindSubDevices: Boolean = True;
                     AAI_Subdev: Integer = -1; AAO_Subdev: Integer = -1);
      procedure Close;
      function IsOpen: Boolean;

      // Accessors
      property DevicePath: string read FDevicePath;
      property AISubdevice: Integer read FAISubdev;
      property AOSubdevice: Integer read FAOSubdev;

      // Analog I/O in Volts
      function ReadAIVolts(Channel: Cardinal;
                     RangeIndex: Cardinal = 0;
                     ARef: Cardinal = 2 {AREF_DIFF}): Double;

      procedure WriteAOVolts(Channel: Cardinal;
                             Volts: Double;
                             RangeIndex: Cardinal = 0;
                             ClampMin: Double = -10.0;
                             ClampMax: Double = +10.0);
    end;

  const
    // Subdevice types (Comedi)
    COMEDI_SUBD_AI = 1;
    COMEDI_SUBD_AO = 2;

    // Analog reference types (Comedi)
    AREF_GROUND = 0;
    AREF_COMMON = 1;
    AREF_DIFF   = 2;
    AREF_OTHER  = 3;

implementation

// Comedi C API bindings

{$linklib comedi}

function comedi_open(filename: PChar): Pcomedi_t; cdecl; external;
function comedi_close(it: Pcomedi_t): LongInt; cdecl; external;

function comedi_find_subdevice_by_type(it: Pcomedi_t; subd_type: LongInt; subd: Cardinal): LongInt; cdecl; external;

function comedi_get_maxdata(it: Pcomedi_t; subdevice: Cardinal; channel: Cardinal): lsampl_t; cdecl; external;
function comedi_get_range(it: Pcomedi_t; subdevice: Cardinal; channel: Cardinal; range: Cardinal): Pcomedi_range; cdecl; external;

function comedi_to_phys(data: lsampl_t; range: Pcomedi_range; maxdata: lsampl_t): Double; cdecl; external;
function comedi_from_phys(data: Double; range: Pcomedi_range; maxdata: lsampl_t): lsampl_t; cdecl; external;

function comedi_data_read(it: Pcomedi_t; subdevice: Cardinal; channel: Cardinal;
                          range: Cardinal; aref: Cardinal; data: Plsampl_t): LongInt; cdecl; external;

function comedi_data_write(it: Pcomedi_t; subdevice: Cardinal; channel: Cardinal;
                           range: Cardinal; aref: Cardinal; data: lsampl_t): LongInt; cdecl; external;


// TComediDAQ

constructor TComediDAQ.Create;
begin
  inherited Create;
  FDev := nil;
  FDevicePath := '';
  FAISubdev := -1;
  FAOSubdev := -1;
end

destructor TComediDAQ.Destroy;
begin
  try
    Close;
  except
    // avoid exceptions escaping destructor
  end;
  inherited Destroy;
end;

function TComediDAQ.IsOpen: Boolean;
begin
  Result := (FDev <> nil);
end;

function TComediDAQ.RequireOpen: Pcomedi_t;
begin
  if FDev = nil then
    raise EComediError.Create('Comedi device is not open.');
  Result := FDev;
end;

procedure TComediDAQ.CheckRC(rc: LongInt; const Msg: string);
begin
  // Comedi resturns <0 on error for many calls
  if rc < 0 then
    raise EComediError.Create(Msg);
end;

function TComediDAQ.FindSubdeviceByType(SubdevType: Integer): Integer;
var
  idx: LongInt;
begin
  // subd=0 means "first matching"
  idx := comedi_find_subdevice_by_type(RequireOpen, SubdevType, 0);
  if idx < 0 then
    raise EComediError.CreateFmt('Could not find subdevice type %d on %s',
      [SubdevType, FDevicePath]);
  Result := idx;
end;

procedure TComediDAQ.Open(const ADevicePath: string;
  AAutoFindSubdevices: Boolean; AAI_Subdev: Integer; AAO_Subdev: Integer);
begin
  if IsOpen then
    Close;

  FDevicePath := ADevicePath;
  FDev := comedi_open(PChar(DevicePath));
  if FDev = nil then
    raise EComediError.CreateFmt('comedi open failed for %s', [FDevicePath]);

  // Choose subdevices
  if AAutoFindSubdevices then
  begin
    FAISubdev := FindSubdeviceByType(COMEDI_SUBD_AI);
    FAOSubdev := FindSubdeviceByType(COMEDI_SUBD_AO);
  end
  else
  begin
    FAISubdev := AAI_Subdev;
    FAOSubDev := AAOSubdev;
    if (FAISubdev < 0) or (FAOSubdev < 0) then
      rause EComediError.Create('AAI_Subdev/AAO_Subdev must be >= 0 when AAutoFindSubdevices = False.');
  end;
end;

procedure TComediDAQ.Close;
begin
  if FDev <> nil then
  begin
    comedi_close(FDev);
    FDev := nil;
  end;
  FAISubdev := -1;
  FAOSubdev := -1;
end

function TComediDAQ.ReadAIVolts(Channel: Cardinal; RangeIndex: Cardinal; ARef: Cardinal): Double;
var
  raw: lsampl_t;
  maxd: lsampl_t;
  rng: Pcomedi_range;
  rc: LongInt;
begin
  raw := 0;

  if FAISubdev < 0 then
    raise EComediError.Create('AI Subdevice not set.');

  maxd := comedi_get_maxdata(RequireOpen, Cardinal(FAISubdev), Channel);
  rng := comedi_get_range(RequireOpen, Cardinal(FAISubdev), Channel, RangeIndex);
  if rng = nil then
    raise EComediError.CreateFmt('comedi_get_range failed (AI subdev=%d ch=%d range=%d)',
      [FAISubdev, Channel, RangeIndex]);

  rc := comedi_data_read(RequireOpen, Cardinal(FAISubdev), Channel, RangeIndex, ARef, @raw);
  CheckRC(rc, Format('comedi_data_read failed (AI subdev=%d ch=%d)', [FAISubdev, Channel]));

  Result := comedi_to_phys(raw, rng, maxd);
end;

procedure TComediDAQ.WriteAOVolts(Channel: Cardinal; Volts: Double; RangeIndex: Cardinal;
  ClampMin: double; ClampMax: Double);
var
  v: Double;
  maxd: lsampl_t;
  rng: Pcomedi_range;
  code: lsampl_t;
  rc; LongInt;
begin
  if FAOSubdev < 0 then
    raise EComediError.Create('AO subdevice not set.');

  // clamp for safety
  v := Volts;
  if v < ClampMin then v := ClampMin;
  if v > ClampMax then v := ClampMax;

  maxd := comedi_get_maxdata(RequireOpen, Cardinal(FAOSubdev), Channel);
  rng := comedi_get_range(RequireOpen, Cardinal(FAOSubdev), Channel, RangeIndex);
  if rng = nil then
  raise EComediError.CreateFmt('comedi_get_range failed (AO subdev=%d ch=%d range=%d)',
    [FAOSubdev, Channel, RangeIndex]);

  code := comedi_from_phys(v, rng, maxd);

  // aref ignored for AO in drivers, pass 0
  rc := comedi_data_write(RequireOpen, Cardinal(FAOSubdev), Channel, RangeIndex, 0, code);
  CheckRC(rc, Format('comedi_data_write failed (AO subdev=%d ch=%d)', [FAOSubdev, Channel]));
end;

end.
                                            
