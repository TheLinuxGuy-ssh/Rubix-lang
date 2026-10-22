# Contributing to Rubix

Thank you for your interest in contributing to the **Rubix Language**!

Rubix is an ultra-fast, zero-dependency systems programming language whose core compiler is implemented entirely in **pure x86-64 assembly** (Intel syntax) with an embedded libc-free runtime.

---

## 🛠️ Development Setup

### Prerequisites
* **Operating System:** Linux x86-64 (or Windows via WSL2 / macOS via a Linux VM).
* **Toolchain:** Only standard GNU Binutils (`as`, `ld`) and `make`.
  ```bash
  sudo apt install build-essential git
  ```
  *(Zero C or C++ compilers required—the compiler builds directly from assembly source).*

### Build & Run Tests
```bash
# 1. Clone your fork
git clone https://github.com/<your-username>/Rubix-lang.git
cd Rubix-lang

# 2. Build the compiler from assembly
make

# 3. Run the complete test suite
./test.sh
```
All tests must pass before opening a Pull Request.

---

## 🏛️ Codebase Architecture

```
Rubix-lang/
├── src/                      # Core x86-64 Assembly Compiler
│   ├── main.s                # Entry point, CLI flags, global buffers
│   ├── constants.s           # Token constants, type IDs, static buffer sizes
│   ├── lexer.s               # Zero-copy lexical scanner
│   ├── parser.s              # Recursive descent parser & assembly codegen
│   ├── symtab.s              # Scoped symbol table & type tracking
│   ├── structs.s             # Struct parsing, field offset calculations
│   └── codegen.s             # Buffer emission, .rodata literals, runtime embedding
├── lib/
│   └── runtime.s             # Standalone libc-free assembly runtime (Arena allocator, syscalls, Windows PEB)
├── rubixc_bootstrap/         # Self-hosting compiler prototype written in Rubix (.ix)
├── examples/                 # Language feature examples and regression test scripts
├── Makefile                  # Build definitions
└── test.sh                   # Comprehensive test runner
```

---

## 📜 Core Guidelines

1. **Zero Libc / Zero External C Dependencies:**
   The core compiler and runtime must never link against `libc`, `crt`, or any C library. System interaction must stay strictly pure assembly syscalls (Linux/Darwin) or PEB-resolved Windows APIs.
2. **Sub-Millisecond Speed & Small Binary Footprint:**
   Keep the compiler binary under 60 KB. Compilation speed should remain under 5 milliseconds.
3. **Deterministic Assembly:**
   Always write clean, commented Intel syntax (`.intel_syntax noprefix`).
4. **Test Everything:**
   Any bug fix or new feature must include a new test file in `examples/` and an entry in `test.sh`.

---

## 🚀 Open Roadmap & Issues

Check out [ROADMAP.md](ROADMAP.md) for a list of prioritized features and issues currently open for contribution.
