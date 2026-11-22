; ============================================================================
; Project: DOOMP
; File:    DPMI.ASM
; Author:  Stefano Pollazzon (www.github.com/StefanoP85)
; Description: Funzioni utili in DPMI
; ============================================================================
IDEAL
JUMPS
LOCALS
P586
MODEL FLAT, C

STRUC TFourRegs
    RegEAX DD ?
    RegEBX DD ?
    RegECX DD ?
    RegEDX DD ?
ENDS  TFourRegs

CODESEG

PROC  EnableLocalApicHardware
    MOV    ECX, 1Bh             ; IA32APICBASE MSR
    RDMSR                       ; Legge l'MSR in EDX:EAX
    OR     EAX, 800h            ; Imposta il bit 11 (APIC Global Enable)
    WRMSR                       ; Scrive l'MSR modificato
    RET
ENDP  EnableLocalApicHardware

PROC  IsPentiumOrNewer
USES  EBX, ESI, EDI
	PUSHFD
	POP     EAX
	MOV     ECX, EAX
	XOR     EAX, 00200000h
	PUSH    EAX
	POPFD
	PUSHFD
	POP     EAX
	PUSH    ECX
	POPFD
	; Controlla se il bit 21 ha cambiato valore
	XOR     EAX, ECX
	TEST    EAX, 00200000h
	SETNZ   AL                         ; AL = 1 se il bit e' cambiato
	RET
ENDP  IsPentiumOrNewer

PROC  DpmiAllocate
ARG   @@BufferSize:DWORD, @@Handle:PTR DWORD, @@Buffer:PTR DWORD
USES  EBX, ESI, EDI
    MOV    EBX, [@@BufferSize]
    MOV    ECX, EBX
    AND    ECX, 0FFFFh
    SHR    EBX, 16                     ; BX:CX = Dimensione in byte (es. 0000h : C000h per 48KB)
    MOV    AX, 0501h                   ; Servizio DPMI: Allocate Linear Memory Block
    INT    31h
    JC     @@Error
    
    ; Ricomponiamo l'indirizzo lineare a 32 bit da BX:CX in EAX
    MOVZX  EAX, BX
    SHL    EAX, 16
    MOV    AX, CX
    MOV    EBX, [@@Buffer]
    MOV    [EBX], EAX
    ; Ricomponiamo l'handle a 32 bit da SI:DI in EAX
    MOVZX  EAX, SI
    SHL    EAX, 16
    MOV    AX, DI
    MOV    EBX, [@@Handle]
    MOV    [EBX], EAX
    MOV    AL, 1                       ; Ritorna True (1) in caso di successo
    JMP    @@Exit

@@Error:
    XOR    AL, AL                      ; Ritorna False (0) in caso di errore
@@Exit:
    RET
ENDP  DpmiAllocate

PROC  DpmiDeallocate
ARG   @@Handle:DWORD
USES  EBX, ESI, EDI
	MOV    AX, 0502h                   ; Servizio DPMI: Free Memory Block
	MOV    SI, [WORD HIGH @@Handle]    ; 16 bit alti dell'handle
	MOV    DI, [WORD LOW  @@Handle]    ; 16 bit bassi dell'handle
	INT    31h
    SETNC  AL
    RET
ENDP  DpmiDeallocate

PROC  DpmiAllocateConventional
ARG   @@BufferSize:DWORD, @@Selector:PTR WORD, @@Buffer:PTR DWORD
USES  EBX, ESI, EDI
    MOV    EBX, [@@BufferSize]
    SHR    EBX, 4                      ; EBX = Dimensione in paragrafi
    MOV    AX, 0100h                   ; Servizio DPMI: Allocate DOS Memory Block
    INT    31h
    JC     @@Error
    
    ; AX = segmento real-mode, DX = selettore
    MOVZX  EAX, AX
    SHL    EAX, 4
    MOV    EBX, [@@Selector]
    MOV    [EBX], DX
    MOV    EBX, [@@Buffer]
    MOV    [EBX], EAX
    MOV    AL, 1                       ; Ritorna True (1) in caso di successo
    JMP    @@Exit

@@Error:
    XOR    AL, AL                      ; Ritorna False (0) in caso di errore
@@Exit:
    RET
ENDP  DpmiAllocateConventional

PROC  DpmiDeallocateConventional
ARG   @@Selector:WORD
USES  EBX, ESI, EDI
	MOV    AX, 0101h                   ; Servizio DPMI: Free DOS Memory Block
	MOV    DX, [@@Selector]            ; 16 bit bassi dell'handle
	INT    31h
    SETNC  AL
    RET
ENDP  DpmiDeallocateConventional

PROC  DpmiPhysicalAddressMapping
ARG   @@PhysicalAddress:DWORD, @@BufferSize:DWORD, @@LinearAddress:PTR DWORD
USES  EBX, ESI, EDI
    MOV    EBX, [@@PhysicalAddress]
    MOV    ECX, EBX
    AND    ECX, 0FFFFh
    SHR    EBX, 16                     ; BX:CX = Indirizzo fisico (High:Low)
    MOV    ESI, [@@BufferSize]
    MOV    EDI, ESI
    AND    EDI, 0FFFFh
    SHR    ESI, 16                     ; SI:DI = Dimensione
    MOV    AX, 0800h                   ; Servizio DPMI: Map Physical Address
    INT    31h
    JC     @@Error
    
    ; Restituisce l'indirizzo lineare mappato in BX:CX
    MOVZX  EAX, BX
    SHL    EAX, 16
    MOV    AX, CX
    MOV    EBX, [@@LinearAddress]
    MOV    [EBX], EAX
    MOV    AL, 1
    JMP    @@Exit

@@Error:
    XOR    AL, AL
@@Exit:
    RET
ENDP  DpmiPhysicalAddressMapping

PROC  DpmiFreePhysicalAddress
ARG   @@LinearAddress:DWORD
USES  EBX, ESI, EDI
    MOV    EBX, [@@LinearAddress]
    MOV    ECX, EBX
    AND    ECX, 0FFFFh
    SHR    EBX, 16                     ; BX:CX = Indirizzo fisico (High:Low)
    MOV    AX, 0801h                   ; Servizio DPMI: Map Physical Address
    INT    31h
    SETNC  AL
    RET
ENDP  DpmiFreePhysicalAddress

PROC  DpmiLockRegion
ARG   @@Address:DWORD, @@RegionSize:DWORD
USES  EBX, ESI, EDI
    MOV    EBX, [@@Address]
    MOV    ECX, [@@RegionSize]
    MOV    ESI, ECX
    SHR    ESI, 16
    MOV    DI, CX
    MOV    CX, BX
    SHR    EBX, 16
    MOV    AX, 0600h
    INT    31h
    SETNC  AL
    RET
ENDP  DpmiLockRegion

PROC  DpmiUnlockRegion
ARG   @@Address:DWORD, @@RegionSize:DWORD
USES  EBX, ESI, EDI
    MOV    EBX, [@@Address]
    MOV    ECX, [@@RegionSize]
    MOV    ESI, ECX
    SHR    ESI, 16
    MOV    DI, CX
    MOV    CX, BX
    SHR    EBX, 16
    MOV    AX, 0601h
    INT    31h
    SETNC  AL
    RET
ENDP  DpmiUnlockRegion

PROC  DpmiSimulateRealModeInterrupt
ARG   @@IntNo:BYTE, @@RegsPtr:DATAPTR
USES  EBX, ESI, EDI
    MOV    BL, [@@IntNo]               ; BL = Numero dell'interrupt da chiamare (es. 10h)
    XOR    CX, CX                      ; CX = 0 (nessun parametro da copiare nello stack RM)
    MOV    EDI, [@@RegsPtr]            ; EDI = Puntatore alla struttura RegsPtr
    MOV    AX, 0300h                   ; Servizio DPMI: Simulate Real Mode Interrupt
    INT    31h
    SETNC  AL
    RET
ENDP  DpmiSimulateRealModeInterrupt

PUBLIC DpmiAllocate
PUBLIC DpmiDeallocate
PUBLIC DpmiAllocateConventional
PUBLIC DpmiDeallocateConventional
PUBLIC DpmiPhysicalAddressMapping
PUBLIC DpmiFreePhysicalAddress
PUBLIC DpmiLockRegion
PUBLIC DpmiUnlockRegion
PUBLIC DpmiSimulateRealModeInterrupt

END
