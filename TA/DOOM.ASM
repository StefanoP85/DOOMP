IDEAL
JUMPS
LOCALS
P286
MODEL SMALL, PASCAL
STACK 400h

Intensity = 6
NumStars  = 100

STRUC TStar
	X        DW ?
	Y        DW ?
	Phase    DB ?
	Col      DB ?
	Duration DB ?
	Active   DB ?
ENDS  TStar

DATASEG
RandSeed DW ?
Star     TStar NumStars dup (?)

BitMask  DB 0,0,1,0,0, 0,0,3,0,0, 1,3,6,3,1, 0,0,3,0,0, 0,0,1,0,0
				 DB 0,0,6,0,0, 0,0,3,0,0, 6,3,1,3,6, 0,0,3,0,0, 0,0,6,0,0

CODESEG

PROC Randomize
	MOV  AH, 2Ch
	INT  21h
	MOV  [WORD LOW  RandSeed], CX
	MOV  [WORD HIGH RandSeed], DX
	RET
ENDP Randomize

PROC Random
ARG  @@Limit:WORD
USES BX, CX, DX
	MOV  AX, [WORD LOW  RandSeed]
	MOV  BX, [WORD HIGH RandSeed]
	MOV  CX, AX
	MOV  DX, 8405h
	MUL  DX
	SHL  CX, 3
	ADD  CH, CL
	ADD  DX, CX
	ADD  DX, BX
	SHL  BX, 2
	ADD  DX, BX
	ADD  DH, BL
	MOV  CL, 5
	SHL  BX, CL
	ADD  AX, 1
	ADC  DX, 0
	MOV  [WORD LOW  RandSeed], AX
	MOV  [WORD HIGH RandSeed], DX
	MOV  BX, [@@Limit]
	XOR  AX, AX
	XCHG AX, DX
	DIV  BX
	XCHG AX, DX
	RET
ENDP Random

PROC DosIsCharAvail
	MOV  AH, 0Bh
	INT  21h
	RET
ENDP DosIsCharAvail

PROC WaitVerticalRetrace
@@VSync:
	MOV  DX, 03DAh
	IN   AL, DX
	TEST AL, 8
	JZ   @@VSync
@@NoVSync:
	IN   AL, DX
	TEST AL, 8
	JNZ  @@NoVSync
	RET
ENDP WaitVerticalRetrace

PROC SetDacReg
ARG  @@Reg:BYTE, @@R:BYTE, @@G:BYTE, @@B:BYTE
	MOV  DX, 03C8h
	MOV  AL, [@@Reg]
	OUT  DX, AL
	INC  DX
	MOV  AL, [@@R]
	OUT  DX, AL
	MOV  AL, [@@G]
	OUT  DX, AL
	MOV  AL, [@@B]
	OUT  DX, AL
	RET
ENDP SetDacReg

Begin:
	MOV  AX, @DATA
	MOV  DS, AX

	; Imposta modalità VGA 13h (320x200 256 colori)
	MOV  AX, 0013h
	INT  10h

	; Inizializzazione Palette DAC
	MOV  CL, 1
	MOV  AL, Intensity
@@DacCycle:
	IMUL CL
	CALL SetDacReg, CX, AX, 0, 0
	MOV  DL, 21
	SUB  DL, CL
	CALL SetDacReg, DX, AX, 0, 0
	MOV  DL, 20
	ADD  DL, CL
	CALL SetDacReg, DX, 0, 0, 0
	MOV  DL, 30
	ADD  DL, CL
	CALL SetDacReg, DX, 0, AX, 0
	MOV  DL, 51
	SUB  DL, CL
	CALL SetDacReg, DX, 0, AX, 0
	MOV  DL, 50
	ADD  DL, CL
	CALL SetDacReg, DX, 0, 0, 0
	MOV  DL, 6
	ADD  DL, CL
	CALL SetDacReg, DX, 0, 0, AX
	MOV  DL, 81
	SUB  DL, CL
	CALL SetDacReg, DX, 0, 0, AX
	MOV  DL, 80
	ADD  DL, CL
	CALL SetDacReg, DX, 0, 0, 0
	MOV  DL, 90
	ADD  DL, CL
	CALL SetDacReg, DX, AX, AX, 0
	MOV  DL, 111
	SUB  DL, CL
	CALL SetDacReg, DX, AX, AX, 0
	MOV  DL, 110
	ADD  DL, CL
	CALL SetDacReg, DX, 0, 0, 0
	MOV  DL, 120
	ADD  DL, CL
	CALL SetDacReg, DX, 0, AX, AX
	MOV  DL, 141
	SUB  DL, CL
	CALL SetDacReg, DX, 0, AX, AX
	MOV  DL, 140
	ADD  DL, CL
	CALL SetDacReg, DX, 0, 0, 0
	MOV  DL, 150
	ADD  DL, CL
	CALL SetDacReg, DX, AX, AX, AX
	MOV  DL, 171
	SUB  DL, CL
	CALL SetDacReg, DX, AX, AX, AX
	MOV  DL, 170
	ADD  DL, CL
	CALL SetDacReg, DX, 0, 0, 0
	INC  CL
	CMP  CL, 10
	JL   @@DacCycle

	CALL Randomize

	; Inizializzazione dati stelle
	MOV  CX, NumStars
	MOV  DI, OFFSET Star
@@StarInit:
	MOV  [(TStar DI).X], 0
	MOV  [(TStar DI).Y], 0
	MOV  [(TStar DI).Col], 0
	MOV  [(TStar DI).Phase], 0
	CALL Random, 20
	INC  AL
	MOV  [(TStar DI).Duration], AL
	MOV  [(TStar DI).Active], 0
	ADD  DI, SIZE TStar
	LOOP @@StarInit

	; Carica il segmento VRAM A000h in ES una volta per tutte
	MOV  AX, 0A000h
	MOV  ES, AX

@@Main:
	CALL WaitVerticalRetrace
	CALL WaitVerticalRetrace

	; Loop 1: Gestione nascite e timer
	MOV  SI, OFFSET Star
	MOV  CX, NumStars
@@Loop1:
	DEC  [(TStar SI).Duration]
	JNZ  @@NextStar1
	CMP  [(TStar SI).Active], 0
	JNE  @@NextStar1

	MOV  [(TStar SI).Active], 1
	MOV  [(TStar SI).Phase], 0
	CALL Random, 6
	IMUL AX, 30
	MOV  [(TStar SI).Col], AL
	CALL Random, 315
	MOV  [(TStar SI).X], AX
	CALL Random, 195
	MOV  [(TStar SI).Y], AX

@@NextStar1:
	ADD  SI, SIZE TStar
	DEC  CX
	JNZ  @@Loop1

	; Loop 2: Rendering e disegno ottimizzato
	MOV  SI, OFFSET Star
	MOV  BP, NumStars
@@Loop2:
	CMP  [(TStar SI).Active], 0
	JE   @@NextStar2

	; Indirizzo base VRAM = Star.Y * 320 + Star.X
	MOV   AX, [(TStar SI).Y]
	IMUL  AX, 320
				ADD   AX, [(TStar SI).X]  ; AX = Offset VRAM base stella

	; Puntatore BitMask (Frame 0 o Frame 1)
	MOV   BX, OFFSET BitMask
	CMP   [(TStar SI).Phase], 10
	JLE   @@FrameReady
	ADD   BX, 25              ; Frame 1
@@FrameReady:

	; Disegno matrice 5x5 usando i registri CX (Y) e DX (X)
	XOR   CX, CX              ; CX = Y_offset (0..4)
@@DrawY:
	XOR   DX, DX              ; DX = X_offset (0..4)
@@DrawX:
	CMP   [BYTE BX], 0
	;MOV   AL, [BX]            ; Legge valore BitMask
	;OR    AL, AL
	JZ    @@SkipPixel

	; Calcolo offset pixel diretto = BaseOffset + Y_offset * 320 + X_offset
	MOV   DI, CX
	IMUL  DI, 320
	ADD   DI, DX
	ADD   DI, AX

	; Colore = BitMask + Star.Col + Star.Phase
	PUSH  AX
	MOV   AL, [BX]            ; Legge valore BitMask
	ADD   AL, [(TStar SI).Col]
	ADD   AL, [(TStar SI).Phase]
	MOV   [ES:DI], AL         ; Scrittura pixel diretta in VRAM
				POP   AX

@@SkipPixel:
	INC   BX                  ; Prossimo byte BitMask
	INC   DX                  ; Incrementa X_offset
	CMP   DX, 5
	JL    @@DrawX

	INC   CX                  ; Incrementa Y_offset
	CMP   CX, 5
	JL    @@DrawY

	; Aggiorna stato animazione
	INC   [(TStar SI).Phase]
	CMP   [(TStar SI).Phase], 20
	JNE   @@NextStar2

	MOV   [(TStar SI).Active], 0
	CALL  Random, 20
	INC   AL
	MOV   [(TStar SI).Duration], AL

@@NextStar2:
	ADD   SI, SIZE TStar
	DEC   BP
	JNZ   @@Loop2

	CALL  DosIsCharAvail
	OR    AL, AL
	JZ    @@Main

	; Ripristina modalità testo 80x25
	MOV   AX, 0003h
	INT   10h

	MOV   AX, 4C00h
	INT   21h
END Begin
