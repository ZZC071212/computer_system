export
	RISCV_PREFIX ?= riscv64-unknown-elf-
#	RISCV_PREFIX ?= riscv64-unknown-linux-gnu-
	RISCV_GCC ?= $(RISCV_PREFIX)gcc
	RISCV_GCC_OPTS ?= -march=rv64i_zicsr -mabi=lp64 -mcmodel=medany -fvisibility=hidden -nostdlib \
		-nostartfiles -DNOBRANCH -ggdb
	RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump -S -j .sbi.text -j .text
	RISCV_OBJCOPY ?= $(RISCV_PREFIX)objcopy -O binary
	RISCV_LD  ?= $(RISCV_PREFIX)ld

ELF         = mini_sbi.elf
BIN         = mini_sbi.bin
ASM 		= mini_sbi.asm
HEX			= mini_sbi.hex

all: sim

sim:
	make -C kernel
	make -C mini_sbi
	make -C rom
	$(RISCV_GCC) $(RISCV_GCC_OPTS) -flto ./mini_sbi/*.o ./kernel/lib/*.o \
		./kernel/arch/riscv/kernel/*.o -T link.ld -o $(ELF)
	$(RISCV_GCC) $(RISCV_GCC_OPTS) -flto ./mini_sbi/*.o ./kernel/lib/*.o \
		./kernel/arch/riscv/kernel/*.o ./rom/*.o \
		-T testcase.ld -o testcase.elf
	$(RISCV_OBJCOPY) $(ELF) tmp
	od -w8 -vAn -tx8 tmp > tmp.hex
	sed 's/@1/@0/g' tmp.hex > $(HEX)
	rm -f tmp tmp.hex
	$(RISCV_OBJDUMP) $(ELF) > $(ASM)

board:
	make -C compress_elf
	make -C kernel
	make -C mini_sbi
	$(RISCV_GCC) $(RISCV_GCC_OPTS) ./mini_sbi/*.o ./kernel/lib/*.o \
		./kernel/arch/riscv/kernel/*.o -T link.ld -o $(ELF)
	$(RISCV_OBJCOPY) $(ELF) tmp
	od -w8 -vAn -tx8 tmp > $(HEX)
	rm -f tmp
	$(RISCV_OBJDUMP) $(ELF) > $(ASM)
	./compress_elf/compress_elf $(ELF) elf.hex elf.bin
	make -C bootload

clean:
	make -C kernel clean
	make -C mini_sbi clean
	make -C rom clean
	make -C bootload clean
	make -C compress_elf clean
	rm -f *.asm *.hex *.elf *.o *.bin
