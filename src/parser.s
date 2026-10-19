.intel_syntax noprefix

.text

# get_cur_tok_ptr() -> rax
get_cur_tok_ptr:
    mov rax, [cur_tok_idx]
    shl rax, 5              # index * 32
    lea rax, [tokens_buf + rax]
    ret

# advance_token()
advance_token:
    inc QWORD PTR [cur_tok_idx]
    ret

# peek_tok_type(rdi: offset) -> rax: type
peek_tok_type:
    mov rax, [cur_tok_idx]
    add rax, rdi
    cmp rax, [tok_count]
    jge .L_peek_eof
    shl rax, 5
    lea rax, [tokens_buf + rax]
    mov rax, [rax + 0]      # token type
    ret
.L_peek_eof:
    mov rax, TOK_EOF
    ret

# expect_tok(rdi: expected_type, rsi: err_msg)
expect_tok:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi

    call get_cur_tok_ptr
    mov rcx, [rax + 0]      # current type
    cmp rcx, rbx
    jne .L_expect_fail

    call advance_token
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_expect_fail:
    call get_cur_tok_ptr
    mov rsi, [rax + 24]     # current line
    mov rdi, r12            # err_msg
    call compiler_panic

# collect_user_functions()
collect_user_functions:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov QWORD PTR [user_fn_count], 0
    xor rbx, rbx

.L_cuf_loop:
    cmp rbx, [tok_count]
    jge .L_cuf_done

    mov rax, rbx
    shl rax, 5              # index * 32
    lea rax, [tokens_buf + rax]
    cmp QWORD PTR [rax + 0], TOK_FN
    jne .L_cuf_next

    # next token must be ident
    inc rbx
    cmp rbx, [tok_count]
    jge .L_cuf_done

    mov rax, rbx
    shl rax, 5
    lea rax, [tokens_buf + rax]
    cmp QWORD PTR [rax + 0], TOK_IDENT
    jne .L_cuf_next

    # add to user_fn_buf
    mov r8, [user_fn_count]
    cmp r8, MAX_USER_FNS
    jge .L_cuf_done

    shl r8, 4               # index * 16
    lea r9, [user_fn_buf + r8]
    mov rcx, [rax + 8]      # name_ptr
    mov rdx, [rax + 16]     # name_len
    mov [r9 + 0], rcx
    mov [r9 + 8], rdx
    inc QWORD PTR [user_fn_count]

.L_cuf_next:
    inc rbx
    jmp .L_cuf_loop

.L_cuf_done:
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# is_user_fn(rdi: name_ptr, rsi: name_len) -> rax (1 if user fn, 0 if not)
is_user_fn:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi            # name_ptr
    mov r13, rsi            # name_len

    xor r14, r14

.L_iuf_loop:
    cmp r14, [user_fn_count]
    jge .L_iuf_no

    mov rbx, r14
    shl rbx, 4              # index * 16
    lea rbx, [user_fn_buf + rbx]

    mov rdi, r12
    mov rsi, r13
    mov rdx, [rbx + 0]      # entry name_ptr
    mov rcx, [rbx + 8]      # entry name_len
    call str_cmp_n
    cmp rax, 0
    je .L_iuf_yes

    inc r14
    jmp .L_iuf_loop

.L_iuf_yes:
    mov rax, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_iuf_no:
    xor rax, rax
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# --- Parser Entry Point ---
# parse_program()
parse_program:
    push rbp
    mov rbp, rsp
    push rbx

    mov QWORD PTR [cur_tok_idx], 0
    mov QWORD PTR [out_len], 0
    mov QWORD PTR [rodata_len], 0
    mov QWORD PTR [str_label_count], 0
    mov QWORD PTR [main_defined], 0

    # Initialize default code emission to out_buffer
    call emit_to_out

    # Pre-collect user-defined function names so they can override built-in print
    call collect_user_functions

    # Emit assembly header
    lea rdi, [str_header]
    call emit_cstr

.L_prog_loop:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]      # token type
    cmp rbx, TOK_EOF
    je .L_prog_done

    cmp rbx, TOK_SEMICOLON
    jne .L_prog_chk_fn
    call advance_token
    jmp .L_prog_loop

.L_prog_chk_fn:
    cmp rbx, TOK_FN
    jne .L_prog_not_fn

    call parse_fn
    jmp .L_prog_loop

.L_prog_not_fn:
    lea rdi, [msg_err_expected_fn]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.L_prog_done:
    call append_rodata_and_runtime

    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# --- Function Parsing ---
# parse_fn()
parse_fn:
    push rbp
    mov rbp, rsp
    sub rsp, 96
    push rbx
    push r12
    push r13
    push r14
    push r15

    # Increment function label base for unique labels across functions
    mov rax, [fn_label_base]
    add rax, 1000000
    mov [fn_label_base], rax

    # expect 'fn'
    mov rdi, TOK_FN
    lea rsi, [msg_err_expected_fn]
    call expect_tok

    # expect identifier
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_IDENT
    jne .L_pfn_err_name

    mov r12, [rax + 8]      # fn_name_ptr
    mov r13, [rax + 16]     # fn_name_len
    call advance_token

    # Check for duplicate main definition
    mov rdi, r12
    mov rsi, r13
    lea rdx, [str_main_name]
    mov rcx, 4
    call str_cmp_n
    cmp rax, 0
    jne .L_pfn_not_main_check

    cmp QWORD PTR [main_defined], 1
    je .L_pfn_err_redef_main
    mov QWORD PTR [main_defined], 1

.L_pfn_not_main_check:
    # expect '('
    mov rdi, TOK_LPAREN
    lea rsi, [msg_err_expected_lparen]
    call expect_tok

    # Clear symbol table and stack offset tracker for new function
    call symtab_clear

    # Parse parameter list (up to 6 parameters)
    xor r14, r14            # param count

.L_pfn_param_loop:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_RPAREN
    je .L_pfn_params_end

    # Check if leading type like `char c` or `bool b`
    cmp rbx, TOK_CHAR_KW
    je .L_pfn_skip_type_tok
    cmp rbx, TOK_BOOL_KW
    jne .L_pfn_chk_ident_type
.L_pfn_skip_type_tok:
    call advance_token
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    jmp .L_pfn_check_id

.L_pfn_chk_ident_type:
    cmp rbx, TOK_IDENT
    jne .L_pfn_err_param
    mov rdi, 1
    call peek_tok_type
    cmp rax, TOK_IDENT
    jne .L_pfn_check_id
    # consume type ident (e.g. `int x`)
    call advance_token
    call get_cur_tok_ptr
    mov rbx, [rax + 0]

.L_pfn_check_id:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_IDENT
    jne .L_pfn_err_param

    cmp r14, MAX_PARAMS
    jge .L_pfn_too_many_params

    # Save param info in fn_params_buf
    mov rcx, [rax + 8]      # param name_ptr
    mov rdx, [rax + 16]     # param name_len
    mov r8, r14
    shl r8, 4               # r14 * 16
    lea r9, [fn_params_buf + r8]
    mov [r9 + 0], rcx
    mov [r9 + 8], rdx
    inc r14

    call advance_token

    # Check if trailing `: type` like `x: int`
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_COLON
    jne .L_pfn_param_comma
    call advance_token      # skip ':'
    call advance_token      # skip type

.L_pfn_param_comma:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_COMMA
    jne .L_pfn_params_end
    call advance_token
    jmp .L_pfn_param_loop

.L_pfn_params_end:
    mov rdi, TOK_RPAREN
    lea rsi, [msg_err_expected_rparen]
    call expect_tok

    # Check if return type `: int` or `: bool` follows ')'
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_COLON
    jne .L_pfn_no_ret_type
    call advance_token      # skip ':'
    call advance_token      # skip return type

.L_pfn_no_ret_type:
    # expect '{'
    mov rdi, TOK_LBRACE
    lea rsi, [msg_err_expected_lbrace]
    call expect_tok

    # Redirect code emission into temporary fn_body_buf while compiling body
    call emit_to_fn

    # Enter function root scope
    call scope_enter

    # Spill parameters to stack
    xor r15, r15            # param index
.L_pfn_spill_params:
    cmp r15, r14
    jge .L_pfn_body

    mov r8, r15
    shl r8, 4               # r15 * 16
    lea r9, [fn_params_buf + r8]
    mov rdi, [r9 + 0]       # name_ptr
    mov rsi, [r9 + 8]       # name_len
    call symtab_add         # returns assigned stack offset in rax
    mov r10, rax            # save local offset in r10

    # Param register or stack for params 7-12
    cmp r15, 6
    jl .L_pfn_use_reg
    # Stack param: mov rax, QWORD PTR [rbp + 16 + (r15-6)*8]
    mov rax, r15
    sub rax, 6
    shl rax, 3               # (r15-6) * 8
    add rax, 16              # + 16 (after saved rbp + return addr)
    push rax
    lea rdi, [str_mov_rax_rbp_stack]
    call emit_cstr
    pop rax
    call emit_int
    lea rdi, [str_close_bracket_nl]
    call emit_cstr
    # Now store rax (loaded from stack param) to local slot at r10 offset
    mov rax, r10             # restore local offset
    push rax
    lea rdi, [str_mov_qword_rbp]
    call emit_cstr
    pop rax
    call emit_int
    lea rdi, [str_close_bracket_rax]
    call emit_cstr
    jmp .L_pfn_spill_next
.L_pfn_use_reg:
    # emit "    mov QWORD PTR [rbp - {offset}], {reg}\n" into fn_body_buf
    push rax                 # rax = local offset from symtab_add
    lea rdi, [str_mov_qword_rbp]
    call emit_cstr
    pop rax
    call emit_int
    lea rdi, [str_close_bracket_comma]
    call emit_cstr

    mov rdi, [param_regs + r15*8]
    call emit_cstr
    call emit_nl
    jmp .L_pfn_spill_next
.L_pfn_store_param:
.L_pfn_spill_next:
    inc r15
    jmp .L_pfn_spill_params

.L_pfn_body:
    # Parse statements until '}'
.L_pfn_body_loop:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_RBRACE
    je .L_pfn_body_done
    cmp rbx, TOK_EOF
    je .L_pfn_err_eof

    call parse_statement
    jmp .L_pfn_body_loop

.L_pfn_body_done:
    # expect '}'
    mov rdi, TOK_RBRACE
    lea rsi, [msg_err_expected_rbrace]
    call expect_tok

    # Exit function root scope
    call scope_exit

    # Switch emission back to out_buffer
    call emit_to_out

    # Calculate dynamic stack frame size
    # After push rbp, rsp ≡ 8 (mod 16). Need X ≡ 8 (mod 16) so rsp ≡ 0 (mod 16) before calls.
    mov rax, [max_stack_offset]
    mov rdx, rax
    and rdx, 15             # rdx = rax % 16 (0 or 8 since rax is multiple of 8)
    jnz .L_pfn_ok_mod16     # already ≡ 8 mod 16
    add rax, 8              # ≡ 0 mod 16 → add 8 to make ≡ 8 mod 16
.L_pfn_ok_mod16:
    cmp rax, 8              # minimum 8 bytes for alignment
    jge .L_pfn_frame_ok
    mov rax, 8
.L_pfn_frame_ok:
    push rax                # save frame_size

    # Emit: .global <name>\n<name>:\n
    lea rdi, [str_global]
    call emit_cstr
    mov rdi, r12
    mov rsi, r13
    call emit_str
    call emit_nl

    mov rdi, r12
    mov rsi, r13
    call emit_str
    lea rdi, [str_colon_nl]
    call emit_cstr

    # Emit dynamic prologue:
    #     push rbp
    #     mov rbp, rsp
    #     sub rsp, {frame_size}
    lea rdi, [str_push_mov_rbp]
    call emit_cstr
    pop rax                 # frame_size
    call emit_int
    call emit_nl

    # Append all buffered statements from fn_body_buf to out_buffer
    lea rdi, [fn_body_buf]
    mov rsi, [fn_body_len]
    call emit_str

    # Function epilogue (default return 0)
    lea rdi, [str_fn_epilogue]
    call emit_cstr

    # Check if this function is "main"
    mov rdi, r12
    mov rsi, r13
    lea rdx, [str_main_name]
    mov rcx, 4
    call str_cmp_n
    cmp rax, 0
    jne .L_pfn_finish

    # Emit _start entry wrapper
    lea rdi, [str_start_entry]
    call emit_cstr

.L_pfn_finish:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_pfn_err_name:
    lea rdi, [msg_err_expected_fn_name]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.L_pfn_err_redef_main:
    lea rdi, [msg_err_redef_main]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.L_pfn_err_param:
    lea rdi, [msg_err_expected_param_name]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.L_pfn_too_many_params:
    lea rdi, [msg_err_too_many_params]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.L_pfn_err_eof:
    lea rdi, [msg_err_unexpected_eof]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

# --- Statements ---
# parse_statement()
parse_statement:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    call get_cur_tok_ptr
    mov rbx, [rax + 0]      # token type

    cmp rbx, TOK_LET
    je .L_stmt_let
    cmp rbx, TOK_RETURN
    je .L_stmt_return
    cmp rbx, TOK_IF
    je .L_stmt_if
    cmp rbx, TOK_WHILE
    je .L_stmt_while
    cmp rbx, TOK_FOR
    je .L_stmt_for
    cmp rbx, TOK_IDENT
    je .L_stmt_ident
    cmp rbx, TOK_SEMICOLON
    je .L_stmt_semi
    cmp rbx, TOK_BREAK
    je .L_stmt_break
    cmp rbx, TOK_CONTINUE
    je .L_stmt_continue

    # Unexpected token
    lea rdi, [msg_err_unexpected_stmt]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.L_stmt_semi:
    call advance_token
    jmp .L_stmt_done

.L_stmt_break:
    call advance_token      # skip 'break'
    # emit "    jmp .L_loop_end_{current_break_label}\n"
    call get_current_break_label
    push rax
    lea rdi, [str_jmp_loop_end]
    call emit_cstr
    pop rax
    call emit_int
    call emit_nl
    # expect semicolon (optional)
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_SEMICOLON
    jne .L_stmt_done
    call advance_token
    jmp .L_stmt_done

.L_stmt_continue:
    call advance_token      # skip 'continue'
    # emit "    jmp .L_loop_{current_continue_label}\n"
    call get_current_continue_label
    push rax
    lea rdi, [str_jmp_loop_start]
    call emit_cstr
    pop rax
    call emit_int
    call emit_nl
    # expect semicolon (optional)
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_SEMICOLON
    jne .L_stmt_done
    call advance_token
    jmp .L_stmt_done

# --- LET STATEMENT ---
# let <id> = <expr>;
# or let <type> <id> = <expr>;
# or let <id>: <type> = <expr>;
.L_stmt_let:
    call advance_token      # skip 'let'

    call get_cur_tok_ptr
    mov rbx, [rax + 0]

    # check leading type (e.g. `let char c` or `let bool b`)
    cmp rbx, TOK_CHAR_KW
    je .L_let_skip_type
    cmp rbx, TOK_BOOL_KW
    jne .L_let_chk_id_type
.L_let_skip_type:
    call advance_token
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    jmp .L_let_got_id

.L_let_chk_id_type:
    cmp rbx, TOK_IDENT
    jne .L_stmt_err_let_id
    mov rdi, 1
    call peek_tok_type
    cmp rax, TOK_IDENT
    jne .L_let_got_id
    # consume type ident (e.g. `let int x`)
    call advance_token
    call get_cur_tok_ptr
    mov rbx, [rax + 0]

.L_let_got_id:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_IDENT
    jne .L_stmt_err_let_id

    mov r12, [rax + 8]      # id_ptr
    mov r13, [rax + 16]     # id_len
    call advance_token

    # check trailing `: type` (e.g. `let x: int = ...`)
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_COLON
    jne .L_let_assign
    call advance_token      # skip ':'
    call advance_token      # skip type

.L_let_assign:
    # expect '='
    mov rdi, TOK_ASSIGN
    lea rsi, [msg_err_expected_assign]
    call expect_tok

    # parse expression into rax
    call parse_expr

    # allocate stack slot in symtab (with scope redeclaration guard)
    mov rdi, r12
    mov rsi, r13
    call symtab_add         # returns offset in rax

    # emit "    mov QWORD PTR [rbp - {offset}], rax\n"
    push rax
    lea rdi, [str_mov_qword_rbp]
    call emit_cstr
    pop rax
    call emit_int
    lea rdi, [str_close_bracket_rax]
    call emit_cstr

    # optional semicolon
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_SEMICOLON
    jne .L_stmt_done
    call advance_token
    jmp .L_stmt_done

.L_stmt_err_let_id:
    lea rdi, [msg_err_expected_let_ident]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

# --- RETURN STATEMENT ---
# return <expr>;
.L_stmt_return:
    call advance_token      # skip 'return'

    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_SEMICOLON
    je .L_stmt_ret_zero
    cmp rbx, TOK_RBRACE
    je .L_stmt_ret_zero

    call parse_expr
    jmp .L_stmt_ret_emit

.L_stmt_ret_zero:
    lea rdi, [str_xor_rax_rax]
    call emit_cstr

.L_stmt_ret_emit:
    lea rdi, [str_ret_code]
    call emit_cstr

    # optional semicolon
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_SEMICOLON
    jne .L_stmt_done
    call advance_token
    jmp .L_stmt_done

# --- IF STATEMENT ---
# if <expr> { <stmts> } [else [if ...] { <stmts> }]
.L_stmt_if:
    call advance_token      # skip 'if'

    # Generate 2 labels: else, end
    mov rax, [label_ctr]
    add rax, 1
    mov [label_ctr], rax
    mov r12, rax # else label
    mov rax, [label_ctr]
    add rax, 1
    mov [label_ctr], rax
    mov r13, rax # end label

    # parse condition into rax
    call parse_expr

    # emit "    cmp rax, 0\n    je .L_else_{r12}\n"
    lea rdi, [str_cmp_rax_zero_je]
    call emit_cstr
    mov rax, r12
    call emit_int
    call emit_nl

    # expect '{'
    mov rdi, TOK_LBRACE
    lea rsi, [msg_err_expected_lbrace]
    call expect_tok

    # Enter block scope
    call scope_enter

.L_stmt_if_then_loop:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_RBRACE
    je .L_stmt_if_then_end
    cmp rbx, TOK_EOF
    je .L_stmt_if_err_eof

    call parse_statement
    jmp .L_stmt_if_then_loop

.L_stmt_if_then_end:
    mov rdi, TOK_RBRACE
    lea rsi, [msg_err_expected_rbrace]
    call expect_tok

    # Exit block scope
    call scope_exit

    # check if 'else' exists
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_ELSE
    jne .L_stmt_if_no_else

    # has else: emit "    jmp .L_end_{r13}\n.L_else_{r12}:\n"
    call advance_token      # skip 'else'
    lea rdi, [str_jmp_end]
    call emit_cstr
    mov rax, r13
    call emit_int
    call emit_nl

    lea rdi, [str_label_else]
    call emit_cstr
    mov rax, r12
    call emit_int
    lea rdi, [str_colon_nl]
    call emit_cstr

    # check if 'else if'
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_IF
    jne .L_stmt_if_else_block

    call parse_statement   # parse the chained 'if'
    jmp .L_stmt_if_emit_end

.L_stmt_if_else_block:
    # expect '{'
    mov rdi, TOK_LBRACE
    lea rsi, [msg_err_expected_lbrace]
    call expect_tok

    # Enter else block scope
    call scope_enter

.L_stmt_if_else_loop:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_RBRACE
    je .L_stmt_if_else_end
    cmp rbx, TOK_EOF
    je .L_stmt_if_err_eof

    call parse_statement
    jmp .L_stmt_if_else_loop

.L_stmt_if_else_end:
    mov rdi, TOK_RBRACE
    lea rsi, [msg_err_expected_rbrace]
    call expect_tok

    # Exit else block scope
    call scope_exit

.L_stmt_if_emit_end:
    lea rdi, [str_label_end]
    call emit_cstr
    mov rax, r13
    call emit_int
    lea rdi, [str_colon_nl]
    call emit_cstr
    jmp .L_stmt_done

.L_stmt_if_no_else:
    # emit ".L_else_{r12}:\n"
    lea rdi, [str_label_else]
    call emit_cstr
    mov rax, r12
    call emit_int
    lea rdi, [str_colon_nl]
    call emit_cstr
    jmp .L_stmt_done

.L_stmt_if_err_eof:
    lea rdi, [msg_err_unexpected_eof]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

# --- WHILE STATEMENT ---
# while <expr> { <stmts> }
.L_stmt_while:
    call advance_token      # skip 'while'

    # Generate 2 labels: start, end
    mov rax, [label_ctr]
    add rax, 1
    mov [label_ctr], rax
    mov r12, rax # start label
    mov rax, [label_ctr]
    add rax, 1
    mov [label_ctr], rax
    mov r13, rax # end label

    # emit ".L_loop_{r12}:\n"
    lea rdi, [str_label_loop]
    call emit_cstr
    mov rax, r12
    call emit_int
    lea rdi, [str_colon_nl]
    call emit_cstr

    # parse condition into rax
    call parse_expr

    # emit "    cmp rax, 0\n    je .L_loop_end_{r13}\n"
    lea rdi, [str_cmp_rax_zero_je_loop]
    call emit_cstr
    mov rax, r13
    call emit_int
    call emit_nl

    # expect '{'
    mov rdi, TOK_LBRACE
    lea rsi, [msg_err_expected_lbrace]
    call expect_tok

    # Enter while block scope
    call scope_enter

    # Push break/continue labels for this loop
    mov rdi, r12      # break label = loop_end
    mov rsi, r13      # wait, break jumps to end, continue jumps to start
    # Actually: break -> .L_loop_end_{r13}, continue -> .L_loop_{r12}
    mov rdi, r13      # break label
    mov rsi, r12      # continue label
    call loop_enter

.L_stmt_while_loop:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_RBRACE
    je .L_stmt_while_done
    cmp rbx, TOK_EOF
    je .L_stmt_if_err_eof

    call parse_statement
    jmp .L_stmt_while_loop

.L_stmt_while_done:
    mov rdi, TOK_RBRACE
    lea rsi, [msg_err_expected_rbrace]
    call expect_tok

    # Exit while block scope
    call loop_exit
    call scope_exit

    # emit "    jmp .L_loop_{r12}\n.L_loop_end_{r13}:\n"
    lea rdi, [str_jmp_loop]
    call emit_cstr
    mov rax, r12
    call emit_int
    call emit_nl

    lea rdi, [str_label_loop_end]
    call emit_cstr
    mov rax, r13
    call emit_int
    lea rdi, [str_colon_nl]
    call emit_cstr
    jmp .L_stmt_done

# --- FOR STATEMENT ---
# for (<init>; <cond>; <incr>) { <stmts> }
# Supports empty init, empty cond (defaults true), empty incr.
# Init: let-decl or expression. Increment: assignment or expression.
.L_stmt_for:
    call advance_token      # skip 'for'
    sub rsp, 40             # allocate local frame for this for loop
    call scope_enter        # scope for loop-scoped variables

    # Generate 3 labels: start, step, end
    mov rax, [label_ctr]
    inc rax
    mov [label_ctr], rax
    mov [rbp - 48], rax     # start_label

    mov rax, [label_ctr]
    inc rax
    mov [label_ctr], rax
    mov [rbp - 56], rax     # step_label (continue target)

    mov rax, [label_ctr]
    inc rax
    mov [label_ctr], rax
    mov [rbp - 64], rax     # end_label (break & false cond target)

    # expect '('
    mov rdi, TOK_LPAREN
    lea rsi, [msg_err_expected_lparen]
    call expect_tok

    # 1. Parse <init>:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_SEMICOLON
    je .L_for_init_empty
    cmp rbx, TOK_LET
    je .L_for_init_is_let
    cmp rbx, TOK_IDENT
    jne .L_for_init_expr
    # Check if assignment (peek next is '=')
    mov rdi, 1
    call peek_tok_type
    cmp rax, TOK_ASSIGN
    jne .L_for_init_expr

    # Init is assignment: ident = expr
    call get_cur_tok_ptr
    mov r8, [rax + 8]
    mov r9, [rax + 16]
    push r8
    push r9
    call advance_token      # skip ident
    call advance_token      # skip '='
    call parse_expr         # result in rax
    pop rsi                 # id_len
    pop rdi                 # id_ptr
    call symtab_find
    cmp rax, -1
    je .L_stmt_err_undef_var
    push rax
    lea rdi, [str_mov_qword_rbp]
    call emit_cstr
    pop rax
    call emit_int
    lea rdi, [str_close_bracket_rax]
    call emit_cstr
    jmp .L_for_init_semi

.L_for_init_is_let:
    # let declaration: let id [: type] = expr
    call advance_token      # skip 'let'
    # parse ident
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_IDENT
    jne .L_stmt_err_let_id
    mov r15, [rax + 8]      # id_ptr
    push QWORD PTR [rax + 16] # id_len
    push r15                # id_ptr
    call advance_token      # skip id
    # check optional ': type'
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_COLON
    jne .L_for_let_no_type
    call advance_token      # skip ':'
    call advance_token      # skip type keyword
.L_for_let_no_type:
    # expect '='
    mov rdi, TOK_ASSIGN
    lea rsi, [msg_err_expected_assign]
    call expect_tok
    call parse_expr         # result in rax
    pop rdi                 # id_ptr
    pop rsi                 # id_len
    call symtab_add         # rax = offset
    push rax
    lea rdi, [str_mov_qword_rbp]
    call emit_cstr
    pop rax
    call emit_int
    lea rdi, [str_close_bracket_rax]
    call emit_cstr
    jmp .L_for_init_semi

.L_for_init_expr:
    call parse_expr
    # discard expression result
    jmp .L_for_init_semi

.L_for_init_empty:
    call advance_token      # skip ';'
    jmp .L_for_after_init

.L_for_init_semi:
    mov rdi, TOK_SEMICOLON
    lea rsi, [msg_err_expected_semi]
    call expect_tok

.L_for_after_init:
    # Emit start label: .L_loop_{start_label}:
    lea rdi, [str_label_loop]
    call emit_cstr
    mov rax, [rbp - 48]
    call emit_int
    lea rdi, [str_colon_nl]
    call emit_cstr

    # 2. Parse <cond>:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_SEMICOLON
    je .L_for_cond_empty

    call parse_expr         # cond in rax
    # emit "    cmp rax, 0\n    je .L_loop_end_{end_label}\n"
    lea rdi, [str_cmp_rax_zero_je_loop]
    call emit_cstr
    mov rax, [rbp - 64]
    call emit_int
    call emit_nl
    jmp .L_for_cond_semi

.L_for_cond_empty:
    # condition is empty -> infinite loop unless break

.L_for_cond_semi:
    mov rdi, TOK_SEMICOLON
    lea rsi, [msg_err_expected_semi]
    call expect_tok

    # 3. Record <step> tokens start position
    mov rax, [cur_tok_idx]
    mov [rbp - 72], rax

    # Scan forward to matching ')'
    xor rcx, rcx            # paren nesting level = 0
.L_for_scan_step:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_EOF
    je .L_for_err_eof
    cmp rbx, TOK_LPAREN
    jne .L_for_scan_not_lparen
    inc rcx
    call advance_token
    jmp .L_for_scan_step
.L_for_scan_not_lparen:
    cmp rbx, TOK_RPAREN
    jne .L_for_scan_advance
    cmp rcx, 0
    je .L_for_step_found_rparen
    dec rcx
    call advance_token
    jmp .L_for_scan_step
.L_for_scan_advance:
    call advance_token
    jmp .L_for_scan_step

.L_for_step_found_rparen:
    # cur_tok_idx is at the closing ')' of the for header
    mov rax, [cur_tok_idx]
    mov [rbp - 80], rax

    call advance_token      # skip ')'

    # expect '{'
    mov rdi, TOK_LBRACE
    lea rsi, [msg_err_expected_lbrace]
    call expect_tok

    # Push loop labels for break and continue:
    # break jumps to end_label, continue jumps to step_label
    mov rdi, [rbp - 64]       # break label = end_label
    mov rsi, [rbp - 56]       # continue label = step_label
    call loop_enter

    # 4. Parse body statements:
.L_for_body_loop:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_RBRACE
    je .L_for_body_done
    cmp rbx, TOK_EOF
    je .L_for_err_eof

    call parse_statement
    jmp .L_for_body_loop

.L_for_body_done:
    mov rdi, TOK_RBRACE
    lea rsi, [msg_err_expected_rbrace]
    call expect_tok

    call loop_exit

    # 5. Emit step label: .L_loop_{step_label}:
    lea rdi, [str_label_loop]
    call emit_cstr
    mov rax, [rbp - 56]
    call emit_int
    lea rdi, [str_colon_nl]
    call emit_cstr

    # 6. Parse and emit <step> if not empty:
    mov rax, [rbp - 72]
    mov rbx, [rbp - 80]
    cmp rax, rbx
    je .L_for_step_done

    push QWORD PTR [cur_tok_idx] # save position after '}'
    mov [cur_tok_idx], rax       # jump back to step_start_idx

    # Check if step is assignment: ident '=' expr
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_IDENT
    jne .L_for_step_as_expr
    mov rdi, 1
    call peek_tok_type
    cmp rax, TOK_ASSIGN
    jne .L_for_step_as_expr

    # Assignment step: ident = expr
    call get_cur_tok_ptr
    mov r8, [rax + 8]
    mov r9, [rax + 16]
    push r8
    push r9
    call advance_token      # skip id
    call advance_token      # skip '='
    call parse_expr         # result in rax
    pop rsi                 # id_len
    pop rdi                 # id_ptr
    call symtab_find
    cmp rax, -1
    je .L_stmt_err_undef_var
    push rax
    lea rdi, [str_mov_qword_rbp]
    call emit_cstr
    pop rax
    call emit_int
    lea rdi, [str_close_bracket_rax]
    call emit_cstr
    jmp .L_for_step_restored

.L_for_step_as_expr:
    call parse_expr

.L_for_step_restored:
    pop QWORD PTR [cur_tok_idx] # restore position back to after '}'

.L_for_step_done:
    # 7. Jump back to start:
    lea rdi, [str_jmp_loop_start]
    call emit_cstr
    mov rax, [rbp - 48]
    call emit_int
    call emit_nl

    # 8. Emit end label: .L_loop_end_{end_label}:
    lea rdi, [str_label_loop_end]
    call emit_cstr
    mov rax, [rbp - 64]
    call emit_int
    lea rdi, [str_colon_nl]
    call emit_cstr

    # 9. Clean up scope and local frame:
    call scope_exit
    add rsp, 40
    jmp .L_stmt_done

.L_for_err_eof:
    lea rdi, [msg_err_unexpected_eof]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

# --- IDENTIFIER (Assignment or Call) ---
.L_stmt_ident:
    # Lookahead to see if next token is '='
    mov rdi, 1
    call peek_tok_type
    cmp rax, TOK_ASSIGN
    je .L_stmt_assign_var
    cmp rax, TOK_LBRACKET
    je .L_stmt_assign_array
    jmp .L_stmt_expr_stmt

.L_stmt_assign_array:
    # Array element assignment: <id>[<index>] = <expr>;
    call get_cur_tok_ptr
    mov r12, [rax + 8]      # id_ptr
    mov r13, [rax + 16]     # id_len

    mov rdi, r12
    mov rsi, r13
    call symtab_find
    cmp rax, -1
    je .L_stmt_err_undef_var
    push rax                # save array variable offset on stack

    call advance_token      # skip id
    call advance_token      # skip '['

    call parse_expr         # evaluate index into rax

    mov rdi, TOK_RBRACKET
    lea rsi, [msg_err_expected_rbracket]
    call expect_tok

    lea rdi, [str_push_rax]
    call emit_cstr

    mov rdi, TOK_ASSIGN
    lea rsi, [msg_err_expected_assign]
    call expect_tok

    call parse_expr         # evaluate RHS into rax

    pop r14                 # restore array variable offset

    push rax
    lea rdi, [str_mov_rbx_rbp]
    call emit_cstr
    mov rax, r14
    call emit_int
    lea rdi, [str_close_bracket_nl]
    call emit_cstr
    pop rax

    lea rdi, [str_store_array_elem]
    call emit_cstr

    # optional semicolon
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_SEMICOLON
    jne .L_stmt_done
    call advance_token
    jmp .L_stmt_done

.L_stmt_assign_var:
    # Assignment: <id> = <expr>
    call get_cur_tok_ptr
    mov r12, [rax + 8]      # id_ptr
    mov r13, [rax + 16]     # id_len
    call advance_token      # skip id
    call advance_token      # skip '='

    # parse expression into rax
    call parse_expr

    # find symbol offset
    mov rdi, r12
    mov rsi, r13
    call symtab_find
    cmp rax, -1
    je .L_stmt_err_undef_var

    # emit "    mov QWORD PTR [rbp - {offset}], rax\n"
    push rax
    lea rdi, [str_mov_qword_rbp]
    call emit_cstr
    pop rax
    call emit_int
    lea rdi, [str_close_bracket_rax]
    call emit_cstr

    # optional semicolon
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_SEMICOLON
    jne .L_stmt_done
    call advance_token
    jmp .L_stmt_done

.L_stmt_expr_stmt:
    # Function call or general expression statement
    call parse_expr
    # optional semicolon
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_SEMICOLON
    jne .L_stmt_done
    call advance_token
    jmp .L_stmt_done

.L_stmt_err_undef_var:
    lea rdi, [msg_err_undef_var]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.L_stmt_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# --- Expressions & Operator Precedence ---
# parse_expr() -> evaluates into rax
parse_expr:
    push rbp
    mov rbp, rsp
    call parse_logical_or
    mov rsp, rbp
    pop rbp
    ret

# Logical OR: ||
parse_logical_or:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    call parse_logical_and

.L_or_loop:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_OR
    jne .L_or_done

    call advance_token
    mov rax, [label_ctr]
    add rax, 1
    mov [label_ctr], rax
    mov r12, rax

    lea rdi, [str_cmp_rax_zero_jne]
    call emit_cstr
    mov rax, r12
    call emit_int
    call emit_nl

    call parse_logical_and

    lea rdi, [str_or_eval_part]
    call emit_cstr
    mov rax, r12
    call emit_int
    call emit_nl

    lea rdi, [str_label_or_true]
    call emit_cstr
    mov rax, r12
    call emit_int
    lea rdi, [str_colon_nl]
    call emit_cstr

    lea rdi, [str_mov_rax_one]
    call emit_cstr

    lea rdi, [str_label_or_end]
    call emit_cstr
    mov rax, r12
    call emit_int
    lea rdi, [str_colon_nl]
    call emit_cstr
    jmp .L_or_loop

.L_or_done:
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# Logical AND: &&
parse_logical_and:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    call parse_equality

.L_and_loop:
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_AND
    jne .L_and_done

    call advance_token
    mov rax, [label_ctr]
    add rax, 1
    mov [label_ctr], rax
    mov r12, rax

    lea rdi, [str_cmp_rax_zero_je_and]
    call emit_cstr
    mov rax, r12
    call emit_int
    call emit_nl

    call parse_equality

    lea rdi, [str_and_eval_part]
    call emit_cstr
    mov rax, r12
    call emit_int
    call emit_nl

    lea rdi, [str_label_and_false]
    call emit_cstr
    mov rax, r12
    call emit_int
    lea rdi, [str_colon_nl]
    call emit_cstr

    lea rdi, [str_xor_rax_rax]
    call emit_cstr

    lea rdi, [str_label_and_end]
    call emit_cstr
    mov rax, r12
    call emit_int
    lea rdi, [str_colon_nl]
    call emit_cstr
    jmp .L_and_loop

.L_and_done:
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# Equality: ==, !=
parse_equality:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    call parse_relational

.L_eq_loop:
    call get_cur_tok_ptr
    mov r12, [rax + 0]      # token type
    cmp r12, TOK_EQ
    je .L_eq_match
    cmp r12, TOK_NEQ
    je .L_eq_match
    jmp .L_eq_done

.L_eq_match:
    call advance_token
    lea rdi, [str_push_rax]
    call emit_cstr

    call parse_relational

    lea rdi, [str_pop_cmp]
    call emit_cstr

    cmp r12, TOK_EQ
    jne .L_eq_neq
    lea rdi, [str_sete]
    call emit_cstr
    jmp .L_eq_loop
.L_eq_neq:
    lea rdi, [str_setne]
    call emit_cstr
    jmp .L_eq_loop

.L_eq_done:
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# Relational: <, <=, >, >=
parse_relational:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    call parse_additive

.L_rel_loop:
    call get_cur_tok_ptr
    mov r12, [rax + 0]
    cmp r12, TOK_LT
    je .L_rel_match
    cmp r12, TOK_LTE
    je .L_rel_match
    cmp r12, TOK_GT
    je .L_rel_match
    cmp r12, TOK_GTE
    je .L_rel_match
    jmp .L_rel_done

.L_rel_match:
    call advance_token
    lea rdi, [str_push_rax]
    call emit_cstr

    call parse_additive

    lea rdi, [str_pop_cmp]
    call emit_cstr

    cmp r12, TOK_LT
    je .L_rel_lt
    cmp r12, TOK_LTE
    je .L_rel_le
    cmp r12, TOK_GT
    je .L_rel_gt
    # TOK_GTE
    lea rdi, [str_setge]
    call emit_cstr
    jmp .L_rel_loop

.L_rel_lt:
    lea rdi, [str_setl]
    call emit_cstr
    jmp .L_rel_loop
.L_rel_le:
    lea rdi, [str_setle]
    call emit_cstr
    jmp .L_rel_loop
.L_rel_gt:
    lea rdi, [str_setg]
    call emit_cstr
    jmp .L_rel_loop

.L_rel_done:
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# Additive: +, -
parse_additive:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    call parse_multiplicative

.L_add_loop:
    call get_cur_tok_ptr
    mov r12, [rax + 0]
    cmp r12, TOK_PLUS
    je .L_add_match
    cmp r12, TOK_MINUS
    je .L_add_match
    jmp .L_add_done

.L_add_match:
    call advance_token
    lea rdi, [str_push_rax]
    call emit_cstr

    call parse_multiplicative

    lea rdi, [str_pop_rbx]
    call emit_cstr

    cmp r12, TOK_PLUS
    jne .L_add_sub
    lea rdi, [str_add_rax_rbx]
    call emit_cstr
    jmp .L_add_loop
.L_add_sub:
    lea rdi, [str_sub_rax_rbx]
    call emit_cstr
    jmp .L_add_loop

.L_add_done:
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# Multiplicative: *, /, % (with Division by Zero Guard)
parse_multiplicative:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    call parse_primary

.L_mul_loop:
    call get_cur_tok_ptr
    mov r12, [rax + 0]
    cmp r12, TOK_STAR
    je .L_mul_match
    cmp r12, TOK_SLASH
    je .L_mul_match
    cmp r12, TOK_PERCENT
    je .L_mul_match
    jmp .L_mul_done

.L_mul_match:
    call advance_token
    lea rdi, [str_push_rax]
    call emit_cstr

    call parse_primary

    lea rdi, [str_pop_rbx]
    call emit_cstr

    cmp r12, TOK_STAR
    je .L_mul_imul
    cmp r12, TOK_SLASH
    je .L_mul_div
    # TOK_PERCENT
    lea rdi, [str_mod_rax_rbx]
    call emit_cstr
    jmp .L_mul_loop

.L_mul_imul:
    lea rdi, [str_imul_rax_rbx]
    call emit_cstr
    jmp .L_mul_loop

.L_mul_div:
    lea rdi, [str_div_rax_rbx]
    call emit_cstr
    jmp .L_mul_loop

.L_mul_done:
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# Primary: numbers, variables, function calls, parentheses, unary minus
parse_primary:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    call get_cur_tok_ptr
    mov rbx, [rax + 0]      # token type

    # 1. Number literal
    cmp rbx, TOK_INT
    jne .L_prim_not_int

    mov rax, [rax + 8]      # value
    push rax
    lea rdi, [str_mov_rax_imm]
    call emit_cstr
    pop rax
    call emit_int
    call emit_nl
    call advance_token
    jmp .L_prim_done

.L_prim_not_int:
    # 2. Unary minus
    cmp rbx, TOK_MINUS
    jne .L_prim_not_neg

    call advance_token
    call parse_primary
    lea rdi, [str_neg_rax]
    call emit_cstr
    jmp .L_prim_done

.L_prim_not_neg:
    # 3. Parentheses: ( <expr> )
    cmp rbx, TOK_LPAREN
    jne .L_prim_not_paren

    call advance_token
    call parse_expr
    mov rdi, TOK_RPAREN
    lea rsi, [msg_err_expected_rparen]
    call expect_tok
    jmp .L_prim_done

.L_prim_not_paren:
    # 4. Boolean literals: true / false
    cmp rbx, TOK_TRUE
    jne .L_prim_not_true
    call advance_token
    lea rdi, [str_mov_rax_one]
    call emit_cstr
    jmp .L_prim_done

.L_prim_not_true:
    cmp rbx, TOK_FALSE
    jne .L_prim_not_false
    call advance_token
    lea rdi, [str_xor_rax_rax]
    call emit_cstr
    jmp .L_prim_done

.L_prim_not_false:
    # 5. Logical NOT: ! <primary>
    cmp rbx, TOK_NOT
    jne .L_prim_not_not
    call advance_token
    call parse_primary
    lea rdi, [str_logical_not]
    call emit_cstr
    jmp .L_prim_done

.L_prim_not_not:
    # 6. Array literal: [ <expr>, ... ]
    cmp rbx, TOK_LBRACKET
    jne .L_prim_not_lbracket

    call advance_token      # skip '['
    xor r14, r14            # element count

    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_RBRACKET
    je .L_prim_arr_empty

.L_prim_arr_loop:
    call parse_expr
    lea rdi, [str_push_rax]
    call emit_cstr
    inc r14

    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_COMMA
    jne .L_prim_arr_end
    call advance_token      # skip ','
    jmp .L_prim_arr_loop

.L_prim_arr_end:
    mov rdi, TOK_RBRACKET
    lea rsi, [msg_err_expected_rbracket]
    call expect_tok

    # Allocate memory for array: r14 * 8 bytes
    lea rdi, [str_mov_rdi_imm]
    call emit_cstr
    mov rax, r14
    shl rax, 3              # r14 * 8
    call emit_int
    call emit_nl

    lea rdi, [str_call_alloc_save_rbx]
    call emit_cstr

    # Pop elements from stack into heap array
    mov r15, r14
.L_prim_arr_pop:
    cmp r15, 0
    je .L_prim_arr_pop_done
    dec r15

    lea rdi, [str_pop_rdx]
    call emit_cstr

    lea rdi, [str_mov_qword_rbx_disp]
    call emit_cstr
    mov rax, r15
    shl rax, 3
    call emit_int
    lea rdi, [str_close_bracket_rdx]
    call emit_cstr
    jmp .L_prim_arr_pop

.L_prim_arr_pop_done:
    lea rdi, [str_mov_rax_rbx]
    call emit_cstr
    jmp .L_prim_done

.L_prim_arr_empty:
    call advance_token      # skip ']'
    lea rdi, [str_mov_rdi_imm]
    call emit_cstr
    mov rax, 8
    call emit_int
    call emit_nl
    lea rdi, [str_call_alloc]
    call emit_cstr
    jmp .L_prim_done

.L_prim_not_lbracket:
    # 7. String literal: "..."
    cmp rbx, TOK_STR
    jne .L_prim_not_str

    call get_cur_tok_ptr
    mov rdi, [rax + 8]      # str_ptr
    mov rsi, [rax + 16]     # str_len
    call rodata_add_str     # rax = label_id
    push rax
    lea rdi, [str_lea_rax_lc]
    call emit_cstr
    pop rax
    call emit_int
    lea rdi, [str_close_bracket_nl]
    call emit_cstr
    call advance_token
    jmp .L_prim_done

.L_prim_not_str:
    # 8. Identifier (Variable, Array Indexing, or Function Call)
    cmp rbx, TOK_IDENT
    jne .L_prim_err

    # Lookahead: is next token '('?
    mov rdi, 1
    call peek_tok_type
    cmp rax, TOK_LPAREN
    je .L_prim_call

    # Lookahead: is next token '['?
    cmp rax, TOK_LBRACKET
    je .L_prim_array_idx

    # It's a variable lookup
    call get_cur_tok_ptr
    mov rdi, [rax + 8]      # name_ptr
    mov rsi, [rax + 16]     # name_len
    call symtab_find
    cmp rax, -1
    je .L_prim_err_undef

    # emit "    mov rax, QWORD PTR [rbp - {offset}]\n"
    push rax
    lea rdi, [str_mov_rax_rbp]
    call emit_cstr
    pop rax
    call emit_int
    lea rdi, [str_close_bracket_nl]
    call emit_cstr
    call advance_token
    jmp .L_prim_done

.L_prim_array_idx:
    # Array indexing: <id>[<expr>]
    call get_cur_tok_ptr
    mov rdi, [rax + 8]      # name_ptr
    mov rsi, [rax + 16]     # name_len
    call symtab_find
    cmp rax, -1
    je .L_prim_err_undef
    push rax                # save array variable offset

    call advance_token      # skip ident
    call advance_token      # skip '['

    call parse_expr         # evaluate index into rax

    mov rdi, TOK_RBRACKET
    lea rsi, [msg_err_expected_rbracket]
    call expect_tok

    pop r14                 # restore array variable offset

    # emit "    mov rbx, QWORD PTR [rbp - {r14}]\n"
    # emit "    mov rax, QWORD PTR [rbx + rax * 8]\n"
    push rax
    lea rdi, [str_mov_rbx_rbp]
    call emit_cstr
    mov rax, r14
    call emit_int
    lea rdi, [str_close_bracket_nl]
    call emit_cstr
    pop rax

    lea rdi, [str_load_array_elem]
    call emit_cstr
    jmp .L_prim_done

.L_prim_call:
    # Function call
    call get_cur_tok_ptr
    mov r12, [rax + 8]      # fn_ptr
    mov r13, [rax + 16]     # fn_len
    call advance_token      # skip fn_name
    call advance_token      # skip '('

    # Check if a user-defined function exists with this name (user fns override built-in print)
    mov rdi, r12
    mov rsi, r13
    call is_user_fn
    cmp rax, 1
    je .L_prim_user_call

    # Check built-in: "print" (len 5)
    mov rdi, r12
    mov rsi, r13
    lea rdx, [str_fn_print]
    mov rcx, 5
    call str_cmp_n
    cmp rax, 0
    jne .L_prim_check_print_str

    # Built-in print(expr)
    call parse_expr
    mov rdi, TOK_RPAREN
    lea rsi, [msg_err_expected_rparen]
    call expect_tok

    lea rdi, [str_call_print_int]
    call emit_cstr
    jmp .L_prim_done

.L_prim_check_print_str:
    # Check built-in: "print_str" (len 9)
    mov rdi, r12
    mov rsi, r13
    lea rdx, [str_fn_print_str]
    mov rcx, 9
    call str_cmp_n
    cmp rax, 0
    jne .L_prim_check_print_char

    # Built-in print_str("...") or print_str(expr)
    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_STR
    jne .L_prim_print_str_expr

    mov rdi, [rax + 8]      # str_ptr
    mov rsi, [rax + 16]     # str_len
    call rodata_add_str     # rax = label_id, rdx = actual_len
    push rax
    push rdx
    call advance_token      # skip string

    mov rdi, TOK_RPAREN
    lea rsi, [msg_err_expected_rparen]
    call expect_tok

    pop rdx                 # actual_len
    pop rax                 # label_id

    push rdx
    push rax                # save label_id
    lea rdi, [str_lea_rdi_lc]
    call emit_cstr
    pop rax                 # restore label_id
    call emit_int
    lea rdi, [str_close_bracket_nl]
    call emit_cstr

    lea rdi, [str_mov_rsi_imm]
    call emit_cstr
    pop rax                 # actual_len
    call emit_int
    call emit_nl

    lea rdi, [str_call_rubix_print_str]
    call emit_cstr
    jmp .L_prim_done

.L_prim_print_str_expr:
    call parse_expr
    mov rdi, TOK_RPAREN
    lea rsi, [msg_err_expected_rparen]
    call expect_tok
    lea rdi, [str_call_puts]
    call emit_cstr
    jmp .L_prim_done

.L_prim_check_print_char:
    # Check built-in: "print_char" (len 10)
    mov rdi, r12
    mov rsi, r13
    lea rdx, [str_fn_print_char]
    mov rcx, 10
    call str_cmp_n
    cmp rax, 0
    jne .L_prim_check_alloc

    call parse_expr
    mov rdi, TOK_RPAREN
    lea rsi, [msg_err_expected_rparen]
    call expect_tok

    lea rdi, [str_call_print_char]
    call emit_cstr
    jmp .L_prim_done

.L_prim_check_alloc:
    # Check built-in: "alloc" (len 5)
    mov rdi, r12
    mov rsi, r13
    lea rdx, [str_fn_alloc]
    mov rcx, 5
    call str_cmp_n
    cmp rax, 0
    jne .L_prim_check_free

    call parse_expr
    mov rdi, TOK_RPAREN
    lea rsi, [msg_err_expected_rparen]
    call expect_tok

    lea rdi, [str_call_alloc]
    call emit_cstr
    jmp .L_prim_done

.L_prim_check_free:
    # Check built-in: "free" (len 4)
    mov rdi, r12
    mov rsi, r13
    lea rdx, [str_fn_free]
    mov rcx, 4
    call str_cmp_n
    cmp rax, 0
    jne .L_prim_user_call

    call parse_expr         # ptr
    lea rdi, [str_push_rax]
    call emit_cstr
    mov rdi, TOK_COMMA
    lea rsi, [msg_err_expected_comma]
    call expect_tok
    call parse_expr         # size
    mov rdi, TOK_RPAREN
    lea rsi, [msg_err_expected_rparen]
    call expect_tok

    lea rdi, [str_pop_rdi]
    call emit_cstr
    lea rdi, [str_mov_rsi_rax]
    call emit_cstr
    lea rdi, [str_call_free]
    call emit_cstr
    jmp .L_prim_done

.L_prim_user_call:
    # User-defined function call
    xor r14, r14            # arg count

    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_RPAREN
    je .L_prim_call_no_args

.L_prim_arg_loop:
    call parse_expr
    lea rdi, [str_push_rax]
    call emit_cstr
    inc r14

    call get_cur_tok_ptr
    mov rbx, [rax + 0]
    cmp rbx, TOK_COMMA
    jne .L_prim_args_end
    call advance_token
    jmp .L_prim_arg_loop

.L_prim_args_end:
.L_prim_call_no_args:
    mov rdi, TOK_RPAREN
    lea rsi, [msg_err_expected_rparen]
    call expect_tok

    cmp r14, MAX_PARAMS
    jg .L_prim_err_too_many_args

    cmp r14, 6
    jg .L_prim_call_many_args

    # Pop args into System V registers in reverse order
    mov r15, r14
.L_prim_pop_args:
    cmp r15, 0
    je .L_prim_do_call
    dec r15

    lea rdi, [str_pop_reg]
    call emit_cstr
    mov rdi, [param_regs + r15*8]
    call emit_cstr
    call emit_nl
    jmp .L_prim_pop_args

.L_prim_call_many_args:
    # r14 > 6:
    # 1. Load first 6 args into registers from stack offsets
    # arg i (0..5) is at [rsp + (r14 - 1 - i) * 8]
    xor r15, r15
.L_prim_load_reg_args:
    cmp r15, 6
    jge .L_prim_reorder_stack_args

    lea rdi, [str_mov_reg_rsp]
    call emit_cstr
    mov rdi, [param_regs + r15*8]
    call emit_cstr
    lea rdi, [str_rsp_disp_bracket]
    call emit_cstr
    mov rax, r14
    sub rax, 1
    sub rax, r15
    shl rax, 3              # (r14 - 1 - r15) * 8
    call emit_int
    lea rdi, [str_close_bracket_nl]
    call emit_cstr
    inc r15
    jmp .L_prim_load_reg_args

.L_prim_reorder_stack_args:
    # 2. Reverse the (r14 - 6) stack arguments currently at [rsp..rsp+(k-1)*8]
    # k = r14 - 6.
    # Swap [rsp + i*8] with [rsp + (k - 1 - i)*8] for i = 0..(k/2 - 1)
    mov rbx, r14
    sub rbx, 6              # rbx = k
    xor r15, r15            # i = 0
.L_prim_swap_loop:
    mov rax, rbx
    shr rax, 1              # k / 2
    cmp r15, rax
    jge .L_prim_do_call

    lea rdi, [str_swap_part1]
    call emit_cstr
    mov rax, r15
    shl rax, 3
    call emit_int
    lea rdi, [str_swap_part2]
    call emit_cstr
    mov rax, rbx
    sub rax, 1
    sub rax, r15
    shl rax, 3
    call emit_int
    lea rdi, [str_swap_part3]
    call emit_cstr
    mov rax, r15
    shl rax, 3
    call emit_int
    lea rdi, [str_swap_part4]
    call emit_cstr
    mov rax, rbx
    sub rax, 1
    sub rax, r15
    shl rax, 3
    call emit_int
    lea rdi, [str_close_bracket_rax]
    call emit_cstr

    inc r15
    jmp .L_prim_swap_loop

.L_prim_do_call:
    lea rdi, [str_call]
    call emit_cstr
    mov rdi, r12
    mov rsi, r13
    call emit_str
    call emit_nl

    # If r14 > 6, clean up the stack: add rsp, r14 * 8
    cmp r14, 6
    jle .L_prim_done

    lea rdi, [str_add_rsp]
    call emit_cstr
    mov rax, r14
    shl rax, 3              # r14 * 8
    call emit_int
    call emit_nl
    jmp .L_prim_done

.L_prim_err_undef:
    lea rdi, [msg_err_undef_var]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.L_prim_err_str_arg:
    lea rdi, [msg_err_expected_str_arg]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.L_prim_err_too_many_args:
    lea rdi, [msg_err_too_many_args]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.L_prim_err:
    lea rdi, [msg_err_expected_expr]
    call get_cur_tok_ptr
    mov rsi, [rax + 24]
    call compiler_panic

.L_prim_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.data
str_header:           .string ".intel_syntax noprefix\n.text\n"
str_global:           .string ".global "
str_colon_nl:         .string ":\n"
str_push_mov_rbp:     .string "    push rbp\n    mov rbp, rsp\n    sub rsp, "
str_fn_epilogue:      .string "    xor rax, rax\n    mov rsp, rbp\n    pop rbp\n    ret\n\n"
str_main_name:        .string "main"
str_start_entry:      .string ".global _start, _start_linux, _start_windows, _start_macos\n_start:\n_start_linux:\n    mov QWORD PTR [rubix_host_os], 1\n    jmp _start_common\n_start_windows:\n    mov QWORD PTR [rubix_host_os], 2\n    jmp _start_common\n_start_macos:\n    mov QWORD PTR [rubix_host_os], 3\n    jmp _start_common\n_start_common:\n    cmp QWORD PTR [rubix_host_os], 2\n    jne .L_init_skip_win\n    call __rubix_win64_init\n.L_init_skip_win:\n    call main\n    mov rdi, rax\n    jmp __rubix_sys_exit\n\n"

str_mov_qword_rbp:    .string "    mov QWORD PTR [rbp - "
str_close_bracket_comma: .string "], "
str_close_bracket_rax:   .string "], rax\n"
str_close_bracket_nl:    .string "]\n"
str_mov_rax_rbp:      .string "    mov rax, QWORD PTR [rbp - "
str_mov_rax_rbp_stack: .string "    mov rax, QWORD PTR [rbp + "
str_mov_rax_imm:      .string "    mov rax, "
str_neg_rax:          .string "    neg rax\n    jo __rubix_overflow_error\n"
str_xor_rax_rax:      .string "    xor rax, rax\n"
str_ret_code:         .string "    mov rsp, rbp\n    pop rbp\n    ret\n"

str_push_rax:         .string "    push rax\n"
str_pop_rbx:          .string "    mov rbx, rax\n    pop rax\n"
str_pop_cmp:          .string "    mov rbx, rax\n    pop rax\n    cmp rax, rbx\n"

str_sete:             .string "    sete al\n    movzx rax, al\n"
str_setne:            .string "    setne al\n    movzx rax, al\n"
str_setl:             .string "    setl al\n    movzx rax, al\n"
str_setle:            .string "    setle al\n    movzx rax, al\n"
str_setg:             .string "    setg al\n    movzx rax, al\n"
str_setge:            .string "    setge al\n    movzx rax, al\n"

str_add_rax_rbx:      .string "    add rax, rbx\n    jo __rubix_overflow_error\n"
str_sub_rax_rbx:      .string "    sub rax, rbx\n    jo __rubix_overflow_error\n"
str_imul_rax_rbx:     .string "    imul rax, rbx\n    jo __rubix_overflow_error\n"
str_div_rax_rbx:      .string "    cmp rbx, 0\n    je __rubix_div_zero_error\n    cqo\n    idiv rbx\n"
str_mod_rax_rbx:      .string "    cmp rbx, 0\n    je __rubix_div_zero_error\n    cqo\n    idiv rbx\n    mov rax, rdx\n"

str_cmp_rax_zero_je:  .string "    cmp rax, 0\n    je .L_else_"
str_jmp_end:          .string "    jmp .L_end_"
str_label_else:       .string ".L_else_"
str_label_end:        .string ".L_end_"

str_label_loop:       .string ".L_loop_"
str_cmp_rax_zero_je_loop: .string "    cmp rax, 0\n    je .L_loop_end_"
str_jmp_loop:         .string "    jmp .L_loop_"
str_jmp_loop_end:     .string "    jmp .L_loop_end_"
str_jmp_loop_start:   .string "    jmp .L_loop_"
str_label_loop_end:   .string ".L_loop_end_"

str_mov_rbx_rbp:          .string "    mov rbx, QWORD PTR [rbp - "
str_store_array_elem:     .string "    pop rcx\n    mov QWORD PTR [rbx + rcx * 8], rax\n"
str_load_array_elem:      .string "    mov rax, QWORD PTR [rbx + rax * 8]\n"
str_mov_rdi_imm:          .string "    mov rdi, "
str_call_alloc_save_rbx:  .string "    mov rdi, rax\n    call __rubix_alloc\n    mov rbx, rax\n"
str_call_alloc:           .string "    mov rdi, rax\n    call __rubix_alloc\n"
str_mov_rax_rbx:          .string "    mov rax, rbx\n"
str_pop_rdx:              .string "    pop rdx\n"
str_pop_rdi:              .string "    pop rdi\n"
str_mov_rsi_rax:          .string "    mov rsi, rax\n"
str_mov_qword_rbx_disp:   .string "    mov QWORD PTR [rbx + "
str_close_bracket_rdx:    .string "], rdx\n"

str_mov_rax_one:          .string "    mov rax, 1\n"
str_logical_not:          .string "    test rax, rax\n    sete al\n    movzx rax, al\n"
str_cmp_rax_zero_jne:     .string "    cmp rax, 0\n    jne .L_or_true_"
str_or_eval_part:         .string "    cmp rax, 0\n    setne al\n    movzx rax, al\n    jmp .L_or_end_"
str_label_or_true:        .string ".L_or_true_"
str_label_or_end:         .string ".L_or_end_"
str_cmp_rax_zero_je_and:  .string "    cmp rax, 0\n    je .L_and_false_"
str_and_eval_part:        .string "    cmp rax, 0\n    setne al\n    movzx rax, al\n    jmp .L_and_end_"
str_label_and_false:      .string ".L_and_false_"
str_label_and_end:        .string ".L_and_end_"

str_fn_print:         .string "print"
str_fn_print_str:     .string "print_str"
str_fn_print_char:    .string "print_char"
str_fn_alloc:         .string "alloc"
str_fn_free:          .string "free"
str_call_print_int:   .string "    mov rdi, rax\n    call __rubix_print_int\n    xor rax, rax\n"
str_call_print_char:  .string "    mov rdi, rax\n    call __rubix_print_char\n    xor rax, rax\n"
str_call_free:        .string "    call __rubix_free\n    xor rax, rax\n"
str_lea_rdi_lc:       .string "    lea rdi, [.LC"
str_lea_rax_lc:       .string "    lea rax, [.LC"
str_mov_rsi_imm:      .string "    mov rsi, "
str_call_rubix_print_str: .string "    call __rubix_print_str\n    xor rax, rax\n"
str_call_puts:        .string "    mov rdi, rax\n    call puts\n    xor rax, rax\n"
str_pop_reg:          .string "    pop "
str_call:             .string "    call "
str_add_rsp:          .string "    add rsp, "

str_mov_reg_rsp:      .string "    mov "
str_rsp_disp_bracket: .string ", QWORD PTR [rsp + "
str_swap_part1:       .string "    mov rax, QWORD PTR [rsp + "
str_swap_part2:       .string "]\n    mov r10, QWORD PTR [rsp + "
str_swap_part3:       .string "]\n    mov QWORD PTR [rsp + "
str_swap_part4:       .string "], r10\n    mov QWORD PTR [rsp + "

reg_rdi: .string "rdi"
reg_rsi: .string "rsi"
reg_rdx: .string "rdx"
reg_rcx: .string "rcx"
reg_r8:  .string "r8"
reg_r9:  .string "r9"

.align 8
param_regs:
    .quad reg_rdi
    .quad reg_rsi
    .quad reg_rdx
    .quad reg_rcx
    .quad reg_r8
    .quad reg_r9

msg_err_expected_fn:         .string "Expected function definition ('fn')"
msg_err_expected_fn_name:    .string "Expected function name identifier"
msg_err_expected_lparen:     .string "Expected '('"
msg_err_expected_rparen:     .string "Expected ')'"
msg_err_expected_lbrace:     .string "Expected '{'"
msg_err_expected_rbrace:     .string "Expected '}'"
msg_err_expected_param_name: .string "Expected parameter name identifier"
msg_err_too_many_params:     .string "Too many parameters (maximum 64 supported)"
msg_err_unexpected_eof:      .string "Unexpected end of file"
msg_err_unexpected_stmt:     .string "Unexpected token in statement"
msg_err_expected_let_ident:  .string "Expected identifier after 'let'"
msg_err_expected_assign:     .string "Expected '=' in variable assignment"
msg_err_undef_var:           .string "Undefined variable"
msg_err_expected_expr:       .string "Expected expression"
msg_err_expected_str_arg:    .string "Expected string literal argument in print_str"
msg_err_too_many_args:       .string "Too many arguments in function call (maximum 64 supported)"
msg_err_redef_main:          .string "Redefinition of main"
msg_err_expected_rbracket:   .string "Expected ']'"
msg_err_expected_comma:      .string "Expected ','"
msg_err_expected_semi:       .string "Expected ';'"
