; boot.asm — a 512-byte boot sector.
; The BIOS loads this at physical address 0x7C00 and jumps to it, in 16-bit
; real mode. We print a message with BIOS interrupt 0x10, then halt.

BITS 16                     ; 16-bit code: the CPU boots in real mode
ORG 0x7C00                  ; the BIOS loads us here, so addresses are relative to 0x7C00

start:
    cli                     ; disable interrupts while we set things up
    xor ax, ax              ; ax = 0
    mov ds, ax              ; data segment = 0 (so our labels resolve correctly)
    mov es, ax
    mov ss, ax              ; stack segment = 0
    mov sp, 0x7C00          ; put the stack just below our code
    sti                     ; re-enable interrupts

    mov si, msg             ; si points to our message string
    call print_string

.hang:
    hlt                     ; halt the CPU
    jmp .hang               ; if it ever wakes, halt again (infinite safe loop)

; print the null-terminated string at ds:si using BIOS teletype
print_string:
    mov ah, 0x0E            ; BIOS function 0x0E = teletype output (print one char)
.next:
    lodsb                   ; load byte at [si] into al, advance si
    test al, al             ; was it the null terminator (0)?
    jz .done                ; if so, we're finished
    int 0x10                ; BIOS video interrupt: print al to the screen
    jmp .next
.done:
    ret

msg: db "hello from em's bootloader!", 13, 10, 0   ; 13,10 = carriage return + newline

; --- boot sector padding and signature ---
times 510 - ($ - $$) db 0   ; fill with zeros up to byte 510
dw 0xAA55                   ; the magic boot signature in the last 2 bytes
