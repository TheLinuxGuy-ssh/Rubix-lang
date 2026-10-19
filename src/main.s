.intel_syntax noprefix

.include "src/constants.s"

.section .bss
.align 16
src_buffer:       .skip SRC_BUF_SIZE
src_len:          .quad 0

.align 16
tokens_buf:       .skip (MAX_TOKENS * TOKEN_SIZE)
tok_count:        .quad 0
cur_tok_idx:      .quad 0
cur_line:         .quad 0

.align 16
out_buffer:       .skip OUT_BUF_SIZE
out_len:          .quad 0

.align 16
rodata_buffer:    .skip RODATA_BUF_SIZE
rodata_len:       .quad 0
str_label_count:  .quad 0
label_counter:    .quad 0

.align 16
symtab_buf:       .skip (MAX_SYMBOLS * SYMBOL_SIZE)
sym_count:        .quad 0
cur_stack_offset: .quad 0
fn_params_buf:    .skip (MAX_PARAMS * 16)

# Dynamic function frame sizing buffers
.align 16
fn_body_buf:      .skip FN_BODY_BUF_SIZE
fn_body_len:      .quad 0
emit_buf_ptr:     .quad 0
emit_len_ptr:     .quad 0
emit_max_size:    .quad 0

# Scope stack for block scoping
.align 16
scope_stack:      .skip (64 * 16)
scope_depth:      .quad 0
max_stack_offset: .quad 0

# Break/continue label stacks for loop tracking
.align 16
break_label_stack: .skip (64 * 8)   # 64 levels * 8 bytes per label
continue_label_stack: .skip (64 * 8) # 64 levels * 8 bytes per label
loop_depth:       .quad 0

# For loop label storage (to avoid register clobbering)
for_start_label:  .quad 0
for_step_label:   .quad 0
for_end_label:    .quad 0
for_step_start:   .quad 0
for_step_end:     .quad 0

# User defined function tracking (up to 1,024 functions)
.align 16
user_fn_buf:      .skip (MAX_USER_FNS * 16)
user_fn_count:    .quad 0

# Duplicate main tracking
main_defined:     .quad 0

# Per-function label base to avoid label collisions across functions
fn_label_base:    .quad 0

# Global label counter - increments for every label, guarantees uniqueness
label_ctr:        .quad 0

# Import module tracking
.align 16
imported_files_buf: .skip (MAX_IMPORTS * 256)
imported_count:     .quad 0

.section .text
.include "src/strings.s"
.include "src/io.s"
.include "src/codegen.s"
.include "src/symtab.s"
.include "src/lexer.s"
.include "src/parser.s"

.section .text
.global _start
_start:
    # Kernel places argc at [rsp], argv[0] at [rsp + 8], argv[1] at [rsp + 16]...
    mov r12, [rsp]          # argc
    cmp r12, 2
    jl .L_usage_err

    mov r13, [rsp + 16]     # argv[1]: input file path

    # Check for argv[2]: output file path
    cmp r12, 3
    jl .L_use_default_out
    mov r14, [rsp + 24]     # argv[2]
    jmp .L_have_out_file

.L_use_default_out:
    lea r14, [default_out_file]

.L_have_out_file:
    # 1. Read source file with recursive multi-file module imports
    mov rdi, r13
    call load_source_with_imports

    # 2. Run Lexer
    call lex_all

    # 3. Run Parser & Code Generator
    call parse_program

    # 4. Write output assembly file
    mov rdi, r14
    lea rsi, [out_buffer]
    mov rdx, [out_len]
    call write_file

    # 5. Print compilation success summary
    lea rdi, [msg_success_compiled]
    call print_msg

    mov rdi, r14
    call print_msg

    lea rdi, [msg_success_end]
    call print_msg

    # Exit cleanly with 0
    mov rax, SYS_EXIT
    xor rdi, rdi
    syscall

.L_usage_err:
    lea rdi, [msg_usage]
    call print_err
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

.section .data
default_out_file:     .string "out.s"
msg_usage:            .string "Usage: rubix_compiler <source.ix> [output.s]\n"
msg_success_compiled: .string "Rubix: successfully compiled -> "
msg_success_end:      .string "\n"
