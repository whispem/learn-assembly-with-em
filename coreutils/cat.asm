global _start

section .rodata
err: db "cat: cannot open file", 10
err_len equ $ - err

section .data
buf: times 8192 db 0

section .text
_start:
    mov r14, [rsp]
    xor r15d, r15d
    cmp r14, 2
    jae .args
    xor edi, edi
    call pump
    jmp .exit

.args:
    mov r13, 1
.loop:
    mov rdi, [rsp + 8 + r13*8]
    mov rax, 2
    xor esi, esi
    xor edx, edx
    syscall
    test rax, rax
    js .fail
    mov rbx, rax
    mov rdi, rbx
    call pump
    mov rax, 3
    mov rdi, rbx
    syscall
    jmp .cont
.fail:
    mov r15d, 1
    mov rax, 1
    mov rdi, 2
    mov rsi, err
    mov rdx, err_len
    syscall
.cont:
    inc r13
    cmp r13, r14
    jb .loop

.exit:
    mov rax, 60
    mov rdi, r15
    syscall

; rdi = fd, copied to stdout until EOF
pump:
    push rbx
    push r12
    mov r12, rdi
.read:
    xor eax, eax
    mov rdi, r12
    mov rsi, buf
    mov edx, 8192
    syscall
    test rax, rax
    jle .done
    mov rbx, rax
    mov r9, buf
.write:
    mov rax, 1
    mov rdi, 1
    mov rsi, r9
    mov rdx, rbx
    syscall
    test rax, rax
    js .done
    add r9, rax
    sub rbx, rax
    jnz .write
    jmp .read
.done:
    pop r12
    pop rbx
    ret

section .note.GNU-stack noalloc noexec nowrite progbits
