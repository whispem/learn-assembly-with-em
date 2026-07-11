global _start

section .rodata
s_race: db "without mutex: ", 0
s_lock: db "with mutex:    ", 0
s_exp: db "expected:      ", 0
nl: db 10

%define NTHREADS 4
%define ITERS 100000
%define STACKSZ 65536
%define CLONE_FLAGS 0x00010900     ; VM|FS|FILES|SIGHAND|THREAD|SYSVSEM

section .data
counter: dq 0
mutex: dd 0
use_lock: dd 0
done: dd 0
nbuf: times 32 db 0

section .bss
stacks: resb NTHREADS * STACKSZ

section .text
_start:
    ; --- pass 1: no locking, watch the race ---
    mov dword [use_lock], 0
    call run_all
    mov rdi, s_race
    call pstr
    mov rdi, [counter]
    call puint

    ; --- pass 2: with the futex mutex ---
    mov qword [counter], 0
    mov dword [use_lock], 1
    call run_all
    mov rdi, s_lock
    call pstr
    mov rdi, [counter]
    call puint

    mov rdi, s_exp
    call pstr
    mov rdi, NTHREADS * ITERS
    call puint

    mov rax, 60
    xor edi, edi
    syscall

; spawns NTHREADS workers and waits for all to finish
run_all:
    mov dword [done], 0
    xor r15d, r15d
.spawn:
    mov rax, 56                 ; clone
    mov edi, CLONE_FLAGS
    mov rsi, stacks
    mov rax, r15
    inc rax
    imul rax, STACKSZ
    lea rsi, [stacks + rax - 16]
    mov rax, 56
    mov edi, CLONE_FLAGS
    xor edx, edx
    xor r10, r10
    xor r8, r8
    syscall
    test rax, rax
    jz worker
    inc r15d
    cmp r15d, NTHREADS
    jb .spawn
.wait:
    mov eax, [done]             ; wait until all workers have signalled done
    cmp eax, NTHREADS
    jae .done
    mov rax, 24                 ; sched_yield — let the workers run
    syscall
    jmp .wait
.done:
    ret

; thread entry: never returns, exits via SYS_exit
worker:
    mov r12, ITERS
.loop:
    cmp dword [use_lock], 0
    je .nolock
    call mutex_lock
.nolock:
    mov rax, [counter]           ; read
    inc rax                      ; modify
    mov r11d, 20                  ; widen the window so the race is visible
.delay:
    dec r11d
    jnz .delay
    mov [counter], rax           ; write back (may clobber another thread's update)
    cmp dword [use_lock], 0
    je .after
    call mutex_unlock
.after:
    dec r12
    jnz .loop

    mov eax, 1                  ; atomically signal completion
    lock xadd dword [done], eax
    mov rax, 60
    xor edi, edi
    syscall

; Drepper 3-state futex mutex: 0 = free, 1 = locked, 2 = locked + waiters
mutex_lock:
    xor eax, eax                ; expect free
    mov ecx, 1
    lock cmpxchg [mutex], ecx
    jz .got                     ; was 0 -> we own it, no contention
.contend:
    mov eax, 2                  ; mark as contended and take it if it was free
    xchg eax, [mutex]           ; eax = previous value
    test eax, eax
    jz .got                     ; previous was 0 -> we now own it (as state 2)
.sleep:
    mov rax, 202                ; futex(&mutex, WAIT, 2)
    mov rdi, mutex
    xor esi, esi
    mov edx, 2
    xor r10, r10
    syscall
    mov eax, 2                  ; re-assert contended, retry
    xchg eax, [mutex]
    test eax, eax
    jnz .sleep                  ; still held by someone -> back to sleep
.got:
    ret

mutex_unlock:
    mov eax, -1
    lock xadd dword [mutex], eax ; eax = old state; mutex = old-1
    dec eax                      ; eax = new state (old-1)
    jz .done                    ; new state 0 -> was 1, no waiters
    mov dword [mutex], 0        ; was 2 -> release fully and wake one
    mov rax, 202                ; futex(&mutex, WAKE, 1)
    mov rdi, mutex
    mov esi, 1
    mov edx, 1
    xor r10, r10
    syscall
.done:
    ret

; rdi = value, decimal + newline
puint:
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

cstrlen:
    mov rax, rdi
.c:
    cmp byte [rax], 0
    je .l
    inc rax
    jmp .c
.l:
    sub rax, rdi
    ret

section .note.GNU-stack noalloc noexec nowrite progbits