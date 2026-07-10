global _start

section .rodata
s_diff: db "p2 - p1 = ", 0
s_align: db "aligned: ", 0
s_write: db "writable: ", 0
s_reuse: db "freed block reused: ", 0
s_coal: db "coalescing works: ", 0
s_big: db "big alloc via brk: ", 0
s_yes: db "yes", 10, 0
s_no: db "no", 10, 0

section .data
heap_start: dq 0
heap_end: dq 0
nbuf: times 32 db 0

section .text
_start:
    mov rdi, 64
    call malloc
    mov r12, rax
    mov rdi, 64
    call malloc
    mov r13, rax

    mov rdi, s_diff
    call pstr
    mov rdi, r13
    sub rdi, r12
    call puintnl

    mov rdi, s_align
    call pstr
    test r12, 15
    mov rdi, s_no
    mov rax, s_yes
    cmovz rdi, rax
    call pstr

    mov rdi, s_write
    call pstr
    xor ecx, ecx
.fill:
    mov [r12 + rcx], cl
    inc ecx
    cmp ecx, 64
    jb .fill
    xor ecx, ecx
.check:
    cmp [r12 + rcx], cl
    jne .w_bad
    inc ecx
    cmp ecx, 64
    jb .check
    mov rdi, s_yes
    jmp .w_out
.w_bad:
    mov rdi, s_no
.w_out:
    call pstr

    mov rdi, r12
    call free
    mov rdi, 48
    call malloc
    mov rdi, s_reuse
    mov r14, rax
    call pstr
    cmp r14, r12
    mov rdi, s_no
    mov rax, s_yes
    cmove rdi, rax
    call pstr

    mov rdi, r13
    call free
    mov rdi, r14
    call free
    mov rdi, 144
    call malloc
    mov r14, rax
    mov rdi, s_coal
    call pstr
    cmp r14, r12
    mov rdi, s_no
    mov rax, s_yes
    cmove rdi, rax
    call pstr

    mov rdi, 100000
    call malloc
    mov r14, rax
    mov rdi, s_big
    call pstr
    test r14, r14
    mov rdi, s_no
    mov rax, s_yes
    cmovnz rdi, rax
    jz .skip_touch
    mov byte [r14], 0x42
    mov byte [r14 + 99999], 0x42
.skip_touch:
    call pstr

    mov rax, 60
    xor edi, edi
    syscall

; block header: 16 bytes = payload size (qword), flags (qword, bit 0 = free)
; rdi = size -> rax = 16-aligned ptr, 0 on failure
malloc:
    push rbx
    push r12
    push r13
    add rdi, 15
    and rdi, -16
    mov r12, rdi
    mov rax, [heap_start]
    test rax, rax
    jnz .walk_setup
    mov rax, 12
    xor edi, edi
    syscall
    mov [heap_start], rax
    mov [heap_end], rax
.walk_setup:
    mov rbx, [heap_start]
.walk:
    cmp rbx, [heap_end]
    jae .grow
    mov r13, [rbx]
    test qword [rbx + 8], 1
    jz .next
    cmp r13, r12
    jb .next
    lea rax, [r12 + 32]
    cmp r13, rax
    jb .take
    lea rax, [rbx + 16]
    add rax, r12
    mov rdx, r13
    sub rdx, r12
    sub rdx, 16
    mov [rax], rdx
    mov qword [rax + 8], 1
    mov [rbx], r12
.take:
    mov qword [rbx + 8], 0
    lea rax, [rbx + 16]
    jmp .out
.next:
    lea rbx, [rbx + 16]
    add rbx, r13
    jmp .walk
.grow:
    lea rbx, [r12 + 16 + 4095]
    and rbx, -4096
    mov rdi, [heap_end]
    add rdi, rbx
    mov rax, 12
    syscall
    cmp rax, rdi
    jne .fail
    mov rdx, [heap_end]
    mov [heap_end], rax
    lea rcx, [rbx - 16]
    mov [rdx], rcx
    mov qword [rdx + 8], 1
    jmp .walk_setup
.fail:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; rdi = ptr from malloc, coalesces with free neighbors above
free:
    test rdi, rdi
    jz .out
    lea rax, [rdi - 16]
    mov qword [rax + 8], 1
.coal:
    mov rdx, [rax]
    lea rcx, [rax + 16]
    add rcx, rdx
    cmp rcx, [heap_end]
    jae .out
    test qword [rcx + 8], 1
    jz .out
    mov rsi, [rcx]
    lea rdx, [rdx + 16]
    add rdx, rsi
    mov [rax], rdx
    jmp .coal
.out:
    ret

; rdi = cstring, written without newline
pstr:
    push rdi
    call cstrlen
    pop rsi
    mov rdx, rax
    mov rax, 1
    mov rdi, 1
    syscall
    ret

; rdi = value, decimal with newline
puintnl:
    mov rax, rdi
    lea rsi, [nbuf + 31]
    mov byte [rsi], 10
    mov rcx, 10
.div:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .div
    lea rdx, [nbuf + 32]
    sub rdx, rsi
    mov rax, 1
    mov rdi, 1
    syscall
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
