; ============================================================================
; Project: DOOMP
; File:    DOOMP1.ASM
; Author:  Stefano Pollazzon (www.github.com/StefanoP85)
; Description: Codice del Core 1
; ============================================================================
IDEAL
JUMPS
LOCALS
P686

MACRO MakeGDTDescriptor Limit0, Base0, Base16, AccessByte, Flags, Base24
    DW Limit0
    DW Base0
    DB Base16
    DB AccessByte
    DB Flags
    DB Base24
ENDM MakeGDTDescriptor

GROUP DGROUP DATA, CODE16, CODE32

StackSize = 256 ; 1024 byte

SEGMENT DATA PUBLIC PARA USE16 'DATA'
    ALIGN 8
    GDTBegin:
        ; 00h: Null descriptor
        MakeGDTDescriptor 0, 0, 0, 0, 0, 0
        ; 08h: Code Segment 32-bit (USE32, Base 0, Limit 4GB)
        MakeGDTDescriptor 0FFFFh, 0000h, 00h, 10011010b, 11001111b, 00h
        ; 10h: Data Segment 32-bit Flat (Base 0, Limit 4GB)
        MakeGDTDescriptor 0FFFFh, 0000h, 00h, 10010010b, 11001111b, 00h
    GDTEnd:

    GDTRLimit  DW GDTEnd - GDTBegin - 1
    GDTRBase   DD 0

    StackSpace DD StackSize dup(0)
ENDS DATA

SEGMENT CODE16 PUBLIC PARA USE16 'CODE'
ASSUME CS:DGROUP, DS:DGROUP
Begin:
    JMP SHORT CodeStart

; - RelocRealSeg : segmento Real Mode in cui e' caricato il programma
RelocRealSeg  DW 0

CodeStart:
    CLI
    MOV     AX, [CS:RelocRealSeg]
    MOV     DS, AX

    ; Imposta EBX all'indirizzo FISICO del codice!
    XOR     EBX, EBX
    MOV     BX, AX
    SHL     EBX, 4
    ; Imposta EBP ed ESP!
    MOV     EAX, OFFSET StackSpace
    ADD     EAX, 256 * 4
    ADD     EAX, EBX
    MOV     EBP, EAX
    MOV     ESP, EAX

    ; Imposta la base fisica della GDT in GDTRBase
    MOV     EAX, OFFSET GDTBegin
    ADD     EAX, EBX
    MOV     [GDTRBase], EAX

    ; Imposta l'indirizzo di salto a 32 bit per il JMP FAR
    MOV     EAX, OFFSET PM32JumpOffset
    MOV     EDX, OFFSET PM32Begin
    ADD     EDX, EBX
    MOV     [EAX], EDX

    ; Imposta la GDT
    LGDT    [FWORD GDTRLimit]

    ; Imposta CR0.PE = 1
    MOV     EAX, CR0
    OR      EAX, 1
    MOV     CR0, EAX

    ; JMP FAR 16:32 verso selettore 08h (32-bit flat, no paging)
    DB      66h
    DB      0EAh
PM32JumpOffset:
    DD      0
    DW      08h
ENDS CODE16

SEGMENT CODE32 PUBLIC BYTE USE32 'CODE'
PM32Begin:
    NOP
    NOP
;    JMP @@PM32Begin
ENDS  CODE32

PUBLIC RelocRealSeg

END
