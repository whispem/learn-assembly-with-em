AS      = nasm
ASFLAGS = -f elf64
LD      = ld

SRCS := $(wildcard */*.asm)
BINS := $(addprefix bin/,$(basename $(notdir $(SRCS))))

vpath %.asm $(sort $(dir $(SRCS)))

all: $(BINS)

bin/%: %.asm | bin
	$(AS) $(ASFLAGS) $< -o $@.o
	$(LD) $@.o -o $@
	@rm -f $@.o

bin:
	@mkdir -p bin

clean:
	rm -rf bin

.PHONY: all clean
