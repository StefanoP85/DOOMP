#include <dos.h>
#include <conio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/nearptr.h> /* Header fondamentale per DJGPP */

#define NUM_STARS 100
#define INTENSITY 6

typedef struct {
    int x, y;
    int phase;
    int col;
    int duration;
    int active;
} TStar;

static const unsigned char BitMask[2][5][5] = {
    { {0,0,1,0,0}, {0,0,3,0,0}, {1,3,6,3,1}, {0,0,3,0,0}, {0,0,1,0,0} },
    { {0,0,6,0,0}, {0,0,3,0,0}, {6,3,1,3,6}, {0,0,3,0,0}, {0,0,6,0,0} }
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
    TStar star[NUM_STARS];
    unsigned char *vram;
    int i, frame, x, y, cl, ax;
    unsigned char color;

    /* Abilita i puntatori "near" per accedere alla RAM DOS a 16-bit */
    if (!__djgpp_nearptr_enable()) {
        return 1; /* Errore di protezione memoria */
    }

    /* Indirizzo della VRAM = Base DOS (0) + 0xA0000 */
    vram = (unsigned char *)(__djgpp_conventional_base + 0xA0000L);

    srand((unsigned)time(NULL));
    SetMode(0x13);

    /* Inizializzazione DAC VGA */
    for (cl = 1; cl <= 9; cl++) {
        ax = INTENSITY * cl;
        SetDacReg(cl, ax, 0, 0);       SetDacReg(21 - cl, ax, 0, 0); SetDacReg(20 + cl, 0, 0, 0);
        SetDacReg(30 + cl, 0, ax, 0);  SetDacReg(51 - cl, 0, ax, 0); SetDacReg(50 + cl, 0, 0, 0);
        SetDacReg(6 + cl, 0, 0, ax);   SetDacReg(81 - cl, 0, 0, ax); SetDacReg(80 + cl, 0, 0, 0);
        SetDacReg(90 + cl, ax, ax, 0); SetDacReg(111 - cl, ax, ax, 0);SetDacReg(110 + cl, 0, 0, 0);
        SetDacReg(120 + cl, 0, ax, ax);SetDacReg(141 - cl, 0, ax, ax);SetDacReg(140 + cl, 0, 0, 0);
        SetDacReg(150 + cl, ax, ax, ax);SetDacReg(171 - cl, ax, ax, ax);SetDacReg(170 + cl, 0, 0, 0);
    }

    for (i = 0; i < NUM_STARS; i++) {
        star[i].x = 0; star[i].y = 0; star[i].col = 0; star[i].phase = 0;
        star[i].duration = (rand() % 20) + 1;
        star[i].active = 0;
    }

    while (!kbhit()) {
        WaitVSync();
        WaitVSync();

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

        for (i = 0; i < NUM_STARS; i++) {
            if (star[i].active) {
                frame = (star[i].phase > 10) ? 1 : 0;
                for (x = 0; x < 5; x++) {
                    for (y = 0; y < 5; y++) {
                        if (BitMask[frame][x][y] > 0) {
                            color = (unsigned char)(BitMask[frame][x][y] + star[i].col + star[i].phase);
                            /* Scrittura diretta consentita grazie a __djgpp_nearptr_enable */
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

    /* Disabilita la protezione al termine */
    __djgpp_nearptr_disable();
    return 0;
}
