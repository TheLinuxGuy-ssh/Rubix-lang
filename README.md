# Rubix Programming Language (`.ix`)

<p align="center">
  <img src="assets/Logo.png" alt="Rubix Logo" width="760" />
</p>

<p align="center">
  <img src="assets/rubix-ix-file-icon.svg" alt="Rubix .ix File Icon" width="84" />
</p>

<p align="center">
  <strong>The 100% Pure x86-64 Assembly Systems Language</strong><br>
  <em>Direct silicon execution breaking the OS barrier across Linux, Windows, and macOS with zero libc dependencies.</em>
</p>

```
   ██████╗ ██╗   ██╗██████╗ ██╗██╗  ██╗
   ██╔══██╗██║   ██║██╔══██╗██║╚██╗██╔╝
   ██████╔╝██║   ██║██████╔╝██║ ╚███╔╝ 
   ██╔══██╗██║   ██║██╔══██╗██║ ██╔██╗ 
   ██║  ██║╚██████╔╝██████╔╝██║██╔╝ ██╗
   ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝╚═╝  ╚═╝
```

> **A sovereign systems programming language whose entire compiler is written from scratch in 100% pure x86-64 assembly.**  
> **Zero libc. Zero C. Zero Python. Zero LLVM. Zero WASM. Zero Virtual Machines.**  
> **Direct native execution breaking the OS barrier across Linux, Windows, and macOS.**

---

## 📄 The `.ix` File Format & Identity

<p align="left">
  <img src="assets/rubix-ix-file-icon.svg" alt="Rubix .ix File Icon" width="80" align="left" style="margin-right: 18px; margin-bottom: 12px;" />
  Every Rubix program is authored in the sovereign <strong><code>.ix</code></strong> file format. Designed for pure systems-level performance, <code>.ix</code> source files are converted directly to native machine code by <code>rubix_compiler</code> and orchestrated via the <code>./rubixc</code> driver. The official <code>.ix</code> file badge reflects Rubix's sharp geometric lineage and uncompromising fidelity to native hardware.
</p>
<br clear="left"/>

---

## ⚡ Highlights

- **Pure Assembly Compiler**: The compiler itself is written completely in GNU x86-64 assembly (`as` + `ld`). No external dependencies or runtime libraries are needed.
- **Tiny & Instant**: The compiler binary is only **~42 KB**, with sub-millisecond compilation times.
- **Zero OS Barrier (Universal Multi-OS Architecture)**:
  - Compiles `.ix` code into standalone native executables equipped with an adaptive runtime.
  - **No WASM, No Virtual Machine**: Architected to execute directly on bare silicon across **Linux, Windows, and macOS** (verified on Linux x86-64).
  - **Dynamic Host OS Detection**: Automatically determines the host OS at binary entry (`rubix_host_os`).
  - **In-Memory Windows Resolver**: Walks the Windows PEB (`gs:[0x60]`) in pure assembly to resolve `kernel32.dll` API exports without external import tables.
- **Rich Language Features**:
  - `for` and `while` loops with `break`, `continue`, and arbitrary nesting
  - Dynamic heap allocation (`alloc`, `free`) using Linux `sys_mmap` or Windows `VirtualAlloc`
  - Dynamic array indexing (`arr[i] = val`) and array literal syntax (`[1, 2, 3]`)
  - First-class function calls with unbounded parameter counts (>6 parameters supported via AMD64 ABI registers + stack spills)
  - Multi-file module imports (`import "lib.ix"`)
  - Embedded standard library: File I/O, string manipulation, and math routines
  - Hardware-trapped integer overflow detection (`jo __rubix_overflow_error`)
  - Rust-style compiler error diagnostics with source code snippets and caret pointers (`^`)

---

## 🏗️ Compiler Architecture

```
                       +-----------------------------------+
                       |    Rubix Source Code (.ix)        |
                       +-----------------------------------+
                                         │
                                         ▼
+---------------------------------------------------------------------------------+
|                                 rubix_compiler                                  |
|                                                                                 |
|  [Lexer (src/lexer.s)]                                                          |
|    • Tokenizer converting source buffers into structured 32-byte token records  |
|                                         │                                       |
|                                         ▼                                       |
|  [Parser (src/parser.s)]                                                        |
|    • Recursive descent parser with Pratt-style operator precedence              |
|    • Handles scopes, statements, expressions, control flow, loops & imports     |
|                                         │                                       |
|                                         ▼                                       |
|  [Symbol Table (src/symtab.s)]                                                  |
|    • Lexical block scoping (up to 64 depth) and stack offset calculation       |
|    • Variable redeclaration guards and symbol lookup                            |
|                                         │                                       |
|                                         ▼                                       |
|  [Code Generator (src/codegen.s)]                                               |
|    • Emits native x86-64 GNU assembly (.intel_syntax noprefix)                  |
|    • Generates .rodata string literals & links embedded assembly runtime        |
+---------------------------------------------------------------------------------+
                                         │
                                         ▼
                       +-----------------------------------+
                       |      x86-64 Assembly (.s)         |
                       +-----------------------------------+
                                         │  (as + ld)
                                         ▼
                       +-----------------------------------+
                       |    Universal Native Executable    |
                       |  (Direct Syscalls / No C / No VM) |
                       +-----------------------------------+
                                         │
                 ┌───────────────────────┼───────────────────────┐
                 ▼                       ▼                       ▼
           [Host: Linux]          [Host: Windows]          [Host: macOS]
           Direct Linux           Dynamic kernel32        Direct Darwin
             Syscalls            PEB Export Resolver         Syscalls
```

---

## 📁 Repository Layout

```
project 2.0/
├── Makefile              # Compiler build automation
├── rubixc                # User-friendly compiler & runner script
├── test.sh               # Complete 14-test verification suite
├── src/                  # 100% Pure x86-64 Assembly Source Code
│   ├── main.s            # Entry point (_start), command line parser, file pipeline
│   ├── constants.s       # Linux syscall numbers, token types, buffer capacity limits
│   ├── strings.s         # String length, compare, copy, and integer conversion routines
│   ├── io.s              # Raw kernel file I/O & Rust-style diagnostic error reporting
│   ├── lexer.s           # Tokenizer & scanner (keywords, identifiers, literals, operators)
│   ├── symtab.s          # Lexical scope stack, symbol table buffer, and stack offsets
│   ├── codegen.s         # Instruction emitters, rodata manager, and standard library runtime
│   └── parser.s          # Recursive-descent parser, operator precedence, and loop frames
└── examples/             # Test & Demonstration Programs
    ├── 01_hello.ix       # Hello World string literal output
    ├── 02_arithmetic.ix  # Expressions, operator precedence, and variables
    ├── 03_control_flow.ix# While loops, if-else chains, and reassignments
    ├── 04_functions.ix   # Multi-parameter functions and recursive Fibonacci
    ├── 05_prime_numbers.ix# Prime number sieve demonstrating nested logic
    ├── 06_arrays.ix      # Dynamic heap allocation, indexing, and array literals
    ├── 07_types_and_logic.ix # Booleans, chars, logical operators (&&, ||, !), optional types
    ├── 08_many_params.ix # Unbounded 8-parameter function caller/callee stack passing
    ├── 09_modules.ix     # Multi-file module import system
    ├── 10_safe_math.ix   # Hardware integer overflow detection trap
    ├── 11_for_loops.ix   # Complete for loops (break, continue, nesting, dynamic arrays)
    ├── 12_stdlib.ix      # Embedded stdlib (File I/O, string manipulation, math routines)
    ├── large_system_test.ix # 200-element Quicksort, 4x4 matrix multiplication, and multi-file math
    └── comprehensive_large_test.ix # Grand stress test: 1,000-element Sieve, binary search, prefix sums
```

---

## 📖 Language Syntax & Capabilities

### 1. Variables & Basic Types
Rubix is statically typed with 64-bit integer primitives (`int`, `bool`, `char`). Type annotations are optional:
```ix
let count = 10;                # Inferred 64-bit int
let flag: bool = true;         # Explicit bool
let symbol: char = 'R';        # Character literal
```

### 2. Operators & Safe Arithmetic
Supports full precedence: `()`, `!`, `-` (unary), `*`, `/`, `%`, `+`, `-`, `<`, `<=`, `>`, `>=`, `==`, `!=`, `&&`, `||`.
All arithmetic operations detect hardware overflow and terminate safely:
```ix
let x = (10 + 5) * 2 - 4 / 2;  # Precedence respected
let valid = (x > 10) && (!flag || x < 100);
```

### 3. For & While Loops with `break` and `continue`
`for` loops support `<init>; <cond>; <step>`, empty clauses, nested loops with isolated stack frames, and control jumps:
```ix
for (let i = 0; i < 20; i = i + 1) {
    if (i >= 15) {
        break;      # Exits loop early
    }
    if (i % 2 == 0) {
        continue;   # Skips to step clause (i = i + 1)
    }
    print(i);       # Prints 1, 3, 5, 7, 9, 11, 13
}
```

### 4. Dynamic Heap Memory & Arrays
Direct interaction with the Linux memory manager via `alloc` and `free` (`mmap`/`munmap`):
```ix
# Dynamic array allocation
let size = 100;
let arr = alloc(size * 8);

for (let i = 0; i < size; i = i + 1) {
    arr[i] = i * i;
}
print(arr[9]);      # Prints 81
free(arr, size * 8);

# Array literal initialization
let primes = [2, 3, 5, 7, 11, 13, 17];
print(primes[4]);   # Prints 11
```

### 5. Functions & Unbounded Parameters
Functions adhere to the AMD64 System V ABI. When more than 6 arguments are supplied, additional arguments are seamlessly spilled and retrieved from the stack frame:
```ix
fn compute_sum(a: int, b: int, c: int, d: int, e: int, f: int, g: int, h: int): int {
    return a + b + c + d + e + f + g + h;
}

fn main(): int {
    let sum = compute_sum(1, 2, 3, 4, 5, 6, 7, 8);
    print(sum);      # Prints 36
    return 0;
}
```

### 6. Multi-File Module System
Split code across multiple files with automatic cycle prevention and deduplication:
```ix
import "examples/math_lib.ix";

fn main(): int {
    let result = compute_cube(5);
    print(result);   # Prints 125
    return 0;
}
```

### 7. Embedded Standard Library Reference

Every Rubix binary includes a built-in standard library with zero external runtime requirements:

| Module | Function | Description |
| :--- | :--- | :--- |
| **I/O** | `print(val)` | Prints a 64-bit signed integer followed by a newline |
| | `print_str(expr)` | Prints a static or dynamic null-terminated string |
| | `print_char(c)` | Prints a single ASCII character |
| **File I/O** | `file_open(path, flags, mode)` | Calls Linux `sys_open` (syscall 2) |
| | `file_read(fd, buf, count)` | Calls Linux `sys_read` (syscall 0) |
| | `file_write(fd, buf, count)` | Calls Linux `sys_write` (syscall 1) |
| | `file_close(fd)` | Calls Linux `sys_close` (syscall 3) |
| **Strings** | `str_len(s)` | Returns length of null-terminated string |
| | `str_cmp(s1, s2)` | Compares strings (`0` if equal) |
| | `str_copy(dst, src)` | Copies source string into destination buffer |
| | `str_cat(dst, src)` | Concatenates source onto destination buffer |
| | `puts(s)` | Writes null-terminated string to stdout |
| **Math** | `math_abs(x)` | Absolute value |
| | `math_min(a, b)` | Minimum of two integers |
| | `math_max(a, b)` | Maximum of two integers |
| | `math_pow(base, exp)` | Integer exponentiation ($base^{exp}$) |
| | `math_sqrt(n)` | Integer square root ($\lfloor\sqrt{n}\rfloor$) |
| **Memory** | `alloc(bytes)` | Allocates memory via `sys_mmap` (syscall 9) |
| | `free(ptr, bytes)` | Releases memory via `sys_munmap` (syscall 11) |

### 8. Universal Multi-OS Architecture (Linux, Windows, macOS)
Rubix binaries break the operating system barrier by incorporating an adaptive native runtime:
- **Multi-OS Entry Points**: Defines `_start`, `_start_linux`, `_start_windows`, and `_start_macos`. The host kernel's loader jumps directly to its corresponding entry vector.
- **Dynamic Host OS Detection**: Automatically sets `rubix_host_os` (1 = Linux, 2 = Windows, 3 = macOS).
- **Universal System Dispatchers**:
  - `__rubix_sys_write`: Linux `sys_write` / Windows `WriteFile` / macOS `0x2000004`
  - `__rubix_sys_read`: Linux `sys_read` / Windows `ReadFile` / macOS `0x2000003`
  - `__rubix_sys_open`: Linux `sys_open` / macOS `0x2000005`
  - `__rubix_sys_close`: Linux `sys_close` / macOS `0x2000006`
  - `__rubix_sys_mmap`: Linux `sys_mmap` / Windows `VirtualAlloc` / macOS `0x20000c5`
  - `__rubix_sys_munmap`: Linux `sys_munmap` / Windows `VirtualFree` / macOS `0x2000049`
  - `__rubix_sys_exit`: Linux `sys_exit` / Windows `ExitProcess` / macOS `0x2000001`
- **Windows PEB / kernel32 Dynamic Resolver**: On Windows x64, dynamically walks the Process Environment Block (`gs:[0x60]`), locates `kernel32.dll`, and resolves API exports without relying on external DLL import tables.

> [!NOTE]
> **Platform & Cross-Compilation**: Rubix natively targets both Linux ELF64 and Windows PE64 (`.exe`) platforms directly from GNU `ld` without external dependencies. The multi-OS entry vectors and Windows PEB resolver are verified on host systems.

---

## 💎 Advanced Systems Capabilities

### 1. Floating-Point Numbers (`f64` / Double Precision) & Type System
Full IEEE-754 64-bit double-precision support with type-aware symbol table resolution, native SSE2 machine code emission (`addsd`, `subsd`, `mulsd`, `divsd`), and polymorphic `print()`:
```rubix
let pi: float = 3.141592;
let rad = 2.5;

// Native SSE2 arithmetic (+, -, *, /) and mixed int-float operations
let area = pi * rad * rad;
print(area); // 19.634950 (automatically dispatches to float formatting)

// Typed function parameters and return types
fn hypot(a: float, b: float): float {
    return a * a + b * b;
}
```
Built-in math routines (`float_add`, `float_sub`, `float_mul`, `float_div`, `float_to_int`, `int_to_float`, `print_float`) remain fully available for backwards compatibility.

### 2. Struct Declarations & Dynamic Instances
User-defined compound data structures with compile-time offset layout, heap instantiation, and member access/mutation:
```rubix
struct Vector3 {
    x: int,
    y: int,
    z: int
}

fn main() {
    let v = Vector3 { x: 10, y: 20, z: 30 };
    print(v.x);
    v.z = v.x + v.y;
    print(v.z); // 30
    free(v, 24);
    return 0;
}
```

### 3. DWARF Debug Information (`gdb` / `lldb`)
The compiler generates native DWARF `.file` and `.loc` debug directives mapping machine instructions directly back to `.ix` source lines:
```bash
./rubixc -g examples/01_hello.ix -o hello_dbg
gdb ./hello_dbg
# (gdb) break 3
# (gdb) run
# Breakpoint 1, main () at examples/01_hello.ix:3
```

### 4. Cross-OS Compilation (Windows PE64)
Produce real 64-bit Windows console executables directly on Linux:
```bash
./rubixc -t windows examples/01_hello.ix -o hello.exe
file hello.exe
# hello.exe: PE32+ executable for MS Windows 5.02 (console), x86-64
```

### 5. Separate Compilation & Static Object Linking
Compile individual `.ix` files into ELF relocatable objects (`.o`) and link multiple units:
```bash
./rubixc -c module1.ix -o module1.o
./rubixc -c module2.ix -o module2.o
./rubixc module1.o module2.o -o my_app
```

---

## 🛠️ Rich Diagnostic Error Reporting

Rubix produces clear, informative compile-time diagnostics pointing directly to the offending token:

```
Rubix Compiler Error: Expected expression
  --> line 4
   |
 4 |     let x = ;
   | ^
```

---

## 🚀 Quickstart & Usage

### Prerequisites
- Linux OS (x86-64)
- GNU Assembler (`as`) and Linker (`ld`) (available via standard `binutils`)

### 1. Build the Compiler
```bash
make clean && make
```
Produces `rubix_compiler` and `lib/runtime.o`.

### 2. Compile and Run a Program
Use the `./rubixc` compiler driver:

```bash
# Compile and immediately run
./rubixc -r examples/15_floats.ix
./rubixc -r examples/16_structs.ix
./rubixc -r examples/17_native_floats.ix

# Compile for Windows PE64
./rubixc -t windows examples/01_hello.ix -o hello.exe

# Compile with DWARF debug info
./rubixc -g examples/01_hello.ix -o hello_dbg
```

### 3. Run the Entire Test Suite
```bash
./test.sh
```
Executes all **18** test suites verifying the compiler build, arithmetic, control flow, functions, prime algorithms, dynamic arrays, modules, loops, standard library, floats, structs, native float SSE2 operators, Windows cross-linking, and separate compilation.

---

## 📜 License

Created with precision in pure x86-64 Assembly. Free and open source.
