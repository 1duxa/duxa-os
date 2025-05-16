[org 0x7C00]
[bits 16]
%define STAGE2_SECTORS 4   
%define STAGE2_ADDRESS 0x1000
start:
    cli                    
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00         
    sti                    
    mov si, msg_booting
    call print_string
    mov si, msg_loading_stage2
    call print_string
    mov ah, 0x02           
    mov al, STAGE2_SECTORS 
    mov ch, 0              
    mov cl, 2              
    mov dh, 0              
    mov dl, 0x80           
    mov bx, STAGE2_ADDRESS 
    mov es, bx
    xor bx, bx             
    int 0x13
    jc disk_error          
    cmp al, STAGE2_SECTORS
    jne sector_count_error
    mov si, msg_jumping_stage2
    call print_string
    mov ax, STAGE2_ADDRESS
    mov ds, ax
    mov es, ax
    jmp STAGE2_ADDRESS:0x0000
disk_error:
    mov si, msg_disk_error
    call print_string
    jmp $
sector_count_error:
    mov si, msg_sector_count_error
    call print_string
    jmp $
print_string:
    pusha
    mov ah, 0x0E 
.loop:
    lodsb      
    test al, al
    jz .done
    int 0x10 
    jmp .loop
.done:
    popa
    ret
msg_booting db 'Booting DuxaOS...', 0x0D, 0x0A, 0
msg_loading_stage2 db 'Loading stage2...', 0x0D, 0x0A, 0
msg_jumping_stage2 db 'Jumping to stage2...', 0x0D, 0x0A, 0
msg_disk_error db 'Disk read error!', 0x0D, 0x0A, 0
msg_sector_count_error db 'Sector count mismatch!', 0x0D, 0x0A, 0
times 510 - ($-$$) db 0    
dw 0xAA55                  