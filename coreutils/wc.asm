global _start

section .rodata
err: db "wc: cannot open file", 10
err_len equ $ - err
nl: db 10

section .data
buf: times 8192 db 0
nbuf: times 32 db 0

section .text
_start:
    xor r12d, r12d              ; fd
    xor r15d, r15d              ; filename, 0 = stdin
    cmp qword [rsp], 2
    jb .counts
    mov rdi, [rsp+16]
    mov r15, rdi
    mov rax, 2
    xor esi, esi
    xor edx, edx
    syscall
    test rax, rax
    js .fail
    mov r12, rax

.counts:
    xor r13d, r13d              ; lines
    xor r14d, r14d              ; words
    xor ebx, ebx                ; bytes
    xor ebp, ebp                ; inside a word
.read:
    xor eax, eax
    mov rdi, r12
    mov rsi, buf
    mov edx, 8192
    syscall
    test rax, rax
    jle .report
    add rbx, rax
    mov rsi, buf
    mov rcx, rax
.byte:
    movzx edx, byte [rsi]
    cmp dl, 10
    jne .blank_test
    inc r13
.blank_test:
    cmp dl, ' '
    je .blank
    lea eax, [rdx-9]
    cmp eax, 4
    jbe .blank
    test ebp, ebp
    jnz .advance
    inc r14
    mov ebp, 1
    jmp .advance
.blank:
    xor ebp, ebp
.advance:
    inc rsi
    dec rcx
    jnz .byte
    jmp .read

.report:
    mov rdi, r13
    mov sil, ' '
    call print_num
    mov rdi, r14
    mov sil, ' '
    call print_num
    mov rdi, rbx
    mov sil, 10
    test r15, r15
    jz .last
    mov sil, ' '
.last:
    call print_num
    test r15, r15
    jz .done
    mov rdi, r15
    call cstrlen
    mov rdx, rax
    mov rsi, r15
    mov rax, 1
    mov rdi, 1
    syscall
    mov rax, 1
    mov rdi, 1
    mov rsi, nl
    mov rdx, 1
    syscall
.done:
    mov rax, 60
    xor edi, edi
    syscall

.fail:
    mov rax, 1
    mov rdi, 2
    mov rsi, err
    mov rdx, err_len
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

; rdi = value, sil = trailing char
print_num:
    mov r9b, sil
    mov rax, rdi
    lea rsi, [nbuf+31]
    mov [rsi], r9b
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
    jz .emit
    dec rsi
    mov byte [rsi], '-'
.emit:
    lea rdx, [nbuf+32]
    sub rdx, rsi
    mov rax, 1
    mov rdi, 1
    syscall
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