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

# rodata_add_float(rdi: str_ptr, rsi: str_len) -> rax: label_id
rodata_add_float:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi            # str_ptr
    mov r13, rsi            # str_len

    inc QWORD PTR [str_label_count]
    mov r14, [str_label_count]  # label_id

    # Emit ".LC{id}:\n    .double "
    lea rdi, [str_lc_prefix]
    call rodata_emit_cstr
    mov rax, r14
    call rodata_emit_int
    lea rdi, [str_lc_colon_double]
    call rodata_emit_cstr

    # Emit float literal characters
    mov rdi, r12
    mov rsi, r13
    call rodata_emit_str

    lea rdi, [str_newline]
    call rodata_emit_cstr

    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# rodata_add_neg_float(rdi: str_ptr, rsi: str_len) -> rax: label_id
rodata_add_neg_float:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi            # str_ptr
    mov r13, rsi            # str_len

    inc QWORD PTR [str_label_count]
    mov r14, [str_label_count]  # label_id

    # Emit ".LC{id}:\n    .double -"
    lea rdi, [str_lc_prefix]
    call rodata_emit_cstr
    mov rax, r14
    call rodata_emit_int
    lea rdi, [str_lc_colon_double_neg]
    call rodata_emit_cstr

    # Emit float literal characters
    mov rdi, r12
    mov rsi, r13
    call rodata_emit_str

    lea rdi, [str_newline]
    call rodata_emit_cstr

    mov rax, r14
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
str_lc_colon_double:  .string ":\n    .double "
str_lc_colon_double_neg: .string ":\n    .double -"
str_comma_space:      .string ", "
str_zero_nl:          .string "0\n"
str_sec_rodata:       .string "\n.section .rodata\n"

str_fcmp:         .string "    movq xmm0, rax\n    movq xmm1, rbx\n    ucomisd xmm0, xmm1\n    jp .L_fcmp_unordered\n    jne .L_fcmp_not_equal\n    mov rax, 1\n    jmp .L_fcmp_done\n.L_fcmp_not_equal:\n    xor rax, rax\n.L_fcmp_done:\n    movq rax, xmm0\n"
str_fsete:        .string "    mov rax, 1\n"
str_fsetne:       .string "    mov rax, 0\n"
str_int_to_float_rax: .string "    cvtsi2sd xmm0, rax\n"
str_float_to_int_rax: .string "    cvttsd2si rax, xmm0\n"

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
.incbin "lib/runtime.s"
.byte 0

.bss
tmp_emit_num: .skip 32
