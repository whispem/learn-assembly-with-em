global _start

section .rodata
f1: db "hello, %s", 10, 0
f2: db "%d + %d = %d", 10, 0
f3: db "%d", 10, 0
f4: db "unsigned: %u", 10, 0
f5: db "hex: %x", 10, 0
f6: db "%c%c%c", 10, 0
f7: db "100%% pure asm", 10, 0
f8: db "%s has %d chars", 10, 0
f9: db "%d %d %d %d %d", 10, 0
f10: db "zero: %x", 10, 0
s_world: db "world", 0
s_syscall: db "syscall", 0
nullstr: db "(null)", 0
digits: db "0123456789abcdef"

section .data
args: times 5 dq 0
olen: dq 0
obuf: times 1024 db 0
nbuf: times 32 db 0

section .text
_start:
    mov rdi, f1
    mov rsi, s_world
    call printf

    mov rdi, f2
    mov rsi, 2
    mov rdx, 40
    mov rcx, 42
    call printf

    mov rdi, f3
    mov rsi, -2026
    call printf

    mov rdi, f4
    mov rsi, -1
    call printf

    mov rdi, f5
    mov esi, 0xdeadbeef
    call printf

    mov rdi, f6
    mov rsi, 'a'
    mov rdx, 's'
    mov rcx, 'm'
    call printf

    mov rdi, f7
    call printf

    mov rdi, f8
    mov rsi, s_syscall
    mov rdx, 7
    call printf

    mov rdi, f9
    mov rsi, 1
    mov rdx, 2
    mov rcx, 3
    mov r8, 4
    mov r9, 5
    call printf

    mov rdi, f10
    xor esi, esi
    call printf

    mov rax, 60
    xor edi, edi
    syscall

; rdi = format, then up to 5 variadic args in rsi, rdx, rcx, r8, r9
; %d %u %x %s %c %%
printf:
    push rbx
    push r12
    mov [args], rsi
    mov [args+8], rdx
    mov [args+16], rcx
    mov [args+24], r8
    mov [args+32], r9
    mov rbx, rdi
    xor r12d, r12d
.next:
    mov al, [rbx]
    test al, al
    jz .end
    inc rbx
    cmp al, '%'
    jne .plain
    mov al, [rbx]
    test al, al
    jz .end
    inc rbx
    cmp al, 'd'
    je .fmt_d
    cmp al, 'u'
    je .fmt_u
    cmp al, 'x'
    je .fmt_x
    cmp al, 's'
    je .fmt_s
    cmp al, 'c'
    je .fmt_c
.plain:
    call putc
    jmp .next
.fmt_d:
    call next_arg
    mov rdi, rax
    call emit_int
    jmp .next
.fmt_u:
    call next_arg
    mov rdi, rax
    mov rsi, 10
    call emit_uint
    jmp .next
.fmt_x:
    call next_arg
    mov rdi, rax
    mov rsi, 16
    call emit_uint
    jmp .next
.fmt_s:
    call next_arg
    mov rdi, rax
    test rdi, rdi
    jnz .s_ok
    mov rdi, nullstr
.s_ok:
    push rdi
    call cstrlen
    pop rdi
    mov rsi, rax
    call emit
    jmp .next
.fmt_c:
    call next_arg
    call putc
    jmp .next
.end:
    call flush
    pop r12
    pop rbx
    ret

; -> rax = next vararg, 0 past the fifth
next_arg:
    xor eax, eax
    cmp r12, 5
    jae .out
    mov rax, [args + r12*8]
    inc r12
.out:
    ret

; rdi = value (signed), printed in decimal
emit_int:
    test rdi, rdi
    jns .pos
    push rdi
    mov al, '-'
    call putc
    pop rdi
    neg rdi
.pos:
    mov rsi, 10
    jmp emit_uint

; rdi = value, rsi = base
emit_uint:
    push rbx
    mov rax, rdi
    mov rbx, rsi
    lea rsi, [nbuf + 32]
.div:
    xor edx, edx
    div rbx
    mov dl, [digits + rdx]
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .div
    lea rdx, [nbuf + 32]
    sub rdx, rsi
    mov rdi, rsi
    mov rsi, rdx
    call emit
    pop rbx
    ret

; rdi = ptr, rsi = len, appended to the output buffer
emit:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi
.byte:
    test r12, r12
    jz .out
    mov al, [rbx]
    call putc
    inc rbx
    dec r12
    jmp .byte
.out:
    pop r12
    pop rbx
    ret

; al = char, buffered write
putc:
    mov rdx, [olen]
    mov [obuf + rdx], al
    inc rdx
    mov [olen], rdx
    cmp rdx, 1024
    jb .ok
    call flush
.ok:
    ret

flush:
    mov rdx, [olen]
    test rdx, rdx
    jz .ok
    mov rax, 1
    mov rdi, 1
    mov rsi, obuf
    syscall
    mov qword [olen], 0
.ok:
    ret

; rdi = cstring -> rax = length
cstrlen:
    mov rax, rdi
.count:
    cmp byte [rax], 0
    je .len
    inc rax
    jmp .count
.len:
    sub rax, rdi
    ret

section .note.GNU-stack noalloc noexec nowrite progbits
