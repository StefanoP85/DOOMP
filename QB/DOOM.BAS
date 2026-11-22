DECLARE SUB SetDacReg (Reg AS INTEGER, R AS INTEGER, G AS INTEGER, B AS INTEGER)
OPTION BASE 0
DEFINT A-Z

CONST NumStars = 100
CONST Intensity = 6

' Struttura dati per memorizzare i dati di ogni stella
TYPE TStar
    X        AS INTEGER
    Y        AS INTEGER
    Phase    AS INTEGER
    Col      AS INTEGER
    Duration AS INTEGER
    Active   AS INTEGER
END TYPE

DIM SHARED Star(0 TO NumStars - 1) AS TStar
DIM SHARED BitMask(0 TO 1, 0 TO 4, 0 TO 4) AS INTEGER

' Imposta la modalità grafica 320x200 a 256 colori (MODE 13h)
SCREEN 13

' Inizializza il generatore casuale
RANDOMIZE TIMER

' Caricamento della BitMask (matrici 5x5 per le 2 fasi)
FOR Frame = 0 TO 1
    FOR X = 0 TO 4
        FOR Y = 0 TO 4
            READ BitMask(Frame, X, Y)
        NEXT Y
    NEXT X
NEXT Frame

' Impostazione della Tavolozza DAC VGA (equivalente al ciclo DacCycle in ASM)
FOR CL = 1 TO 9
    AX = Intensity * CL
    
    ' Sfumature Rosso
    CALL SetDacReg(CL, AX, 0, 0)
    CALL SetDacReg(21 - CL, AX, 0, 0)
    CALL SetDacReg(20 + CL, 0, 0, 0)
    
    ' Sfumature Verde
    CALL SetDacReg(30 + CL, 0, AX, 0)
    CALL SetDacReg(51 - CL, 0, AX, 0)
    CALL SetDacReg(50 + CL, 0, 0, 0)
    
    ' Sfumature Blu
    CALL SetDacReg(6 + CL, 0, 0, AX)
    CALL SetDacReg(81 - CL, 0, 0, AX)
    CALL SetDacReg(80 + CL, 0, 0, 0)
    
    ' Sfumature Giallo
    CALL SetDacReg(90 + CL, AX, AX, 0)
    CALL SetDacReg(111 - CL, AX, AX, 0)
    CALL SetDacReg(110 + CL, 0, 0, 0)
    
    ' Sfumature Ciano
    CALL SetDacReg(120 + CL, 0, AX, AX)
    CALL SetDacReg(141 - CL, 0, AX, AX)
    CALL SetDacReg(140 + CL, 0, 0, 0)
    
    ' Sfumature Bianco/Grigio
    CALL SetDacReg(150 + CL, AX, AX, AX)
    CALL SetDacReg(171 - CL, AX, AX, AX)
    CALL SetDacReg(170 + CL, 0, 0, 0)
NEXT CL

' Inizializzazione delle stelle
FOR I = 0 TO NumStars - 1
    Star(I).X = 0
    Star(I).Y = 0
    Star(I).Col = 0
    Star(I).Phase = 0
    Star(I).Duration = INT(RND * 20) + 1
    Star(I).Active = 0
NEXT I

' Ciclo Principale (Main Loop)
DO WHILE INKEY$ = ""
    ' Attesa del sincronismo verticale (WaitVerticalRetrace)
    WAIT &H3DA, 8
    WAIT &H3DA, 8, 8
    
    ' Loop 1: Gestione nascite e posizionamento delle stelle
    FOR I = 0 TO NumStars - 1
        Star(I).Duration = Star(I).Duration - 1
        IF Star(I).Duration <= 0 AND Star(I).Active = 0 THEN
            Star(I).Active = 1
            Star(I).Phase = 0
            Star(I).Col = INT(RND * 6) * 30
            Star(I).X = INT(RND * 315)
            Star(I).Y = INT(RND * 195)
        END IF
    NEXT I
    
    ' Loop 2: Disegno delle stelle attive e gestione animazione
    DEF SEG = &HA000 ' Segmento di memoria video VGA Modalità 13h
    FOR I = 0 TO NumStars - 1
        IF Star(I).Active <> 0 THEN
            Frame = 0
            IF Star(I).Phase > 10 THEN Frame = 1
            
            FOR X = 0 TO 4
                FOR Y = 0 TO 4
                    BM = BitMask(Frame, X, Y)
                    IF BM > 0 THEN
                        PX = Star(I).X + X
                        PY = Star(I).Y + Y
                        C = (BM + Star(I).Col + Star(I).Phase) AND 255
                        ' POKE scrive direttamente nel buffer video A000:0000
                        POKE (PY * 320& + PX), C
                    END IF
                NEXT Y
            NEXT X
            
            ' Avanzamento della fase di animazione della stella
            Star(I).Phase = Star(I).Phase + 1
            IF Star(I).Phase >= 20 THEN
                Star(I).Active = 0
                Star(I).Duration = INT(RND * 20) + 1
            END IF
        END IF
    NEXT I
LOOP

' Ripristino della modalità testo 80x25 all'uscita
SCREEN 0
WIDTH 80
END

' Dati della BitMask (corrispondenti a BitMask in STARS.ASM)
' Frame 0 (stella piccola per fase <= 10)
DATA 0,0,1,0,0, 0,0,3,0,0, 1,3,6,3,1, 0,0,3,0,0, 0,0,1,0,0
' Frame 1 (stella estesa per fase > 10)
DATA 0,0,6,0,0, 0,0,3,0,0, 6,3,1,3,6, 0,0,3,0,0, 0,0,6,0,0

DEFSNG A-Z
' Routine per impostare un colore nella tavolozza DAC VGA
SUB SetDacReg (Reg AS INTEGER, R AS INTEGER, G AS INTEGER, B AS INTEGER)
    OUT &H3C8, Reg
    OUT &H3C9, R
    OUT &H3C9, G
    OUT &H3C9, B
END SUB

