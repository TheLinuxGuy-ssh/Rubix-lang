.intel_syntax noprefix

.text

# symtab_clear()
symtab_clear:
    mov QWORD PTR [sym_count], 0
    mov QWORD PTR [cur_stack_offset], 0
    mov QWORD PTR [max_stack_offset], 0
    mov QWORD PTR [scope_depth], 0
    ret

# scope_enter()
scope_enter:
    push rbp
    mov rbp, rsp
    push rbx

    mov rax, [scope_depth]
    cmp rax, 64
    jge .L_scope_overflow

    shl rax, 4              # index * 16
    lea rcx, [scope_stack + rax]
    mov rdx, [sym_count]
    mov [rcx + 0], rdx      # saved sym_count
    mov rdx, [cur_stack_offset]
    mov [rcx + 8], rdx      # saved cur_stack_offset

    inc QWORD PTR [scope_depth]

    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_scope_overflow:
    lea rdi, [msg_err_scope_overflow]
    mov rsi, [cur_line]
    call compiler_panic

# scope_exit()
scope_exit:
    push rbp
    mov rbp, rsp

    mov rax, [scope_depth]
    cmp rax, 0
    jle .L_scope_exit_done

    dec rax
    mov [scope_depth], rax
    shl rax, 4              # index * 16
    lea rcx, [scope_stack + rax]
    mov rdx, [rcx + 0]
    mov [sym_count], rdx
    mov rdx, [rcx + 8]
    mov [cur_stack_offset], rdx

.L_scope_exit_done:
    mov rsp, rbp
    pop rbp
    ret

# loop_enter(rdi: break_label, rsi: continue_label)
loop_enter:
    push rbp
    mov rbp, rsp
    push rbx

    mov rax, [loop_depth]
    cmp rax, MAX_LOOP_DEPTH
    jge .L_loop_depth_overflow

    shl rax, 3              # index * 8
    lea rbx, [break_label_stack + rax]
    mov [rbx], rdi          # save break label
    lea rbx, [continue_label_stack + rax]
    mov [rbx], rsi          # save continue label

    inc QWORD PTR [loop_depth]

    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_loop_depth_overflow:
    lea rdi, [msg_err_loop_depth_overflow]
    mov rsi, [cur_line]
    call compiler_panic
    ret

# loop_exit()
loop_exit:
    push rbp
    mov rbp, rsp

    mov rax, [loop_depth]
    cmp rax, 0
    jle .L_loop_exit_done

    dec rax
    mov [loop_depth], rax

.L_loop_exit_done:
    mov rsp, rbp
    pop rbp
    ret

# get_current_break_label() -> rax
get_current_break_label:
    push rbp
    mov rbp, rsp

    mov rax, [loop_depth]
    dec rax
    shl rax, 3              # index * 8
    lea rbx, [break_label_stack + rax]
    mov rax, [rbx]

    mov rsp, rbp
    pop rbp
    ret

# get_current_continue_label() -> rax
get_current_continue_label:
    push rbp
    mov rbp, rsp

    mov rax, [loop_depth]
    dec rax
    shl rax, 3              # index * 8
    lea rbx, [continue_label_stack + rax]
    mov rax, [rbx]

    mov rsp, rbp
    pop rbp
    ret

# symtab_add(rdi: name_ptr, rsi: name_len) -> rax: assigned_stack_offset
symtab_add:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi            # name_ptr
    mov r13, rsi            # name_len

    # Check for redeclaration in the current scope
    # Current scope start is scope_stack[scope_depth - 1].saved_sym_count, or 0 if scope_depth == 0
    xor r14, r14
    mov rax, [scope_depth]
    cmp rax, 0
    je .L_redecl_search

    dec rax
    shl rax, 4              # index * 16
    lea rcx, [scope_stack + rax]
    mov r14, [rcx + 0]      # scope start sym_count

.L_redecl_search:
    mov rbx, r14
.L_redecl_loop:
    cmp rbx, [sym_count]
    jge .L_redecl_ok

    mov rcx, rbx
    mov rax, rbx
    shl rax, 6              # index * 64
    shl rbx, 5              # index * 32
    add rax, rbx            # index * 96
    mov rcx, rax            # rcx = index * 96
    lea rcx, [symtab_buf + rcx]

    # Compare name: entry name at [rcx] with len at [rcx+64] vs target(r12, r13)
    mov rdi, rcx            # entry name
    mov rsi, [rcx + 64]     # entry name_len
    mov rdx, r12            # target name
    mov rcx, r13            # target len
    call str_cmp_n
    cmp rax, 0
    je .L_redecl_err

    inc rbx
    jmp .L_redecl_loop

.L_redecl_ok:
    mov rbx, [sym_count]
    cmp rbx, MAX_SYMBOLS
    jge .L_sym_overflow

    # calculate offset = cur_stack_offset + 8
    mov rax, [cur_stack_offset]
    add rax, 8
    mov [cur_stack_offset], rax

    # update max_stack_offset if cur_stack_offset is larger
    mov rdx, [max_stack_offset]
    cmp rax, rdx
    jle .L_sym_no_max_update
    mov [max_stack_offset], rax

.L_sym_no_max_update:
    push rax                # save offset to return

    mov rax, rbx            # rbx = sym_count (index for new entry)
    shl rax, 6              # rax = index * 64
    shl rbx, 5              # rbx = index * 32
    add rax, rbx            # rax = index * 96
    mov rbx, rax            # rbx = index * 96
    lea rcx, [symtab_buf]
    add rcx, rbx

    # Copy name string into entry[0..63]
    mov rdi, rcx            # dest = entry name buffer
    mov rsi, r12            # src = original name_ptr
    mov rdx, r13            # len = name_len
    call str_copy
    mov BYTE PTR [rdi + r13], 0  # null-terminate (rdi preserved by str_copy)

    mov [rdi + 64], r13     # name_len
    pop rax                 # restore offset
    mov [rdi + 72], rax     # stack_offset (rdi = entry pointer, preserved by str_copy)
    mov QWORD PTR [rdi + 80], TYPE_UNKNOWN # type_id
    mov QWORD PTR [rdi + 88], 0            # type_extra

    inc QWORD PTR [sym_count]

    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_redecl_err:
    lea rdi, [msg_err_redeclared_var]
    mov rsi, [cur_line]
    call compiler_panic

.L_sym_overflow:
    lea rdi, [msg_err_sym_overflow]
    mov rsi, [cur_line]
    call compiler_panic

# symtab_lookup(rdi: name_ptr, rsi: name_len) -> rax: entry_ptr (or 0 if not found)
symtab_lookup:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi            # target name_ptr
    mov r13, rsi            # target name_len

    mov r14, [sym_count]
    cmp r14, 0
    je .L_lookup_not_found

.L_lookup_search_loop:
    dec r14
    mov rbx, r14
    mov rax, rbx
    shl rax, 6              # index * 64
    shl rbx, 5              # index * 32
    add rax, rbx            # index * 96
    mov rbx, rax            # rbx = index * 96
    lea rbx, [symtab_buf + rbx]

    # compare: entry name at [rbx] with len at [rbx+64] vs target(r12, r13)
    mov rdi, rbx            # entry name
    mov rsi, [rbx + 64]     # entry name_len
    mov rdx, r12            # target name
    mov rcx, r13            # target len
    call str_cmp_n
    cmp rax, 0
    je .L_lookup_found

    cmp r14, 0
    jg .L_lookup_search_loop

.L_lookup_not_found:
    xor rax, rax
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

.L_lookup_found:
    mov rax, rbx            # return entry_ptr
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret

# symtab_find(rdi: name_ptr, rsi: name_len) -> rax: stack_offset (or -1 if not found)
symtab_find:
    push rbp
    mov rbp, rsp
    call symtab_lookup
    cmp rax, 0
    je .L_find_not_found
    mov rax, [rax + 72]     # stack_offset
    mov rsp, rbp
    pop rbp
    ret
.L_find_not_found:
    mov rax, -1
    mov rsp, rbp
    pop rbp
    ret

# symtab_get_type(rdi: name_ptr, rsi: name_len) -> rax: type_id
symtab_get_type:
    push rbp
    mov rbp, rsp
    call symtab_lookup
    cmp rax, 0
    je .L_type_not_found
    mov rax, [rax + 80]     # type_id
    mov rsp, rbp
    pop rbp
    ret
.L_type_not_found:
    mov rax, TYPE_UNKNOWN
    mov rsp, rbp
    pop rbp
    ret

# symtab_set_type(rdi: stack_offset, rsi: type_id, rdx: type_extra)
symtab_set_type:
    push rbp
    mov rbp, rsp
    mov rcx, [sym_count]
    cmp rcx, 0
    je .L_set_type_done
.L_set_type_loop:
    dec rcx
    mov rax, rcx
    shl rax, 6
    mov r8, rcx
    shl r8, 5
    add rax, r8             # index * 96
    lea rax, [symtab_buf + rax]
    cmp [rax + 72], rdi     # match stack_offset
    jne .L_set_type_next
    mov [rax + 80], rsi     # type_id
    mov [rax + 88], rdx     # type_extra
    jmp .L_set_type_done
.L_set_type_next:
    cmp rcx, 0
    jg .L_set_type_loop
.L_set_type_done:
    mov rsp, rbp
    pop rbp
    ret

.data
msg_err_sym_overflow:    .string "Symbol table overflow (too many local variables)"
msg_err_scope_overflow:  .string "Scope nesting overflow (maximum 64 levels exceeded)"
msg_err_redeclared_var:  .string "Redeclaration of variable in current scope"
msg_err_loop_depth_overflow: .string "Loop nesting overflow (maximum 64 levels exceeded)"
