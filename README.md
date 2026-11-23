# DOOMP
# DOOMP — Real-Time RAM Patcher for *The Ultimate Doom* (E4M3) via APIC Multi-Core

> **Nota sulla community e sull'uso:** Questo progetto è un esperimento tecnico su architettura x86, DPMI/PMODE/W e APIC multi-core applicato a *The Ultimate Doom* (episodio 4, mappa 3 — *Sever the Wicked*). **Non è pensato per speedrun, demo o classifiche ufficiali**, poiché modifica attivamente lo stato delle entità in RAM a runtime.

## Panoramica

**DOOMP** è un'utility per DOS/x86 suddivisa in due ruoli principali:
- **Core 0 (BSP, `DOOMP0.C` + `DPMI.ASM`):** gira in protected mode tramite Open Watcom e PMODE/W, alloca la memoria convenzionale per il trampolino, mappa il Local APIC (`0xFEE00000`) via DPMI (`INT 31h`, funzione `0800h`), calibra il timing con `RDTSC` e il PIT (`0x046C`), avvia il Core 1 tramite la sequenza **INIT–SIPI–SIPI** sui registri ICR (`+0x300` / `+0x310`), lancia `DOOM.EXE` (`-warp 4 3 -nomonsters`) e ripulisce le risorse all'uscita.
- **Core 1 (AP, `DOOMP1.ASM` + `DOOMP2.ASM`):** entra in **32-bit flat protected mode senza paginazione** (GDT con selettori flat a 4 GB) ed esegue in background una scansione attraverso l'algoritmo **Boyer–Moore–Horspool (`BMHSearch`)** sulla memoria fisica per individuare le due *Tall Red Torch* (`MT_MISC41`, tipo `0x5D`) alle coordinate `(-1328, -1968)` e `(-1328, -2128)` in formato `fixed_t` (`* 65536`), azzerando il flag `MF_SOLID` (`0x02`) sull'oggetto `mobj_t` per renderle attraversabili.

## Architettura e build

Il payload del Core 1 viene assemblato con **TASM** separando l'inizializzazione a 16 bit (`DOOMP1.ASM`) e il codice a 32 bit (`DOOMP2.ASM`, con segmenti `CODE32 PUBLIC BYTE USE32` uniti senza padding), collegato come raw binary tramite **Open Watcom WLINK** (`DOOMP1.DEF`) e convertito in oggetto collegabile (`DMCORE.OBJ`) con **`BINOBJ.EXE`**.

Strumenti utilizzati nello sviluppo e nei test:
- **Open Watcom** (`WCC386.EXE`, `WCL386.EXE`, `WLINK.EXE`) e **PMODE/W** (`PMWSETUP.EXE`)
- **Borland Turbo Assembler (`TASM.EXE`)** e **`BINOBJ.EXE`**
- **QEMU** (configurato con `-smp 2` e 64 MB di RAM per i test del Core 1 e di *Doom*)

## Note tecniche e sviluppo

Durante la messa a punto del progetto ho realizzato diversi "surrogati", per testare la compatibilità del DOS Extender PMODEW con altri sistemi:
- **Real Mode:** scritti in QBasic, Turbo C 2.01, Turbo C++ 3.0, Turbo Pascal 7.0 e Turbo Assembler 5.0.
- **Protected mode 16 bit:** scritti in Borland C++ 3.1 e Borland Pascal 7.0.
- **Protected mode 32 bit:** scritti in Watcom C con i DOS Extender DOS4GW.EXE e PMODEW.EXE, in DJGPP con il DPMI host CWSDPMI.EXE ed infine con il DOS Extender HX HDPMI32.EXE.

## Requisiti e disclaimer

- Richiede una copia legittima di *The Ultimate Doom* (`DOOM.EXE` / IWAD) e un ambiente DOS/emulatore compatibile con APIC/SMP e PMODE/W.
- *DOOM* e *The Ultimate Doom* sono marchi dei rispettivi proprietari; questo repository non include file di gioco protetti da copyright.

La mia configurazione di QEMU è la seguente.

```bash
qemu-system-i386.exe -m 64 -cpu coreduo -smp 2,cores=2 -audiodev dsound,id=snd0 -device ich9-intel-hda -device hda-duplex,audiodev=snd0 -rtc base=localtime -boot c -drive file=C:\QDOS\DOS.qcow2,format=qcow2
```

La funzione P_UnsetThingPosition, in P_MAPUTL.C, contiene un potenziale hack; io ho disassemblato in WinDBG il codice estratto da QEMU:

```
; void __watcall P_UnsetThingPosition(mobj_t *thing)
; Ingresso: EAX = thing

004844F0: 53                push ebx
004844F1: 51                push ecx
004844F2: 52                push edx
004844F3: 56                push esi
004844F4: 57                push edi
004844F5: 55                push ebp

; --- Scollegamento dalla lista del Settore (snext / sprev) ---
004844F6: F6 40 68 08       test byte ptr [eax+68h], 08h    ; thing->flags & MF_NOSECTOR ?
004844FA: 75 29             jnz  00484525h                  ; se attivo, salta la gestione settore

004844FC: 8B 50 18          mov  edx, [eax+18h]             ; edx = thing->snext
004844FF: 85 D2             test edx, edx                   ; if (thing->snext)
00484501: 74 08             jz   0048450Bh
00484503: 89 D3             mov  ebx, edx                   ; ebx = thing->snext
00484505: 8B 50 1C          mov  edx, [eax+1Ch]             ; edx = thing->sprev
00484508: 89 53 1C          mov  [ebx+1Ch], edx             ; thing->snext->sprev = thing->sprev

0048450B: 8B 58 1C          mov  ebx, [eax+1Ch]             ; ebx = thing->sprev
0048450E: 85 DB             test ebx, ebx                   ; if (thing->sprev)
00484510: 74 08             jz   0048451Ah                  ; se sprev == NULL, aggiorna sector->thinglist
00484512: 8B 50 18          mov  edx, [eax+18h]             ; edx = thing->snext
00484515: 89 53 18          mov  [ebx+18h], edx             ; thing->sprev->snext = thing->snext
00484518: EB 0B             jmp  00484525h                  ; passa alla gestione blockmap

; Caso sprev == NULL: l'oggetto era in testa alla lista del settore
0048451A: 8B 50 34          mov  edx, [eax+34h]             ; edx = thing->subsector
0048451D: 8B 1A             mov  ebx, [edx]                 ; ebx = thing->subsector->sector
0048451F: 8B 50 18          mov  edx, [eax+18h]             ; edx = thing->snext
00484522: 89 53 46          mov  [ebx+46h], edx             ; sector->thinglist = thing->snext

; --- Scollegamento dalla Blockmap (bnext / bprev) ---
00484525: F6 40 68 10       test byte ptr [eax+68h], 10h    ; thing->flags & MF_NOBLOCKMAP ?
00484529: 0F 85 63 00 00 00 jnz  00484592h                  ; se attivo, vai direttamente all'epilogo

0048452F: 8B 48 2C          mov  ecx, [eax+2Ch]             ; ecx = thing->bnext
00484532: 85 C9             test ecx, ecx                   ; if (thing->bnext)
00484534: 74 06             jz   0048453Ch
00484536: 8B 50 30          mov  edx, [eax+30h]             ; edx = thing->bprev
00484539: 89 51 30          mov  [ecx+30h], edx             ; thing->bnext->bprev = thing->bprev

0048453C: 8B 70 30          mov  esi, [eax+30h]             ; esi = thing->bprev
0048453F: 85 F6             test esi, esi                   ; if (thing->bprev)
00484541: 74 08             jz   0048454Bh                  ; se bprev == NULL, aggiorna blocklinks[]
00484543: 8B 40 2C          mov  eax, [eax+2Ch]             ; eax = thing->bnext
00484546: 89 46 2C          mov  [esi+2Ch], eax             ; thing->bprev->bnext = thing->bnext
00484549: EB 47             jmp  00484592h                  ; vai all'epilogo

; Caso bprev == NULL: l'oggetto era il primo nel blocco della Blockmap
0048454B: 8B 3D D8 C4 44 00 mov  edi, [0044C4D8h]           ; edi = bmaporgx
00484551: 8B 2D DC C4 44 00 mov  ebp, [0044C4DCh]           ; ebp = bmaporgy
00484557: 8B 58 0C          mov  ebx, [eax+0Ch]             ; ebx = thing->x
0048455A: 8B 50 10          mov  edx, [eax+10h]             ; edx = thing->y
0048455D: 29 FB             sub  ebx, edi                   ; ebx = thing->x - bmaporgx
0048455F: 29 EA             sub  edx, ebp                   ; edx = thing->y - bmaporgy
00484561: C1 FB 17          sar  ebx, 17h                   ; blockx = (thing->x - bmaporgx) >> 23
00484564: C1 FA 17          sar  edx, 17h                   ; blocky = (thing->y - bmaporgy) >> 23

if (blockx >= 0 && blockx < bmapwidth && blocky >= 0 && blocky < bmapheight)
{
    blocklinks[blocky*bmapwidth + blockx] = thing->bnext;
}

00484567: 85 DB             test ebx, ebx                   ; if (blockx < 0)
00484569: 7C 27             jl   00484592h                  ;   esci
0048456B: 8B 0D D0 C4 44 00 mov  ecx, [0044C4D0h]           ; ecx = bmapwidth
00484571: 39 CB             cmp  ebx, ecx                   ; if (blockx >= bmapwidth)
00484573: 7D 1D             jge  00484592h                  ;   esci
00484575: 85 D2             test edx, edx                   ; if (blocky < 0)
00484577: 7C 19             jl   00484592h                  ;   esci
00484579: 3B 15 E4 C4 44 00 cmp  edx, [0044C4E4h]           ; if (blocky >= bmapheight)
0048457F: 7D 11             jge  00484592h                  ;   esci

00484581: 0F AF D1          imul edx, ecx                   ; edx = blocky * bmapwidth
00484584: 01 DA             add  edx, ebx                   ; edx = blocky * bmapwidth + blockx
00484586: 8B 1D CC C4 44 00 mov  ebx, [0044C4CCh]           ; ebx = blocklinks (puntatore base array)
0048458C: 8B 40 2C          mov  eax, [eax+2Ch]             ; eax = thing->bnext
0048458F: 89 04 93          mov  [ebx+edx*4], eax           ; blocklinks[indice] = thing->bnext

;if (blockx >= 0 && blockx < bmapwidth && blocky >= 0 && blocky < bmapheight)
;{
;    blocklinks[blocky*bmapwidth + blockx] = thing->bnext;
;}

; --- Epilogo ---
00484592: 5D                pop  ebp
00484593: 5F                pop  edi
00484594: 5E                pop  esi
00484595: 5A                pop  edx
00484596: 59                pop  ecx
00484597: 5B                pop  ebx
00484598: C3                ret
```

Se io riuscissi a controllare i campi snext (+0x18) e sprev (+0x1C) — oppure bnext (+0x2C) e bprev (+0x30) — di un qualsiasi oggetto thing in memoria prima che si muova o venga distrutto, nel momento in cui il gioco chiama P_UnsetThingPosition(thing) eseguirebbe due scritture controllate:

```asm
mov [ebx+1Ch], edx   ; scrive il valore di sprev all'indirizzo (snext + 0x1C)
mov [ebx+18h], edx   ; scrive il valore di snext all'indirizzo (sprev + 0x18)
```

Per alterare snext/sprev o bnext/bprev usando solo il motore di gioco (tramite un file .WAD o una demo .LMP creata ad hoc), esistono meccanismi noti nella scena Doom ACE (Arbitrary Code Execution):

• Overflow nel caricamento del WAD (WAD Exploit): Molti lump dei file WAD (come NODES, SEGS, BLOCKMAP o TEXTURE1) vengono caricati nella Zone Memory di Doom senza controlli rigidi sulle dimensioni o sugli indici. Un lump malformato può sbordare nell'heap e sovrascrivere la struttura mobj_t di un oggetto adiacente (o alterare il puntatore globale blocklinks a 0x0044C4CC), preparando i puntatori falsi per P_UnsetThingPosition.

• Overflow dei limiti interni (es. Intercepts Overflow / Spechits Overflow): Alcuni array statici di Doom (come intercepts[128] o spechit[8]) non hanno controlli di limite (bounds check) durante il gameplay. Superando il limite (ad esempio attraversando più di 8 linee speciali nello stesso tic o sparando attraverso oltre 128 entità/linee in un singolo colpo), la scrittura sborda sulle variabili globali adiacenti nel segmento .BSS / .DATA (dove risiedono anche puntatori chiave come blocklinks, sectors o thinkercap).

Poiché gli overflow di una demo .LMP scrivono nel segmento .DATA/.BSS e non direttamente nell'heap della Zone Memory dove vivono gli mobj_t, serve una strada per arrivare all'esecuzione di codice attraverso un overflow - da trovare.
