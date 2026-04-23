ASM_SRC		= $(wildcard *.S)
C_SRC       = $(wildcard *.c)
OBJ		    = $(ASM_SRC:.S=.o) $(C_SRC:.c=.o)

all: $(OBJ)
	# rm -rf $(TARGET)

%.o: %.S
	$(RISCV_GCC) $(RISCV_GCC_OPTS) -c $<

%.o: %.c
	$(RISCV_GCC) $(RISCV_GCC_OPTS) -c $<

clean:
	rm -f *.o *.asm *.elf *.bin
