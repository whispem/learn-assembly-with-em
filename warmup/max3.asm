global _start

section .rodata
usage: db "usage: max3 A B C", 10
usage_len equ $ - usage

section .data
buf: times 32 db 0

section .text
_start:
    cmp qword [rsp], 4
    jne .usage

    mov rdi, [rsp+16]
    call atoi
    mov rbx, rax

    mov rdi, [rsp+24]
    call atoi
    cmp rax, rbx
    cmovg rbx, rax

    mov rdi, [rsp+32]
    call atoi
    cmp rax, rbx
    cmovg rbx, rax

    mov rdi, rbx
    call print_int

    mov rax, 60
    xor edi, edi
    syscall

.usage:
    mov rax, 1
    mov rdi, 2
    mov rsi, usage
    mov rdx, usage_len
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

; rdi = string -> rax = value
atoi:
    xor eax, eax
    xor r8d, r8d
    cmp byte [rdi], '-'
    jne .digits
    inc r8d
    inc rdi
.digits:
    movzx ecx, byte [rdi]
    sub ecx, '0'
    cmp ecx, 9
    ja .done
    imul rax, 10
    add rax, rcx
    inc rdi
    jmp .digits
.done:
    test r8d, r8d
    jz .ret
    neg rax
.ret:
    ret

; rdi = value, printed in decimal with trailing newline
print_int:
    mov rax, rdi
    lea rsi, [buf+31]
    mov byte [rsi], 10
    mov rcx, 10
    xor r8d, r8d
    test rax, rax
    jns .conv
    neg rax
    inc r8d
.conv:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .conv
    test r8d, r8d
    jz .write
    dec rsi
    mov byte [rsi], '-'
.write:
    lea rdx, [buf+32]
    sub rdx, rsi
    mov rax, 1
    mov rdi, 1
    syscall
    ret

section .note.GNU-stack noalloc noexec nowrite progbits