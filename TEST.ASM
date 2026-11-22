IDEAL
JUMPS
LOCALS
P386

MACRO MakeCString Id, Msg
    IFB <Id>
        DISPLAY "Bisogna specificare il nome della stringa IN MakeCString"
        ERR
    ELSE
        IFB <Msg>
            DISPLAY "Bisogna passare la stringa a MakeCString"
            ERR
        ELSE
            Id DB &Msg&
            DB 0
        ENDIF
    ENDIF
ENDM  MakeCString
MACRO MakePascalString Id, Msg
    LOCAL EndStr
    IFB <Id>
        DISPLAY "Bisogna specificare il nome della stringa IN MakePascalString"
        ERR
    ELSE
        IFB <Msg>
            DISPLAY "Bisogna passare la stringa a MakePascalString"
            ERR
        ELSE
            Id DB EndStr - Id - 1, &Msg&
            LABEL EndStr BYTE
        ENDIF
    ENDIF
ENDM  MakePascalString
MACRO MakeGDTDescriptor Limit0, Base0, Base16, AccessByte, Flags, Base24
    DW Limit0
    DW Base0
    DB Base16
    DB AccessByte
    DB Flags
    DB Base24
ENDM  MakePascalString

SEGMENT DATA USE16 'DATA'
    MsgErrVM86 DB "Errore: CPU IN V86 mode (EMM386/QEMM attivo).", 0Dh, 0Ah, '$'
    MsgOk      DB "Ciclo RM -> PM32 -> PM16 -> RM completato! LAPIC letta.", 0Dh, 0Ah, '$'

    ALIGN 8
    GDTBegin:
        ; Null descriptor
        MakeGDTDescriptor 0, 0, 0, 0, 0, 0
 
        ; 08h: Code Segment 32-bit (USE32, Base 0, Limit 4GB, D=1, Present, Ring 0, Code, Exec/Read)
        MakeGDTDescriptor 0FFFFh, 0000h, 00h, 10011010b, 11001111b, 00h
 
        ; 10h: Data Segment 32-bit Flat (Base 0, Limit 4GB, B=1, Present, Ring 0, Data, Read/Write)
        MakeGDTDescriptor 0FFFFh, 0000h, 00h, 10010010b, 11001111b, 00h

        ; 18h: Code Segment 16-bit per il rientro (USE16, Limit 64KB, D=0)
        ; (La base verra' riempita a runtime con l'indirizzo fisico di CODE16)
        MakeGDTDescriptor 0FFFFh, 0000h, 00h, 10011010b, 00000000b, 00h
 
        ; 20h: Data Segment 16-bit per il rientro (Limit 64KB, B=0)
        MakeGDTDescriptor 0FFFFh, 0000h, 00h, 10010010b, 00000000b, 00h
    GDTEnd:

    GDTRLimit  DW GDTEnd - GDTBegin - 1
    GDTRBase   DD 0
    LapicID    DD 0
    SavedSP    DW 0
    SavedSS    DW 0
ENDS DATA

SEGMENT STACKSEG STACK USE16 'STACK'
    DB 1024 dup(?)
ENDS STACKSEG

SEGMENT CODE32 USE32 'CODE'
ASSUME CS:CODE32, DS:DATA
PM32Begin:
    ; Qui siamo IN pura Protected Mode a 32-bit!
    MOV     AX, 10h                    ; Selettore Data Flat 32-bit (Base 0, 4GB)
    MOV     DS, AX
    MOV     ES, AX
    MOV     FS, AX
    MOV     GS, AX
    MOV     SS, AX
    MOV     ESP, 90000h                ; Stack temporaneo sicuro IN memoria bassa

    ; Leggi il registro LAPIC ID (indirizzo fisico 0FEE00020h)
    MOV     EBX, [0FEE00020h]          ; Nessun prefisso override necessario: siamo IN USE32!

    ; --- PASSAGGIO A 16-BIT PROTECTED MODE ---
    ; Eseguiamo un JMP FAR 16:32 verso il selettore 18h (Code 16-bit)
    DB      66h                       ; Override operando a 16-bit per il JMP FAR
    DB      0EAh                      ; Opcode JMP FAR
    DW      OFFSET PM16Entry          ; OFFSET a 16-bit dentro CODE16
    DW      18h                       ; Selettore Code 16-bit (D=0)
ENDS CODE32

SEGMENT CODE16 USE16 'CODE'
ASSUME CS:CODE16, DS:DATA, SS:STACKSEG
Begin:
    MOV     AX, DATA
    MOV     DS, AX

    ; Verifica se siamo IN V86 mode
    SMSW    AX
    TEST    AX, 1
    JNZ     InV86Mode

    ; Salva SS:SP della Real Mode
    MOV     [SavedSS], SS
    MOV     [SavedSP], SP

    ; Calcola l'indirizzo fisico della GDT
    XOR     EAX, EAX
    MOV     AX, DATA
    SHL     EAX, 4
    ADD     AX, OFFSET GDTBegin
    MOV     [GDTRBase], EAX

    ; Calcola l'indirizzo fisico di CODE16 e patcha il descrittore 18h nella GDT
    ; (Cosi' gli OFFSET dentro CODE16 coincidono tra Real Mode e PM 16-bit)
    XOR     EAX, EAX
    MOV     AX, CODE16
    SHL     EAX, 4
    MOV     [WORD GDTBegin + 18h + 2], AX      ; Base 0..15
    SHR     EAX, 16
    MOV     [BYTE GDTBegin + 18h + 4], AL      ; Base 16..23

    ; Calcola l'indirizzo fisico lineare di 'PM32Begin' per il salto IN PM32
    XOR     EAX, EAX
    MOV     AX, CODE32
    SHL     EAX, 4
    ADD     EAX, OFFSET PM32Begin
    MOV     [DWORD PM32JumpOffset], EAX

    ; Abilita linea A20 (Fast A20 via porta 92h)
    IN      AL, 92h
    OR      AL, 2
    AND     AL, 0FEh
    OUT     92h, AL

    ; Entra ib Protected Mode a 32-bit
    CLI
    LGDT    [FWORD GDTRLimit]

    MOV     EAX, CR0
    OR      EAX, 1
    MOV     CR0, EAX

    ; Salto FAR verso il selettore 08h (Code 32-bit, Base 0)
    DB      66h                       ; Prefisso per OFFSET a 32-bit
    DB      0EAh                      ; Opcode JMP FAR
PM32JumpOffset:
    DD      0                         ; Patchato al passo 5 con indirizzo fisico di PM32Begin
    DW      08h                       ; Selettore Code 32-bit (USE32)

PM16Entry:
    ; Ora CS ha finalmente D=0 e limite 64KB!
    ; Ripristiniamo anche i selettori dati e stack con limiti a 64KB (selettore 20h)
    MOV     AX, 20h
    MOV     DS, AX
    MOV     ES, AX
    MOV     FS, AX
    MOV     GS, AX
    MOV     SS, AX

    ; Disabilita Protected Mode (PE = 0 in CR0)
    MOV     EAX, cr0
    AND     EAX, 0FFFFFFFEh
    MOV     cr0, EAX

    ; Salto FAR per ricaricare CS con il vero segmento Real Mode (CODE16)
    DB      0EAh
    DW      OFFSET RMEntry
    DW      CODE16

RMEntry:
    MOV     AX, DATA
    MOV     DS, AX
    MOV     ES, AX
    MOV     FS, AX
    MOV     GS, AX

    ; Ripristina lo stack originale del DOS
    MOV     SS, [SavedSS]
    MOV     SP, [SavedSP]

    STI 
    ; Salva il valore della LAPIC letto IN PM32 (conservato IN EBX)
    MOV     [LapicID], EBX

    ; Stampa messaggio di conferma
    MOV     AH, 09h
    MOV     DX, OFFSET MsgOk
    INT     21h
    MOV     AX, 4C00h
    INT     21h

InV86Mode:
    MOV     AH, 09h
    MOV     DX, OFFSET MsgErrVM86
    INT     21h
    MOV     AX, 4C01h
    INT     21h
ENDS CODE16
END Begin
