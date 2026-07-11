global _start

%define COLS 10
%define ROWS 20
%define CELL_W 2

section .rodata
; each tetromino: 4 rotations x 4 (row,col) cells, packed as bytes
; order: I O T S Z J L
pieces:
    ; I
    db 1,0, 1,1, 1,2, 1,3,   0,2, 1,2, 2,2, 3,2,   2,0, 2,1, 2,2, 2,3,   0,1, 1,1, 2,1, 3,1
    ; O
    db 0,1, 0,2, 1,1, 1,2,   0,1, 0,2, 1,1, 1,2,   0,1, 0,2, 1,1, 1,2,   0,1, 0,2, 1,1, 1,2
    ; T
    db 0,1, 1,0, 1,1, 1,2,   0,1, 1,1, 1,2, 2,1,   1,0, 1,1, 1,2, 2,1,   0,1, 1,0, 1,1, 2,1
    ; S
    db 0,1, 0,2, 1,0, 1,1,   0,1, 1,1, 1,2, 2,2,   1,1, 1,2, 2,0, 2,1,   0,0, 1,0, 1,1, 2,1
    ; Z
    db 0,0, 0,1, 1,1, 1,2,   0,2, 1,1, 1,2, 2,1,   1,0, 1,1, 2,1, 2,2,   0,1, 1,0, 1,1, 2,0
    ; J
    db 0,0, 1,0, 1,1, 1,2,   0,1, 0,2, 1,1, 2,1,   1,0, 1,1, 1,2, 2,2,   0,1, 1,1, 2,0, 2,1
    ; L
    db 0,2, 1,0, 1,1, 1,2,   0,1, 1,1, 2,1, 2,2,   1,0, 1,1, 1,2, 2,0,   0,0, 0,1, 1,1, 2,1

; ANSI background colors per piece (teal / cyan family), as full escape strings
col_I: db 27,"[48;2;0;180;180m",0
col_O: db 27,"[48;2;0;150;170m",0
col_T: db 27,"[48;2;32;178;170m",0     ; light sea green / teal
col_S: db 27,"[48;2;0;206;209m",0      ; dark turquoise
col_Z: db 27,"[48;2;72;209;204m",0     ; medium turquoise
col_J: db 27,"[48;2;0;128;128m",0      ; teal
col_L: db 27,"[48;2;64;224;208m",0     ; turquoise
col_tbl: dq col_I, col_O, col_T, col_S, col_Z, col_J, col_L

reset:   db 27,"[0m",0
clear:   db 27,"[2J",27,"[H",0
home:    db 27,"[H",0
hidecur: db 27,"[?25l",0
showcur: db 27,"[?25h",0
wall:    db 27,"[48;2;40;40;40m  ",27,"[0m",0
empty:   db 27,"[48;2;16;16;24m  ",27,"[0m",0
msg_over: db 10,"  game over",10,0
msg_score: db "  lines: ",0

section .data
orig_termios: times 60 db 0
raw_termios:  times 60 db 0
rng:      dq 88172645463325252
cur_piece: dd 0
cur_rot:   dd 0
cur_row:   dd 0
cur_col:   dd 0
lines:     dd 0
tick:      dd 0
nbuf:      times 16 db 0
; playfield: 0 = empty, 1..7 = filled with piece color+1
field: times (COLS*ROWS) db 0
scrbuf: times 8192 db 0

section .bss
readc: resb 8

section .text
_start:
    ; --- save termios, switch to raw ---
    mov rax, 16
    mov rdi, 0
    mov rsi, 0x5401             ; TCGETS
    mov rdx, orig_termios
    syscall
    ; copy to raw
    mov rsi, orig_termios
    mov rdi, raw_termios
    mov rcx, 60
.cp:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .cp
    ; c_lflag &= ~(ICANON|ECHO)  -> c_lflag at offset 12
    mov eax, [raw_termios + 12]
    and eax, ~(0x2 | 0x8)
    mov [raw_termios + 12], eax
    ; VMIN=0, VTIME=0 -> non-blocking read; c_cc at offset 17, VMIN=17+6, VTIME=17+5
    mov byte [raw_termios + 23], 0    ; VMIN
    mov byte [raw_termios + 22], 0    ; VTIME
    mov rax, 16
    mov rdi, 0
    mov rsi, 0x5402             ; TCSETS
    mov rdx, raw_termios
    syscall

    ; hide cursor, clear
    mov rsi, hidecur
    call puts_raw
    mov rsi, clear
    call puts_raw

    call spawn_piece

.game_loop:
    call draw

    ; ~500ms gravity: 50 polls of 10ms
    mov dword [tick], 0
.frame:
    ; read a key (non-blocking)
    xor eax, eax
    xor edi, edi
    mov rsi, readc
    mov edx, 1
    syscall
    test rax, rax
    jle .no_key
    mov al, [readc]
    cmp al, 'q'
    je .quit
    cmp al, 'a'
    je .left
    cmp al, 'd'
    je .right
    cmp al, 'w'
    je .rotate
    cmp al, 's'
    je .softdrop
    cmp al, ' '
    je .softdrop
    jmp .no_key
.left:
    mov edi, -1
    call try_move_h
    jmp .redraw
.right:
    mov edi, 1
    call try_move_h
    jmp .redraw
.rotate:
    call try_rotate
    jmp .redraw
.softdrop:
    call step_down
    jmp .redraw
.redraw:
    call draw
.no_key:
    ; sleep 10ms
    call sleep10
    inc dword [tick]
    cmp dword [tick], 50
    jb .frame

    ; gravity tick
    call step_down
    jmp .game_loop

.quit:
    call restore
    mov rax, 60
    xor edi, edi
    syscall

; drop one row; on landing, lock + clear + respawn; if spawn blocked -> game over
step_down:
    mov eax, [cur_row]
    inc eax
    mov edi, eax
    mov esi, [cur_col]
    mov edx, [cur_rot]
    call collides
    test eax, eax
    jz .ok
    ; locked
    call lock_piece
    call clear_lines
    call spawn_piece
    test eax, eax
    jnz .over
    ret
.ok:
    inc dword [cur_row]
    ret
.over:
    call draw
    mov rsi, msg_over
    call puts_raw
    call restore
    mov rax, 60
    xor edi, edi
    syscall

; edi = direction (-1 left, +1 right)
try_move_h:
    mov esi, [cur_col]
    add esi, edi                ; candidate column
    push rsi                    ; preserve across collides
    mov edi, [cur_row]
    mov edx, [cur_rot]
    call collides
    pop rsi
    test eax, eax
    jnz .blocked
    mov [cur_col], esi          ; commit the candidate column
.blocked:
    ret

; horizontal move done cleanly
; edi (dir) preserved via stack
try_rotate:
    mov eax, [cur_rot]
    inc eax
    and eax, 3
    mov edx, eax
    mov edi, [cur_row]
    mov esi, [cur_col]
    call collides
    test eax, eax
    jnz .no
    mov eax, [cur_rot]
    inc eax
    and eax, 3
    mov [cur_rot], eax
.no:
    ret

; edi=row, esi=col, edx=rot -> eax=1 if collision/out of bounds
collides:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi               ; base row
    mov r13d, esi               ; base col
    ; cell table pointer: pieces + piece*128 + rot*8
    mov eax, [cur_piece]
    imul eax, 32
    mov r14d, edx
    imul r14d, 8
    add eax, r14d
    lea r15, [pieces]
    add r15, rax
    xor ebx, ebx
.cell:
    movzx edi, byte [r15 + rbx*2]      ; dr
    movzx esi, byte [r15 + rbx*2 + 1]  ; dc
    add edi, r12d                      ; row
    add esi, r13d                      ; col
    ; bounds
    cmp esi, 0
    jl .hit
    cmp esi, COLS
    jge .hit
    cmp edi, ROWS
    jge .hit
    cmp edi, 0
    jl .next                    ; above top is allowed
    ; field occupied?
    mov eax, edi
    imul eax, COLS
    add eax, esi
    cmp byte [field + rax], 0
    jne .hit
.next:
    inc ebx
    cmp ebx, 4
    jb .cell
    xor eax, eax
    jmp .out
.hit:
    mov eax, 1
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; write current piece cells into field with color id
lock_piece:
    push rbx
    push r15
    mov eax, [cur_piece]
    imul eax, 32
    mov edx, [cur_rot]
    imul edx, 8
    add eax, edx
    lea r15, [pieces]
    add r15, rax
    mov ecx, [cur_piece]
    inc ecx                     ; color id 1..7
    xor ebx, ebx
.cell:
    movzx edi, byte [r15 + rbx*2]
    movzx esi, byte [r15 + rbx*2 + 1]
    add edi, [cur_row]
    add esi, [cur_col]
    cmp edi, 0
    jl .next
    mov eax, edi
    imul eax, COLS
    add eax, esi
    mov [field + rax], cl
.next:
    inc ebx
    cmp ebx, 4
    jb .cell
    pop r15
    pop rbx
    ret

; remove full rows, shift down, bump line counter
clear_lines:
    push rbx
    push r12
    mov r12d, ROWS - 1          ; scan from bottom
.scan:
    cmp r12d, 0
    jl .done
    ; is row r12 full?
    mov ebx, 0
.check:
    mov eax, r12d
    imul eax, COLS
    add eax, ebx
    cmp byte [field + rax], 0
    je .notfull
    inc ebx
    cmp ebx, COLS
    jb .check
    ; full -> shift everything above down by one
    mov edi, r12d
.shift:
    cmp edi, 0
    jle .cleartop
    mov eax, edi
    imul eax, COLS
    mov esi, edi
    dec esi
    imul esi, COLS
    mov ecx, COLS
.crow:
    mov dl, [field + rsi]
    mov [field + rax], dl
    inc rax
    inc rsi
    dec ecx
    jnz .crow
    dec edi
    jmp .shift
.cleartop:
    mov ecx, COLS
    xor eax, eax
.ct:
    mov byte [field + rax], 0
    inc rax
    dec ecx
    jnz .ct
    inc dword [lines]
    jmp .scan                   ; re-check same row index after shift
.notfull:
    dec r12d
    jmp .scan
.done:
    pop r12
    pop rbx
    ret

; pick a new piece at top center; eax=1 if it immediately collides (game over)
spawn_piece:
    call rand7
    mov [cur_piece], eax
    mov dword [cur_rot], 0
    mov dword [cur_row], 0
    mov dword [cur_col], 3
    mov edi, 0
    mov esi, 3
    mov edx, 0
    call collides
    ret

; xorshift -> eax in 0..6
rand7:
    mov rax, [rng]
    mov rdx, rax
    shl rax, 13
    xor rax, rdx
    mov rdx, rax
    shr rax, 7
    xor rax, rdx
    mov rdx, rax
    shl rax, 17
    xor rax, rdx
    mov [rng], rax
    xor edx, edx
    mov ecx, 7
    div ecx
    mov eax, edx
    ret

; render field + current piece into scrbuf, then one write
draw:
    push rbx
    push r12
    push r13
    ; stamp current piece into a scratch copy? simpler: draw field, overlay piece live
    lea r13, [scrbuf]
    ; home cursor
    mov rsi, home
    call append
    ; top wall
    call append_wall_row
    xor r12d, r12d              ; row
.row:
    ; left wall
    mov rsi, wall
    call append
    xor ebx, ebx               ; col
.col:
    ; is current piece occupying (r12,ebx)?
    mov edi, r12d
    mov esi, ebx
    call piece_has
    test eax, eax
    jnz .piece_cell
    ; else field
    mov eax, r12d
    imul eax, COLS
    add eax, ebx
    movzx ecx, byte [field + rax]
    test ecx, ecx
    jz .empty_cell
    ; filled block: color by id
    dec ecx
    mov rsi, [col_tbl + rcx*8]
    call append
    mov rsi, blockchars
    call append
    mov rsi, reset
    call append
    jmp .cell_done
.piece_cell:
    mov ecx, [cur_piece]
    mov rsi, [col_tbl + rcx*8]
    call append
    mov rsi, blockchars
    call append
    mov rsi, reset
    call append
    jmp .cell_done
.empty_cell:
    mov rsi, empty
    call append
.cell_done:
    inc ebx
    cmp ebx, COLS
    jb .col
    ; right wall + newline
    mov rsi, wall
    call append
    mov byte [r13], 10
    inc r13
    inc r12d
    cmp r12d, ROWS
    jb .row
    ; bottom wall
    call append_wall_row
    ; score line
    mov rsi, msg_score
    call append
    mov eax, [lines]
    call append_num
    mov byte [r13], 10
    inc r13

    ; flush
    mov rax, 1
    mov rdi, 1
    lea rsi, [scrbuf]
    mov rdx, r13
    sub rdx, rsi
    syscall
    pop r13
    pop r12
    pop rbx
    ret

; does current piece cover (edi=row, esi=col)?  eax=1 yes
piece_has:
    push rbx
    push r14
    push r15
    mov r14d, edi
    mov r15d, esi
    mov eax, [cur_piece]
    imul eax, 32
    mov edx, [cur_rot]
    imul edx, 8
    add eax, edx
    lea rbx, [pieces]
    add rbx, rax
    xor ecx, ecx
.c:
    movzx eax, byte [rbx + rcx*2]
    add eax, [cur_row]
    cmp eax, r14d
    jne .n
    movzx eax, byte [rbx + rcx*2 + 1]
    add eax, [cur_col]
    cmp eax, r15d
    jne .n
    mov eax, 1
    jmp .o
.n:
    inc ecx
    cmp ecx, 4
    jb .c
    xor eax, eax
.o:
    pop r15
    pop r14
    pop rbx
    ret

append_wall_row:
    mov ecx, COLS + 2
.w:
    push rcx
    mov rsi, wall
    call append
    pop rcx
    dec ecx
    jnz .w
    mov byte [r13], 10
    inc r13
    ret

; append cstring at rsi into r13
append:
    push rax
.a:
    mov al, [rsi]
    test al, al
    jz .d
    mov [r13], al
    inc r13
    inc rsi
    jmp .a
.d:
    pop rax
    ret

; append eax as decimal into r13
append_num:
    push rbx
    lea rbx, [nbuf + 12]
    mov ecx, 10
.d:
    xor edx, edx
    div ecx
    add dl, '0'
    dec rbx
    mov [rbx], dl
    test eax, eax
    jnz .d
    lea rcx, [nbuf + 12]
.c:
    mov dl, [rbx]
    mov [r13], dl
    inc r13
    inc rbx
    cmp rbx, rcx
    jb .c
    pop rbx
    ret

puts_raw:
    push rsi
    mov rdi, rsi
    call slen
    pop rsi
    mov rdx, rax
    mov rax, 1
    mov rdi, 1
    syscall
    ret

slen:
    xor rax, rax
.s:
    cmp byte [rdi + rax], 0
    je .d
    inc rax
    jmp .s
.d:
    ret

sleep10:
    lea rsi, [ts10]
    mov rdi, rsi
    xor esi, esi
    mov rax, 35                 ; nanosleep
    lea rdi, [ts10]
    xor esi, esi
    syscall
    ret

restore:
    mov rsi, showcur
    call puts_raw
    mov rsi, reset
    call puts_raw
    mov rax, 16
    mov rdi, 0
    mov rsi, 0x5402
    mov rdx, orig_termios
    syscall
    ret

section .data
blockchars: db "  ",0            ; two spaces = a square cell (colored via bg)
ts10: dq 0, 10000000             ; 10 ms

section .note.GNU-stack noalloc noexec nowrite progbits
