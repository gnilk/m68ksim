EXENAME          = sim

OSD_DOS          = osd_dos.c

OSDFILES         = $(OSD_DOS)
MAINFILES        = sim.cpp simulator.c
MUSASHIFILES     = m68kcpu.c m68kdasm.c
MUSASHIGENCFILES = m68kops.c m68kopac.c m68kopdm.c m68kopnz.c
MUSASHIGENHFILES = m68kops.h
MUSASHIGENERATOR = m68kmake
HELLO            = hello.bin

EXE = 
EXEPATH = ./
# EXE =
# EXEPATH = ./

.CFILES   = $(MAINFILES) $(OSDFILES) $(MUSASHIFILES) $(MUSASHIGENCFILES)
.OFILES   = $(.CFILES:%.c=%.o)

CC        = cc
WARNINGS  = -Wall -pedantic
CFLAGS    = $(WARNINGS) -I../
LFLAGS    = $(WARNINGS)

TARGET = $(EXENAME)$(EXE)

DELETEFILES = $(MUSASHIGENCFILES) $(MUSASHIGENHFILES) $(.OFILES) $(TARGET) $(MUSASHIGENERATOR)$(EXE) $(HELLO)


all: $(TARGET)

clean:
	rm -f $(DELETEFILES)

$(TARGET): $(MUSASHIGENHFILES) $(.OFILES) makefile $(HELLO)
	$(CC) -o $@ $(.OFILES) $(LFLAGS)

$(HELLO): hello.s
	vasmm68k_mot -phxass -m68060 -Fbin hello.s -o hello.bin
	
$(MUSASHIGENCFILES) $(MUSASHIGENHFILES): $(MUSASHIGENERATOR)$(EXE)
	$(EXEPATH)$(MUSASHIGENERATOR)$(EXE)

$(MUSASHIGENERATOR)$(EXE):  $(MUSASHIGENERATOR).c
	$(CC) -o  $(MUSASHIGENERATOR)$(EXE)  $(MUSASHIGENERATOR).c
