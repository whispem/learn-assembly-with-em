global _start

section .rodata
dot: db ".", 0
usage: db "usage: ls [DIR]", 10
usage_len equ $ - usage
err_open: db "ls: cannot open directory", 10
err_open_len equ $ - err_open
err_full: db "ls: too many entries", 10
err_full_len equ $ - err_full

section .data
dbuf: times 8192 db 0
names: times 32768 db 0
names_end:
ptrs: times 2048 dq 0

section .text
_start:
    mov rax, [rsp]
    cmp rax, 2
    ja .usage
    mov rdi, dot
    cmp rax, 2
    jb .open
    mov rdi, [rsp+16]
.open:
    mov rax, 2
    mov esi, 0x10000            ; O_RDONLY | O_DIRECTORY
    xor edx, edx
    syscall
    test rax, rax
    js .openfail
    mov r12, rax

    xor r14d, r14d              ; entry count
    mov r15, names              ; heap cursor
.getdents:
    mov rax, 217
    mov rdi, r12
    mov rsi, dbuf
    mov edx, 8192
    syscall
    test rax, rax
    jle .list
    mov rbx, dbuf
    lea rbp, [dbuf + rax]
.entry:
    cmp rbx, rbp
    jae .getdents
    cmp byte [rbx + 19], '.'
    je .skip
    cmp r14, 2048
    jae .toofull
    mov [ptrs + r14*8], r15
    lea rsi, [rbx + 19]
.copy:
    cmp r15, names_end
    jae .toofull
    mov al, [rsi]
    mov [r15], al
    inc rsi
    inc r15
    test al, al
    jnz .copy
    inc r14
.skip:
    movzx eax, word [rbx + 16]
    add rbx, rax
    jmp .entry

.list:
    mov rax, 3
    mov rdi, r12
    syscall
    call sort_names
    xor rbx, rbx
.print:
    cmp rbx, r14
    jae .exit
    mov rdi, [ptrs + rbx*8]
    call cstrlen
    mov rsi, [ptrs + rbx*8]
    mov byte [rsi + rax], 10
    lea rdx, [rax + 1]
    mov rax, 1
    mov rdi, 1
    syscall
    inc rbx
    jmp .print
.exit:
    mov rax, 60
    xor edi, edi
    syscall

.usage:
    mov rsi, usage
    mov rdx, usage_len
    jmp .die
.openfail:
    mov rsi, err_open
    mov rdx, err_open_len
    jmp .die
.toofull:
    mov rsi, err_full
    mov rdx, err_full_len
.die:
    mov rax, 1
    mov rdi, 2
    syscall
    mov rax, 60
    mov rdi, 2
    syscall

; insertion sort of ptrs[0..r14) by strcmp
sort_names:
    cmp r14, 2
    jb .done
    mov rbx, 1
.outer:
    cmp rbx, r14
    jae .done
    mov r12, [ptrs + rbx*8]
    mov r13, rbx
.inner:
    test r13, r13
    jz .place
    mov rdi, [ptrs + r13*8 - 8]
    mov rsi, r12
    call strcmp
    test eax, eax
    jle .place
    mov rax, [ptrs + r13*8 - 8]
    mov [ptrs + r13*8], rax
    dec r13
    jmp .inner
.place:
    mov [ptrs + r13*8], r12
    inc rbx
    jmp .outer
.done:
    ret

; rdi, rsi = strings -> rax = byte-order difference
strcmp:
.next:
    movzx eax, byte [rdi]
    movzx ecx, byte [rsi]
    sub eax, ecx
    jnz .out
    test ecx, ecx
    jz .out
    inc rdi
    inc rsi
    jmp .next
.out:
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
