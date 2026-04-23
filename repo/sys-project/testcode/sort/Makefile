export
	RISCV_PREFIX ?= riscv64-unknown-elf-
	RISCV_GCC ?= $(RISCV_PREFIX)gcc
	RISCV_GCC_OPTS ?= -march=rv64i_zicsr -mabi=lp64 -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles
	RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump -Mno-aliases -D
	RISCV_OBJCOPY ?= $(RISCV_PREFIX)objcopy -O binary
	RISCV_LD  	  ?= $(RISCV_PREFIX)ld

gen:
	make -C ../rom

	$(RISCV_GCC) $(RISCV_GCC_OPTS) div.S -c -o div.o
	$(RISCV_GCC) $(RISCV_GCC_OPTS) muldi3.S -c -o muldi3.o

	$(RISCV_GCC) $(RISCV_GCC_OPTS) sort.c -c -o sort.o
	$(RISCV_GCC) $(RISCV_GCC_OPTS) loader.S -c -o loader.o

	$(RISCV_LD) -T link.ld sort.o loader.o div.o muldi3.o -o sort.elf
	$(RISCV_LD) -T testcase.ld sort.o loader.o div.o muldi3.o -o testcase.elf

	$(RISCV_OBJDUMP) sort.elf > sort.asm
	${RISCV_OBJCOPY} sort.elf tmp.bin
	od -v -An -tx8 tmp.bin > sort.hex

	rm tmp.bin sort.o loader.o div.o muldi3.o

clean:
	rm -f *.o *.elf *.asm *.hex