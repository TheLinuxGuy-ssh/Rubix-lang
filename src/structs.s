.intel_syntax noprefix

.text

# struct_find(rdi: name_ptr, rsi: name_len) -> rax: struct_entry_ptr or 0
struct_find:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi            # target name
    mov r13, rsi            # target len

    xor rbx, rbx            # index
.L_sf_loop:
    cmp rbx, [structs_count]
    jge .L_sf_not_found

    mov rax, rbx
    imul rax, STRUCT_ENTRY_SIZE
    lea r14, [structs_buf + rax]

    # Compare struct name
    mov rdi, r12
    mov rsi, r13
    lea rdx, [r14 + 0]
    mov rcx, [r14 + 32]
    call str_cmp_n
    cmp rax, 0
    je .L_sf_found

    inc rbx
    jmp .L_sf_loop

.L_sf_found:
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_sf_not_found:
    xor rax, rax
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# struct_get_field_offset(rdi: struct_entry_ptr, rsi: field_name_ptr, rdx: field_name_len) -> rax: offset (or -1 if not found)
struct_get_field_offset:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi            # entry_ptr (or 0)
    mov r13, rsi            # field name
    mov r14, rdx            # field name len

    test r12, r12
    jnz .L_sgf_search_entry

    # If entry_ptr is 0, search all structs
    xor rbx, rbx
.L_sgf_all_structs:
    cmp rbx, [structs_count]
    jge .L_sgf_not_found
    mov rax, rbx
    imul rax, STRUCT_ENTRY_SIZE
    lea r12, [structs_buf + rax]

    # Search fields of this struct
    mov r15, [r12 + 40]     # field_count
    xor rcx, rcx            # field idx
.L_sgf_fields_all:
    cmp rcx, r15
    jge .L_sgf_next_struct

    push rcx
    mov rax, rcx
    imul rax, STRUCT_FIELD_SIZE
    lea rax, [r12 + 48 + rax]

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rax + 0]
    mov rcx, [rax + 32]
    push rax
    call str_cmp_n
    pop r8
    pop rcx
    test rax, rax
    jz .L_sgf_matched_r8

    inc rcx
    jmp .L_sgf_fields_all

.L_sgf_next_struct:
    inc rbx
    jmp .L_sgf_all_structs

.L_sgf_search_entry:
    mov r15, [r12 + 40]     # field_count
    xor rcx, rcx
.L_sgf_entry_loop:
    cmp rcx, r15
    jge .L_sgf_not_found

    push rcx
    mov rax, rcx
    imul rax, STRUCT_FIELD_SIZE
    lea rax, [r12 + 48 + rax]

    mov rdi, r13
    mov rsi, r14
    lea rdx, [rax + 0]
    mov rcx, [rax + 32]
    push rax
    call str_cmp_n
    pop r8
    pop rcx
    test rax, rax
    jz .L_sgf_matched_r8

    inc rcx
    jmp .L_sgf_entry_loop

.L_sgf_matched_r8:
    mov rax, [r8 + 40]      # field offset
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_sgf_not_found:
    mov rax, -1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# parse_struct_decl()
# Expects cur_tok to be TOK_STRUCT
parse_struct_decl:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    call advance_token      # skip 'struct'

    # Expect struct name
    call get_cur_tok_ptr
    mov r12, [rax + 8]      # struct name ptr
    mov r13, [rax + 16]     # struct name len
    mov rdi, TOK_IDENT
    lea rsi, [msg_err_expected_struct_name]
    call expect_tok         # verifies ident and advances past it

    # Check if struct is already declared (e.g. from prepass)
    mov rdi, r12
    mov rsi, r13
    call struct_find
    test rax, rax
    jz .L_psd_do_register

    # Already declared: just skip to closing '}'
    xor rcx, rcx
.L_psd_skip_loop:
    call get_cur_tok_ptr
    mov rax, [rax + 0]
    cmp rax, TOK_RBRACE
    je .L_psd_skip_done
    cmp rax, TOK_EOF
    je .L_psd_err_eof
    call advance_token
    jmp .L_psd_skip_loop
.L_psd_skip_done:
    call advance_token      # skip '}'
    call get_cur_tok_ptr
    mov rax, [rax + 0]
    cmp rax, TOK_SEMICOLON
    jne .L_psd_skip_ret
    call advance_token
.L_psd_skip_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_psd_do_register:
    # Check capacity
    mov rax, [structs_count]
    cmp rax, MAX_STRUCTS
    jge .L_psd_overflow

    # Allocate new struct entry
    imul rax, STRUCT_ENTRY_SIZE
    lea r14, [structs_buf + rax]
    inc QWORD PTR [structs_count]

    # Copy struct name into entry
    xor rcx, rcx
.L_psd_cp_name:
    cmp rcx, r13
    jge .L_psd_name_done
    cmp rcx, 31
    jge .L_psd_name_done
    mov dl, [r12 + rcx]
    mov [r14 + rcx], dl
    inc rcx
    jmp .L_psd_cp_name
.L_psd_name_done:
    mov BYTE PTR [r14 + rcx], 0
    mov [r14 + 32], r13     # struct name len
    mov QWORD PTR [r14 + 40], 0 # initial field count

    # Expect '{'
    mov rdi, TOK_LBRACE
    lea rsi, [msg_err_expected_lbrace]
    call expect_tok

    xor r15, r15            # field count
    xor rbx, rbx            # field byte offset (0, 8, 16...)

.L_psd_field_loop:
    call get_cur_tok_ptr
    mov rax, [rax + 0]      # token type
    cmp rax, TOK_RBRACE
    je .L_psd_done
    cmp rax, TOK_EOF
    je .L_psd_err_eof

    cmp rax, TOK_SEMICOLON
    jne .L_psd_chk_ident
    call advance_token
    jmp .L_psd_field_loop

.L_psd_chk_ident:
    cmp rax, TOK_IDENT
    jne .L_psd_err_expected_field

    call get_cur_tok_ptr
    mov r12, [rax + 8]      # field name ptr
    mov r13, [rax + 16]     # field name len
    call advance_token

    # Add field to entry: field slot at r14 + 48 + (r15 * 48)
    mov rax, r15
    imul rax, STRUCT_FIELD_SIZE
    lea r8, [r14 + 48 + rax]

    # Copy field name
    xor rcx, rcx
.L_psd_cp_fname:
    cmp rcx, r13
    jge .L_psd_fname_done
    cmp rcx, 31
    jge .L_psd_fname_done
    mov dl, [r12 + rcx]
    mov [r8 + rcx], dl
    inc rcx
    jmp .L_psd_cp_fname
.L_psd_fname_done:
    mov BYTE PTR [r8 + rcx], 0
    mov [r8 + 32], r13      # field name len
    mov [r8 + 40], rbx      # field offset
    add rbx, 8              # each field is 8 bytes
    inc r15                 # field_count++

    # Check for ':' type annotation
    call get_cur_tok_ptr
    mov rax, [rax + 0]
    cmp rax, TOK_COLON
    jne .L_psd_chk_comma
    call advance_token      # skip ':'
    call advance_token      # skip type (int, float, etc.)

.L_psd_chk_comma:
    call get_cur_tok_ptr
    mov rax, [rax + 0]
    cmp rax, TOK_COMMA
    jne .L_psd_chk_semi
    call advance_token
    jmp .L_psd_field_loop

.L_psd_chk_semi:
    cmp rax, TOK_SEMICOLON
    jne .L_psd_field_loop
    call advance_token
    jmp .L_psd_field_loop

.L_psd_done:
    call advance_token      # skip '}'
    # Optional trailing semicolon
    call get_cur_tok_ptr
    mov rax, [rax + 0]
    cmp rax, TOK_SEMICOLON
    jne .L_psd_ret
    call advance_token

.L_psd_ret:
    mov [r14 + 40], r15     # store final field count
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# collect_structs()
# Scans all tokens and parses all top-level struct declarations ahead of function body parsing
collect_structs:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov r12, [cur_tok_idx]  # save cur_tok_idx
    mov QWORD PTR [cur_tok_idx], 0
    mov QWORD PTR [structs_count], 0

.L_cs_loop:
    call get_cur_tok_ptr
    mov rax, [rax + 0]
    cmp rax, TOK_EOF
    je .L_cs_done

    cmp rax, TOK_STRUCT
    jne .L_cs_next

    call parse_struct_decl
    jmp .L_cs_loop

.L_cs_next:
    call advance_token
    jmp .L_cs_loop

.L_cs_done:
    mov [cur_tok_idx], r12  # restore cur_tok_idx
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_psd_err_eof:
    lea rdi, [msg_err_unexpected_eof]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.L_psd_err_expected_field:
    lea rdi, [msg_err_expected_field_name]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.L_psd_overflow:
    lea rdi, [msg_err_struct_overflow]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.data
msg_err_expected_struct_name: .string "Expected struct name after 'struct'"
msg_err_expected_field_name:  .string "Expected field identifier in struct declaration"
msg_err_struct_overflow:      .string "Maximum number of structs exceeded"
