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
