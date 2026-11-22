/*
 * ============================================================================
 * Project: DOOMP
 * File:    DOOMP0.C
 * Author:  Stefano Pollazzon (www.github.com/StefanoP85)
 * Description: Programma principale
 * ============================================================================
 */
#include <dos.h>
#include <i86.h>
#include <process.h>
#include <stdio.h>

// Watcom C supporta __int64 e ha int32_t e uint32_t in libreria
typedef signed char            int8_t;
typedef short int              int16_t;
typedef long int               int32_t;
typedef signed __int64         int64_t;
typedef unsigned char          uint8_t;
typedef unsigned short int     uint16_t;
typedef unsigned long int      uint32_t;
typedef unsigned __int64       uint64_t;

// Esegue CPUID (0F A2) prima di RDTSC
// per svuotare la pipeline ed evitare Out-of-Order execution
extern uint64_t GetRDTSCSerialized(void);
#pragma aux GetRDTSCSerialized = \
	"push eax"                   \
	"push ebx"                   \
	"push ecx"                   \
	"push edx"                   \
	"xor eax, eax"               \
	"cpuid"                      \
	"pop edx"                    \
	"pop ecx"                    \
	"pop ebx"                    \
	"pop eax"                    \
	"db 0x0F, 0x31"              \
	value [edx eax];

void PAUSE(void);
#pragma aux PAUSE = \
    0xF3 0x90       \
    modify exact [];

// Codice del Core 1 incorporato come costante
extern unsigned char far DMCORE[];
unsigned int DMCORESize = 1502;

typedef struct _TDpmiRequestRegs
{
	uint32_t EDI;
	uint32_t ESI;
	uint32_t EBP;
	uint32_t Reserved;
	uint32_t EBX;
	uint32_t EDX;
	uint32_t ECX;
	uint32_t EAX;
	uint16_t Flags;
	uint16_t ES;
	uint16_t DS;
	uint16_t FS;
	uint16_t GS;
	uint16_t IP;
	uint16_t CS;
	uint16_t SP;
	uint16_t SS;
} TDpmiRequestRegs;

extern uint8_t __cdecl DpmiAllocate(uint32_t Size, uint32_t* Handle, uint32_t* Buffer);
extern uint8_t __cdecl DpmiDeallocate(uint32_t Handle);
extern uint8_t __cdecl DpmiAllocateConventional(uint32_t Size, uint16_t* Selector, uint32_t* Buffer);
extern uint8_t __cdecl DpmiDeallocateConventional(uint16_t Selector);
extern uint8_t __cdecl DpmiPhysicalAddressMapping(uint32_t PhysicalAddress, uint32_t Size, uint32_t* LinearAddress);
extern uint8_t __cdecl DpmiFreePhysicalAddress(uint32_t LinearAddress);
extern uint8_t __cdecl DpmiLockRegion(uint32_t Address, uint32_t RegionSize);
extern uint8_t __cdecl DpmiUnlockRegion(uint32_t Address, uint32_t RegionSize);
extern uint8_t __cdecl DpmiSimulateRealModeInterrupt(uint8_t IntNo, TDpmiRequestRegs* Regs);

// Misura la frequenza della CPU usando il PIT come riferimento (18.2 Hz).
#define BIOS_TICKS_PTR ((volatile uint32_t*)0x046C)
double CalibrateCpuFrequencyHz(uint16_t WaitTicks)
{
	volatile uint32_t* GetClockTicks = BIOS_TICKS_PTR;
	uint32_t StartTick;
	uint64_t T1, T2;
	double ElapsedSeconds;

	// Sincronizza su un nuovo tick.
	StartTick = *GetClockTicks;
	while (*GetClockTicks == StartTick)
		PAUSE();

	// Legge RDTSC esattamente ad inizio tick.
	T1 = GetRDTSCSerialized();
	StartTick = *GetClockTicks;

	// Attende il numero ti tick specificato.
	while ((*GetClockTicks - StartTick) < WaitTicks)
		PAUSE();

	// Legge RDTSC nuovamente.
	T2 = GetRDTSCSerialized();

	// Calcola la stima della frequenza della CPU in Hz.
	ElapsedSeconds = ((double)WaitTicks * 65536.0) / 1193182.0;
	return (double)(T2 - T1) / ElapsedSeconds;
}

void DelayTicks(uint32_t Ticks)
{
	uint64_t Start = GetRDTSCSerialized();
	while (1)
	{
		uint64_t Current = GetRDTSCSerialized();
		if ((Current - Start) >= Ticks)
			break;
	}
}


void SendIIPI(uint32_t ApicId, uint32_t LapicBase)
{
	volatile uint32_t* IcrLow = (volatile uint32_t*)(LapicBase + 0x0300);
	volatile uint32_t* IcrHigh = (volatile uint32_t*)(LapicBase + 0x0310);

	// Aspetta che l'APIC sia libero (bit 12 == 0)
	while (*IcrLow & 0x00001000)
		PAUSE();

	// Scrive il target core in ICR High
	*IcrHigh = (ApicId << 24);

	// Invia INIT IPI (0x4500)
	*IcrLow = 0x000C4500;

	// Aspetta che l'IPI sia inviato
	while (*IcrLow & 0x00001000)
		PAUSE();
}

void SendSIPI(uint32_t ApicId, uint32_t VectorPage, uint32_t LapicBase)
{
	volatile uint32_t* IcrLow = (volatile uint32_t*)(LapicBase + 0x0300);
	volatile uint32_t* IcrHigh = (volatile uint32_t*)(LapicBase + 0x0310);

	while (*IcrLow & 0x00001000)
		PAUSE();

	*IcrHigh = (ApicId << 24);

	// Invia STARTUP IPI (0x4600 | VectorPage)
	*IcrLow = 0x000C4600 | (VectorPage & 0xFF);

	while (*IcrLow & 0x00001000)
		PAUSE();
}

void EnableLocalApicSoftware(uint32_t LapicBase)
{
	// Il registro Spurious Interrupt Vector si trova a 0xFEE000F0
	volatile uint32_t* Pointer = (volatile uint32_t*)(LapicBase + 0x00F0);

	// Legge il valore attuale, imposta il bit 8 (Software Enable) 
	// e assegna un vettore di interrupt spurio (es. 0xFF)
	*Pointer = (*Pointer & ~0xFF) | 0x1FF;
}

int main(int argc, char* argv[])
{
    uint16_t CodeSelector = 0;
    uint32_t CodePointer = 0;
    uint32_t LapicBase = 0;
    uint32_t AddressTrampoline = 0;
	uint32_t VectorPage;
	uint16_t* PointerPatch;
	uint16_t PatchValue;
    uint8_t* Pointer;
	double CpuFrequencyHz;
    uint32_t I;

    if ((DpmiAllocateConventional(0x2000u, &CodeSelector, &CodePointer) == 0) || (CodeSelector == 0) || (CodePointer == 0))
    {
        puts("Could not allocate 8192 bytes of conventional memory.\n");
        return 1;
    }

    if ((DpmiPhysicalAddressMapping(0xFEE00000u, 0x00001000u, &LapicBase) == 0) || (LapicBase == 0))
    {
		DpmiDeallocateConventional(CodeSelector);
        puts("Could not map LAPIC MMIO.\n");
        return 1;
    }

    // Carica il codice del Core 1.	
	//printf("LapicBase = %i\n", LapicBase);
    AddressTrampoline = (CodePointer + 4095) & 0xFFFFF000;
	//printf("AddressTrampoline = %i\n", AddressTrampoline);
	VectorPage = AddressTrampoline >> 12;
	PatchValue = AddressTrampoline >> 4;
	PointerPatch = (uint16_t*)(&DMCORE[2]);
	*PointerPatch = PatchValue;
    Pointer = (uint8_t*)AddressTrampoline;
    for (I = 0; I < DMCORESize; I++)
    {
        *Pointer = DMCORE[I];
        Pointer++;
    }

	// Avvia il Core 1.
	CpuFrequencyHz = CalibrateCpuFrequencyHz(60);
	EnableLocalApicSoftware(LapicBase);
	SendIIPI(1, LapicBase);
	DelayTicks(CpuFrequencyHz * 0.01);
	SendSIPI(1, VectorPage, LapicBase);
	DelayTicks(CpuFrequencyHz * 0.0002);
	SendSIPI(1, VectorPage, LapicBase);
	DelayTicks(CpuFrequencyHz * 0.0002);

    spawnl(P_WAIT, "doom.exe", "doom.exe", "-warp", "4", "3", "-nomonsters", NULL);

	// Spegne il Core 1.
	SendIIPI(1, LapicBase);
	DelayTicks(CpuFrequencyHz * 0.001);
    DpmiFreePhysicalAddress(LapicBase);
    DpmiDeallocateConventional(CodeSelector);
    return 0;
}
