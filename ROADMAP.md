# Rubix Engineering Roadmap & Community Issues

This document outlines the major architectural milestones and open issues where contributors can make a direct impact. Each issue includes target files, design specifications, and acceptance criteria.

---

### Issue 1: Complete the Self-Hosting Compiler (`rubixc_bootstrap/`)
* **Difficulty:** Advanced
* **Area:** Language Design & Self-Hosting
* **Target Files:** `rubixc_bootstrap/src/*.ix`
* **Description:**
  Rubix's primary compiler is currently written in ~3,500 lines of x86-64 assembly (`src/*.s`). The self-hosted compiler in `rubixc_bootstrap/` is an early prototype (~1,000 lines).
* **Goal:**
  Expand the lexer, parser, and code emitter in `rubixc_bootstrap/src/` to support all language features (structs, arrays, floats, modules) so that Rubix can compile itself into native machine code.
* **Acceptance Criteria:**
  - `rubixc_bootstrap` compiles all files in `examples/*.ix`.
  - Self-hosting milestone test passes natively.

---

### Issue 2: Native Mach-O Support for macOS (`-t macos`)
* **Difficulty:** Intermediate
* **Area:** Platform Support / Binary Formats
* **Target Files:** `src/codegen.s`, `src/main.s`, `lib/runtime.s`, `rubixc`
* **Description:**
  Rubix currently produces Linux ELF64 and Windows PE64 executables. While Darwin syscall stubs exist in `lib/runtime.s`, the compiler still emits Linux ELF assembly syntax that macOS `clang`/`ld64` rejects.
* **Goal:**
  Add a `-t macos` target flag in `src/main.s` and `rubixc` that emits:
  1. Mach-O segment and section declarations (`__TEXT,__text`).
  2. Darwin 64-bit syscall offset (`0x2000000 | sys_id`).
  3. Proper symbol leading underscores (e.g., `_main` instead of `_start` or `main`).
* **Acceptance Criteria:**
  - Running `./rubixc -t macos examples/01_hello.ix -o hello_mac` produces an executable that links and runs on macOS.

---

### Issue 3: Direct ELF64 Emission (Eliminate GNU `as` & `ld`)
* **Difficulty:** Advanced
* **Area:** Toolchain Independence
* **Target Files:** `src/codegen.s`, `src/main.s`
* **Description:**
  Currently, `rubixc` emits `.s` assembly text into memory and invokes the external GNU `as` and `ld` utilities to generate binary executables.
* **Goal:**
  Implement a direct ELF64 object/executable writer directly in assembly:
  1. Write ELF Header (`\x7fELF`, 64-bit, little-endian, `ET_EXEC`).
  2. Write Program Headers (`PT_LOAD` segments for `.text`, `.rodata`).
  3. Encode machine instructions directly into bytes rather than text strings.
* **Acceptance Criteria:**
  - Rubix compiles source `.ix` files into runnable Linux executables on a minimal Linux installation that does not have `binutils`, `as`, or `ld` installed.

---

### Issue 4: BSD Sockets API in Pure Assembly Runtime
* **Difficulty:** Intermediate
* **Area:** Standard Library / Networking
* **Target Files:** `lib/runtime.s`, `src/parser.s`
* **Description:**
  To build network services, web servers, and connected desktop tools, Rubix needs native socket primitives without linking `libc`.
* **Goal:**
  Add pure assembly syscall wrappers in `lib/runtime.s`:
  - `socket(domain, type, protocol) -> fd` (Linux `sys_socket` = 41)
  - `connect(fd, sockaddr_ptr, addrlen) -> status` (Linux `sys_connect` = 42)
  - `bind(fd, sockaddr_ptr, addrlen) -> status` (Linux `sys_bind` = 49)
  - `listen(fd, backlog) -> status` (Linux `sys_listen` = 50)
  - `accept(fd, sockaddr_ptr, addrlen_ptr) -> client_fd` (Linux `sys_accept` = 43)
  - `send(fd, buf, len, flags) -> bytes_sent` (Linux `sys_sendto` = 44)
  - `recv(fd, buf, len, flags) -> bytes_received` (Linux `sys_recvfrom` = 45)
* **Acceptance Criteria:**
  - An example `examples/19_http_server.ix` that starts a minimal HTTP server responding "HTTP/1.1 200 OK" to curl requests.

---

### Issue 5: Length-Prefixed Arrays & Runtime Bounds Checking
* **Difficulty:** Intermediate
* **Area:** Memory Safety
* **Target Files:** `src/parser.s`, `lib/runtime.s`
* **Description:**
  Array indexing currently emits un-clamped base-index addressing: `mov rax, [rbx + rax * 8]`. Negative indices or out-of-range indices silently read/write arbitrary heap or stack memory.
* **Goal:**
  1. When allocating dynamic arrays, allocate 8 extra bytes for a length header: `[len: u64][elem_0][elem_1]...`.
  2. On array index read/write `arr[i]`:
     - Compare index `i` against array length `[arr - 8]`.
     - If index `< 0` or index `>= length`, trigger `__rubix_bounds_error` with file/line diagnostics.
* **Acceptance Criteria:**
  - Out-of-bounds indexing prints a clean error: `Rubix Runtime Error: index out of bounds` instead of silent memory corruption.

---

### Issue 6: ARM64 (AArch64) Instruction Generation Backend
* **Difficulty:** Advanced
* **Area:** Multi-Architecture Support
* **Target Files:** `src/codegen.s`, `src/parser.s`
* **Description:**
  Rubix currently compiles exclusively to x86-64 machine instructions.
* **Goal:**
  Add an AArch64 code emission mode (`--target=arm64`):
  - Map registers: `x0-x7` for parameters, `x8` for syscalls, `sp` and `fp` for stack.
  - Emit ARM64 instructions: `ldr`, `str`, `add`, `sub`, `mul`, `sdiv`, `svc #0`.
* **Acceptance Criteria:**
  - Rubix-compiled binaries run natively on Raspberry Pi (Linux ARM64) and Apple Silicon.
