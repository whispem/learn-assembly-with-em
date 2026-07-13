global _start

; ---- a small Forth ----
; data stack in r15 (grows down in dstack), dictionary is a linked list.
; a "word" entry: [link:8][flags/len:1][name...][code-ptr:8 or inline threaded]
; To keep it in pure asm and small, primitives are native routines; colon
; definitions store a list of execution tokens (pointers) that the inner
; interpreter walks.

%define DSTACK_SIZE 4096
%define RSTACK_SIZE 4096
%define DICT_SIZE   65536
%define TIB_SIZE    4096
%define PAD_SIZE    256

section .rodata
prompt:   db "ok", 10
ok_len    equ $ - prompt
err_unk:  db "?", 10
err_unk_len equ $ - err_unk
err_stack: db "stack underflow", 10
err_stack_len equ $ - err_stack
div0:     db "division by zero", 10
div0_len  equ $ - div0

section .data
; execution tokens for primitives are their routine addresses.
; The dictionary is built at runtime in .bss (dict area) so names live together.
dsp:      dq 0           ; data stack pointer (points to top)
latest:   dq 0           ; latest dictionary entry
here:     dq 0           ; next free dict byte
state:    dq 0           ; 0 = interpret, 1 = compile
tib_len:  dq 0           ; chars in TIB
tib_pos:  dq 0           ; parse position
cur_def:  dq 0           ; entry being compiled
neg_flag: db 0
numbuf:   times 32 db 0

section .bss
dstack:   resq DSTACK_SIZE
rstack:   resq RSTACK_SIZE
dict:     resb DICT_SIZE
tib:      resb TIB_SIZE
word_buf: resb 256

section .text
_start:
    lea rax, [dstack + DSTACK_SIZE*8]
    mov [dsp], rax
    mov rax, dict
    mov [here], rax
    mov qword [latest], 0

    call build_dict

.repl:
    ; read a line into TIB
    xor eax, eax
    xor edi, edi
    mov rsi, tib
    mov edx, TIB_SIZE
    syscall
    test rax, rax
    jle .bye
    mov [tib_len], rax
    mov qword [tib_pos], 0

.interpret_loop:
    call parse_word            ; -> rax=ptr, rdx=len (len 0 = end of line)
    test rdx, rdx
    jz .line_done
    ; look the word up
    mov rdi, rax
    mov rsi, rdx
    call find_word             ; -> rax = entry or 0
    test rax, rax
    jz .try_number
    ; found: rax = entry. Decide compile vs interpret.
    mov rbx, rax
    cmp qword [state], 0
    je .exec_word
    ; compile state: immediate words execute, others get compiled
    movzx ecx, byte [rbx + 8]
    test ecx, 0x80             ; immediate flag
    jnz .exec_word
    ; compile a call token (the entry pointer) into current definition
    mov rax, [here]
    mov rdx, rbx
    mov [rax], rdx
    add qword [here], 8
    jmp .interpret_loop
.exec_word:
    call execute_entry
    jmp .interpret_loop

.try_number:
    mov rdi, [word_ptr_save]
    mov rsi, [word_len_save]
    call parse_number          ; -> rax=value, rdx=ok(1/0)
    test rdx, rdx
    jz .unknown
    cmp qword [state], 0
    je .push_num
    ; compile: store a LIT token then the value
    mov rcx, [here]
    mov rdx, lit_token
    mov [rcx], rdx
    mov rdx, rax
    mov [rcx+8], rdx
    add qword [here], 16
    jmp .interpret_loop
.push_num:
    call push_rax
    jmp .interpret_loop

.unknown:
    mov rax, 1
    mov rdi, 2
    mov rsi, err_unk
    mov rdx, err_unk_len
    syscall
    jmp .interpret_loop

.line_done:
    cmp qword [state], 0
    jne .repl                  ; still compiling, no prompt
    mov rax, 1
    mov rdi, 1
    mov rsi, prompt
    mov rdx, ok_len
    syscall
    jmp .repl

.bye:
    mov rax, 60
    xor edi, edi
    syscall

; ------- parse a whitespace-delimited word from TIB -------
; returns rax=ptr into word_buf (null-terminated), rdx=len
section .data
word_ptr_save: dq 0
word_len_save: dq 0
section .text
parse_word:
    mov rsi, [tib_pos]
    mov rcx, [tib_len]
.skip:
    cmp rsi, rcx
    jae .empty
    mov al, [tib + rsi]
    cmp al, ' '
    je .adv
    cmp al, 9
    je .adv
    cmp al, 10
    je .adv
    cmp al, 13
    je .adv
    jmp .start
.adv:
    inc rsi
    jmp .skip
.start:
    xor rdi, rdi
.copy:
    cmp rsi, rcx
    jae .fin
    mov al, [tib + rsi]
    cmp al, ' '
    je .fin
    cmp al, 9
    je .fin
    cmp al, 10
    je .fin
    cmp al, 13
    je .fin
    mov [word_buf + rdi], al
    inc rsi
    inc rdi
    cmp rdi, 255
    jb .copy
.fin:
    mov [tib_pos], rsi
    mov byte [word_buf + rdi], 0
    mov rax, word_buf
    mov rdx, rdi
    mov [word_ptr_save], rax
    mov [word_len_save], rdx
    ret
.empty:
    mov [tib_pos], rsi
    xor rdx, rdx
    mov rax, word_buf
    ret

; ------- find_word: rdi=name ptr, rsi=len -> rax=entry or 0 -------
find_word:
    mov r8, [latest]
.loop:
    test r8, r8
    jz .none
    movzx ecx, byte [r8 + 8]
    and ecx, 0x1f              ; length in low 5 bits
    cmp rcx, rsi
    jne .next
    ; compare names
    lea r9, [r8 + 9]
    mov r10, rdi
    mov r11, rsi
.cmp:
    test r11, r11
    jz .match
    mov al, [r9]
    mov dl, [r10]
    cmp al, dl
    jne .next
    inc r9
    inc r10
    dec r11
    jmp .cmp
.match:
    mov rax, r8
    ret
.next:
    mov r8, [r8]               ; follow link
    jmp .loop
.none:
    xor eax, eax
    ret

; ------- parse_number: rdi=ptr, rsi=len -> rax=value, rdx=1 ok / 0 fail -------
parse_number:
    xor rax, rax
    xor r8, r8                 ; sign
    xor r9, r9                 ; index
    test rsi, rsi
    jz .fail
    mov cl, [rdi]
    cmp cl, '-'
    jne .digits
    cmp rsi, 1
    je .fail                   ; just "-" is not a number
    mov r8, 1
    inc r9
.digits:
    cmp r9, rsi
    jae .done
    movzx ecx, byte [rdi + r9]
    sub ecx, '0'
    cmp ecx, 9
    ja .fail
    imul rax, rax, 10
    add rax, rcx
    inc r9
    jmp .digits
.done:
    test r8, r8
    jz .ok
    neg rax
.ok:
    mov rdx, 1
    ret
.fail:
    xor rax, rax
    xor rdx, rdx
    ret

; ------- execute an entry: rbx=entry -------
; entry layout: [link:8][flags:1][name..][pad to 8][kind:8][body...]
; kind 0 = primitive: body[0] = routine address, call it.
; kind 1 = colon: body = list of entry-pointers terminated by exit_token; walk them.
execute_entry:
    ; compute body pointer = entry + 9 + namelen, aligned to 8
    movzx ecx, byte [rbx + 8]
    and ecx, 0x1f
    lea rax, [rbx + 9]
    add rax, rcx
    add rax, 7
    and rax, -8
    mov rsi, rax               ; rsi -> kind
    mov rdi, [rsi]             ; kind
    add rsi, 8                 ; rsi -> body
    test rdi, rdi
    jz .prim
    ; colon word: inner interpreter over token list
    push r12
    mov r12, rsi
.inner:
    mov rax, [r12]
    cmp rax, exit_token
    je .inner_done
    cmp rax, lit_token
    je .do_lit
    ; else it's an entry pointer -> execute recursively
    push r12
    mov rbx, rax
    call execute_entry
    pop r12
    add r12, 8
    jmp .inner
.do_lit:
    mov rax, [r12 + 8]
    call push_rax
    add r12, 16
    jmp .inner
.inner_done:
    pop r12
    ret
.prim:
    mov rax, [rsi]             ; routine address
    jmp rax                    ; tail-call primitive; it returns to our caller

; ================= primitives =================
; convention: they pop/push via dsp, then ret.

prim_add:
    call pop_rbx
    call pop_rax
    add rax, rbx
    call push_rax
    ret
prim_sub:
    call pop_rbx
    call pop_rax
    sub rax, rbx
    call push_rax
    ret
prim_mul:
    call pop_rbx
    call pop_rax
    imul rax, rbx
    call push_rax
    ret
prim_div:
    call pop_rbx
    call pop_rax
    test rbx, rbx
    jz .dz
    cqo
    idiv rbx
    call push_rax
    ret
.dz:
    mov rax, 1
    mov rdi, 2
    mov rsi, div0
    mov rdx, div0_len
    syscall
    ret
prim_mod:
    call pop_rbx
    call pop_rax
    test rbx, rbx
    jz .dz
    cqo
    idiv rbx
    mov rax, rdx
    call push_rax
    ret
.dz:
    mov rax, 1
    mov rdi, 2
    mov rsi, div0
    mov rdx, div0_len
    syscall
    ret
prim_dup:
    call pop_rax
    call push_rax
    call push_rax
    ret
prim_drop:
    call pop_rax
    ret
prim_swap:
    call pop_rbx
    call pop_rax
    mov rcx, rbx
    call push_rcx
    call push_rax
    ret
prim_over:
    call pop_rbx
    call pop_rax
    call push_rax
    mov rcx, rbx
    call push_rcx
    mov rcx, rax
    call push_rcx
    ret
prim_rot:
    ; ( a b c -- b c a )
    call pop_rcx               ; c
    call pop_rbx               ; b
    call pop_rax               ; a
    push rcx
    mov rcx, rbx
    call push_rcx              ; b
    pop rcx
    call push_rcx              ; c
    mov rcx, rax
    call push_rcx             ; a
    ret
prim_dot:
    call pop_rax
    call print_int
    ret
prim_dots:
    ; .s prints the stack (bottom to top) — non-destructive
    mov rax, [dsp]
    lea rbx, [dstack + DSTACK_SIZE*8]
.loop:
    cmp rax, rbx
    jae .done
    mov rdi, [rbx - 8]
    push rax
    push rbx
    mov rax, rdi
    call print_int
    pop rbx
    pop rax
    sub rbx, 8
    jmp .loop
.done:
    ret
prim_eq:
    call pop_rbx
    call pop_rax
    cmp rax, rbx
    sete al
    movzx rax, al
    neg rax                    ; Forth true = -1
    call push_rax
    ret
prim_lt:
    call pop_rbx
    call pop_rax
    cmp rax, rbx
    setl al
    movzx rax, al
    neg rax
    call push_rax
    ret
prim_gt:
    call pop_rbx
    call pop_rax
    cmp rax, rbx
    setg al
    movzx rax, al
    neg rax
    call push_rax
    ret
prim_and:
    call pop_rbx
    call pop_rax
    and rax, rbx
    call push_rax
    ret
prim_or:
    call pop_rbx
    call pop_rax
    or rax, rbx
    call push_rax
    ret
prim_emit:
    call pop_rax
    mov [numbuf], al
    mov rax, 1
    mov rdi, 1
    mov rsi, numbuf
    mov rdx, 1
    syscall
    ret
prim_cr:
    mov byte [numbuf], 10
    mov rax, 1
    mov rdi, 1
    mov rsi, numbuf
    mov rdx, 1
    syscall
    ret

; ':' start a definition
prim_colon:
    ; read the name of the new word
    call parse_word            ; rax=ptr, rdx=len
    ; create dict header at here
    mov rcx, [here]
    mov r8, [latest]
    mov [rcx], r8              ; link
    mov [latest], rcx
    ; flags/len byte
    mov [rcx + 8], dl
    ; copy name
    lea rdi, [rcx + 9]
    mov rsi, rax
    mov r9, rdx
.cpy:
    test r9, r9
    jz .named
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec r9
    jmp .cpy
.named:
    ; align to 8 for kind field
    lea rax, [rdi + 7]
    and rax, -8
    mov qword [rax], 1         ; kind = colon
    add rax, 8
    mov [here], rax           ; body starts here
    mov qword [state], 1
    ret

; ';' end a definition
prim_semicolon:
    mov rcx, [here]
    mov rdx, exit_token
    mov [rcx], rdx
    add qword [here], 8
    mov qword [state], 0
    ret

; ================= stack helpers =================
push_rax:
    mov r11, [dsp]
    sub r11, 8
    mov [r11], rax
    mov [dsp], r11
    ret
push_rcx:
    mov r11, [dsp]
    sub r11, 8
    mov [r11], rcx
    mov [dsp], r11
    ret
pop_rax:
    mov r11, [dsp]
    lea rax, [dstack + DSTACK_SIZE*8]
    cmp r11, rax
    jae .under
    mov rax, [r11]
    add r11, 8
    mov [dsp], r11
    ret
.under:
    mov rax, 1
    mov rdi, 2
    mov rsi, err_stack
    mov rdx, err_stack_len
    syscall
    xor eax, eax
    ret
pop_rbx:
    call pop_rax
    mov rbx, rax
    ret
pop_rcx:
    call pop_rax
    mov rcx, rax
    ret

; print rax as signed decimal + space
print_int:
    mov r10, rax
    lea rsi, [numbuf + 31]
    mov byte [rsi], ' '
    mov rcx, 10
    xor r8, r8
    test rax, rax
    jns .conv
    neg rax
    mov r8, 1
.conv:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .conv
    test r8, r8
    jz .out
    dec rsi
    mov byte [rsi], '-'
.out:
    lea rdx, [numbuf + 32]
    sub rdx, rsi
    mov rax, 1
    mov rdi, 1
    syscall
    ret

; ================= dictionary construction =================
; helper: add a primitive. rsi=name ptr, rdx=len, rdi=routine, r8=immediate?
add_prim:
    mov rcx, [here]
    mov rax, [latest]
    mov [rcx], rax            ; link
    mov [latest], rcx
    ; flags/len
    mov al, dl
    or al, r8b                ; immediate flag if r8=0x80
    mov [rcx + 8], al
    lea r9, [rcx + 9]
.cpy:
    test rdx, rdx
    jz .done
    mov al, [rsi]
    mov [r9], al
    inc rsi
    inc r9
    dec rdx
    jmp .cpy
.done:
    lea rax, [r9 + 7]
    and rax, -8
    mov qword [rax], 0        ; kind = primitive
    mov [rax + 8], rdi        ; routine address
    add rax, 16
    mov [here], rax
    ret

%macro DEFPRIM 3
    ; %1 = name string label, %2 = name len, %3 = routine, imm via 4th? keep simple
    lea rsi, [%1]
    mov rdx, %2
    mov rdi, %3
    xor r8, r8
    call add_prim
%endmacro

%macro DEFIMM 3
    lea rsi, [%1]
    mov rdx, %2
    mov rdi, %3
    mov r8, 0x80
    call add_prim
%endmacro

section .rodata
n_add: db "+"
n_sub: db "-"
n_mul: db "*"
n_div: db "/"
n_mod: db "mod"
n_dup: db "dup"
n_drop: db "drop"
n_swap: db "swap"
n_over: db "over"
n_rot: db "rot"
n_dot: db "."
n_dots: db ".s"
n_eq: db "="
n_lt: db "<"
n_gt: db ">"
n_and: db "and"
n_or: db "or"
n_emit: db "emit"
n_cr: db "cr"
n_colon: db ":"
n_semi: db ";"

section .text
build_dict:
    DEFPRIM n_add,1,prim_add
    DEFPRIM n_sub,1,prim_sub
    DEFPRIM n_mul,1,prim_mul
    DEFPRIM n_div,1,prim_div
    DEFPRIM n_mod,3,prim_mod
    DEFPRIM n_dup,3,prim_dup
    DEFPRIM n_drop,4,prim_drop
    DEFPRIM n_swap,4,prim_swap
    DEFPRIM n_over,4,prim_over
    DEFPRIM n_rot,3,prim_rot
    DEFPRIM n_dot,1,prim_dot
    DEFPRIM n_dots,2,prim_dots
    DEFPRIM n_eq,1,prim_eq
    DEFPRIM n_lt,1,prim_lt
    DEFPRIM n_gt,1,prim_gt
    DEFPRIM n_and,3,prim_and
    DEFPRIM n_or,2,prim_or
    DEFPRIM n_emit,4,prim_emit
    DEFPRIM n_cr,2,prim_cr
    DEFIMM n_colon,1,prim_colon
    DEFIMM n_semi,1,prim_semicolon
    ret

; sentinel tokens (unique addresses)
lit_token:  ret
exit_token: ret

section .note.GNU-stack noalloc noexec nowrite progbits
