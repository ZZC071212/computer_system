ASM_SRC := $(wildcard *.S)
C_SRC := $(wildcard *.c)
ASM_OBJ :=$(ASM_SRC:.S=.o)
C_OBJ :=$(C_SRC:.c=.o)
OBJ := $(ASM_OBJ) $(C_OBJ)

.PHONY: all clean

all: $(OBJ)

clean:
	rm -f *.o

%.o: %.S
	$(GCC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -c $<
%.o: %.c
	$(GCC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -c $<