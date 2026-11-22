program Stars;
uses Crt;

const
	NumStars  = 100;
	Intensity = 6;

type
	TStar = record
		X, Y     : Integer;
		Phase    : Integer;
		Col      : Integer;
		Duration : Integer;
		Active   : Boolean;
	end;

const
	{ Matrice 5x5 per le 2 fasi di animazione della stella }
	BitMask: array[0..1, 0..4, 0..4] of Byte = (
		((0,0,1,0,0), (0,0,3,0,0), (1,3,6,3,1), (0,0,3,0,0), (0,0,1,0,0)),
		((0,0,6,0,0), (0,0,3,0,0), (6,3,1,3,6), (0,0,3,0,0), (0,0,6,0,0))
	);

var
	Star : array[0..NumStars - 1] of TStar;
	I, Frame, X, Y, C, CL, AX : Integer;

procedure SetMode13h; assembler;
asm
	mov ax, $0013
	int $10
end;

procedure SetTextMode; assembler;
asm
	mov ax, $0003
	int $10
end;

procedure SetDacReg(Reg, R, G, B: Byte);
begin
	Port[$3C8] := Reg;
	Port[$3C9] := R;
	Port[$3C9] := G;
	Port[$3C9] := B;
end;

procedure WaitVSync;
begin
	while (Port[$3DA] and 8) <> 0 do;
	while (Port[$3DA] and 8) = 0 do;
end;

procedure SetupPalette;
begin
	for CL := 1 to 9 do
	begin
		AX := Intensity * CL;
		{ Rosso, Verde, Blu, Giallo, Ciano, Bianco/Grigio }
		SetDacReg(CL, AX, 0, 0);      SetDacReg(21 - CL, AX, 0, 0);  SetDacReg(20 + CL, 0, 0, 0);
		SetDacReg(30 + CL, 0, AX, 0);  SetDacReg(51 - CL, 0, AX, 0);  SetDacReg(50 + CL, 0, 0, 0);
		SetDacReg(6 + CL, 0, 0, AX);   SetDacReg(81 - CL, 0, 0, AX);  SetDacReg(80 + CL, 0, 0, 0);
		SetDacReg(90 + CL, AX, AX, 0); SetDacReg(111 - CL, AX, AX, 0);SetDacReg(110 + CL, 0, 0, 0);
		SetDacReg(120 + CL, 0, AX, AX);SetDacReg(141 - CL, 0, AX, AX);SetDacReg(140 + CL, 0, 0, 0);
		SetDacReg(150 + CL, AX, AX, AX);SetDacReg(171 - CL, AX, AX, AX);SetDacReg(170 + CL, 0, 0, 0);
	end;
end;

begin
	Randomize;
	SetMode13h;
	SetupPalette;

	for I := 0 to NumStars - 1 do
	begin
		Star[I].X := 0;
		Star[I].Y := 0;
		Star[I].Col := 0;
		Star[I].Phase := 0;
		Star[I].Duration := Random(20) + 1;
		Star[I].Active := False;
	end;

	repeat
		WaitVSync;
		WaitVSync;

		{ Aggiornamento stato e nascita stelle }
		for I := 0 to NumStars - 1 do
		begin
			Dec(Star[I].Duration);
			if (Star[I].Duration <= 0) and not Star[I].Active then
			begin
				Star[I].Active := True;
				Star[I].Phase := 0;
				Star[I].Col := Random(6) * 30;
				Star[I].X := Random(315);
				Star[I].Y := Random(195);
			end;
		end;

		{ Rendering diretto in VRAM $A000 }
		for I := 0 to NumStars - 1 do
		begin
			if Star[I].Active then
			begin
				if Star[I].Phase > 10 then Frame := 1 else Frame := 0;

				for X := 0 to 4 do
					for Y := 0 to 4 do
						if BitMask[Frame, X, Y] > 0 then
						begin
							C := (BitMask[Frame, X, Y] + Star[I].Col + Star[I].Phase) and $FF;
							Mem[$A000: LongInt(Star[I].Y + Y) * 320 + (Star[I].X + X)] := C;
						end;

				Inc(Star[I].Phase);
				if Star[I].Phase >= 20 then
				begin
					Star[I].Active := False;
					Star[I].Duration := Random(20) + 1;
				end;
			end;
		end;
	until KeyPressed;

	SetTextMode;
end.
