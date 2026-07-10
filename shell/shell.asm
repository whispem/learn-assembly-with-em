global _start

section .rodata
prompt: db "em$ ", 0
s_pipe: db "|", 0
s_lt: db "<", 0
s_gt: db ">", 0
s_gtgt: db ">>", 0
s_cd: db "cd", 0
s_exit: db "exit", 0
default_path: db "/usr/bin:/bin", 0
e_nf: db ": command not found", 10
e_nf_len equ $ - e_nf
e_cd: db "cd: cannot chdir", 10
e_cd_len equ $ - e_cd
e_syn: db "syntax error", 10
e_syn_len equ $ - e_syn
e_in: db "cannot open input", 10
e_in_len equ $ - e_in
e_out: db "cannot open output", 10
e_out_len equ $ - e_out
nl: db 10

section .data
envp: dq 0
path_val: dq 0
ntoks: dq 0
cargc: dq 0
seg_in: dq 0
seg_out: dq 0
seg_append: dq 0
rdpos: dq 0
rdlen: dq 0
pipefds: dd 0, 0
rdbuf: times 4096 db 0
inbuf: times 4096 db 0
pathbuf: times 4096 db 0
toks: times 256 dq 0
cargv: times 128 dq 0

section .text
_start:
    mov rax, [rsp]
    lea rax, [rsp + rax*8 + 16]
    mov [envp], rax
    call find_path

main_loop:
    mov rax, 1
    mov rdi, 2
    mov rsi, prompt
    mov rdx, 4
    syscall

    call getline
    cmp rax, -1
    je .eof
    call tokenize
    cmp qword [ntoks], 0
    je main_loop

    mov rdi, [toks]
    mov rsi, s_exit
    call strcmp
    test eax, eax
    jz .bye

    mov rdi, [toks]
    mov rsi, s_cd
    call strcmp
    test eax, eax
    jnz .run
    cmp qword [ntoks], 2
    jb .cderr
    mov rax, 80
    mov rdi, [toks + 8]
    syscall
    test rax, rax
    jns main_loop
.cderr:
    mov rsi, e_cd
    mov rdx, e_cd_len
    call werr
    jmp main_loop

.run:
    call run_pipeline
    jmp main_loop

.eof:
    mov rax, 1
    mov rdi, 2
    mov rsi, nl
    mov rdx, 1
    syscall
.bye:
    mov rax, 60
    xor edi, edi
    syscall

; executes toks[0..ntoks) as a pipeline
run_pipeline:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor ebx, ebx                ; token index
    xor r12d, r12d              ; children
    mov r13, -1                 ; prev pipe read end
    mov r14, [ntoks]

.segment:
    mov qword [cargc], 0
    mov qword [seg_in], 0
    mov qword [seg_out], 0
    mov qword [seg_append], 0
    xor r15d, r15d              ; last flag
.collect:
    cmp rbx, r14
    jb .tok
    inc r15d
    jmp .built
.tok:
    mov rdi, [toks + rbx*8]
    mov rsi, s_pipe
    call strcmp
    test eax, eax
    jnz .not_pipe
    inc rbx
    jmp .built
.not_pipe:
    mov rdi, [toks + rbx*8]
    mov rsi, s_lt
    call strcmp
    test eax, eax
    jnz .not_lt
    inc rbx
    cmp rbx, r14
    jae .syntax
    mov rax, [toks + rbx*8]
    mov [seg_in], rax
    inc rbx
    jmp .collect
.not_lt:
    mov rdi, [toks + rbx*8]
    mov rsi, s_gtgt
    call strcmp
    test eax, eax
    jnz .not_gtgt
    mov qword [seg_append], 1
    jmp .grab_out
.not_gtgt:
    mov rdi, [toks + rbx*8]
    mov rsi, s_gt
    call strcmp
    test eax, eax
    jnz .word
.grab_out:
    inc rbx
    cmp rbx, r14
    jae .syntax
    mov rax, [toks + rbx*8]
    mov [seg_out], rax
    inc rbx
    jmp .collect
.word:
    mov rdx, [cargc]
    cmp rdx, 126
    jae .syntax
    mov rax, [toks + rbx*8]
    mov [cargv + rdx*8], rax
    inc qword [cargc]
    inc rbx
    jmp .collect

.built:
    mov rdx, [cargc]
    test rdx, rdx
    jz .syntax
    mov qword [cargv + rdx*8], 0

    test r15d, r15d
    jnz .no_pipe
    mov rax, 22
    mov rdi, pipefds
    syscall
.no_pipe:
    mov rax, 57
    syscall
    test rax, rax
    jz .child

    inc r12d
    cmp r13, -1
    je .p_nokeep
    mov rax, 3
    mov rdi, r13
    syscall
.p_nokeep:
    test r15d, r15d
    jnz .waitall
    mov eax, [pipefds + 4]
    mov edi, eax
    mov rax, 3
    syscall
    mov r13d, [pipefds]
    jmp .segment

.child:
    cmp r13, -1
    je .c_nostdin
    mov rax, 33
    mov rdi, r13
    xor esi, esi
    syscall
    mov rax, 3
    mov rdi, r13
    syscall
.c_nostdin:
    test r15d, r15d
    jnz .c_nopipe
    mov eax, [pipefds]
    mov edi, eax
    mov rax, 3
    syscall
    mov rax, 33
    mov edi, [pipefds + 4]
    mov esi, 1
    syscall
    mov rax, 3
    mov edi, [pipefds + 4]
    syscall
.c_nopipe:
    mov rdi, [seg_in]
    test rdi, rdi
    jz .c_noin
    mov rax, 2
    xor esi, esi
    xor edx, edx
    syscall
    test rax, rax
    js .c_inerr
    mov rdi, rax
    push rdi
    mov rax, 33
    xor esi, esi
    syscall
    pop rdi
    mov rax, 3
    syscall
.c_noin:
    mov rdi, [seg_out]
    test rdi, rdi
    jz .c_noout
    mov esi, 0x241
    cmp qword [seg_append], 0
    je .c_flags
    mov esi, 0x441
.c_flags:
    mov rax, 2
    mov edx, 420
    syscall
    test rax, rax
    js .c_outerr
    mov rdi, rax
    push rdi
    mov rax, 33
    mov esi, 1
    syscall
    pop rdi
    mov rax, 3
    syscall
.c_noout:
    call exec_path
.c_inerr:
    mov rsi, e_in
    mov rdx, e_in_len
    call werr
    mov rax, 60
    mov rdi, 1
    syscall
.c_outerr:
    mov rsi, e_out
    mov rdx, e_out_len
    call werr
    mov rax, 60
    mov rdi, 1
    syscall

.syntax:
    mov rsi, e_syn
    mov rdx, e_syn_len
    call werr
    cmp r13, -1
    je .waitall
    mov rax, 3
    mov rdi, r13
    syscall
.waitall:
    test r12d, r12d
    jz .done
    mov rax, 61
    mov rdi, -1
    xor esi, esi
    xor edx, edx
    xor r10d, r10d
    syscall
    dec r12d
    jmp .waitall
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; never returns: tries cargv[0] directly or through PATH, exit 127 on failure
exec_path:
    mov rdi, [cargv]
.slash:
    mov al, [rdi]
    test al, al
    jz .search
    cmp al, '/'
    je .direct
    inc rdi
    jmp .slash
.direct:
    mov rdi, [cargv]
    mov rsi, cargv
    mov rdx, [envp]
    mov rax, 59
    syscall
    jmp .notfound
.search:
    mov rbx, [path_val]
.comp:
    mov rdi, pathbuf
.copy:
    mov al, [rbx]
    test al, al
    jz .cap
    cmp al, ':'
    je .cap
    mov [rdi], al
    inc rdi
    inc rbx
    jmp .copy
.cap:
    cmp rdi, pathbuf
    je .name
    mov byte [rdi], '/'
    inc rdi
.name:
    mov rsi, [cargv]
.cname:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .cname
    mov rdi, pathbuf
    mov rsi, cargv
    mov rdx, [envp]
    mov rax, 59
    syscall
    cmp byte [rbx], 0
    je .notfound
    inc rbx
    jmp .comp
.notfound:
    mov rdi, [cargv]
    call cstrlen
    mov rdx, rax
    mov rsi, [cargv]
    mov rax, 1
    mov rdi, 2
    syscall
    mov rsi, e_nf
    mov rdx, e_nf_len
    call werr
    mov rax, 60
    mov rdi, 127
    syscall

; finds PATH= in envp, falls back to default_path
find_path:
    mov qword [path_val], default_path
    mov rsi, [envp]
.next:
    mov rdi, [rsi]
    test rdi, rdi
    jz .out
    cmp dword [rdi], 'PATH'
    jne .adv
    cmp byte [rdi + 4], '='
    jne .adv
    lea rdi, [rdi + 5]
    mov [path_val], rdi
    ret
.adv:
    add rsi, 8
    jmp .next
.out:
    ret

; -> rax = line length in inbuf (0-terminated), -1 on EOF
getline:
    xor r9d, r9d
.next:
    mov rax, [rdpos]
    cmp rax, [rdlen]
    jb .have
    xor eax, eax
    xor edi, edi
    mov rsi, rdbuf
    mov edx, 4096
    syscall
    test rax, rax
    jle .end
    mov [rdlen], rax
    mov qword [rdpos], 0
    jmp .next
.have:
    mov rdx, rax
    inc rax
    mov [rdpos], rax
    mov al, [rdbuf + rdx]
    cmp al, 10
    je .line
    cmp r9, 4095
    jae .next
    mov [inbuf + r9], al
    inc r9
    jmp .next
.end:
    test r9, r9
    jnz .line
    mov rax, -1
    ret
.line:
    mov rax, r9
    mov byte [inbuf + r9], 0
    ret

; splits inbuf on spaces and tabs into toks
tokenize:
    mov qword [ntoks], 0
    mov rsi, inbuf
.skip:
    mov al, [rsi]
    test al, al
    jz .out
    cmp al, ' '
    je .adv
    cmp al, 9
    je .adv
    mov rdx, [ntoks]
    cmp rdx, 255
    jae .out
    mov [toks + rdx*8], rsi
    inc qword [ntoks]
.scan:
    inc rsi
    mov al, [rsi]
    test al, al
    jz .out
    cmp al, ' '
    je .cut
    cmp al, 9
    je .cut
    jmp .scan
.cut:
    mov byte [rsi], 0
.adv:
    inc rsi
    jmp .skip
.out:
    ret

; rsi = msg, rdx = len, written to stderr
werr:
    mov rax, 1
    mov rdi, 2
    syscall
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
