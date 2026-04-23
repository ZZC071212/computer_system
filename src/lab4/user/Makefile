CPPFLAGS += -I$(CURDIR)/include

C_SRC := $(wildcard src/*.c) $(wildcard ../lib/*.c)
ASM_SRC := $(wildcard src/*.S) $(wildcard ../lib/*.S)
OBJ := $(C_SRC:.c=.o) $(ASM_SRC:.S=.o)

.PHONY: all clean

all:
	$(MAKE) -C ../lib all
	$(MAKE) -C src all
	$(MAKE) uapp.o uapp.asm uapp.map

uapp.o: uapp.bin
	$(GCC) $(CFLAGS) -c uapp.S

uapp.elf: $(OBJ)
	$(LD) -T uapp.lds -o $@ $(OBJ)

uapp.bin: uapp.elf
	$(OBJCOPY) $< -O binary $@

uapp.asm: uapp.elf
	$(OBJDUMP) -S $< > $@

uapp.map: uapp.elf
	$(NM) $< > $@

clean:
	$(MAKE) -C src clean
	rm -f *.o *.d *.elf *.bin *.asm *.map
