.intel_syntax noprefix

.text

# Target buffer redirection for dynamic stack allocation
emit_to_out:
    lea rax, [out_buffer]
    mov [emit_buf_ptr], rax
    lea rax, [out_len]
    mov [emit_len_ptr], rax
    mov QWORD PTR [emit_max_size], OUT_BUF_SIZE
    ret

emit_to_fn:
    lea rax, [fn_body_buf]
    mov [emit_buf_ptr], rax
    lea rax, [fn_body_len]
    mov [emit_len_ptr], rax
    mov QWORD PTR [fn_body_len], 0
    mov QWORD PTR [emit_max_size], FN_BODY_BUF_SIZE
    ret

# emit_str(rdi: str_ptr, rsi: len)
emit_str:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov r12, rdi            # str_ptr
    mov r13, rsi            # len

    mov rax, [emit_len_ptr]
    mov rbx, [rax]          # current len
    lea rdx, [rbx + r13]
    cmp rdx, [emit_max_size]
    jge .L_emit_overflow

    mov rax, [emit_buf_ptr]
    lea rdi, [rax + rbx]
    mov rsi, r12
    mov rdx, r13
    call str_copy

    mov rax, [emit_len_ptr]
    add [rax], r13

    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_emit_overflow:
    lea rdi, [msg_err_emit_overflow]
    mov rsi, [cur_line]
    call compiler_panic

# emit_cstr(rdi: null-terminated str_ptr)
emit_cstr:
    push rbp
    mov rbp, rsp
    push rdi
    call str_len
    mov rsi, rax            # len
    pop rdi                 # str_ptr
    call emit_str
    mov rsp, rbp
    pop rbp
    ret

# emit_int(rax: int)
emit_int:
    push rbp
    mov rbp, rsp
    lea rdi, [tmp_emit_num]
    call int_to_str
    mov rsi, rax            # len
    lea rdi, [tmp_emit_num]
    call emit_str
    mov rsp, rbp
    pop rbp
    ret

# emit_nl()
emit_nl:
    push rbp
    mov rbp, rsp
    lea rdi, [str_newline]
    mov rsi, 1
    call emit_str
    mov rsp, rbp
    pop rbp
    ret

# Helper to append to rodata_buffer
# rodata_emit_str(rdi: str_ptr, rsi: len)
rodata_emit_str:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    mov rbx, [rodata_len]
    lea rax, [rbx + r13]
    cmp rax, RODATA_BUF_SIZE
    jge .L_rodata_overflow

    lea rdi, [rodata_buffer + rbx]
    mov rsi, r12
    mov rdx, r13
    call str_copy

    add [rodata_len], r13

    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_rodata_overflow:
    lea rdi, [msg_err_rodata_overflow]
    mov rsi, [cur_line]
    call compiler_panic

# rodata_emit_cstr(rdi: null-terminated str_ptr)
rodata_emit_cstr:
    push rbp
    mov rbp, rsp
    push rdi
    call str_len
    mov rsi, rax
    pop rdi
    call rodata_emit_str
    mov rsp, rbp
    pop rbp
    ret

# rodata_emit_int(rax: int)
rodata_emit_int:
    push rbp
    mov rbp, rsp
    lea rdi, [tmp_emit_num]
    call int_to_str
    mov rsi, rax
    lea rdi, [tmp_emit_num]
    call rodata_emit_str
    mov rsp, rbp
    pop rbp
    ret

# rodata_add_str(rdi: str_ptr, rsi: str_len) -> rax: label_id, rdx: actual_len
rodata_add_str:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi            # str_ptr
    mov r13, rsi            # str_len

    inc QWORD PTR [str_label_count]
    mov r14, [str_label_count]  # label_id

    # Emit ".LC{id}:\n    .byte "
    lea rdi, [str_lc_prefix]
    call rodata_emit_cstr
    mov rax, r14
    call rodata_emit_int
    lea rdi, [str_lc_colon]
    call rodata_emit_cstr

    xor rbx, rbx            # src index
    xor r15, r15            # actual byte count

.L_rodata_byte_loop:
    cmp rbx, r13
    jge .L_rodata_byte_done

    movzx rax, BYTE PTR [r12 + rbx]
    # Check escape character '\'
    cmp rax, '\\'
    jne .L_rodata_regular_char
    # Check if next char exists
    lea rcx, [rbx + 1]
    cmp rcx, r13
    jge .L_rodata_regular_char
    inc rbx
    movzx rax, BYTE PTR [r12 + rbx]
    cmp rax, 'n'
    je .L_rodata_esc_n
    cmp rax, 't'
    je .L_rodata_esc_t
    cmp rax, 'r'
    je .L_rodata_esc_r
    cmp rax, '0'
    je .L_rodata_esc_0
    cmp rax, '\\'
    je .L_rodata_esc_slash
    cmp rax, '"'
    je .L_rodata_esc_quote
    # Unknown escape, just output the char
    jmp .L_rodata_output_byte

.L_rodata_esc_n:
    mov rax, 10
    jmp .L_rodata_output_byte
.L_rodata_esc_t:
    mov rax, 9
    jmp .L_rodata_output_byte
.L_rodata_esc_r:
    mov rax, 13
    jmp .L_rodata_output_byte
.L_rodata_esc_0:
    mov rax, 0
    jmp .L_rodata_output_byte
.L_rodata_esc_slash:
    mov rax, 92
    jmp .L_rodata_output_byte
.L_rodata_esc_quote:
    mov rax, 34
    jmp .L_rodata_output_byte

.L_rodata_regular_char:
    # rax has char

.L_rodata_output_byte:
    push rax
    call rodata_emit_int
    lea rdi, [str_comma_space]
    call rodata_emit_cstr
    pop rax
    inc r15                 # actual length incremented
    inc rbx
    jmp .L_rodata_byte_loop

.L_rodata_byte_done:
    # Null terminator byte '0\n'
    lea rdi, [str_zero_nl]
    call rodata_emit_cstr

    mov rax, r14            # return label_id
    mov rdx, r15            # return actual string length

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# append_rodata_and_runtime()
append_rodata_and_runtime:
    push rbp
    mov rbp, rsp

    # If rodata is not empty, append section .rodata
    mov rax, [rodata_len]
    cmp rax, 0
    je .L_skip_rodata

    lea rdi, [str_sec_rodata]
    call emit_cstr
    lea rdi, [rodata_buffer]
    mov rsi, [rodata_len]
    call emit_str

.L_skip_rodata:
    # Append embedded runtime library functions
    lea rdi, [str_runtime_code]
    call emit_cstr

    mov rsp, rbp
    pop rbp
    ret

.data
str_newline:          .string "\n"
str_lc_prefix:        .string ".LC"
str_lc_colon:         .string ":\n    .byte "
str_comma_space:      .string ", "
str_zero_nl:          .string "0\n"
str_sec_rodata:       .string "\n.section .rodata\n"

msg_err_emit_overflow:   .string "Output assembly buffer overflow"
msg_err_rodata_overflow: .string "Rodata buffer overflow"

# ==============================================================================
# Rubix Arithmetic Specification:
# 64-bit signed integers in two's complement format.
# Standard CPU wrapping semantics apply to operations (add, sub, imul).
# Division and modulo include a zero-divisor runtime guard.
# ==============================================================================

# Embedded Rubix runtime library for integer & string output and error handling
# Embedded Rubix runtime library for cross-OS universal execution
str_runtime_code:
.ascii "\n# --- Rubix Built-in Universal Runtime (Linux, Windows, macOS) ---\n"
.ascii ".text\n"
.ascii ".globl __rubix_sys_write, __rubix_sys_read, __rubix_sys_open, __rubix_sys_close\n"
.ascii ".globl __rubix_sys_mmap, __rubix_sys_munmap, __rubix_sys_exit\n"
.ascii "\n"
.ascii "__rubix_sys_write:\n"
.ascii "    push rbp\n"
.ascii "    mov rbp, rsp\n"
.ascii "    cmp QWORD PTR [rubix_host_os], 2\n"
.ascii "    je .L_usw_win\n"
.ascii "    cmp QWORD PTR [rubix_host_os], 3\n"
.ascii "    je .L_usw_mac\n"
.ascii "    mov rax, 1\n"
.ascii "    syscall\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n"
.ascii ".L_usw_mac:\n"
.ascii "    mov rax, 0x2000004\n"
.ascii "    syscall\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n"
.ascii ".L_usw_win:\n"
.ascii "    sub rsp, 48\n"
.ascii "    mov rcx, [win_stdout_handle]\n"
.ascii "    mov r8, rdx\n"
.ascii "    mov rdx, rsi\n"
.ascii "    lea r9, [rsp + 40]\n"
.ascii "    mov QWORD PTR [rsp + 32], 0\n"
.ascii "    call [win_fn_WriteFile]\n"
.ascii "    mov rax, [rsp + 40]\n"
.ascii "    add rsp, 48\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n\n"
.ascii "__rubix_sys_read:\n"
.ascii "    push rbp\n"
.ascii "    mov rbp, rsp\n"
.ascii "    cmp QWORD PTR [rubix_host_os], 2\n"
.ascii "    je .L_usr_win\n"
.ascii "    cmp QWORD PTR [rubix_host_os], 3\n"
.ascii "    je .L_usr_mac\n"
.ascii "    mov rax, 0\n"
.ascii "    syscall\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n"
.ascii ".L_usr_mac:\n"
.ascii "    mov rax, 0x2000003\n"
.ascii "    syscall\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n"
.ascii ".L_usr_win:\n"
.ascii "    sub rsp, 48\n"
.ascii "    mov rcx, rdi\n"
.ascii "    mov r8, rdx\n"
.ascii "    mov rdx, rsi\n"
.ascii "    lea r9, [rsp + 40]\n"
.ascii "    mov QWORD PTR [rsp + 32], 0\n"
.ascii "    call [win_fn_ReadFile]\n"
.ascii "    mov rax, [rsp + 40]\n"
.ascii "    add rsp, 48\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n\n"
.ascii "__rubix_sys_open:\n"
.ascii "    push rbp\n"
.ascii "    mov rbp, rsp\n"
.ascii "    cmp QWORD PTR [rubix_host_os], 3\n"
.ascii "    je .L_uso_mac\n"
.ascii "    mov rax, 2\n"
.ascii "    syscall\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n"
.ascii ".L_uso_mac:\n"
.ascii "    mov rax, 0x2000005\n"
.ascii "    syscall\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n\n"
.ascii "__rubix_sys_close:\n"
.ascii "    push rbp\n"
.ascii "    mov rbp, rsp\n"
.ascii "    cmp QWORD PTR [rubix_host_os], 3\n"
.ascii "    je .L_usc_mac\n"
.ascii "    mov rax, 3\n"
.ascii "    syscall\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n"
.ascii ".L_usc_mac:\n"
.ascii "    mov rax, 0x2000006\n"
.ascii "    syscall\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n\n"
.ascii "__rubix_sys_mmap:\n"
.ascii "    push rbp\n"
.ascii "    mov rbp, rsp\n"
.ascii "    cmp QWORD PTR [rubix_host_os], 2\n"
.ascii "    je .L_usm_win\n"
.ascii "    cmp QWORD PTR [rubix_host_os], 3\n"
.ascii "    je .L_usm_mac\n"
.ascii "    mov rsi, rdi\n"
.ascii "    cmp rsi, 0\n"
.ascii "    jg .L_usm_ok\n"
.ascii "    mov rsi, 4096\n"
.ascii ".L_usm_ok:\n"
.ascii "    xor rdi, rdi\n"
.ascii "    mov rdx, 3\n"
.ascii "    mov r10, 34\n"
.ascii "    mov r8, -1\n"
.ascii "    xor r9, r9\n"
.ascii "    mov rax, 9\n"
.ascii "    syscall\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n"
.ascii ".L_usm_mac:\n"
.ascii "    mov rsi, rdi\n"
.ascii "    cmp rsi, 0\n"
.ascii "    jg .L_usm_mac_ok\n"
.ascii "    mov rsi, 4096\n"
.ascii ".L_usm_mac_ok:\n"
.ascii "    xor rdi, rdi\n"
.ascii "    mov rdx, 3\n"
.ascii "    mov r10, 0x1002\n"
.ascii "    mov r8, -1\n"
.ascii "    xor r9, r9\n"
.ascii "    mov rax, 0x20000c5\n"
.ascii "    syscall\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n"
.ascii ".L_usm_win:\n"
.ascii "    sub rsp, 32\n"
.ascii "    mov rdx, rdi\n"
.ascii "    cmp rdx, 0\n"
.ascii "    jg .L_usm_win_ok\n"
.ascii "    mov rdx, 4096\n"
.ascii ".L_usm_win_ok:\n"
.ascii "    xor rcx, rcx\n"
.ascii "    mov r8, 0x3000\n"
.ascii "    mov r9, 0x04\n"
.ascii "    call [win_fn_VirtualAlloc]\n"
.ascii "    add rsp, 32\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n\n"
.ascii "__rubix_sys_munmap:\n"
.ascii "    push rbp\n"
.ascii "    mov rbp, rsp\n"
.ascii "    cmp QWORD PTR [rubix_host_os], 2\n"
.ascii "    je .L_usmu_win\n"
.ascii "    cmp QWORD PTR [rubix_host_os], 3\n"
.ascii "    je .L_usmu_mac\n"
.ascii "    mov rax, 11\n"
.ascii "    syscall\n"
.ascii "    xor rax, rax\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n"
.ascii ".L_usmu_mac:\n"
.ascii "    mov rax, 0x2000049\n"
.ascii "    syscall\n"
.ascii "    xor rax, rax\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n"
.ascii ".L_usmu_win:\n"
.ascii "    sub rsp, 32\n"
.ascii "    mov rcx, rdi\n"
.ascii "    xor rdx, rdx\n"
.ascii "    mov r8, 0x8000\n"
.ascii "    call [win_fn_VirtualFree]\n"
.ascii "    xor rax, rax\n"
.ascii "    add rsp, 32\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n\n"
.ascii "__rubix_sys_exit:\n"
.ascii "    cmp QWORD PTR [rubix_host_os], 2\n"
.ascii "    je .L_use_win\n"
.ascii "    cmp QWORD PTR [rubix_host_os], 3\n"
.ascii "    je .L_use_mac\n"
.ascii "    mov rax, 60\n"
.ascii "    syscall\n"
.ascii ".L_use_mac:\n"
.ascii "    mov rax, 0x2000001\n"
.ascii "    syscall\n"
.ascii ".L_use_win:\n"
.ascii "    sub rsp, 32\n"
.ascii "    mov rcx, rdi\n"
.ascii "    call [win_fn_ExitProcess]\n\n"
.ascii "# --- Windows Dynamic Resolver ---\n"
.ascii "__rubix_win64_init:\n"
.ascii "    push rbp\n"
.ascii "    mov rbp, rsp\n"
.ascii "    push rbx\n"
.ascii "    push r12\n"
.ascii "    push r13\n"
.ascii "    push r14\n"
.ascii "    push r15\n"
.ascii "    mov rax, QWORD PTR gs:[0x60]\n"
.ascii "    test rax, rax\n"
.ascii "    jz .L_wi_done\n"
.ascii "    mov rax, [rax + 0x18]\n"
.ascii "    mov rbx, [rax + 0x20]\n"
.ascii "    mov rbx, [rbx]\n"
.ascii "    mov rbx, [rbx]\n"
.ascii "    mov r12, [rbx + 0x20]\n"
.ascii "    mov [win_kernel32_base], r12\n"
.ascii "    mov eax, [r12 + 0x3c]\n"
.ascii "    lea r13, [r12 + rax]\n"
.ascii "    mov eax, [r13 + 0x88]\n"
.ascii "    test eax, eax\n"
.ascii "    jz .L_wi_done\n"
.ascii "    lea r14, [r12 + rax]\n"
.ascii "    mov eax, [r14 + 0x1c]\n"
.ascii "    lea r15, [r12 + rax]\n"
.ascii "    mov [win_addr_functions], r15\n"
.ascii "    mov eax, [r14 + 0x20]\n"
.ascii "    lea rbx, [r12 + rax]\n"
.ascii "    mov [win_addr_names], rbx\n"
.ascii "    mov eax, [r14 + 0x24]\n"
.ascii "    lea rcx, [r12 + rax]\n"
.ascii "    mov [win_addr_ordinals], rcx\n"
.ascii "    mov eax, [r14 + 0x18]\n"
.ascii "    mov [win_num_names], rax\n"
.ascii "    lea rdi, [str_win_GetStdHandle]\n"
.ascii "    call __rubix_win_get_proc\n"
.ascii "    mov [win_fn_GetStdHandle], rax\n"
.ascii "    lea rdi, [str_win_WriteFile]\n"
.ascii "    call __rubix_win_get_proc\n"
.ascii "    mov [win_fn_WriteFile], rax\n"
.ascii "    lea rdi, [str_win_ReadFile]\n"
.ascii "    call __rubix_win_get_proc\n"
.ascii "    mov [win_fn_ReadFile], rax\n"
.ascii "    lea rdi, [str_win_VirtualAlloc]\n"
.ascii "    call __rubix_win_get_proc\n"
.ascii "    mov [win_fn_VirtualAlloc], rax\n"
.ascii "    lea rdi, [str_win_VirtualFree]\n"
.ascii "    call __rubix_win_get_proc\n"
.ascii "    mov [win_fn_VirtualFree], rax\n"
.ascii "    lea rdi, [str_win_ExitProcess]\n"
.ascii "    call __rubix_win_get_proc\n"
.ascii "    mov [win_fn_ExitProcess], rax\n"
.ascii "    mov rcx, -11\n"
.ascii "    sub rsp, 32\n"
.ascii "    call [win_fn_GetStdHandle]\n"
.ascii "    add rsp, 32\n"
.ascii "    mov [win_stdout_handle], rax\n"
.ascii ".L_wi_done:\n"
.ascii "    pop r15\n"
.ascii "    pop r14\n"
.ascii "    pop r13\n"
.ascii "    pop r12\n"
.ascii "    pop rbx\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n\n"
.ascii "__rubix_win_get_proc:\n"
.ascii "    push rbp\n"
.ascii "    mov rbp, rsp\n"
.ascii "    push rbx\n"
.ascii "    push r12\n"
.ascii "    push r13\n"
.ascii "    push r14\n"
.ascii "    mov r12, rdi\n"
.ascii "    mov r13, [win_num_names]\n"
.ascii "    xor r14, r14\n"
.ascii ".L_wgp_l:\n"
.ascii "    cmp r14, r13\n"
.ascii "    jge .L_wgp_nf\n"
.ascii "    mov rbx, [win_addr_names]\n"
.ascii "    mov eax, [rbx + r14 * 4]\n"
.ascii "    add rax, [win_kernel32_base]\n"
.ascii "    xor rcx, rcx\n"
.ascii ".L_wgp_c:\n"
.ascii "    mov dl, BYTE PTR [r12 + rcx]\n"
.ascii "    mov dh, BYTE PTR [rax + rcx]\n"
.ascii "    cmp dl, dh\n"
.ascii "    jne .L_wgp_nxt\n"
.ascii "    cmp dl, 0\n"
.ascii "    je .L_wgp_m\n"
.ascii "    inc rcx\n"
.ascii "    jmp .L_wgp_c\n"
.ascii ".L_wgp_nxt:\n"
.ascii "    inc r14\n"
.ascii "    jmp .L_wgp_l\n"
.ascii ".L_wgp_m:\n"
.ascii "    mov rbx, [win_addr_ordinals]\n"
.ascii "    movzx eax, WORD PTR [rbx + r14 * 2]\n"
.ascii "    mov rbx, [win_addr_functions]\n"
.ascii "    mov eax, [rbx + rax * 4]\n"
.ascii "    add rax, [win_kernel32_base]\n"
.ascii "    jmp .L_wgp_d\n"
.ascii ".L_wgp_nf:\n"
.ascii "    xor rax, rax\n"
.ascii ".L_wgp_d:\n"
.ascii "    pop r14\n"
.ascii "    pop r13\n"
.ascii "    pop r12\n"
.ascii "    pop rbx\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n\n"
.ascii "__rubix_print_int:\n"
.ascii "    push rbp\n"
.ascii "    mov rbp, rsp\n"
.ascii "    sub rsp, 48\n"
.ascii "    mov rax, rdi\n"
.ascii "    xor r8, r8\n"
.ascii "    cmp rax, 0\n"
.ascii "    jge .L_pi_pos\n"
.ascii "    neg rax\n"
.ascii "    mov r8, 1\n"
.ascii ".L_pi_pos:\n"
.ascii "    lea r9, [rbp - 1]\n"
.ascii "    mov BYTE PTR [r9], 10\n"
.ascii "    mov rcx, 1\n"
.ascii "    mov rbx, 10\n"
.ascii ".L_pi_loop:\n"
.ascii "    dec r9\n"
.ascii "    inc rcx\n"
.ascii "    xor rdx, rdx\n"
.ascii "    div rbx\n"
.ascii "    add dl, '0'\n"
.ascii "    mov [r9], dl\n"
.ascii "    cmp rax, 0\n"
.ascii "    jne .L_pi_loop\n"
.ascii "    cmp r8, 1\n"
.ascii "    jne .L_pi_write\n"
.ascii "    dec r9\n"
.ascii "    inc rcx\n"
.ascii "    mov BYTE PTR [r9], '-'\n"
.ascii ".L_pi_write:\n"
.ascii "    mov rdi, 1\n"
.ascii "    mov rsi, r9\n"
.ascii "    mov rdx, rcx\n"
.ascii "    call __rubix_sys_write\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n\n"
.ascii "__rubix_print_str:\n"
.ascii "    push rbp\n"
.ascii "    mov rbp, rsp\n"
.ascii "    mov rdx, rsi\n"
.ascii "    mov rsi, rdi\n"
.ascii "    mov rdi, 1\n"
.ascii "    call __rubix_sys_write\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n\n"
.ascii "__rubix_print_char:\n"
.ascii "    push rbp\n"
.ascii "    mov rbp, rsp\n"
.ascii "    sub rsp, 16\n"
.ascii "    mov [rbp - 8], dil\n"
.ascii "    mov rdi, 1\n"
.ascii "    lea rsi, [rbp - 8]\n"
.ascii "    mov rdx, 1\n"
.ascii "    call __rubix_sys_write\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n\n"
.ascii "__rubix_alloc:\n"
.ascii "    jmp __rubix_sys_mmap\n\n"
.ascii "__rubix_free:\n"
.ascii "    jmp __rubix_sys_munmap\n\n"
.ascii "# --- Standard Library: File I/O ---\n"
.ascii ".globl file_open, file_read, file_write, file_close\n"
.ascii "file_open:\n"
.ascii "    jmp __rubix_sys_open\n\n"
.ascii "file_read:\n"
.ascii "    jmp __rubix_sys_read\n\n"
.ascii "file_write:\n"
.ascii "    jmp __rubix_sys_write\n\n"
.ascii "file_close:\n"
.ascii "    jmp __rubix_sys_close\n\n"
.ascii "# --- Standard Library: Strings ---\n"
.ascii ".globl str_len, str_cmp, str_copy, str_cat\n"
.ascii "str_len:\n"
.ascii "    xor rax, rax\n"
.ascii ".L_r_sl_loop:\n"
.ascii "    cmp BYTE PTR [rdi + rax], 0\n"
.ascii "    je .L_r_sl_done\n"
.ascii "    inc rax\n"
.ascii "    jmp .L_r_sl_loop\n"
.ascii ".L_r_sl_done:\n"
.ascii "    ret\n\n"
.ascii "str_cmp:\n"
.ascii "    xor rcx, rcx\n"
.ascii ".L_r_sc_loop:\n"
.ascii "    movzx rax, BYTE PTR [rdi + rcx]\n"
.ascii "    movzx rdx, BYTE PTR [rsi + rcx]\n"
.ascii "    cmp rax, rdx\n"
.ascii "    jne .L_r_sc_diff\n"
.ascii "    cmp rax, 0\n"
.ascii "    je .L_r_sc_eq\n"
.ascii "    inc rcx\n"
.ascii "    jmp .L_r_sc_loop\n"
.ascii ".L_r_sc_diff:\n"
.ascii "    sub rax, rdx\n"
.ascii "    ret\n"
.ascii ".L_r_sc_eq:\n"
.ascii "    xor rax, rax\n"
.ascii "    ret\n\n"
.ascii "str_copy:\n"
.ascii "    mov rax, rdi\n"
.ascii "    xor rcx, rcx\n"
.ascii ".L_r_scpy_loop:\n"
.ascii "    mov dl, BYTE PTR [rsi + rcx]\n"
.ascii "    mov BYTE PTR [rdi + rcx], dl\n"
.ascii "    cmp dl, 0\n"
.ascii "    je .L_r_scpy_done\n"
.ascii "    inc rcx\n"
.ascii "    jmp .L_r_scpy_loop\n"
.ascii ".L_r_scpy_done:\n"
.ascii "    ret\n\n"
.ascii "str_cat:\n"
.ascii "    mov rax, rdi\n"
.ascii ".L_r_scat_find:\n"
.ascii "    cmp BYTE PTR [rdi], 0\n"
.ascii "    je .L_r_scat_copy\n"
.ascii "    inc rdi\n"
.ascii "    jmp .L_r_scat_find\n"
.ascii ".L_r_scat_copy:\n"
.ascii "    xor rcx, rcx\n"
.ascii ".L_r_scat_loop:\n"
.ascii "    mov dl, BYTE PTR [rsi + rcx]\n"
.ascii "    mov BYTE PTR [rdi + rcx], dl\n"
.ascii "    cmp dl, 0\n"
.ascii "    je .L_r_scat_done\n"
.ascii "    inc rcx\n"
.ascii "    jmp .L_r_scat_loop\n"
.ascii ".L_r_scat_done:\n"
.ascii "    ret\n\n"
.ascii ".globl puts\n"
.ascii "puts:\n"
.ascii "    push rbp\n"
.ascii "    mov rbp, rsp\n"
.ascii "    push rdi\n"
.ascii "    call str_len\n"
.ascii "    mov rdx, rax\n"
.ascii "    pop rsi\n"
.ascii "    mov rdi, 1\n"
.ascii "    call __rubix_sys_write\n"
.ascii "    mov rsp, rbp\n"
.ascii "    pop rbp\n"
.ascii "    ret\n\n"
.ascii "# --- Standard Library: Math ---\n"
.ascii ".globl math_abs, math_min, math_max, math_pow, math_sqrt\n"
.ascii "math_abs:\n"
.ascii "    mov rax, rdi\n"
.ascii "    cmp rax, 0\n"
.ascii "    jge .L_r_ma_done\n"
.ascii "    neg rax\n"
.ascii ".L_r_ma_done:\n"
.ascii "    ret\n\n"
.ascii "math_min:\n"
.ascii "    mov rax, rdi\n"
.ascii "    cmp rax, rsi\n"
.ascii "    jle .L_r_mmin_done\n"
.ascii "    mov rax, rsi\n"
.ascii ".L_r_mmin_done:\n"
.ascii "    ret\n\n"
.ascii "math_max:\n"
.ascii "    mov rax, rdi\n"
.ascii "    cmp rax, rsi\n"
.ascii "    jge .L_r_mmax_done\n"
.ascii "    mov rax, rsi\n"
.ascii ".L_r_mmax_done:\n"
.ascii "    ret\n\n"
.ascii "math_pow:\n"
.ascii "    cmp rsi, 0\n"
.ascii "    jl .L_r_pow_zero\n"
.ascii "    je .L_r_pow_one\n"
.ascii "    mov rax, 1\n"
.ascii "    mov rcx, rsi\n"
.ascii ".L_r_pow_loop:\n"
.ascii "    cmp rcx, 0\n"
.ascii "    jle .L_r_pow_done\n"
.ascii "    imul rax, rdi\n"
.ascii "    dec rcx\n"
.ascii "    jmp .L_r_pow_loop\n"
.ascii ".L_r_pow_zero:\n"
.ascii "    xor rax, rax\n"
.ascii "    ret\n"
.ascii ".L_r_pow_one:\n"
.ascii "    mov rax, 1\n"
.ascii "    ret\n"
.ascii ".L_r_pow_done:\n"
.ascii "    ret\n\n"
.ascii "math_sqrt:\n"
.ascii "    mov rcx, rdi\n"
.ascii "    cmp rcx, 0\n"
.ascii "    jle .L_r_sqrt_zero\n"
.ascii "    cmp rcx, 1\n"
.ascii "    je .L_r_sqrt_one\n"
.ascii "    mov r8, 1\n"
.ascii "    mov r9, rcx\n"
.ascii "    xor rax, rax\n"
.ascii ".L_r_sqrt_loop:\n"
.ascii "    cmp r8, r9\n"
.ascii "    jg .L_r_sqrt_done\n"
.ascii "    mov r10, r8\n"
.ascii "    add r10, r9\n"
.ascii "    shr r10, 1\n"
.ascii "    mov r11, r10\n"
.ascii "    imul r11, r10\n"
.ascii "    cmp r11, rcx\n"
.ascii "    je .L_r_sqrt_exact\n"
.ascii "    jl .L_r_sqrt_less\n"
.ascii "    lea r9, [r10 - 1]\n"
.ascii "    jmp .L_r_sqrt_loop\n"
.ascii ".L_r_sqrt_less:\n"
.ascii "    mov rax, r10\n"
.ascii "    lea r8, [r10 + 1]\n"
.ascii "    jmp .L_r_sqrt_loop\n"
.ascii ".L_r_sqrt_exact:\n"
.ascii "    mov rax, r10\n"
.ascii "    ret\n"
.ascii ".L_r_sqrt_zero:\n"
.ascii "    xor rax, rax\n"
.ascii "    ret\n"
.ascii ".L_r_sqrt_one:\n"
.ascii "    mov rax, 1\n"
.ascii "    ret\n"
.ascii ".L_r_sqrt_done:\n"
.ascii "    ret\n\n"
.ascii "# --- Division by zero runtime guard ---\n"
.ascii "__rubix_div_zero_error:\n"
.ascii "    lea rdi, [.L_msg_div_zero]\n"
.ascii "    mov rsi, 39\n"
.ascii "    call __rubix_print_str\n"
.ascii "    mov rdi, 1\n"
.ascii "    jmp __rubix_sys_exit\n\n"
.ascii "# --- Integer overflow runtime guard ---\n"
.ascii "__rubix_overflow_error:\n"
.ascii "    lea rdi, [.L_msg_overflow]\n"
.ascii "    mov rsi, 38\n"
.ascii "    call __rubix_print_str\n"
.ascii "    mov rdi, 1\n"
.ascii "    jmp __rubix_sys_exit\n\n"
.ascii ".section .rodata\n"
.ascii ".L_msg_div_zero:\n"
.ascii "    .string \"Rubix Runtime Error: division by zero\\n\"\n"
.ascii ".L_msg_overflow:\n"
.ascii "    .string \"Rubix Runtime Error: integer overflow\\n\"\n"
.ascii "str_win_GetStdHandle: .string \"GetStdHandle\\0\"\n"
.ascii "str_win_WriteFile:    .string \"WriteFile\\0\"\n"
.ascii "str_win_ReadFile:     .string \"ReadFile\\0\"\n"
.ascii "str_win_VirtualAlloc: .string \"VirtualAlloc\\0\"\n"
.ascii "str_win_VirtualFree:  .string \"VirtualFree\\0\"\n"
.ascii "str_win_ExitProcess:  .string \"ExitProcess\\0\"\n"
.ascii "\n"
.ascii ".data\n"
.ascii ".align 8\n"
.ascii ".globl rubix_host_os\n"
.ascii "rubix_host_os:        .quad 1\n\n"
.ascii ".bss\n"
.ascii ".align 8\n"
.ascii "win_stdout_handle:    .quad 0\n"
.ascii "win_kernel32_base:    .quad 0\n"
.ascii "win_addr_functions:   .quad 0\n"
.ascii "win_addr_names:       .quad 0\n"
.ascii "win_addr_ordinals:    .quad 0\n"
.ascii "win_num_names:        .quad 0\n"
.ascii "win_fn_GetStdHandle:  .quad 0\n"
.ascii "win_fn_WriteFile:     .quad 0\n"
.ascii "win_fn_ReadFile:      .quad 0\n"
.ascii "win_fn_VirtualAlloc:  .quad 0\n"
.ascii "win_fn_VirtualFree:   .quad 0\n"
.ascii "win_fn_ExitProcess:   .quad 0\n"
.ascii "\0"

.bss
tmp_emit_num: .skip 32
