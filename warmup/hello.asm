global _start

section .rodata
msg: db "hello, world", 10
len equ $ - msg

section .text
_start:
    mov rax, 1
    mov rdi, 1
    mov rsi, msg
    mov rdx, len
    syscall

    mov rax, 60
    xor edi, edi
    syscall

section .note.GNU-stack noalloc noexec nowrite progbits
