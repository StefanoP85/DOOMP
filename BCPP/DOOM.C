#include <dos.h>
#include <conio.h>
#include <stdlib.h>
#include <time.h>

#define NUM_STARS 100
#define INTENSITY 6

typedef struct {
    int x;
    int y;
    int phase;
    int col;
    int duration;
    int active;
} TStar;

/* Matrice BitMask 5x5 per le 2 fasi di animazione */
static const unsigned char BitMask[2][5][5] = {
    {
        {0,0,1,0,0}, {0,0,3,0,0}, {1,3,6,3,1}, {0,0,3,0,0}, {0,0,1,0,0}
    },
    {
        {0,0,6,0,0}, {0,0,3,0,0}, {6,3,1,3,6}, {0,0,3,0,0}, {0,0,6,0,0}
    }
};

void SetMode(int mode) {
    union REGS regs;
    regs.h.ah = 0;
    regs.h.al = (unsigned char)mode;
    int86(0x10, &regs, &regs);
}

void SetDacReg(unsigned char reg, unsigned char r, unsigned char g, unsigned char b) {
    (void)outp(0x3C8, reg);
    (void)outp(0x3C9, r);
    (void)outp(0x3C9, g);
    (void)outp(0x3C9, b);
}

void WaitVSync(void) {
    while (inp(0x3DA) & 8);
    while (!(inp(0x3DA) & 8));
}

int main(void) {
    /* Dichiarazioni C89 all'inizio del blocco per Turbo C 2.01 */
    TStar star[NUM_STARS];
    unsigned char far* vram = (unsigned char far*)0xA0000000L;
    int i, frame, x, y, cl, ax;
    unsigned char color;

    srand((unsigned)time(NULL));
    SetMode(0x13);

    /* Inizializzazione Palette DAC VGA */
    for (cl = 1; cl <= 9; cl++) {
        ax = INTENSITY * cl;

        SetDacReg((unsigned char)cl, (unsigned char)ax, 0, 0);
        SetDacReg((unsigned char)(21 - cl), (unsigned char)ax, 0, 0);
        SetDacReg((unsigned char)(20 + cl), 0, 0, 0);

        SetDacReg((unsigned char)(30 + cl), 0, (unsigned char)ax, 0);
        SetDacReg((unsigned char)(51 - cl), 0, (unsigned char)ax, 0);
        SetDacReg((unsigned char)(50 + cl), 0, 0, 0);

        SetDacReg((unsigned char)(6 + cl), 0, 0, (unsigned char)ax);
        SetDacReg((unsigned char)(81 - cl), 0, 0, (unsigned char)ax);
        SetDacReg((unsigned char)(80 + cl), 0, 0, 0);

        SetDacReg((unsigned char)(90 + cl), (unsigned char)ax, (unsigned char)ax, 0);
        SetDacReg((unsigned char)(111 - cl), (unsigned char)ax, (unsigned char)ax, 0);
        SetDacReg((unsigned char)(110 + cl), 0, 0, 0);

        SetDacReg((unsigned char)(120 + cl), 0, (unsigned char)ax, (unsigned char)ax);
        SetDacReg((unsigned char)(141 - cl), 0, (unsigned char)ax, (unsigned char)ax);
        SetDacReg((unsigned char)(140 + cl), 0, 0, 0);

        SetDacReg((unsigned char)(150 + cl), (unsigned char)ax, (unsigned char)ax, (unsigned char)ax);
        SetDacReg((unsigned char)(171 - cl), (unsigned char)ax, (unsigned char)ax, (unsigned char)ax);
        SetDacReg((unsigned char)(170 + cl), 0, 0, 0);
    }

    /* Stato iniziale stelle */
    for (i = 0; i < NUM_STARS; i++) {
        star[i].x = 0;
        star[i].y = 0;
        star[i].col = 0;
        star[i].phase = 0;
        star[i].duration = (rand() % 20) + 1;
        star[i].active = 0;
    }

    /* Ciclo Principale */
    while (!kbhit()) {
        WaitVSync();
        WaitVSync();

        /* Gestione nascite e timer */
        for (i = 0; i < NUM_STARS; i++) {
            star[i].duration--;
            if (star[i].duration <= 0 && !star[i].active) {
                star[i].active = 1;
                star[i].phase = 0;
                star[i].col = (rand() % 6) * 30;
                star[i].x = rand() % 315;
                star[i].y = rand() % 195;
            }
        }

        /* Rendering diretto su VRAM */
        for (i = 0; i < NUM_STARS; i++) {
            if (star[i].active) {
                frame = (star[i].phase > 10) ? 1 : 0;

                for (x = 0; x < 5; x++) {
                    for (y = 0; y < 5; y++) {
                        if (BitMask[frame][x][y] > 0) {
                            color = (unsigned char)(BitMask[frame][x][y] + star[i].col + star[i].phase);
                            vram[(long)(star[i].y + y) * 320L + (star[i].x + x)] = color;
                        }
                    }
                }

                star[i].phase++;
                if (star[i].phase >= 20) {
                    star[i].active = 0;
                    star[i].duration = (rand() % 20) + 1;
                }
            }
        }
    }

    SetMode(0x03);
    return 0;
}
