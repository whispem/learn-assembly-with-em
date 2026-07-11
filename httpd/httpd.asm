global _start

section .rodata
h200: db "HTTP/1.0 200 OK", 13, 10, "Content-Type: text/plain; charset=utf-8", 13, 10, "Content-Length: ", 0
h200_len equ $ - h200 - 1
crlf2: db 13, 10, 13, 10
h404: db "HTTP/1.0 404 Not Found", 13, 10, "Content-Type: text/plain; charset=utf-8", 13, 10, "Content-Length: 10", 13, 10, 13, 10, "not found", 10
h404_len equ $ - h404
def_path: db "README.md", 0
s_listen: db "listening on http://localhost:8080", 10, 0
s_200: db "200 /", 0
s_404: db "404 /", 0
e_bind: db "httpd: cannot bind port 8080", 10
e_bind_len equ $ - e_bind
nl: db 10, 0

section .data
addr: dw 2
      dw 0x901f
      dd 0
      dq 0
optval: dd 1
sigact: dq 1, 0, 0, 0
statbuf: times 144 db 0
nbuf: times 32 db 0
pathbuf: times 1040 db 0
rbuf: times 4096 db 0
fbuf: times 8192 db 0

section .text
_start:
    mov rax, 13                 ; rt_sigaction(SIGPIPE, SIG_IGN)
    mov edi, 13
    mov rsi, sigact
    xor edx, edx
    mov r10d, 8
    syscall

    mov rax, 41                 ; socket(AF_INET, SOCK_STREAM, 0)
    mov edi, 2
    mov esi, 1
    xor edx, edx
    syscall
    test rax, rax
    js .die
    mov r12, rax

    mov rax, 54                 ; setsockopt(SO_REUSEADDR)
    mov rdi, r12
    mov esi, 1
    mov edx, 2
    mov r10, optval
    mov r8d, 4
    syscall

    mov rax, 49
    mov rdi, r12
    mov rsi, addr
    mov edx, 16
    syscall
    test rax, rax
    js .die

    mov rax, 50
    mov rdi, r12
    mov esi, 16
    syscall

    mov rdi, s_listen
    call pstr

.accept:
    mov rax, 43
    mov rdi, r12
    xor esi, esi
    xor edx, edx
    syscall
    test rax, rax
    js .accept
    mov r13, rax

    mov byte [pathbuf], 0
    xor eax, eax
    mov rdi, r13
    mov rsi, rbuf
    mov edx, 4096
    syscall
    cmp rax, 5
    jl .close_conn

    cmp dword [rbuf], 'GET '
    jne .send404

    lea rsi, [rbuf + 4]
    cmp byte [rsi], '/'
    jne .copy_path
    inc rsi
.copy_path:
    mov rdi, pathbuf
    xor ecx, ecx
.copy:
    mov al, [rsi]
    cmp al, ' '
    je .capped
    cmp al, 13
    je .capped
    cmp al, 10
    je .capped
    cmp al, '?'
    je .capped
    test al, al
    jz .capped
    mov [rdi], al
    inc rsi
    inc rdi
    inc ecx
    cmp ecx, 1024
    jb .copy
.capped:
    mov byte [rdi], 0
    test ecx, ecx
    jnz .have_path
    mov rsi, def_path
    mov rdi, pathbuf
.defcpy:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .defcpy
.have_path:
    mov rsi, pathbuf            ; reject ".."
.dots:
    mov al, [rsi]
    test al, al
    jz .open
    cmp al, '.'
    jne .ndot
    cmp byte [rsi + 1], '.'
    je .send404
.ndot:
    inc rsi
    jmp .dots

.open:
    mov rax, 2
    mov rdi, pathbuf
    xor esi, esi
    xor edx, edx
    syscall
    test rax, rax
    js .send404
    mov r14, rax

    mov rax, 5                  ; fstat
    mov rdi, r14
    mov rsi, statbuf
    syscall
    mov eax, [statbuf + 24]     ; st_mode: regular files only
    and eax, 0xf000
    cmp eax, 0x8000
    jne .close404
    mov r15, [statbuf + 48]     ; st_size

    mov rax, 1
    mov rdi, r13
    mov rsi, h200
    mov rdx, h200_len
    syscall
    mov rdi, r15
    call size_str
    mov rax, 1
    mov rdi, r13
    syscall
    mov rax, 1
    mov rdi, r13
    mov rsi, crlf2
    mov edx, 4
    syscall

.send_body:
    test r15, r15
    jz .sent
    mov rax, 40                 ; sendfile(conn, file, NULL, remaining)
    mov rdi, r13
    mov rsi, r14
    xor edx, edx
    mov r10, r15
    syscall
    test rax, rax
    jle .pump
    sub r15, rax
    jnz .send_body
    jmp .sent
.pump:                          ; fallback: read + write
    xor eax, eax
    mov rdi, r14
    mov rsi, fbuf
    mov edx, 8192
    syscall
    test rax, rax
    jle .sent
    mov rbx, rax
    mov rbp, fbuf
.pw:
    mov rax, 1
    mov rdi, r13
    mov rsi, rbp
    mov rdx, rbx
    syscall
    test rax, rax
    jle .sent
    add rbp, rax
    sub rbx, rax
    jnz .pw
    jmp .pump
.sent:
    mov rax, 3
    mov rdi, r14
    syscall
    mov rdi, s_200
    call pstr
    mov rdi, pathbuf
    call pstr
    mov rdi, nl
    call pstr
    jmp .close_conn

.close404:
    mov rax, 3
    mov rdi, r14
    syscall
.send404:
    mov rax, 1
    mov rdi, r13
    mov rsi, h404
    mov rdx, h404_len
    syscall
    mov rdi, s_404
    call pstr
    mov rdi, pathbuf
    call pstr
    mov rdi, nl
    call pstr

.close_conn:
    mov rax, 3
    mov rdi, r13
    syscall
    jmp .accept

.die:
    mov rax, 1
    mov rdi, 2
    mov rsi, e_bind
    mov rdx, e_bind_len
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

; rdi = value -> rsi = decimal digits, rdx = length
size_str:
    mov rax, rdi
    lea rsi, [nbuf + 32]
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
    ret

; rdi = cstring, written to stdout
pstr:
    push rdi
    call cstrlen
    pop rsi
    mov rdx, rax
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
