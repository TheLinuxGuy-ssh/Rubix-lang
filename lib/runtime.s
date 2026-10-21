# ==============================================================================
# Rubix Standard Runtime Library (Pure x86-64 Assembly)
# Universal Cross-OS Architecture (Linux, Windows, macOS)
# ==============================================================================
.intel_syntax noprefix
.text
.globl __rubix_sys_write, __rubix_sys_read, __rubix_sys_open, __rubix_sys_close
.globl __rubix_sys_mmap, __rubix_sys_munmap, __rubix_sys_exit
.globl __rubix_print_int, __rubix_print_str, __rubix_print_char, __rubix_print_float
.globl __rubix_alloc, __rubix_free
.globl file_open, file_read, file_write, file_close
.globl str_len, str_cmp, str_copy, str_cat, puts
.globl math_abs, math_min, math_max, math_pow, math_sqrt
.globl mem_get_u8, mem_set_u8, mem_get_u32, mem_set_u32, mem_get_u64, mem_set_u64
.globl __rubix_div_zero_error, __rubix_overflow_error

# --- Universal OS Dispatchers ---

__rubix_sys_write:
    push rbp
    mov rbp, rsp
    cmp QWORD PTR [rubix_host_os], 2
    je .L_usw_win
    cmp QWORD PTR [rubix_host_os], 3
    je .L_usw_mac
    mov rax, 1                  # Linux sys_write
    syscall
    mov rsp, rbp
    pop rbp
    ret
.L_usw_mac:
    mov rax, 0x2000004          # macOS Darwin sys_write
    syscall
    mov rsp, rbp
    pop rbp
    ret
.L_usw_win:
    sub rsp, 48                 # Windows shadow space + 16 bytes local
    mov rcx, [win_stdout_handle]
    mov r8, rdx                 # nNumberOfBytesToWrite
    mov rdx, rsi                # lpBuffer
    lea r9, [rsp + 40]          # lpNumberOfBytesWritten
    mov QWORD PTR [rsp + 32], 0 # lpOverlapped = NULL
    call [win_fn_WriteFile]
    mov rax, [rsp + 40]
    add rsp, 48
    mov rsp, rbp
    pop rbp
    ret

__rubix_sys_read:
    push rbp
    mov rbp, rsp
    cmp QWORD PTR [rubix_host_os], 2
    je .L_usr_win
    cmp QWORD PTR [rubix_host_os], 3
    je .L_usr_mac
    mov rax, 0                  # Linux sys_read
    syscall
    mov rsp, rbp
    pop rbp
    ret
.L_usr_mac:
    mov rax, 0x2000003          # macOS Darwin sys_read
    syscall
    mov rsp, rbp
    pop rbp
    ret
.L_usr_win:
    sub rsp, 48
    mov rcx, rdi                # hFile
    mov r8, rdx                 # nNumberOfBytesToRead
    mov rdx, rsi                # lpBuffer
    lea r9, [rsp + 40]          # lpNumberOfBytesRead
    mov QWORD PTR [rsp + 32], 0
    call [win_fn_ReadFile]
    mov rax, [rsp + 40]
    add rsp, 48
    mov rsp, rbp
    pop rbp
    ret

__rubix_sys_open:
    push rbp
    mov rbp, rsp
    cmp QWORD PTR [rubix_host_os], 3
    je .L_uso_mac
    mov rax, 2                  # Linux sys_open
    syscall
    mov rsp, rbp
    pop rbp
    ret
.L_uso_mac:
    mov rax, 0x2000005          # macOS Darwin sys_open
    syscall
    mov rsp, rbp
    pop rbp
    ret

__rubix_sys_close:
    push rbp
    mov rbp, rsp
    cmp QWORD PTR [rubix_host_os], 3
    je .L_usc_mac
    mov rax, 3                  # Linux sys_close
    syscall
    mov rsp, rbp
    pop rbp
    ret
.L_usc_mac:
    mov rax, 0x2000006          # macOS Darwin sys_close
    syscall
    mov rsp, rbp
    pop rbp
    ret

__rubix_sys_mmap:
    push rbp
    mov rbp, rsp
    cmp QWORD PTR [rubix_host_os], 2
    je .L_usm_win
    cmp QWORD PTR [rubix_host_os], 3
    je .L_usm_mac
    mov rsi, rdi
    cmp rsi, 0
    jg .L_usm_ok
    mov rsi, 4096
.L_usm_ok:
    xor rdi, rdi
    mov rdx, 3                  # PROT_READ | PROT_WRITE
    mov r10, 34                 # MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9, r9
    mov rax, 9                  # Linux sys_mmap
    syscall
    mov rsp, rbp
    pop rbp
    ret
.L_usm_mac:
    mov rsi, rdi
    cmp rsi, 0
    jg .L_usm_mac_ok
    mov rsi, 4096
.L_usm_mac_ok:
    xor rdi, rdi
    mov rdx, 3
    mov r10, 0x1002             # Darwin MAP_PRIVATE | MAP_ANON
    mov r8, -1
    xor r9, r9
    mov rax, 0x20000c5          # Darwin mmap
    syscall
    mov rsp, rbp
    pop rbp
    ret
.L_usm_win:
    sub rsp, 32
    mov rdx, rdi
    cmp rdx, 0
    jg .L_usm_win_ok
    mov rdx, 4096
.L_usm_win_ok:
    xor rcx, rcx
    mov r8, 0x3000              # MEM_COMMIT | MEM_RESERVE
    mov r9, 0x04                # PAGE_READWRITE
    call [win_fn_VirtualAlloc]
    add rsp, 32
    mov rsp, rbp
    pop rbp
    ret

__rubix_sys_munmap:
    push rbp
    mov rbp, rsp
    cmp QWORD PTR [rubix_host_os], 2
    je .L_usmu_win
    cmp QWORD PTR [rubix_host_os], 3
    je .L_usmu_mac
    mov rax, 11                 # Linux sys_munmap
    syscall
    xor rax, rax
    mov rsp, rbp
    pop rbp
    ret
.L_usmu_mac:
    mov rax, 0x2000049          # Darwin munmap
    syscall
    xor rax, rax
    mov rsp, rbp
    pop rbp
    ret
.L_usmu_win:
    sub rsp, 32
    mov rcx, rdi
    xor rdx, rdx
    mov r8, 0x8000              # MEM_RELEASE
    call [win_fn_VirtualFree]
    xor rax, rax
    add rsp, 32
    mov rsp, rbp
    pop rbp
    ret

__rubix_sys_exit:
    cmp QWORD PTR [rubix_host_os], 2
    je .L_use_win
    cmp QWORD PTR [rubix_host_os], 3
    je .L_use_mac
    mov rax, 60                 # Linux sys_exit
    syscall
.L_use_mac:
    mov rax, 0x2000001          # Darwin sys_exit
    syscall
.L_use_win:
    sub rsp, 32
    mov rcx, rdi
    call [win_fn_ExitProcess]

# --- Windows Dynamic Resolver ---
__rubix_win64_init:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rax, QWORD PTR gs:[0x60]
    test rax, rax
    jz .L_wi_done
    mov rax, [rax + 0x18]
    mov rbx, [rax + 0x20]
    mov rbx, [rbx]
    mov rbx, [rbx]
    mov r12, [rbx + 0x20]
    mov [win_kernel32_base], r12
    mov eax, [r12 + 0x3c]
    lea r13, [r12 + rax]
    mov eax, [r13 + 0x88]
    test eax, eax
    jz .L_wi_done
    lea r14, [r12 + rax]
    mov eax, [r14 + 0x1c]
    lea r15, [r12 + rax]
    mov [win_addr_functions], r15
    mov eax, [r14 + 0x20]
    lea rbx, [r12 + rax]
    mov [win_addr_names], rbx
    mov eax, [r14 + 0x24]
    lea rcx, [r12 + rax]
    mov [win_addr_ordinals], rcx
    mov eax, [r14 + 0x18]
    mov [win_num_names], rax
    lea rdi, [str_win_GetStdHandle]
    call __rubix_win_get_proc
    mov [win_fn_GetStdHandle], rax
    lea rdi, [str_win_WriteFile]
    call __rubix_win_get_proc
    mov [win_fn_WriteFile], rax
    lea rdi, [str_win_ReadFile]
    call __rubix_win_get_proc
    mov [win_fn_ReadFile], rax
    lea rdi, [str_win_VirtualAlloc]
    call __rubix_win_get_proc
    mov [win_fn_VirtualAlloc], rax
    lea rdi, [str_win_VirtualFree]
    call __rubix_win_get_proc
    mov [win_fn_VirtualFree], rax
    lea rdi, [str_win_ExitProcess]
    call __rubix_win_get_proc
    mov [win_fn_ExitProcess], rax
    mov rcx, -11
    sub rsp, 32
    call [win_fn_GetStdHandle]
    add rsp, 32
    mov [win_stdout_handle], rax
.L_wi_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

__rubix_win_get_proc:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, [win_num_names]
    xor r14, r14
.L_wgp_l:
    cmp r14, r13
    jge .L_wgp_nf
    mov rbx, [win_addr_names]
    mov eax, [rbx + r14 * 4]
    add rax, [win_kernel32_base]
    xor rcx, rcx
.L_wgp_c:
    mov dl, BYTE PTR [r12 + rcx]
    mov dh, BYTE PTR [rax + rcx]
    cmp dl, dh
    jne .L_wgp_nxt
    cmp dl, 0
    je .L_wgp_m
    inc rcx
    jmp .L_wgp_c
.L_wgp_nxt:
    inc r14
    jmp .L_wgp_l
.L_wgp_m:
    mov rbx, [win_addr_ordinals]
    movzx eax, WORD PTR [rbx + r14 * 2]
    mov rbx, [win_addr_functions]
    mov eax, [rbx + rax * 4]
    add rax, [win_kernel32_base]
    jmp .L_wgp_d
.L_wgp_nf:
    xor rax, rax
.L_wgp_d:
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# --- Output Routines ---

__rubix_print_int:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov rax, rdi
    xor r8, r8
    cmp rax, 0
    jge .L_pi_pos
    neg rax
    mov r8, 1
.L_pi_pos:
    lea r9, [rbp - 1]
    mov BYTE PTR [r9], 10
    mov rcx, 1
    mov rbx, 10
.L_pi_loop:
    dec r9
    inc rcx
    xor rdx, rdx
    div rbx
    add dl, '0'
    mov [r9], dl
    cmp rax, 0
    jne .L_pi_loop
    cmp r8, 1
    jne .L_pi_write
    dec r9
    inc rcx
    mov BYTE PTR [r9], '-'
.L_pi_write:
    mov rdi, 1
    mov rsi, r9
    mov rdx, rcx
    call __rubix_sys_write
    mov rsp, rbp
    pop rbp
    ret

__rubix_print_str:
    push rbp
    mov rbp, rsp
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, 1
    call __rubix_sys_write
    mov rsp, rbp
    pop rbp
    ret

__rubix_print_char:
    push rbp
    mov rbp, rsp
    sub rsp, 16
    mov [rbp - 8], dil
    mov rdi, 1
    lea rsi, [rbp - 8]
    mov rdx, 1
    call __rubix_sys_write
    mov rsp, rbp
    pop rbp
    ret

__rubix_print_float:
    push rbp
    mov rbp, rsp
    sub rsp, 80
    # Accept float in xmm0 or rdi (bits)
    # If xmm0 is zero and rdi is non-zero, load from rdi
    movq [rbp-8], xmm0
    test rdi, rdi
    jz .L_pf_have_xmm
    # Check if xmm0 is 0
    pxor xmm1, xmm1
    ucomisd xmm0, xmm1
    jp .L_pf_load_rdi
    jnz .L_pf_have_xmm
.L_pf_load_rdi:
    movq xmm0, rdi
    movq [rbp-8], xmm0
.L_pf_have_xmm:
    lea r8, [rbp-64]        # output buffer start
    mov r9, r8             # write cursor

    # Check negative
    pxor xmm1, xmm1
    ucomisd xmm1, xmm0
    jbe .L_pf_non_neg
    # Prepend "-"
    mov BYTE PTR [r9], '-'
    inc r9
    # Negate
    pxor xmm1, xmm1
    subsd xmm1, [rbp-8]
    movsd [rbp-8], xmm1
    movsd xmm0, xmm1

.L_pf_non_neg:
    # Int part
    cvttsd2si rax, xmm0
    mov [rbp-16], rax
    
    # Store int digits backwards on stack
    lea rcx, [rbp-40]
    lea r10, [rbp-40]       # upper limit
    mov rbx, 10
    cmp rax, 0
    jne .L_pf_int_loop
    mov BYTE PTR [r9], '0'
    inc r9
    jmp .L_pf_int_done
.L_pf_int_loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    mov [rcx], dl
    dec rcx
    cmp rax, 0
    jne .L_pf_int_loop
    # Copy int digits to buffer
    inc rcx
.L_pf_copy_int:
    cmp rcx, r10
    ja .L_pf_int_done
    mov dl, [rcx]
    mov [r9], dl
    inc r9
    inc rcx
    jmp .L_pf_copy_int

.L_pf_int_done:
    # Decimal point
    mov BYTE PTR [r9], '.'
    inc r9

    # Fraction: xmm0 - int(rax)
    mov rax, [rbp-16]
    cvtsi2sd xmm1, rax
    movsd xmm0, [rbp-8]
    subsd xmm0, xmm1

    # 6 digits
    mov QWORD PTR [rbp-24], 6
.L_pf_frac_loop:
    mov rax, 10
    cvtsi2sd xmm1, rax
    mulsd xmm0, xmm1
    cvttsd2si rax, xmm0
    cmp rax, 9
    jle .L_pf_d_ok1
    mov rax, 9
.L_pf_d_ok1:
    cmp rax, 0
    jge .L_pf_d_ok2
    xor rax, rax
.L_pf_d_ok2:
    add al, '0'
    mov [r9], al
    inc r9
    sub al, '0'
    movzx rax, al
    cvtsi2sd xmm1, rax
    subsd xmm0, xmm1
    dec QWORD PTR [rbp-24]
    jnz .L_pf_frac_loop

    # Newline
    mov BYTE PTR [r9], 10
    inc r9

    # Write out via __rubix_sys_write
    mov rdi, 1
    mov rsi, r8
    mov rdx, r9
    sub rdx, r8
    call __rubix_sys_write

    mov rsp, rbp
    pop rbp
    ret

# --- Memory Allocation ---

__rubix_alloc:
    jmp __rubix_sys_mmap

__rubix_free:
    jmp __rubix_sys_munmap

# --- Standard Library: File I/O ---

file_open:
    jmp __rubix_sys_open

file_read:
    jmp __rubix_sys_read

file_write:
    jmp __rubix_sys_write

file_close:
    jmp __rubix_sys_close

# --- Standard Library: Strings ---

str_len:
    xor rax, rax
.L_r_sl_loop:
    cmp BYTE PTR [rdi + rax], 0
    je .L_r_sl_done
    inc rax
    jmp .L_r_sl_loop
.L_r_sl_done:
    ret

str_cmp:
    xor rcx, rcx
.L_r_sc_loop:
    movzx rax, BYTE PTR [rdi + rcx]
    movzx rdx, BYTE PTR [rsi + rcx]
    cmp rax, rdx
    jne .L_r_sc_diff
    cmp rax, 0
    je .L_r_sc_eq
    inc rcx
    jmp .L_r_sc_loop
.L_r_sc_diff:
    sub rax, rdx
    ret
.L_r_sc_eq:
    xor rax, rax
    ret

str_copy:
    mov rax, rdi
    xor rcx, rcx
.L_r_scpy_loop:
    mov dl, BYTE PTR [rsi + rcx]
    mov BYTE PTR [rdi + rcx], dl
    cmp dl, 0
    je .L_r_scpy_done
    inc rcx
    jmp .L_r_scpy_loop
.L_r_scpy_done:
    ret

str_cat:
    mov rax, rdi
.L_r_scat_find:
    cmp BYTE PTR [rdi], 0
    je .L_r_scat_copy
    inc rdi
    jmp .L_r_scat_find
.L_r_scat_copy:
    xor rcx, rcx
.L_r_scat_loop:
    mov dl, BYTE PTR [rsi + rcx]
    mov BYTE PTR [rdi + rcx], dl
    cmp dl, 0
    je .L_r_scat_done
    inc rcx
    jmp .L_r_scat_loop
.L_r_scat_done:
    ret

puts:
    push rbp
    mov rbp, rsp
    push rdi
    call str_len
    mov rdx, rax
    pop rsi
    mov rdi, 1
    call __rubix_sys_write
    mov rsp, rbp
    pop rbp
    ret

# --- Standard Library: Math ---

math_abs:
    mov rax, rdi
    cmp rax, 0
    jge .L_r_ma_done
    neg rax
.L_r_ma_done:
    ret

math_min:
    mov rax, rdi
    cmp rax, rsi
    jle .L_r_mmin_done
    mov rax, rsi
.L_r_mmin_done:
    ret

math_max:
    mov rax, rdi
    cmp rax, rsi
    jge .L_r_mmax_done
    mov rax, rsi
.L_r_mmax_done:
    ret

math_pow:
    cmp rsi, 0
    jl .L_r_pow_zero
    je .L_r_pow_one
    mov rax, 1
    mov rcx, rsi
.L_r_pow_loop:
    cmp rcx, 0
    jle .L_r_pow_done
    imul rax, rdi
    dec rcx
    jmp .L_r_pow_loop
.L_r_pow_zero:
    xor rax, rax
    ret
.L_r_pow_one:
    mov rax, 1
    ret
.L_r_pow_done:
    ret

math_sqrt:
    mov rcx, rdi
    cmp rcx, 0
    jle .L_r_sqrt_zero
    cmp rcx, 1
    je .L_r_sqrt_one
    mov r8, 1
    mov r9, rcx
    xor rax, rax
.L_r_sqrt_loop:
    cmp r8, r9
    jg .L_r_sqrt_done
    mov r10, r8
    add r10, r9
    shr r10, 1
    mov r11, r10
    imul r11, r10
    cmp r11, rcx
    je .L_r_sqrt_exact
    jl .L_r_sqrt_less
    lea r9, [r10 - 1]
    jmp .L_r_sqrt_loop
.L_r_sqrt_less:
    mov rax, r10
    lea r8, [r10 + 1]
    jmp .L_r_sqrt_loop
.L_r_sqrt_exact:
    mov rax, r10
    ret
.L_r_sqrt_zero:
    xor rax, rax
    ret
.L_r_sqrt_one:
    mov rax, 1
    ret
.L_r_sqrt_done:
    ret

# --- Standard Library: Floating-point Math (f64 / double) ---

float_add:
fadd:
    movq xmm0, rdi
    movq xmm1, rsi
    addsd xmm0, xmm1
    movq rax, xmm0
    ret

float_sub:
fsub:
    movq xmm0, rdi
    movq xmm1, rsi
    subsd xmm0, xmm1
    movq rax, xmm0
    ret

float_mul:
fmul:
    movq xmm0, rdi
    movq xmm1, rsi
    mulsd xmm0, xmm1
    movq rax, xmm0
    ret

float_div:
fdiv:
    movq xmm0, rdi
    movq xmm1, rsi
    divsd xmm0, xmm1
    movq rax, xmm0
    ret

float_to_int:
    movq xmm0, rdi
    cvttsd2si rax, xmm0
    ret

int_to_float:
    cvtsi2sd xmm0, rdi
    movq rax, xmm0
    ret

# --- Runtime Guards ---


# --- Byte & Word Memory Primitives ---
# mem_get_u8(base_ptr: int, offset: int) -> int
mem_get_u8:
    movzx rax, BYTE PTR [rdi + rsi]
    ret

# mem_set_u8(base_ptr: int, offset: int, val: int)
mem_set_u8:
    mov [rdi + rsi], dl
    ret

# mem_get_u32(base_ptr: int, offset: int) -> int
mem_get_u32:
    mov eax, DWORD PTR [rdi + rsi]
    ret

# mem_set_u32(base_ptr: int, offset: int, val: int)
mem_set_u32:
    mov [rdi + rsi], edx
    ret

# mem_get_u64(base_ptr: int, offset: int) -> int
mem_get_u64:
    mov rax, QWORD PTR [rdi + rsi]
    ret

# mem_set_u64(base_ptr: int, offset: int, val: int)
mem_set_u64:
    mov [rdi + rsi], rdx
    ret

__rubix_div_zero_error:
    lea rdi, [.L_msg_div_zero]
    mov rsi, 39
    call __rubix_print_str
    mov rdi, 1
    jmp __rubix_sys_exit

__rubix_overflow_error:
    lea rdi, [.L_msg_overflow]
    mov rsi, 38
    call __rubix_print_str
    mov rdi, 1
    jmp __rubix_sys_exit

.section .rodata
.L_msg_div_zero:
    .string "Rubix Runtime Error: division by zero\n"
.L_msg_overflow:
    .string "Rubix Runtime Error: integer overflow\n"
str_win_GetStdHandle: .string "GetStdHandle\0"
str_win_WriteFile:    .string "WriteFile\0"
str_win_ReadFile:     .string "ReadFile\0"
str_win_VirtualAlloc: .string "VirtualAlloc\0"
str_win_VirtualFree:  .string "VirtualFree\0"
str_win_ExitProcess:  .string "ExitProcess\0"

.data
.align 8
.globl rubix_host_os
rubix_host_os:        .quad 1

.bss
.align 8
win_stdout_handle:    .quad 0
win_kernel32_base:    .quad 0
win_addr_functions:   .quad 0
win_addr_names:       .quad 0
win_addr_ordinals:    .quad 0
win_num_names:        .quad 0
win_fn_GetStdHandle:  .quad 0
win_fn_WriteFile:     .quad 0
win_fn_ReadFile:      .quad 0
win_fn_VirtualAlloc:  .quad 0
win_fn_VirtualFree:   .quad 0
win_fn_ExitProcess:   .quad 0
