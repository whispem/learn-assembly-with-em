global _start

section .rodata
usage: db "usage: quicksort N [N ...]", 10
usage_len equ $ - usage

section .data
buf: times 32 db 0
nums: times 4096 dq 0

section .text
_start:
    mov r14, [rsp]
    cmp r14, 2
    jb .usage
    dec r14
    cmp r14, 4096
    ja .usage

    lea r15, [rsp+16]
    mov rbx, nums
    xor r13d, r13d
.parse:
    mov rdi, [r15 + r13*8]
    call atoi
    mov [rbx + r13*8], rax
    inc r13
    cmp r13, r14
    jb .parse

    mov rdi, rbx
    lea rsi, [rbx + r14*8 - 8]
    call qsort

    xor r13d, r13d
.print:
    mov rdi, [rbx + r13*8]
    call print_int
    inc r13
    cmp r13, r14
    jb .print

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

; rdi = lo, rsi = hi (qword pointers, inclusive), Lomuto partition
qsort:
    cmp rdi, rsi
    jb .go
    ret
.go:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r13, rsi
    mov r8, [r13]
    lea r9, [rdi-8]
    mov r10, rdi
.scan:
    cmp r10, r13
    jae .place
    mov r11, [r10]
    cmp r11, r8
    jg .next
    add r9, 8
    mov rax, [r9]
    mov [r9], r11
    mov [r10], rax
.next:
    add r10, 8
    jmp .scan
.place:
    add r9, 8
    mov rax, [r9]
    mov rcx, [r13]
    mov [r9], rcx
    mov [r13], rax
    mov r12, r9
    mov rdi, rbx
    lea rsi, [r12-8]
    call qsort
    lea rdi, [r12+8]
    mov rsi, r13
    call qsort
    pop r13
    pop r12
    pop rbx
    ret

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