global _start

section .rodata
align 4
; first 32 bits of the fractional parts of the cube roots of the first 64 primes
K:
    dd 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5
    dd 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    dd 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3
    dd 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    dd 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc
    dd 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    dd 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7
    dd 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    dd 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13
    dd 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
    dd 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3
    dd 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    dd 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5
    dd 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    dd 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208
    dd 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
hexchars: db "0123456789abcdef"

section .data
align 4
; initial hash: fractional parts of square roots of first 8 primes
H: dd 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
   dd 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
total_len: dq 0
w: times 64 dd 0
block: times 64 db 0
hexout: times 65 db 0

section .bss
inbuf: resb 65536

section .text
_start:
    ; stream stdin, hashing each full 64-byte block
.read:
    xor eax, eax
    xor edi, edi
    mov rsi, inbuf
    mov edx, 65536
    syscall
    test rax, rax
    jle .finish
    add [total_len], rax
    mov r12, inbuf
    mov r13, rax
    mov r14, [block_fill]       ; current fill level of `block`
.fill_loop:
    test r13, r13
    jz .save_fill
    mov al, [r12]
    mov [block + r14], al
    inc r12
    dec r13
    inc r14
    cmp r14, 64
    jb .fill_loop
    call compress
    xor r14d, r14d              ; block consumed, start fresh
    jmp .fill_loop
.save_fill:
    mov [block_fill], r14
    jmp .read

.finish:
    ; padding: append 0x80, then zeros, then 64-bit big-endian bit length
    mov r14, [block_fill]
    mov byte [block + r14], 0x80
    inc r14
    cmp r14, 56
    jbe .padzero
    ; not enough room for length -> zero-fill, compress, start fresh block
.fillrest:
    cmp r14, 64
    jae .flush_extra
    mov byte [block + r14], 0
    inc r14
    jmp .fillrest
.flush_extra:
    call compress
    xor r14d, r14d
.padzero:
    cmp r14, 56
    jae .putlen
    mov byte [block + r14], 0
    inc r14
    jmp .padzero
.putlen:
    ; bit length = total_len * 8, written big-endian in the last 8 bytes
    mov rax, [total_len]
    shl rax, 3
    bswap rax
    mov [block + 56], rax
    call compress

    ; emit H[0..7] as big-endian hex
    lea rdi, [hexout]
    xor ebx, ebx
.emit:
    mov eax, [H + rbx*4]
    mov ecx, 8
.byte_nibbles:
    rol eax, 4
    mov edx, eax
    and edx, 0xf
    mov dl, [hexchars + rdx]
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .byte_nibbles
    inc ebx
    cmp ebx, 8
    jb .emit
    mov byte [rdi], 10

    mov rax, 1
    mov rdi, 1
    lea rsi, [hexout]
    mov rdx, 65
    syscall

    mov rax, 60
    xor edi, edi
    syscall

; compresses the 64-byte `block` into H
compress:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    ; message schedule: first 16 words are big-endian from block
    xor ecx, ecx
.load16:
    mov eax, [block + rcx*4]
    bswap eax
    mov [w + rcx*4], eax
    inc ecx
    cmp ecx, 16
    jb .load16

    ; extend to 64 words
    mov ecx, 16
.extend:
    ; s0 = ror(w[i-15],7) ^ ror(w[i-15],18) ^ (w[i-15]>>3)
    mov eax, [w + rcx*4 - 60]
    mov edx, eax
    ror eax, 7
    mov edi, edx
    ror edi, 18
    xor eax, edi
    shr edx, 3
    xor eax, edx
    mov r8d, eax                ; s0
    ; s1 = ror(w[i-2],17) ^ ror(w[i-2],19) ^ (w[i-2]>>10)
    mov eax, [w + rcx*4 - 8]
    mov edx, eax
    ror eax, 17
    mov edi, edx
    ror edi, 19
    xor eax, edi
    shr edx, 10
    xor eax, edx
    ; w[i] = w[i-16] + s0 + w[i-7] + s1
    add eax, r8d
    add eax, [w + rcx*4 - 64]
    add eax, [w + rcx*4 - 28]
    mov [w + rcx*4], eax
    inc ecx
    cmp ecx, 64
    jb .extend

    ; working vars a..h in registers
    mov eax, [H]                ; a
    mov ebx, [H + 4]            ; b
    mov r12d, [H + 8]           ; c
    mov r13d, [H + 12]          ; d
    mov r14d, [H + 16]          ; e
    mov r15d, [H + 20]          ; f
    mov ebp, [H + 24]           ; g
    mov edi, [H + 28]           ; h  (kept in memory slot via stack)
    mov [hvar], edi

    xor ecx, ecx
.round:
    ; S1 = ror(e,6) ^ ror(e,11) ^ ror(e,25)
    mov edx, r14d
    ror edx, 6
    mov edi, r14d
    ror edi, 11
    xor edx, edi
    mov edi, r14d
    ror edi, 25
    xor edx, edi                ; edx = S1
    ; ch = (e & f) ^ (~e & g)
    mov edi, r14d
    and edi, r15d
    mov esi, r14d
    not esi
    and esi, ebp
    xor edi, esi                ; edi = ch
    ; t1 = h + S1 + ch + K[i] + w[i]
    add edx, edi
    mov edi, [hvar]
    add edx, edi
    mov edi, [K + rcx*4]
    add edx, edi
    mov edi, [w + rcx*4]
    add edx, edi                ; edx = t1
    ; S0 = ror(a,2) ^ ror(a,13) ^ ror(a,22)
    mov esi, eax
    ror esi, 2
    mov edi, eax
    ror edi, 13
    xor esi, edi
    mov edi, eax
    ror edi, 22
    xor esi, edi                ; esi = S0
    ; maj = (a & b) ^ (a & c) ^ (b & c)
    mov edi, eax
    and edi, ebx
    mov r8d, eax
    and r8d, r12d
    xor edi, r8d
    mov r8d, ebx
    and r8d, r12d
    xor edi, r8d                ; edi = maj
    ; t2 = S0 + maj
    add esi, edi                ; esi = t2

    ; h=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2
    mov edi, ebp
    mov [hvar], edi             ; h = g
    mov ebp, r15d               ; g = f
    mov r15d, r14d              ; f = e
    mov r14d, r13d
    add r14d, edx               ; e = d + t1
    mov r13d, r12d              ; d = c
    mov r12d, ebx               ; c = b
    mov ebx, eax                ; b = a
    mov eax, edx
    add eax, esi                ; a = t1 + t2

    inc ecx
    cmp ecx, 64
    jb .round

    ; feed back into H
    add [H], eax
    add [H + 4], ebx
    add [H + 8], r12d
    add [H + 12], r13d
    add [H + 16], r14d
    add [H + 20], r15d
    add [H + 24], ebp
    mov edi, [hvar]
    add [H + 28], edi

    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .data
block_fill: dq 0
hvar: dd 0

section .note.GNU-stack noalloc noexec nowrite progbits
