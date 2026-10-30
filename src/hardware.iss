[Code]
{ ---------- Hardware detection: which apps suit this PC, and why ---------- }

var
  Recommended: array[0..MaxApps - 1] of Boolean;
  RecommendReasons: array[0..MaxApps - 1] of String;
  HardwareText: String;
  HardwareDetected: Boolean;
  AmdGpuFound: Boolean;
  NvidiaGpuFound: Boolean;

function VarText(const V: Variant): String;
begin
  if VarIsNull(V) or VarIsEmpty(V) then
    Result := ''
  else
    Result := V;
end;

{ Reason is the message (lang\*.isl) that completes the "Recommended because..." line of the details panel }
procedure Recommend(const Component, Reason: String);
var
  I: Integer;
begin
  for I := 0 to AppCount - 1 do
    if CompareText(AppComponents[I], Component) = 0 then
    begin
      Recommended[I] := True;
      RecommendReasons[I] := CustomMessage(Reason);
    end;
end;

procedure AddHardware(const Text: String);
begin
  if Pos(Text, HardwareText) > 0 then
    Exit;
  if HardwareText <> '' then
    HardwareText := HardwareText + ' · ';
  HardwareText := HardwareText + Text;
end;

{ Short graphics card name ("NVIDIA RTX 4070"). Right after formatting Windows still calls it "basic", so the brand is used. }
function GpuText(const Name, Vendor: String): String;
begin
  Result := Name;
  StringChangeEx(Result, '(R)', '', True);
  StringChangeEx(Result, '(TM)', '', True);
  StringChangeEx(Result, 'GeForce ', '', True);
  StringChangeEx(Result, ' Laptop GPU', '', True);
  StringChangeEx(Result, ' Graphics', '', True);
  Result := Trim(Result);
  if (Result = '') or (Pos('MICROSOFT', UpperCase(Result)) > 0) then
    Result := Vendor;
end;

procedure DetectBrand(const Maker: String; IsBoard: Boolean);
var
  M: String;
begin
  M := UpperCase(Maker);
  if (Pos('MICRO-STAR', M) > 0) or (Copy(M, 1, 3) = 'MSI') then
  begin
    AddHardware('MSI');
    Recommend('brand\msicenter', 'WhyMsi');
  end
  else if Pos('ASUS', M) > 0 then
  begin
    AddHardware('ASUS');
    { MyASUS is for ASUS laptops and PCs; Armoury Crate, for their motherboards }
    if IsBoard then
      Recommend('brand\armourycrate', 'WhyAsusBoard')
    else
      Recommend('brand\myasus', 'WhyAsus');
  end
  else if Pos('LENOVO', M) > 0 then
  begin
    AddHardware('Lenovo');
    Recommend('brand\lenovovantage', 'WhyLenovo');
  end
  else if Pos('DELL', M) > 0 then
  begin
    AddHardware('Dell');
    Recommend('brand\dellupdate', 'WhyDell');
  end;
end;

{ Reads the hardware through WMI. It uses vendor IDs (VEN_/VID_) instead of names, because right after
  formatting Windows does not know the commercial names yet. If WMI fails, nothing is recommended. }
procedure DetectHardware;
var
  Locator, Wmi, Items, Item: Variant;
  I: Integer;
  Pnp, Name: String;
begin
  { Almost every PC needs these }
  Recommend('runtimes\vcredist64', 'WhyEveryPc');
  Recommend('runtimes\vcredist86', 'WhyEveryPc');
  Recommend('runtimes\directx', 'WhyEveryPc');
  Recommend('runtimes\dotnet8', 'WhyEveryPc');
  Recommend('runtimes\dotnet10', 'WhyEveryPc');
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Wmi := Locator.ConnectServer('.', 'root\CIMV2');

    Items := Wmi.ExecQuery('SELECT Name, PNPDeviceID FROM Win32_VideoController');
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items.ItemIndex(I);
      Pnp := UpperCase(VarText(Item.PNPDeviceID));
      Name := VarText(Item.Name);
      if Pos('VEN_10DE', Pnp) > 0 then
      begin
        AddHardware(GpuText(Name, 'NVIDIA'));
        NvidiaGpuFound := True;
        Recommend('graphics\nvidiaapp', 'WhyNvidia');
        Recommend('graphics\nvidiapanel', 'WhyNvidia');
      end
      else if Pos('VEN_1002', Pnp) > 0 then
      begin
        AddHardware(GpuText(Name, 'AMD'));
        AmdGpuFound := True;
      end
      else if Pos('VEN_8086', Pnp) > 0 then
      begin
        AddHardware(GpuText(Name, 'Intel'));
        Recommend('graphics\intelgcc', 'WhyIntelGpu');
      end;
    end;

    Items := Wmi.ExecQuery('SELECT Manufacturer FROM Win32_Processor');
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items.ItemIndex(I);
      Name := UpperCase(VarText(Item.Manufacturer));
      if Pos('INTEL', Name) > 0 then
      begin
        AddHardware(CustomMessage('HwIntelCpu'));
        Recommend('graphics\inteldsa', 'WhyIntelCpu');
      end
      else if Pos('AMD', Name) > 0 then
        AddHardware(CustomMessage('HwAmdCpu'));
    end;

    Items := Wmi.ExecQuery('SELECT Manufacturer FROM Win32_ComputerSystem');
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items.ItemIndex(I);
      DetectBrand(VarText(Item.Manufacturer), False);
    end;
    Items := Wmi.ExecQuery('SELECT Manufacturer FROM Win32_BaseBoard');
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items.ItemIndex(I);
      DetectBrand(VarText(Item.Manufacturer), True);
    end;

    Items := Wmi.ExecQuery('SELECT PNPDeviceID FROM Win32_SoundDevice');
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items.ItemIndex(I);
      if Pos('VEN_10EC', UpperCase(VarText(Item.PNPDeviceID))) > 0 then
      begin
        AddHardware('Realtek');
        Recommend('graphics\realtek', 'WhyRealtek');
      end;
    end;

    Items := Wmi.ExecQuery('SELECT Name FROM Win32_PnPEntity WHERE Name LIKE ''%Thunderbolt%''');
    if Items.Count > 0 then
    begin
      AddHardware('Thunderbolt');
      Recommend('graphics\thunderbolt', 'WhyThunderbolt');
    end;

    { USB peripherals by vendor. From Logitech only the LIGHTSPEED receivers, which belong to the G line
      (G HUB); office ones use another program. }
    Items := Wmi.ExecQuery('SELECT Name, PNPDeviceID FROM Win32_PnPEntity WHERE ' +
      'PNPDeviceID LIKE ''USB\\VID_1B1C%'' OR PNPDeviceID LIKE ''USB\\VID_1532%'' OR ' +
      'PNPDeviceID LIKE ''USB\\VID_1038%'' OR PNPDeviceID LIKE ''USB\\VID_046D%''');
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items.ItemIndex(I);
      Pnp := UpperCase(VarText(Item.PNPDeviceID));
      Name := UpperCase(VarText(Item.Name));
      if Pos('VID_1B1C', Pnp) > 0 then
      begin
        AddHardware('Corsair');
        Recommend('gaminghardware\icue', 'WhyCorsair');
      end
      else if Pos('VID_1532', Pnp) > 0 then
      begin
        AddHardware('Razer');
        Recommend('gaminghardware\synapse', 'WhyRazer');
      end
      else if Pos('VID_1038', Pnp) > 0 then
      begin
        AddHardware('SteelSeries');
        Recommend('gaminghardware\steelseries', 'WhySteelSeries');
      end
      else if Pos('LIGHTSPEED', Name) > 0 then
      begin
        AddHardware('Logitech G');
        Recommend('gaminghardware\ghub', 'WhyLogitech');
      end;
    end;

    Items := Wmi.ExecQuery('SELECT Name FROM Win32_Printer');
    for I := 0 to Items.Count - 1 do
    begin
      Item := Items.ItemIndex(I);
      if Pos('HP ', UpperCase(VarText(Item.Name)) + ' ') > 0 then
      begin
        AddHardware(CustomMessage('HwHpPrinter'));
        Recommend('brand\hpsmart', 'WhyHpPrinter');
      end;
    end;
  except
    Log('Hardware detection incomplete: ' + GetExceptionMessage);
  end;
  Log('Hardware detected: ' + HardwareText);
end;

function RecommendedCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to AppCount - 1 do
    if Recommended[I] then
      Result := Result + 1;
end;
