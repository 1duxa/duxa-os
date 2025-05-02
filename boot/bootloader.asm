[org 0x7C00]
[bits 16]

start:
    cli ; disable interrupts
    xor ax, ax ; clear registers
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00  ; stack pointer
    sti ; enable interrupts back

    ; Load kernel manually 
    mov si, 0x7E00       ;  extra sectors 
    mov di, 0x10000      ;  load address
    mov cx, KERNEL_SIZE  ; 
.copy_kernel:
    cmp cx, 0
    je .done
    mov al, [si]
    mov [di], al
    inc si
    inc di
    dec cx
    jmp .copy_kernel
.done:
    jmp 0x1000:0x0000    

KERNEL_SIZE equ 512 * 4  ; 4 sectors 

times 510 - ($ - $$) db 0
dw 0xAA55              
; Not sure tbh :P