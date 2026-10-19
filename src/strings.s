.intel_syntax noprefix

.text

# str_len(rdi: null-terminated str) -> rax: length
str_len:
    xor rax, rax
.L_sl_loop:
    cmp BYTE PTR [rdi + rax], 0
    je .L_sl_done
    inc rax
    jmp .L_sl_loop
.L_sl_done:
    ret

# str_cmp_n(rdi: str1, rsi: len1, rdx: str2, rcx: len2) -> rax (0 if equal, 1 if not)
str_cmp_n:
    cmp rsi, rcx
    jne .L_sc_diff
    xor rax, rax
.L_sc_loop:
    cmp rax, rsi
    je .L_sc_match
    mov r8b, [rdi + rax]
    mov r9b, [rdx + rax]
    cmp r8b, r9b
    jne .L_sc_diff
    inc rax
    jmp .L_sc_loop
.L_sc_match:
    xor rax, rax
    ret
.L_sc_diff:
    mov rax, 1
    ret

# str_copy(rdi: dest, rsi: src, rdx: len)
str_copy:
    xor rcx, rcx
.L_cp_loop:
    cmp rcx, rdx
    je .L_cp_done
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    inc rcx
    jmp .L_cp_loop
.L_cp_done:
    ret

# int_to_str(rax: int, rdi: dest_buffer) -> rax: num_chars_written
int_to_str:
    push rbp
    mov rbp, rsp
    sub rsp, 32
    push rbx
    push r12
    push r13

    mov r12, rdi            # dest buffer
    cmp rax, 0
    jne .L_its_nonzero
    mov BYTE PTR [r12], '0'
    mov rax, 1
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_its_nonzero:
    xor r13, r13            # negative flag
    cmp rax, 0
    jge .L_its_pos
    neg rax
    mov r13, 1              # was negative
.L_its_pos:
    lea r9, [rbp - 1]       # buffer backwards
    xor rcx, rcx            # digit count
    mov rbx, 10
.L_its_div_loop:
    xor rdx, rdx
    div rbx                 # rax = rax / 10, rdx = rem
    add dl, '0'
    mov [r9], dl
    dec r9
    inc rcx
    cmp rax, 0
    jne .L_its_div_loop

    cmp r13, 1
    jne .L_its_copy
    mov BYTE PTR [r9], '-'
    dec r9
    inc rcx

.L_its_copy:
    inc r9                  # start of formatted string
    xor rdx, rdx
.L_its_cp_loop:
    cmp rdx, rcx
    je .L_its_finish
    mov al, [r9 + rdx]
    mov [r12 + rdx], al
    inc rdx
    jmp .L_its_cp_loop

.L_its_finish:
    mov rax, rcx            # return length
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret
