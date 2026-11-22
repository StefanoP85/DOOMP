; ============================================================================
; Project: DOOMP
; File:    DOOMP2.ASM
; Author:  Stefano Pollazzon (www.github.com/StefanoP85)
; Description: Codice del Core 1 a 32 bit
; ============================================================================
IDEAL
JUMPS
LOCALS
P686
MODEL FLAT, PASCAL

GROUP DGROUP CODE32

SEGMENT CODE32 BYTE PUBLIC 'CODE'
ASSUME CS:CODE32, DS:CODE32
PM32Begin:
    ; Imposta i selettori; ESP ed EBP puntano allo stack in DATA!
    MOV     AX, 10h
    MOV     DS, AX
    MOV     ES, AX
    MOV     FS, AX
    MOV     GS, AX
    MOV     SS, AX

BmhInfiniteLoop:
    CALL    PatchRedTorch295 
    CALL    PatchRedTorch296
    JMP     BmhInfiniteLoop

PROC  BMHSearch PASCAL USE32
ARG   @@Pattern:DWORD, @@PatternSize:DWORD
LOCAL @@SkipTable:BYTE:256, @@MaxShiftConst:DWORD
USES  EBX, ESI, EDI
    ; Uso dei registri
    ; [EBP + 00h] = vecchio EBP
    ; [EBP + 04h] = indirizzo di ritorno
    ; [EBP + 08h] = secondo argomento PASCAL (@@PatternSize)
    ; [EBP + 0Ch] = primo argomento PASCAL   (@@Pattern)

    ; MOV     ESI, 0010FFF0h             ; Puntatore all'inizio della RAM da cercare, dopo la HMA
    ; MOV     EDI, [EBP + 0Ch]           ; Puntatore al pattern da cercare
    ; MOV     ECX, 3F00000h              ; Contatore di byte da scansionare
    ; MOV     EBX, [@@PatternSize]       ; Contatore dei byte del pattern

    MOV     ESI, 0010FFF0h
    MOV     EDI, [EBP + 0Ch]
    MOV     ECX, 3F00000h
    MOV     EBX, [EBP + 08h]

    ; 0. Controllo input
    TEST    EBX, EBX
    JZ      @@NotFound
    CMP     ECX, EBX
    JB      @@NotFound

    ; 1. Riempi Skip Table con PatternSize (max 255)
    MOV     EAX, EBX
    MOV     EDX, 255
    CMP     EAX, EDX
    CMOVA   EAX, EDX                   ; EAX = Min(PatternSize, 255)
    ; Replica AL nei 4 byte di EAX (es. 0x08 -> 0x08080808)
    IMUL    EAX, 01010101h
    LEA     EDI, [@@SkipTable]
    MOV     ECX, 64                    ; 64 DWORD = 256 BYTE
    CLD
    REP     STOSD

    ; 2. Calcola gli shift per Pattern[0 .. m-2]
    MOV     [@@MaxShiftConst], 255
    MOV     EDI, [EBP + 0Ch]
    MOV     ECX, [EBP + 08h]
    DEC     ECX                        ; ECX = m - 1
    JZ      @@MainSearchLoop
    XOR     EAX, EAX                   ; EAX = k = 0
@@BuildTable:
    MOVZX   EDX, [BYTE (EDI + EAX)]    ; EDX = Pattern[k]
    PUSH    ECX
    SUB     ECX, EAX                   ; ECX = (m - 1) - k
    CMP     ECX, 255
    CMOVA   ECX, [@@MaxShiftConst]
    PUSH    EBX
    LEA     EBX, [@@SkipTable]
    MOV     [EBX + EDX], CL
    POP     EBX
    POP     ECX
    INC     EAX
    CMP     EAX, ECX
    JB      @@BuildTable

    ; 3. Ciclo di ricerca
@@MainSearchLoop:
    MOV     EAX, 3F00000h
    SUB     EAX, EBX                   ; EAX = (n - m)
    ADD     EAX, ESI                   ; EAX = puntatore massimo valido nel Buffer
    ; Pre-calcoliamo (m - 1)
    DEC     EBX                        ; EBX ora vale (m - 1) fisso per tutto il loop!
@@OuterLoop:
    CMP     ESI, EAX                   ; Puntatore corrente > puntatore massimo?
    JA      @@NotFound
    MOV     ECX, EBX                   ; ECX = j = m - 1
@@InnerLoop:
    ; Usiamo movzx a 32-bit per evitare qualsiasi partial register stall sul Pentium Pro
    MOVZX   EDX, [BYTE (ESI + ECX)]
    CMP     DL, [BYTE (EDI + ECX)]
    JNE     @@Mismatch
    DEC     ECX
    JNS     @@InnerLoop
    ; Match trovato! ESI contiene l'indirizzo FISICO
    MOV     EAX, ESI
    JMP     @@Exit
@@Mismatch:
    ; EBX vale già (m - 1), quindi [esi + ebx] è direttamente l'ultimo byte della finestra!
    MOVZX   EDX, [BYTE (ESI + EBX)]
    PUSH    EBX
    LEA     EBX, [@@SkipTable]
    MOVZX   EDX, [BYTE (EBX + EDX)]
    POP     EBX
    ADD     ESI, EDX
    JMP     @@OuterLoop
@@NotFound:
    ; Match non trovato: restituisce ZERO
    MOV     EAX, 0
@@Exit:
    RET
ENDP  BMHSearch

RedTorch295X = -1328 * 65536
RedTorch295Y = -1968 * 65536

PROC  PatchRedTorch295 PASCAL USE32
LOCAL @@TargetCoords:DWORD:2
USES  EBX, ESI, EDI
    LEA     EBX, [@@TargetCoords]
    MOV     [DWORD EBX], RedTorch295X
    MOV     [DWORD EBX + 4], RedTorch295Y
    CALL    BMHSearch, EBX, 8
    TEST    EAX, EAX
    JZ      @@Exit
    ; EAX = indirizzo fisico di X (mobj_start + 0Ch)
    ; Controlla type a mobj_start + 58h -> (EAX - 0Ch) + 58h = EAX + 4Ch
    CMP     [DWORD EAX + 4Ch], 05Dh
    JNE     @@Exit
    ; Rimuove MF_SOLID (bit 1 = 02h) a mobj_start + 68h -> (EAX - 0Ch) + 68h = EAX + 5Ch
    AND     [DWORD EAX + 5Ch], NOT 2
@@Exit:
    RET    
ENDP  PatchRedTorch295

RedTorch296X = -1328 * 65536
RedTorch296Y = -2128 * 65536

PROC  PatchRedTorch296 PASCAL USE32
LOCAL @@TargetCoords:DWORD:2
USES  EBX, ESI, EDI
    LEA     EBX, [@@TargetCoords]
    MOV     [DWORD EBX], RedTorch296X
    MOV     [DWORD EBX + 4], RedTorch296Y
    CALL    BMHSearch, EBX, 8
    TEST    EAX, EAX
    JZ      @@Exit
    ; EAX = indirizzo fisico di X (mobj_start + 0Ch)
    ; Controlla type a mobj_start + 58h -> (EAX - 0Ch) + 58h = EAX + 4Ch
    CMP     [DWORD EAX + 4Ch], 05Dh
    JNE     @@Exit
    ; Rimuove MF_SOLID (bit 1 = 02h) a mobj_start + 68h -> (EAX - 0Ch) + 68h = EAX + 5Ch
    AND     [DWORD EAX + 5Ch], NOT 2
@@Exit:
    RET    
ENDP  PatchRedTorch296

ENDS  CODE32

END
