global _start

section .rodata
usage: db "usage: grep PATTERN [FILE]", 10
usage_len equ $ - usage
err: db "grep: cannot open file", 10
err_len equ $ - err

section .data
buf: times 8192 db 0
line: times 8200 db 0
matched: db 0

section .text
_start:
    mov rax, [rsp]
    cmp rax, 2
    jb .usage
    cmp rax, 3
    ja .usage

    mov r13, [rsp+16]
    mov rdi, r13
    call cstrlen
    mov r14, rax

    xor r12d, r12d
    cmp qword [rsp], 3
    jb .go
    mov rdi, [rsp+24]
    mov rax, 2
    xor esi, esi
    xor edx, edx
    syscall
    test rax, rax
    js .openfail
    mov r12, rax

.go:
    xor r15d, r15d
.read:
    xor eax, eax
    mov rdi, r12
    mov rsi, buf
    mov edx, 8192
    syscall
    test rax, rax
    jle .eof
    mov rbp, buf
    lea rbx, [buf + rax]
.scan:
    cmp rbp, rbx
    jae .read
    movzx edx, byte [rbp]
    inc rbp
    cmp dl, 10
    je .line_end
    mov [line + r15], dl
    inc r15
    cmp r15, 8192
    jb .scan
.line_end:
    call emit_if_match
    xor r15d, r15d
    jmp .scan

.eof:
    test r15, r15
    jz .close
    call emit_if_match
.close:
    test r12, r12
    jz .status
    mov rax, 3
    mov rdi, r12
    syscall
.status:
    movzx edi, byte [matched]
    xor edi, 1
    mov rax, 60
    syscall

.usage:
    mov rax, 1
    mov rdi, 2
    mov rsi, usage
    mov rdx, usage_len
    syscall
    jmp .die
.openfail:
    mov rax, 1
    mov rdi, 2
    mov rsi, err
    mov rdx, err_len
    syscall
.die:
    mov rax, 60
    mov rdi, 2
    syscall

; searches pattern (r13, len r14) in line[0..r15), prints line on match
emit_if_match:
    lea rdi, [line]
    mov rsi, r15
    mov rdx, r13
    mov rcx, r14
    call contains
    test eax, eax
    jz .no
    mov byte [matched], 1
    mov byte [line + r15], 10
    lea rsi, [line]
    lea rdx, [r15 + 1]
    mov rax, 1
    mov rdi, 1
    syscall
.no:
    ret

; rdi = hay, rsi = hay len, rdx = needle, rcx = needle len -> rax = 1 if found
contains:
    xor eax, eax
    cmp rcx, rsi
    ja .done
    mov r8, rsi
    sub r8, rcx
    xor r9d, r9d
.try:
    xor r10d, r10d
    lea r11, [rdi + r9]
.byte:
    cmp r10, rcx
    jae .hit
    mov al, [r11 + r10]
    cmp al, [rdx + r10]
    jne .miss
    inc r10
    jmp .byte
.miss:
    inc r9
    cmp r9, r8
    jbe .try
    xor eax, eax
.done:
    ret
.hit:
    mov eax, 1
    ret

; rdi = cstring -> rax = length
cstrlen:
    mov rax, rdi
.next:
    cmp byte [rax], 0
    je .len
    inc rax
    jmp .next
.len:
    sub rax, rdi
    ret

section .note.GNU-stack noalloc noexec nowrite progbits
