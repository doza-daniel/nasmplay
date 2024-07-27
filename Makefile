BIN=hello

${BIN}: ${BIN}.o
	ld -m elf_i386 $< -o $@

${BIN}.o: ${BIN}.s
	nasm -f elf $< -o $@

.PHONY: clean

clean:
	rm -rf ${BIN} ${BIN}.o
