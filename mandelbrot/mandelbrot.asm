global _start

section .rodata
align 32
lane_off: dd 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0
four:     dd 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0
one:      dd 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0

%define WIDTH  120
%define HEIGHT 40
%define MAXITER 80

section .data
align 32
xmin_v:   dd -2.5
xspan_v:  dd 3.5
width_v:  dd 120.0
dx_v:     dd 0.0
yspan_v:  dd 2.4
height_v: dd 40.0
ymin_v:   dd -1.2
esc_pre:  db 27, "[48;2;"
reset:    db 27, "[0m", 10
row:      times (WIDTH*24 + 32) db 0
nbuf:     times 16 db 0

section .bss
align 32
iters: resd 8

section .text
_start:
    movss xmm0, [xspan_v]
    divss xmm0, [width_v]
    movss [dx_v], xmm0

    vbroadcastss ymm15, [dx_v]
    vbroadcastss ymm14, [xmin_v]
    vmovaps ymm13, [lane_off]
    vmovaps ymm12, [four]
    vmovaps ymm11, [one]

    xor r14d, r14d
.row_loop:
    cvtsi2ss xmm0, r14d
    mulss xmm0, [yspan_v]
    divss xmm0, [height_v]
    addss xmm0, [ymin_v]
    vbroadcastss ymm10, xmm0

    lea r15, [row]
    xor r13d, r13d
.col_loop:
    cvtsi2ss xmm1, r13d
    vbroadcastss ymm0, xmm1
    vaddps ymm0, ymm0, ymm13
    vmulps ymm0, ymm0, ymm15
    vaddps ymm9, ymm0, ymm14           ; cx per lane

    vxorps ymm2, ymm2, ymm2            ; zx
    vxorps ymm3, ymm3, ymm3            ; zy
    vxorps ymm4, ymm4, ymm4            ; iteration counts

    mov ecx, MAXITER
.iter:
    vmulps ymm5, ymm2, ymm2           ; zx^2
    vmulps ymm6, ymm3, ymm3           ; zy^2
    vaddps ymm7, ymm5, ymm6           ; zx^2+zy^2
    vcmpps ymm8, ymm7, ymm12, 1       ; mask: |z|^2 < 4  (0xffffffff where alive)
    vmovmskps eax, ymm8               ; gather sign bits
    test eax, eax
    jz .done_iter                     ; all 8 lanes escaped
    vandps ymm0, ymm8, ymm11          ; 1.0 on alive lanes, 0.0 elsewhere
    vaddps ymm4, ymm4, ymm0           ; bump counts of alive lanes

    vsubps ymm0, ymm5, ymm6           ; zx^2 - zy^2
    vaddps ymm0, ymm0, ymm9           ; + cx
    vmulps ymm1, ymm2, ymm3           ; zx*zy
    vaddps ymm1, ymm1, ymm1           ; 2*zx*zy
    vaddps ymm3, ymm1, ymm10          ; new zy = 2zxzy + cy
    vmovaps ymm2, ymm0                ; new zx
    dec ecx
    jnz .iter
.done_iter:
    vmovaps [iters], ymm4

    xor ebx, ebx
.emit_lane:
    cvttss2si eax, [iters + rbx*4]
    call put_pixel
    inc ebx
    cmp ebx, 8
    jb .emit_lane

    add r13d, 8
    cmp r13d, WIDTH
    jb .col_loop

    mov rsi, reset
    mov ecx, 5
.cr:
    mov dl, [rsi]
    mov [r15], dl
    inc r15
    inc rsi
    dec ecx
    jnz .cr

    mov rax, 1
    mov rdi, 1
    lea rsi, [row]
    mov rdx, r15
    sub rdx, rsi
    syscall

    inc r14d
    cmp r14d, HEIGHT
    jb .row_loop

    mov rax, 60
    xor edi, edi
    syscall

; eax = iteration count -> append ANSI truecolor block to [r15]
put_pixel:
    mov rsi, esc_pre
    mov ecx, 7
.cpre:
    mov dl, [rsi]
    mov [r15], dl
    inc r15
    inc rsi
    dec ecx
    jnz .cpre

    cmp eax, MAXITER
    jl .colored
    xor eax, eax                       ; in-set -> black
    call emit_byte
    mov byte [r15], ';'
    inc r15
    xor eax, eax
    call emit_byte
    mov byte [r15], ';'
    inc r15
    xor eax, eax
    call emit_byte
    jmp .close
.colored:
    mov r10d, eax                      ; it
    ; R = (it*7) & 255
    imul eax, r10d, 7
    and eax, 255
    call emit_byte
    mov byte [r15], ';'
    inc r15
    ; G = (it*3) & 255
    imul eax, r10d, 3
    and eax, 255
    call emit_byte
    mov byte [r15], ';'
    inc r15
    ; B = (it*11 + 40) & 255
    imul eax, r10d, 11
    add eax, 40
    and eax, 255
    call emit_byte
.close:
    mov byte [r15], 'm'
    inc r15
    mov byte [r15], ' '
    inc r15
    ret

; eax = 0..255 -> decimal ASCII at [r15]
emit_byte:
    lea rsi, [nbuf + 12]
    mov ecx, 10
.d:
    xor edx, edx
    div ecx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test eax, eax
    jnz .d
    lea rcx, [nbuf + 12]
.copy:
    mov dl, [rsi]
    mov [r15], dl
    inc r15
    inc rsi
    cmp rsi, rcx
    jb .copy
    ret

section .note.GNU-stack noalloc noexec nowrite progbits
