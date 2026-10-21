.intel_syntax noprefix

.text

# add_token(rdi: type, rsi: val, rdx: len, rcx: line)
add_token:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, [tok_count]
    cmp rbx, MAX_TOKENS
    jge .L_tok_overflow

    shl rbx, 5              # multiply by 32 (TOKEN_SIZE)
    lea rax, [tokens_buf]
    add rax, rbx

    mov [rax + 0], rdi      # type
    mov [rax + 8], rsi      # val/ptr
    mov [rax + 16], rdx     # len
    mov [rax + 24], rcx     # line

    inc QWORD PTR [tok_count]

    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_tok_overflow:
    lea rdi, [msg_err_tok_overflow]
    mov rsi, [cur_line]
    call compiler_panic

# lex_all()
lex_all:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov QWORD PTR [cur_line], 1
    mov QWORD PTR [tok_count], 0
    lea r12, [src_buffer]   # r12 = current src_ptr

.L_lex_loop:
    movzx r13, BYTE PTR [r12]
    cmp r13, 0
    je .L_lex_eof

    # check whitespace
    cmp r13, ' '
    je .L_lex_skip_ws
    cmp r13, '\t'
    je .L_lex_skip_ws
    cmp r13, '\r'
    je .L_lex_skip_ws
    cmp r13, '\n'
    je .L_lex_newline

    # check comment '#'
    cmp r13, '#'
    je .L_lex_skip_comment

    # check comment '//'
    cmp r13, '/'
    jne .L_lex_not_slash_comment
    movzx rax, BYTE PTR [r12 + 1]
    cmp rax, '/'
    je .L_lex_skip_slash_comment
.L_lex_not_slash_comment:

    # check number: '0' <= c <= '9'
    cmp r13, '0'
    jl .L_lex_not_num
    cmp r13, '9'
    jg .L_lex_not_num
    jmp .L_lex_number

.L_lex_not_num:
    # check string literal '"'
    cmp r13, '"'
    je .L_lex_string

    # check identifier: [a-zA-Z_]
    cmp r13, '_'
    je .L_lex_ident
    cmp r13, 'a'
    jl .L_lex_check_upper
    cmp r13, 'z'
    jle .L_lex_ident
.L_lex_check_upper:
    cmp r13, 'A'
    jl .L_lex_check_char
    cmp r13, 'Z'
    jle .L_lex_ident

.L_lex_check_char:
    cmp r13, '\''
    je .L_lex_char_literal

.L_lex_check_ops:
    # check &&
    cmp r13, '&'
    jne .L_lex_chk_pipe
    movzx rax, BYTE PTR [r12 + 1]
    cmp rax, '&'
    je .L_lex_op_and
.L_lex_chk_pipe:
    # check ||
    cmp r13, '|'
    jne .L_lex_chk_eq
    movzx rax, BYTE PTR [r12 + 1]
    cmp rax, '|'
    je .L_lex_op_or
.L_lex_chk_eq:
    # multi-character operators: ==, !=, <=, >=
    movzx rax, BYTE PTR [r12 + 1]
    cmp r13, '='
    jne .L_lex_chk_ne
    cmp rax, '='
    je .L_lex_op_eq
.L_lex_chk_ne:
    cmp r13, '!'
    jne .L_lex_chk_le
    cmp rax, '='
    je .L_lex_op_ne
.L_lex_chk_le:
    cmp r13, '<'
    jne .L_lex_chk_ge
    cmp rax, '='
    je .L_lex_op_le
.L_lex_chk_ge:
    cmp r13, '>'
    jne .L_lex_single_ops
    cmp rax, '='
    je .L_lex_op_ge

.L_lex_single_ops:
    cmp r13, '+'
    je .L_lex_op_plus
    cmp r13, '-'
    je .L_lex_op_minus
    cmp r13, '*'
    je .L_lex_op_star
    cmp r13, '/'
    je .L_lex_op_slash
    cmp r13, '%'
    je .L_lex_op_pct
    cmp r13, '='
    je .L_lex_op_assign
    cmp r13, '<'
    je .L_lex_op_lt
    cmp r13, '>'
    je .L_lex_op_gt
    cmp r13, '('
    je .L_lex_op_lparen
    cmp r13, ')'
    je .L_lex_op_rparen
    cmp r13, '{'
    je .L_lex_op_lbrace
    cmp r13, '}'
    je .L_lex_op_rbrace
    cmp r13, ','
    je .L_lex_op_comma
    cmp r13, ';'
    je .L_lex_op_semi
    cmp r13, ':'
    je .L_lex_op_colon
    cmp r13, '['
    je .L_lex_op_lbracket
    cmp r13, ']'
    je .L_lex_op_rbracket
    cmp r13, '!'
    je .L_lex_op_not
    cmp r13, '.'
    je .L_lex_op_dot

    # Unrecognized character
    lea rdi, [msg_err_unknown_char]
    mov rsi, [cur_line]
    call compiler_panic

# --- Handlers ---

.L_lex_skip_ws:
    inc r12
    jmp .L_lex_loop

.L_lex_newline:
    inc QWORD PTR [cur_line]
    inc r12
    jmp .L_lex_loop

.L_lex_skip_comment:
    inc r12
    movzx rax, BYTE PTR [r12]
    cmp rax, 0
    je .L_lex_loop
    cmp rax, '\n'
    je .L_lex_newline
    jmp .L_lex_skip_comment

.L_lex_skip_slash_comment:
    add r12, 2
.L_lex_slash_loop:
    movzx rax, BYTE PTR [r12]
    cmp rax, 0
    je .L_lex_loop
    cmp rax, '\n'
    je .L_lex_newline
    inc r12
    jmp .L_lex_slash_loop

.L_lex_number:
    mov r14, r12            # start of number
    xor rax, rax            # accumulator
    mov rbx, 10
    xor r15, r15            # dot_count = 0
.L_lex_num_loop:
    movzx rcx, BYTE PTR [r12]
    cmp rcx, '0'
    jl .L_lex_num_chk_dot
    cmp rcx, '9'
    jg .L_lex_num_chk_dot
    sub rcx, '0'
    mul rbx                 # rax = rax * 10
    add rax, rcx
    inc r12
    jmp .L_lex_num_loop

.L_lex_num_chk_dot:
    cmp rcx, '.'
    jne .L_lex_num_done
    # Check if next char is digit
    movzx rdx, BYTE PTR [r12 + 1]
    cmp rdx, '0'
    jl .L_lex_num_done
    cmp rdx, '9'
    jg .L_lex_num_done
    # It is a float!
    inc r12                 # skip '.'
    inc r15                 # dot_count++
.L_lex_float_frac_loop:
    movzx rcx, BYTE PTR [r12]
    cmp rcx, '0'
    jl .L_lex_float_chk_multi_dot
    cmp rcx, '9'
    jg .L_lex_float_chk_multi_dot
    inc r12
    jmp .L_lex_float_frac_loop

.L_lex_float_chk_multi_dot:
    cmp rcx, '.'
    jne .L_lex_float_done
    # Encountered another '.' in float literal
    inc r15                 # dot_count++
    lea rdi, [msg_err_multi_dot_float]
    mov rsi, [cur_line]
    call compiler_panic

.L_lex_float_done:
    mov rdi, TOK_FLOAT
    mov rsi, r14            # string start pointer
    mov rdx, r12
    sub rdx, r14            # string length
    mov rcx, [cur_line]
    call add_token
    jmp .L_lex_loop

.L_lex_num_done:
    mov rdi, TOK_INT
    mov rsi, rax            # value
    xor rdx, rdx
    mov rcx, [cur_line]
    call add_token
    jmp .L_lex_loop

.L_lex_string:
    inc r12                 # skip opening quote
    mov r14, r12            # string start pointer
.L_lex_str_loop:
    movzx rax, BYTE PTR [r12]
    cmp rax, 0
    je .L_lex_str_unterminated
    cmp rax, '\n'
    je .L_lex_str_unterminated
    cmp rax, '\\'
    jne .L_lex_str_check_quote
    inc r12
    movzx rax, BYTE PTR [r12]
    cmp rax, 0
    je .L_lex_str_unterminated
    cmp rax, '\n'
    je .L_lex_str_unterminated
    inc r12
    jmp .L_lex_str_loop

.L_lex_str_check_quote:
    cmp rax, '"'
    je .L_lex_str_end
    inc r12
    jmp .L_lex_str_loop
.L_lex_str_end:
    mov r15, r12
    sub r15, r14            # string length
    inc r12                 # skip closing quote
    mov rdi, TOK_STR
    mov rsi, r14            # string pointer
    mov rdx, r15            # string length
    mov rcx, [cur_line]
    call add_token
    jmp .L_lex_loop

.L_lex_str_unterminated:
    lea rdi, [msg_err_unterminated_str]
    mov rsi, [cur_line]
    call compiler_panic

.L_lex_ident:
    mov r14, r12            # ident start
.L_lex_ident_loop:
    inc r12
    movzx rax, BYTE PTR [r12]
    cmp rax, '_'
    je .L_lex_ident_loop
    cmp rax, 'a'
    jl .L_lex_id_chk_upper
    cmp rax, 'z'
    jle .L_lex_ident_loop
.L_lex_id_chk_upper:
    cmp rax, 'A'
    jl .L_lex_id_chk_num
    cmp rax, 'Z'
    jle .L_lex_ident_loop
.L_lex_id_chk_num:
    cmp rax, '0'
    jl .L_lex_ident_done
    cmp rax, '9'
    jle .L_lex_ident_loop
.L_lex_ident_done:
    mov r15, r12
    sub r15, r14            # ident len

    # Match keywords
    # "fn" (len 2)
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_fn]
    mov rcx, 2
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_let
    mov rdi, TOK_FN
    jmp .L_emit_kw

.L_kw_let:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_let]
    mov rcx, 3
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_if
    mov rdi, TOK_LET
    jmp .L_emit_kw

.L_kw_if:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_if]
    mov rcx, 2
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_else
    mov rdi, TOK_IF
    jmp .L_emit_kw

.L_kw_else:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_else]
    mov rcx, 4
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_while
    mov rdi, TOK_ELSE
    jmp .L_emit_kw

.L_kw_while:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_while]
    mov rcx, 5
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_return
    mov rdi, TOK_WHILE
    jmp .L_emit_kw

.L_kw_return:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_return]
    mov rcx, 6
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_true
    mov rdi, TOK_RETURN
    jmp .L_emit_kw

.L_kw_true:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_true]
    mov rcx, 4
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_false
    mov rdi, TOK_TRUE
    jmp .L_emit_kw

.L_kw_false:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_false]
    mov rcx, 5
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_char
    mov rdi, TOK_FALSE
    jmp .L_emit_kw

.L_kw_char:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_char]
    mov rcx, 4
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_bool
    mov rdi, TOK_CHAR_KW
    jmp .L_emit_kw

.L_kw_bool:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_bool]
    mov rcx, 4
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_break
    mov rdi, TOK_BOOL_KW
    jmp .L_emit_kw

.L_kw_break:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_break]
    mov rcx, 5
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_continue
    mov rdi, TOK_BREAK
    jmp .L_emit_kw

.L_kw_continue:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_continue]
    mov rcx, 8
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_for
    mov rdi, TOK_CONTINUE
    jmp .L_emit_kw

.L_kw_for:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_for]
    mov rcx, 3
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_struct
    mov rdi, TOK_FOR
    jmp .L_emit_kw

.L_kw_struct:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_struct]
    mov rcx, 6
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_float
    mov rdi, TOK_STRUCT
    jmp .L_emit_kw

.L_kw_float:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_float]
    mov rcx, 5
    call str_cmp_n
    cmp rax, 0
    jne .L_kw_int
    mov rdi, TOK_FLOAT_KW
    jmp .L_emit_kw

.L_kw_int:
    mov rdi, r14
    mov rsi, r15
    lea rdx, [kw_int]
    mov rcx, 3
    call str_cmp_n
    cmp rax, 0
    jne .L_emit_ident
    mov rdi, TOK_INT_KW
    jmp .L_emit_kw

.L_emit_kw:
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, [cur_line]
    call add_token
    jmp .L_lex_loop

.L_emit_ident:
    mov rdi, TOK_IDENT
    mov rsi, r14            # name pointer
    mov rdx, r15            # name length
    mov rcx, [cur_line]
    call add_token
    jmp .L_lex_loop

# Operators
.L_lex_op_eq:
    add r12, 2
    mov rdi, TOK_EQ
    jmp .L_emit_simple_op
.L_lex_op_ne:
    add r12, 2
    mov rdi, TOK_NEQ
    jmp .L_emit_simple_op
.L_lex_op_le:
    add r12, 2
    mov rdi, TOK_LTE
    jmp .L_emit_simple_op
.L_lex_op_ge:
    add r12, 2
    mov rdi, TOK_GTE
    jmp .L_emit_simple_op

.L_lex_op_plus:
    inc r12
    mov rdi, TOK_PLUS
    jmp .L_emit_simple_op
.L_lex_op_minus:
    inc r12
    mov rdi, TOK_MINUS
    jmp .L_emit_simple_op
.L_lex_op_star:
    inc r12
    mov rdi, TOK_STAR
    jmp .L_emit_simple_op
.L_lex_op_slash:
    inc r12
    mov rdi, TOK_SLASH
    jmp .L_emit_simple_op
.L_lex_op_pct:
    inc r12
    mov rdi, TOK_PERCENT
    jmp .L_emit_simple_op
.L_lex_op_assign:
    inc r12
    mov rdi, TOK_ASSIGN
    jmp .L_emit_simple_op
.L_lex_op_lt:
    inc r12
    mov rdi, TOK_LT
    jmp .L_emit_simple_op
.L_lex_op_gt:
    inc r12
    mov rdi, TOK_GT
    jmp .L_emit_simple_op
.L_lex_op_lparen:
    inc r12
    mov rdi, TOK_LPAREN
    jmp .L_emit_simple_op
.L_lex_op_rparen:
    inc r12
    mov rdi, TOK_RPAREN
    jmp .L_emit_simple_op
.L_lex_op_lbrace:
    inc r12
    mov rdi, TOK_LBRACE
    jmp .L_emit_simple_op
.L_lex_op_rbrace:
    inc r12
    mov rdi, TOK_RBRACE
    jmp .L_emit_simple_op
.L_lex_op_comma:
    inc r12
    mov rdi, TOK_COMMA
    jmp .L_emit_simple_op
.L_lex_op_semi:
    inc r12
    mov rdi, TOK_SEMICOLON
    jmp .L_emit_simple_op
.L_lex_op_colon:
    inc r12
    mov rdi, TOK_COLON
    jmp .L_emit_simple_op

.L_lex_op_lbracket:
    inc r12
    mov rdi, TOK_LBRACKET
    jmp .L_emit_simple_op
.L_lex_op_rbracket:
    inc r12
    mov rdi, TOK_RBRACKET
    jmp .L_emit_simple_op
.L_lex_op_and:
    add r12, 2
    mov rdi, TOK_AND
    jmp .L_emit_simple_op
.L_lex_op_or:
    add r12, 2
    mov rdi, TOK_OR
    jmp .L_emit_simple_op
.L_lex_op_not:
    inc r12
    mov rdi, TOK_NOT
    jmp .L_emit_simple_op
.L_lex_op_dot:
    inc r12
    mov rdi, TOK_DOT
    jmp .L_emit_simple_op

.L_lex_char_literal:
    inc r12
    movzx rax, BYTE PTR [r12]
    cmp rax, 0
    je .L_char_err
    cmp rax, '\n'
    je .L_char_err
    cmp rax, '\\'
    jne .L_char_normal
    inc r12
    movzx rax, BYTE PTR [r12]
    cmp rax, 'n'
    je .L_char_esc_n
    cmp rax, 't'
    je .L_char_esc_t
    cmp rax, 'r'
    je .L_char_esc_r
    cmp rax, '0'
    je .L_char_esc_0
    cmp rax, '\\'
    je .L_char_esc_bs
    cmp rax, '\''
    je .L_char_esc_sq
    jmp .L_char_got_val
.L_char_esc_n:
    mov rax, 10
    jmp .L_char_got_val
.L_char_esc_t:
    mov rax, 9
    jmp .L_char_got_val
.L_char_esc_r:
    mov rax, 13
    jmp .L_char_got_val
.L_char_esc_0:
    xor eax, eax
    jmp .L_char_got_val
.L_char_esc_bs:
    mov rax, 92
    jmp .L_char_got_val
.L_char_esc_sq:
    mov rax, 39
    jmp .L_char_got_val
.L_char_normal:
.L_char_got_val:
    inc r12
    movzx rcx, BYTE PTR [r12]
    cmp rcx, '\''
    jne .L_char_err
    inc r12
    mov rdi, TOK_INT
    mov rsi, rax
    xor rdx, rdx
    mov rcx, [cur_line]
    call add_token
    jmp .L_lex_loop

.L_char_err:
    lea rdi, [msg_err_unclosed_char]
    mov rsi, [cur_line]
    call compiler_panic

.L_emit_simple_op:
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, [cur_line]
    call add_token
    jmp .L_lex_loop

.L_lex_eof:
    mov rdi, TOK_EOF
    xor rsi, rsi
    xor rdx, rdx
    mov rcx, [cur_line]
    call add_token

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.data
kw_fn:     .string "fn"
kw_let:    .string "let"
kw_if:     .string "if"
kw_else:   .string "else"
kw_while:  .string "while"
kw_return: .string "return"
kw_true:   .string "true"
kw_false:  .string "false"
kw_char:   .string "char"
kw_bool:   .string "bool"
kw_break:  .string "break"
kw_continue: .string "continue"
kw_for:    .string "for"
kw_struct: .string "struct"
kw_float:  .string "float"
kw_int:    .string "int"

msg_err_tok_overflow:     .string "Too many tokens (buffer overflow)"
msg_err_unknown_char:     .string "Unrecognized character in source"
msg_err_unterminated_str: .string "Unterminated string literal"
msg_err_unclosed_char:    .string "Unclosed character literal"
msg_err_multi_dot_float:  .string "Invalid floating-point literal: multiple decimal points"
