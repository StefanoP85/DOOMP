import socket
import struct
import time

HOST = "127.0.0.1"
PORT = 1234
RAM_SIZE = 64 * 1024 * 1024  # 64 MB
CHUNK_SIZE = 0x1000  # 4 KB
StartAddress = 0x00100000
RamBuffer = bytearray(RAM_SIZE)
OkPages = 0
ErrPages = 0

def GdbCommand(Sock: socket.socket, Payload: str) -> bytes:
    # Invia un comando RSP GDB con checksum e restituisce i dati della risposta.
    CheckSum = sum(Payload.encode("ascii")) % 256
    Packet = f"${Payload}#{CheckSum:02x}".encode("ascii")
    Sock.sendall(Packet)
    Buffer = bytearray()
    while True:
        Chunk = Sock.recv(65536)
        if not Chunk:
            break
        Buffer.extend(Chunk)
        # Controlla se abbiamo ricevuto il pacchetto completo ($...#XX)
        Dollar = Buffer.find(b"$")
        if Dollar != -1:
            HashIdx = Buffer.find(b"#", Dollar)
            if HashIdx != -1 and len(Buffer) >= HashIdx + 3:
                # Invia ACK '+' a QEMU
                Sock.sendall(b"+")
                return bytes(Buffer[Dollar + 1 : HashIdx])
    return b""

def BoyerMooreHorspoolSearch(Data: bytes, Pattern: bytes) -> list[int]:
    # Ricerca Boyer-Moore-Horspool.
    M, N = len(Pattern), len(Data)
    if M == 0 or N < M:
        return []
    Skip = [M] * 256
    for I in range(M - 1):
        Skip[Pattern[I]] = M - 1 - I
    Matches, I = [], 0
    while I <= N - M:
        J = M - 1
        while J >= 0 and Pattern[J] == Data[I + J]:
            J -= 1
        if J < 0:
            Matches.append(I)
            I += 1
        else:
            I += Skip[Data[I + M - 1]]
    return Matches

def main():
    Targets = {
        "Thing 295 (-1328, -1968)": struct.pack("<ii", -1328 << 16, -1968 << 16),
        "Thing 296 (-1328, -2128)": struct.pack("<ii", -1328 << 16, -2128 << 16),
    }
    print(f"[*] Connessione a QEMU GDB stub ({HOST}:{PORT})...")
    with socket.create_connection((HOST, PORT), timeout=10) as Sock:
        # Disabilita la modalita' non-stop / handshake iniziale
        Sock.sendall(b"+")
        time.sleep(0.1)
        # Iniziamo da 0x100000 (1 MB): DOS/4GW alloca la Zone Memory di Doom sopra 1 MB
        StartAddress = 0x100000
        print(f"[*] Lettura RAM da 0x{StartAddress:08X} a 0x{RAM_SIZE:08X} in corso...")
        OkPages = 0
        ErrPages = 0
        for Address in range(StartAddress, RAM_SIZE, CHUNK_SIZE):
                Response = GdbCommand(Sock, f"m{Address:x},{CHUNK_SIZE:x}")
                if Response.startswith(b"E") or not Response:
                        ErrPages += 1
                        continue
                Raw = bytes.fromhex(Response.decode("ascii"))
                RamBuffer[Address : Address + len(Raw)] = Raw
                OkPages += 1
                print(f"[*] Pagine lette: {OkPages} OK ({OkPages * 4} KB), {ErrPages} con errore/non mappate.")
        print("[*] Scansione Boyer-Moore-Horspool delle coordinate...\n")
        PatchedCount = 0
        for Name, Sig in Targets.items():
            Offsets = BoyerMooreHorspoolSearch(RamBuffer, Sig)
            for Offset in Offsets:
                MobjBegin = Offset - 0x0C
                MobjAngle, = struct.unpack_from("<I", RamBuffer, MobjBegin + 0x20)
                MobjType, = struct.unpack_from("<I", RamBuffer, MobjBegin + 0x58)
                MobjFlags = MobjBegin + 0x68
                Flags, = struct.unpack_from("<I", RamBuffer, MobjFlags)
                # Verifica di sicurezza: controlla che sia davvero Tall Red Torch (0x46)
                if MobjType == 0x5D:
                    print(f"[+] TROVATA {Name}!")
                    print(f"    base   : 0x{MobjBegin:08X}")
                    print(f"    angle  : 0x{MobjAngle:08X}")
                    print(f"    type   : 0x{MobjType:08X} (MT_MISC41 - Tall Red Torch)")
                    print(f"    flags  : 0x{MobjFlags:08X} | val prima: 0x{Flags:08X}")
                    # Rimuove solo il bit MF_SOLID (0x00000002), lasciando intatti eventuali altri flag
                    NewFlags = Flags & ~0x00000002
                    HexVal = struct.pack("<I", NewFlags).hex()
                    WriteResult = GdbCommand(Sock, f"M{MobjFlags:x},4:{HexVal}")
                    if WriteResult == b"OK":
                        print(f"    [OK] MF_SOLID rimosso! Nuovo valore Flags: 0x{NewFlags:08X}\n")
                        PatchedCount += 1
                    else:
                        print(f"    [!] Errore scrittura GDB: {WriteResult}\n")
        # Riprende l'esecuzione della CPU in QEMU prima di disconnettersi
        print("[*] Invio comando 'c' (continue) a QEMU...")
        Payload = "c"
        CheckSum = sum(Payload.encode("ascii")) % 256
        Sock.sendall(f"${Payload}#{CheckSum:02x}".encode("ascii"))
        Sock.settimeout(1.0)
        try:
                Ack = Sock.recv(1)
                if Ack == b"+":
                        print("    [OK] ACK ricevuto, esecuzione ripresa.")
        except TimeoutError:
                print("    [i] Nessun ACK immediato, proseguo con la chiusura pulita.")
        if PatchedCount == 2:
            print("=== FATTO! Entrambe le torce ora non sono piu' solide. Buona caccia al 100% Secrets! ===")
        else:
            print(f"=== Attenzione: patchate {PatchedCount}/2 torce. Assicurati di essere gia' dentro E4M3! ===")

if __name__ == "__main__":
        main()
