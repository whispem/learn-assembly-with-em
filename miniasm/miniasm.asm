global _start

; miniasm — a tiny x86-64 assembler.
; Reads assembly source on stdin, writes an ELF64 executable to argv[1].
; Supports: mov reg,imm ; mov reg,reg ; add reg,imm ; add reg,reg ;
;           xor reg,reg ; syscall ; and comments (; ...) and blank lines.
; Registers: rax rcx rdx rbx rsp rbp rsi rdi (encodings 0..7).
; The encodings match NASM byte-for-byte for this subset.

%define VADDR 0x400000

section .rodata
e_usage:  db "usage: miniasm <out> < in.asm", 10
e_usage_len equ $ - e_usage
e_syntax: db "syntax error", 10
e_syntax_len equ $ - e_syntax
e_reg:    db "unknown register", 10
e_reg_len equ $ - e_reg
e_ins:    db "unknown instruction", 10
e_ins_len equ $ - e_ins
e_write:  db "cannot open output", 10
e_write_len equ $ - e_write

; register name table: 3 chars each, index = encoding
regs:     db "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi"

; mnemonics
m_mov:    db "mov", 0
m_add:    db "add", 0
m_xor:    db "xor", 0
m_syscall: db "syscall", 0

section .data
srclen:   dq 0
pos:      dq 0
codelen:  dq 0

section .bss
src:      resb 65536
code:     resb 65536
tok:      resb 64
elfbuf:   resb 65536

section .text
_start:
    mov rax, [rsp]
    cmp rax, 2
    jb .usage
    mov rax, [rsp + 16]        ; argv[1]
    mov [argv1], rax

    ; read all of stdin into src
    xor r12d, r12d
.read:
    xor eax, eax
    xor edi, edi
    lea rsi, [src + r12]
    mov edx, 65536
    sub rdx, r12
    syscall
    test rax, rax
    jle .read_done
    add r12, rax
    jmp .read
.read_done:
    mov [srclen], r12
    mov qword [pos], 0
    mov qword [codelen], 0

.line_loop:
    call skip_ws_and_comments
    mov rax, [pos]
    cmp rax, [srclen]
    jae .assemble_done
    ; read a mnemonic token
    call read_token
    cmp rdx, 0
    je .line_loop

    ; dispatch on mnemonic
    lea rsi, [m_syscall]
    call tok_is
    test eax, eax
    jnz .do_syscall
    lea rsi, [m_mov]
    call tok_is
    test eax, eax
    jnz .do_mov
    lea rsi, [m_add]
    call tok_is
    test eax, eax
    jnz .do_add
    lea rsi, [m_xor]
    call tok_is
    test eax, eax
    jnz .do_xor
    jmp .bad_ins

.do_syscall:
    mov al, 0x0f
    call emit
    mov al, 0x05
    call emit
    jmp .line_loop

.do_mov:
    call read_operand          ; -> rax=kind(0 reg/1 imm), rbx=value
    mov r13, rax               ; dst kind (must be reg)
    mov r14, rbx               ; dst reg
    test r13, r13
    jnz .syntax
    call expect_comma
    call read_operand          ; second operand
    test rax, rax
    jnz .mov_imm
    ; mov reg, reg : REX.W 89 /r  (src in reg field, dst in r/m)
    mov r15, rbx               ; src reg
    mov al, 0x48
    or al, 0                   ; REX.W (no extension bits for regs 0..7)
    call emit
    mov al, 0x89
    call emit
    ; ModRM: 11 (src) (dst)
    mov al, 0xc0
    mov cl, r15b
    shl cl, 3
    or al, cl
    or al, r14b
    call emit
    jmp .line_loop
.mov_imm:
    ; mov reg, imm32 : B8+reg id  (NASM emits no REX for imm-to-reg here)
    mov al, 0xb8
    or al, r14b
    call emit
    mov rax, rbx
    call emit_dword
    jmp .line_loop

.do_add:
    call read_operand
    mov r14, rbx               ; dst reg
    test rax, rax
    jnz .syntax                ; dst must be reg
    call expect_comma
    call read_operand
    test rax, rax
    jnz .add_imm
    ; add reg, reg : REX.W 01 /r
    mov r15, rbx
    mov al, 0x48
    call emit
    mov al, 0x01
    call emit
    mov al, 0xc0
    mov cl, r15b
    shl cl, 3
    or al, cl
    or al, r14b
    call emit
    jmp .line_loop
.add_imm:
    ; add reg, imm : REX.W 83 /0 ib  (assume imm fits in signed byte)
    mov al, 0x48
    call emit
    mov al, 0x83
    call emit
    ; ModRM: 11 000 reg   (/0 = add)
    mov al, 0xc0
    or al, r14b
    call emit
    mov al, bl                 ; imm8
    call emit
    jmp .line_loop

.do_xor:
    call read_operand
    mov r14, rbx
    test rax, rax
    jnz .syntax
    call expect_comma
    call read_operand
    test rax, rax
    jnz .syntax                ; only xor reg,reg supported
    mov r15, rbx
    ; xor reg, reg : REX.W 31 /r
    mov al, 0x48
    call emit
    mov al, 0x31
    call emit
    mov al, 0xc0
    mov cl, r15b
    shl cl, 3
    or al, cl
    or al, r14b
    call emit
    jmp .line_loop

.assemble_done:
    call write_elf
    mov rax, 60
    xor edi, edi
    syscall

.usage:
    mov rax, 1
    mov rdi, 2
    mov rsi, e_usage
    mov rdx, e_usage_len
    syscall
    mov rax, 60
    mov rdi, 1
    syscall
.syntax:
    mov rsi, e_syntax
    mov rdx, e_syntax_len
    jmp .die
.bad_ins:
    mov rsi, e_ins
    mov rdx, e_ins_len
.die:
    mov rax, 1
    mov rdi, 2
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

; ---- lexer ----

; advance pos over spaces, tabs, newlines, and ; comments
skip_ws_and_comments:
    mov rsi, [pos]
    mov rcx, [srclen]
.loop:
    cmp rsi, rcx
    jae .done
    mov al, [src + rsi]
    cmp al, ' '
    je .adv
    cmp al, 9
    je .adv
    cmp al, 10
    je .adv
    cmp al, 13
    je .adv
    cmp al, ';'
    je .comment
    jmp .done
.adv:
    inc rsi
    jmp .loop
.comment:
    inc rsi
.ceat:
    cmp rsi, rcx
    jae .done
    mov al, [src + rsi]
    inc rsi
    cmp al, 10
    jne .ceat
    jmp .loop
.done:
    mov [pos], rsi
    ret

; read an identifier/number token into tok (null-terminated) -> rdx=len
read_token:
    mov rsi, [pos]
    mov rcx, [srclen]
    xor rdi, rdi
.loop:
    cmp rsi, rcx
    jae .done
    mov al, [src + rsi]
    ; stop on whitespace, comma, comment, newline
    cmp al, ' '
    je .done
    cmp al, 9
    je .done
    cmp al, 10
    je .done
    cmp al, 13
    je .done
    cmp al, ','
    je .done
    cmp al, ';'
    je .done
    mov [tok + rdi], al
    inc rsi
    inc rdi
    cmp rdi, 63
    jb .loop
.done:
    mov [pos], rsi
    mov byte [tok + rdi], 0
    mov rdx, rdi
    ret

; is tok equal to the C-string at rsi? -> eax=1/0
tok_is:
    lea rdi, [tok]
.cmp:
    mov al, [rdi]
    mov cl, [rsi]
    cmp al, cl
    jne .no
    test al, al
    jz .yes
    inc rdi
    inc rsi
    jmp .cmp
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; read an operand: skip ws, read token, classify.
; -> rax = 0 if register (rbx = encoding), 1 if immediate (rbx = value)
read_operand:
    call skip_ws_and_comments
    call read_token
    test rdx, rdx
    jz .synerr
    call match_reg             ; -> rax=1 & rbx=enc if matched
    test rax, rax
    jnz .isreg
    ; parse as number immediate
    call parse_tok_number      ; -> rax=value
    mov rbx, rax
    mov rax, 1
    ret
.isreg:
    xor rax, rax               ; kind 0 = register, rbx = encoding
    ret
.synerr:
    mov rsi, e_syntax
    mov rdx, e_syntax_len
    mov rax, 1
    mov rdi, 2
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

; match tok against register table -> rax=1,rbx=enc  or rax=0
match_reg:
    xor r8, r8
.loop:
    cmp r8, 8
    jae .no
    ; compare 3 bytes: tok[0..2] vs regs[r8*3 .. +2], and tok[3]==0
    lea rsi, [regs]
    mov rax, r8
    imul rax, 3
    add rsi, rax
    mov al, [tok]
    cmp al, [rsi]
    jne .next
    mov al, [tok+1]
    cmp al, [rsi+1]
    jne .next
    mov al, [tok+2]
    cmp al, [rsi+2]
    jne .next
    cmp byte [tok+3], 0
    jne .next
    mov rbx, r8
    mov rax, 1
    ret
.next:
    inc r8
    jmp .loop
.no:
    xor rax, rax
    ret

; parse tok as a decimal (optionally negative) number -> rax
parse_tok_number:
    xor rax, rax
    xor r9, r9
    lea rdi, [tok]
    cmp byte [rdi], '-'
    jne .digits
    mov r9, 1
    inc rdi
.digits:
    movzx ecx, byte [rdi]
    test cl, cl
    jz .done
    sub ecx, '0'
    cmp ecx, 9
    ja .done
    imul rax, 10
    add rax, rcx
    inc rdi
    jmp .digits
.done:
    test r9, r9
    jz .ok
    neg rax
.ok:
    ret

; expect a comma next (skips ws)
expect_comma:
    call skip_ws_and_comments
    mov rsi, [pos]
    cmp rsi, [srclen]
    jae .err
    mov al, [src + rsi]
    cmp al, ','
    jne .err
    inc rsi
    mov [pos], rsi
    ret
.err:
    mov rsi, e_syntax
    mov rdx, e_syntax_len
    mov rax, 1
    mov rdi, 2
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

; ---- code buffer ----
; emit al into code
emit:
    mov rcx, [codelen]
    mov [code + rcx], al
    inc rcx
    mov [codelen], rcx
    ret

; emit eax as little-endian dword
emit_dword:
    mov rcx, [codelen]
    mov [code + rcx], al
    shr eax, 8
    mov [code + rcx + 1], al
    shr eax, 8
    mov [code + rcx + 2], al
    shr eax, 8
    mov [code + rcx + 3], al
    add rcx, 4
    mov [codelen], rcx
    ret

; ---- ELF writer ----
; builds a minimal ELF64 executable: ELF header (64) + one program header (56)
; + code, entry at VADDR + 120.
write_elf:
    ; open argv[1] for writing (O_CREAT|O_WRONLY|O_TRUNC, 0755)
    mov rdi, [argv1]
    mov rax, 2
    mov esi, 0x241              ; O_WRONLY|O_CREAT|O_TRUNC
    mov edx, 0o755
    syscall
    test rax, rax
    js .werr
    mov r13, rax               ; fd

    ; assemble ELF into elfbuf
    lea rdi, [elfbuf]
    ; ELF header
    mov byte [rdi+0], 0x7f
    mov byte [rdi+1], 'E'
    mov byte [rdi+2], 'L'
    mov byte [rdi+3], 'F'
    mov byte [rdi+4], 2         ; 64-bit
    mov byte [rdi+5], 1         ; little-endian
    mov byte [rdi+6], 1         ; version
    mov byte [rdi+7], 0
    ; pad to 16
    mov qword [rdi+8], 0
    mov word  [rdi+16], 2       ; e_type = ET_EXEC
    mov word  [rdi+18], 0x3e    ; e_machine = x86-64
    mov dword [rdi+20], 1       ; e_version
    ; e_entry = VADDR + headers(120)
    mov rax, VADDR + 120
    mov [rdi+24], rax
    mov qword [rdi+32], 64      ; e_phoff
    mov qword [rdi+40], 0       ; e_shoff
    mov dword [rdi+48], 0       ; e_flags
    mov word  [rdi+52], 64      ; e_ehsize
    mov word  [rdi+54], 56      ; e_phentsize
    mov word  [rdi+56], 1       ; e_phnum
    mov word  [rdi+58], 0       ; e_shentsize
    mov word  [rdi+60], 0       ; e_shnum
    mov word  [rdi+62], 0       ; e_shstrndx
    ; program header at offset 64
    mov dword [rdi+64], 1       ; p_type = PT_LOAD
    mov dword [rdi+68], 5       ; p_flags = R+X
    mov qword [rdi+72], 0       ; p_offset
    mov qword [rdi+80], VADDR   ; p_vaddr
    mov qword [rdi+88], VADDR   ; p_paddr
    ; p_filesz = p_memsz = 120 + codelen
    mov rax, [codelen]
    add rax, 120
    mov [rdi+96], rax           ; p_filesz
    mov [rdi+104], rax          ; p_memsz
    mov qword [rdi+112], 0x1000 ; p_align

    ; copy code after the 120-byte headers
    mov rsi, code
    lea rdi, [elfbuf + 120]
    mov rcx, [codelen]
.copy:
    test rcx, rcx
    jz .copied
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jmp .copy
.copied:
    ; write headers+code
    mov rax, 1
    mov rdi, r13
    lea rsi, [elfbuf]
    mov rdx, [codelen]
    add rdx, 120
    syscall
    ; close
    mov rax, 3
    mov rdi, r13
    syscall
    ret
.werr:
    mov rax, 1
    mov rdi, 2
    mov rsi, e_write
    mov rdx, e_write_len
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

section .data
argv1: dq 0

section .note.GNU-stack noalloc noexec nowrite progbits
