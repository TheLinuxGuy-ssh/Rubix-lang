.intel_syntax noprefix

.text

# print_msg(rdi: null-terminated str)
print_msg:
    push rbp
    mov rbp, rsp
    push rdi
    call str_len
    mov rdx, rax            # length
    pop rsi                 # buffer
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall
    mov rsp, rbp
    pop rbp
    ret

# print_err(rdi: null-terminated str)
print_err:
    push rbp
    mov rbp, rsp
    push rdi
    call str_len
    mov rdx, rax            # length
    pop rsi                 # buffer
    mov rax, SYS_WRITE
    mov rdi, STDERR
    syscall
    mov rsp, rbp
    pop rbp
    ret

# read_file(rdi: filename_ptr) -> rax: bytes_read
read_file:
    push rbp
    mov rbp, rsp
    push rbx

    # sys_open(filename, O_RDONLY, 0)
    mov rax, SYS_OPEN
    mov rsi, O_RDONLY
    xor rdx, rdx
    syscall

    cmp rax, 0
    jl .L_rf_open_err

    mov rbx, rax            # save fd

    # sys_read(fd, src_buffer, SRC_BUF_SIZE - 1)
    mov rax, SYS_READ
    mov rdi, rbx
    lea rsi, [src_buffer]
    mov rdx, SRC_BUF_SIZE - 1
    syscall

    cmp rax, 0
    jl .L_rf_read_err

    # store src_len and null terminate
    mov [src_len], rax
    lea rdi, [src_buffer]
    mov BYTE PTR [rdi + rax], 0

    # sys_close(fd)
    push rax                # save bytes_read
    mov rax, SYS_CLOSE
    mov rdi, rbx
    syscall
    pop rax                 # restore bytes_read

    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_rf_open_err:
    lea rdi, [msg_err_open]
    call print_err
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

.L_rf_read_err:
    lea rdi, [msg_err_read]
    call print_err
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

# load_source_with_imports(rdi: root_filename)
load_source_with_imports:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov QWORD PTR [imported_count], 0
    mov QWORD PTR [src_len], 0

    call load_file_recursive

    # Null terminate src_buffer
    mov rax, [src_len]
    lea rdi, [src_buffer]
    mov BYTE PTR [rdi + rax], 0

    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# load_file_recursive(rdi: filename_ptr)
load_file_recursive:
    push rbp
    mov rbp, rsp
    sub rsp, 288            # 256 bytes for path buffer, plus locals
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi            # filename_ptr

    # 1. Check if already imported
    xor r14, r14
.L_chk_imp_loop:
    cmp r14, [imported_count]
    jge .L_not_yet_imported

    mov rbx, r14
    shl rbx, 8              # index * 256
    lea r15, [imported_files_buf + rbx]

    mov rdi, r12
    call str_len
    mov r13, rax            # len1

    mov rdi, r15
    call str_len
    mov rcx, rax            # len2

    mov rdi, r12            # str1
    mov rsi, r13            # len1
    mov rdx, r15            # str2
    call str_cmp_n
    cmp rax, 0
    je .L_already_imported

    inc r14
    jmp .L_chk_imp_loop

.L_already_imported:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_not_yet_imported:
    # Add to imported_files_buf
    mov rbx, [imported_count]
    cmp rbx, MAX_IMPORTS
    jge .L_too_many_imports

    mov rdi, r12
    call str_len
    mov rdx, rax
    inc rdx                 # include null terminator
    shl rbx, 8              # index * 256
    lea rdi, [imported_files_buf + rbx]
    mov rsi, r12
    call str_copy

    inc QWORD PTR [imported_count]

    # Open file
    mov rax, SYS_OPEN
    mov rdi, r12
    mov rsi, O_RDONLY
    xor rdx, rdx
    syscall

    cmp rax, 0
    jl .L_rf_open_err

    mov r13, rax            # fd

    # Read into [src_buffer + src_len]
    mov rbx, [src_len]
    lea rsi, [src_buffer + rbx]
    mov rdx, SRC_BUF_SIZE
    sub rdx, rbx
    dec rdx
    cmp rdx, 0
    jle .L_rf_overflow

    mov rax, SYS_READ
    mov rdi, r13
    syscall

    cmp rax, 0
    jl .L_rf_read_err

    mov r14, rax            # bytes read
    add [src_len], r14

    # Close file
    mov rax, SYS_CLOSE
    mov rdi, r13
    syscall

    # Append newline
    mov rax, [src_len]
    lea rdi, [src_buffer]
    mov BYTE PTR [rdi + rax], 10
    inc QWORD PTR [src_len]

    # Scan chunk for import "..."
    lea r15, [src_buffer + rbx]
    lea rbx, [r15 + r14]    # chunk end

.L_scan_imp_loop:
    cmp r15, rbx
    jge .L_scan_imp_done

    movzx rax, BYTE PTR [r15]
    cmp rax, 'i'
    jne .L_scan_next_char

    lea rdi, [r15]
    mov rsi, 6
    lea rdx, [str_kw_import]
    mov rcx, 6
    call str_cmp_n
    cmp rax, 0
    jne .L_scan_next_char

    movzx rax, BYTE PTR [r15 + 6]
    cmp rax, ' '
    je .L_found_import_kw
    cmp rax, '\t'
    je .L_found_import_kw
    jmp .L_scan_next_char

.L_found_import_kw:
    mov r8, r15             # start of import statement
    add r15, 6

.L_skip_ws_to_quote:
    cmp r15, rbx
    jge .L_scan_imp_done
    movzx rax, BYTE PTR [r15]
    cmp rax, '"'
    je .L_found_imp_quote
    cmp rax, '\n'
    je .L_scan_next_char
    inc r15
    jmp .L_skip_ws_to_quote

.L_found_imp_quote:
    inc r15                 # skip opening quote
    mov r9, r15             # path start

.L_scan_imp_path:
    cmp r15, rbx
    jge .L_scan_imp_done
    movzx rax, BYTE PTR [r15]
    cmp rax, '"'
    je .L_found_imp_end_quote
    cmp rax, '\n'
    je .L_scan_next_char
    inc r15
    jmp .L_scan_imp_path

.L_found_imp_end_quote:
    mov rcx, r15
    sub rcx, r9             # path len
    cmp rcx, 255
    jge .L_imp_path_too_long

    lea rdi, [rbp - 288]
    mov rsi, r9
    mov rdx, rcx
    call str_copy
    lea rdi, [rbp - 288]
    mov BYTE PTR [rdi + rcx], 0

    # Blank out import statement with spaces
    mov rdx, r8
.L_blank_loop:
    cmp rdx, r15
    jg .L_blank_done
    cmp BYTE PTR [rdx], '\n'
    je .L_skip_blank_nl
    mov BYTE PTR [rdx], ' '
.L_skip_blank_nl:
    inc rdx
    jmp .L_blank_loop
.L_blank_done:

    inc r15                 # skip closing quote

    # Blank out optional trailing spaces and ';'
.L_blank_semi_loop:
    cmp r15, rbx
    jge .L_done_blank_semi
    movzx rax, BYTE PTR [r15]
    cmp rax, ' '
    je .L_blank_semi_char
    cmp rax, '\t'
    je .L_blank_semi_char
    cmp rax, ';'
    je .L_blank_semi_char
    jmp .L_done_blank_semi
.L_blank_semi_char:
    mov BYTE PTR [r15], ' '
    inc r15
    jmp .L_blank_semi_loop
.L_done_blank_semi:
    push rbx
    push r15
    lea rdi, [rbp - 288]
    call load_file_recursive
    pop r15
    pop rbx

    jmp .L_scan_imp_loop

.L_scan_next_char:
    inc r15
    jmp .L_scan_imp_loop

.L_scan_imp_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_too_many_imports:
    lea rdi, [msg_err_too_many_imports]
    call print_err
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

.L_rf_overflow:
    lea rdi, [msg_err_src_overflow]
    call print_err
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

.L_imp_path_too_long:
    lea rdi, [msg_err_imp_path_long]
    call print_err
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

# write_file(rdi: filename, rsi: buffer, rdx: len)
write_file:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov r12, rsi            # buffer
    mov r13, rdx            # len

    # sys_open(filename, O_WRONLY|O_CREAT|O_TRUNC, 0644 octal = 420)
    mov rax, SYS_OPEN
    mov rsi, 577            # 1 | 64 | 512
    mov rdx, 420            # 0644
    syscall

    cmp rax, 0
    jl .L_wf_open_err

    mov rbx, rax            # fd

    # sys_write(fd, buffer, len)
    mov rax, SYS_WRITE
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    syscall

    # sys_close(fd)
    mov rax, SYS_CLOSE
    mov rdi, rbx
    syscall

    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_wf_open_err:
    lea rdi, [msg_err_write]
    call print_err
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

# compiler_panic(rdi: msg_ptr, rsi: line_num)
compiler_panic:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi            # msg
    mov r12, rsi            # line

    # 1. Print "Rubix Compiler Error: <msg>\n"
    lea rdi, [msg_panic_prefix]
    call print_err
    mov rdi, rbx
    call print_err
    lea rdi, [msg_newline]
    call print_err

    # If line <= 0, exit immediately
    cmp r12, 0
    jle .L_panic_exit

    # 2. Print "  --> line <line_num>\n"
    lea rdi, [msg_panic_arrow]
    call print_err
    mov rax, r12
    lea rdi, [tmp_num_buf]
    call int_to_str
    mov rdx, rax
    lea rsi, [tmp_num_buf]
    mov rax, SYS_WRITE
    mov rdi, STDERR
    syscall
    lea rdi, [msg_newline]
    call print_err

    # 3. Print "   |\n"
    lea rdi, [msg_panic_gutter]
    call print_err

    # 4. Find line r12 in src_buffer
    lea r13, [src_buffer]   # r13 = src_buffer base (callee-saved)
    mov r10, [src_len]      # r10 = total src len
    xor rcx, rcx            # current index in src_buffer
    mov r8, 1               # current line number

.L_find_line_loop:
    cmp rcx, r10
    jge .L_panic_exit
    cmp r8, r12
    je .L_found_line_start
    cmp BYTE PTR [r13 + rcx], 10   # '\n'
    jne .L_skip_char
    inc r8
.L_skip_char:
    inc rcx
    jmp .L_find_line_loop

.L_found_line_start:
    mov r14, rcx            # r14 = line_start offset (callee-saved)

.L_find_line_end:
    cmp rcx, r10
    jge .L_found_line_end
    cmp BYTE PTR [r13 + rcx], 10
    je .L_found_line_end
    cmp BYTE PTR [r13 + rcx], 13   # '\r'
    je .L_found_line_end
    inc rcx
    jmp .L_find_line_end

.L_found_line_end:
    mov r15, rcx
    sub r15, r14            # r15 = line length (callee-saved)

    # Print " " + line_num + " | "
    lea rdi, [msg_space]
    call print_err
    mov rax, r12
    lea rdi, [tmp_num_buf]
    call int_to_str
    mov rdx, rax
    lea rsi, [tmp_num_buf]
    mov rax, SYS_WRITE
    mov rdi, STDERR
    syscall
    lea rdi, [msg_pipe_space]
    call print_err

    # Print the line text itself
    cmp r15, 0
    jle .L_print_caret
    mov rax, SYS_WRITE
    mov rdi, STDERR
    lea rsi, [r13 + r14]
    mov rdx, r15
    syscall

.L_print_caret:
    lea rdi, [msg_newline]
    call print_err

    # Print "   | ^\n"
    lea rdi, [msg_panic_caret_line]
    call print_err

.L_panic_exit:
    mov rax, SYS_EXIT
    mov rdi, 1
    syscall

.data
msg_err_open:          .string "Error: Failed to open input file\n"
msg_err_read:          .string "Error: Failed to read input file\n"
msg_err_write:         .string "Error: Failed to create/write output file\n"
msg_panic_prefix:      .string "Rubix Compiler Error: "
msg_panic_arrow:       .string "  --> line "
msg_panic_gutter:      .string "   |\n"
msg_space:             .string " "
msg_pipe_space:        .string " | "
msg_panic_caret_line:  .string "   | ^\n"
msg_newline:           .string "\n"
str_kw_import:           .string "import"
msg_err_too_many_imports: .string "Error: Maximum imported modules limit exceeded\n"
msg_err_src_overflow:     .string "Error: Source buffer overflow (source files too large)\n"
msg_err_imp_path_long:    .string "Error: Import path too long (maximum 255 characters)\n"

.bss
tmp_num_buf: .skip 32
