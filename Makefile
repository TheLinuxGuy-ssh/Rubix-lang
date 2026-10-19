AS = as
LD = ld

SRCS = src/main.s \
       src/constants.s \
       src/strings.s \
       src/io.s \
       src/codegen.s \
       src/symtab.s \
       src/structs.s \
       src/lexer.s \
       src/parser.s \
       lib/runtime.s

TARGET = rubix_compiler
RUNTIME = lib/runtime.o

all: $(TARGET) $(RUNTIME)
	@echo "Build complete: $(TARGET) (pure x86-64 assembly executable for Rubix)"

$(TARGET): $(SRCS)
	$(AS) src/main.s -o rubix_compiler.o
	$(LD) rubix_compiler.o -o $(TARGET)
	rm -f rubix_compiler.o

$(RUNTIME): lib/runtime.s
	$(AS) lib/runtime.s -o $(RUNTIME)

test: all
	./test.sh

clean:
	rm -f $(TARGET) $(RUNTIME) *.o *.s 01_hello 02_arithmetic 03_control_flow 04_functions 05_prime_numbers 06_arrays 07_types_and_logic 08_many_params 09_modules 10_safe_math 15_floats 16_structs hello arith cf fn_prog prime_app

.PHONY: all test clean
