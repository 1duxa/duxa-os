[org 0x10000]
[bits 16]

; Constants
KERNEL_SECTORS equ 16 
KERNEL_START_SECTOR equ 6
KERNEL_DRIVE equ 0x80
KERNEL_LOAD_SEG equ 0x2000  ; Load kernel at 0x20000

stage2_start:
    mov ax, 0x1000              
    mov ds, ax
    mov es, ax
    mov ax, 0x9000         
    mov ss, ax
    mov sp, 0xFFFF
    sti                    
    mov si, MSG_STAGE2_LOADED
    call print_string
    call load_kernel
    jc kernel_load_error
    mov si, MSG_KERNEL_LOADED
    call print_string
    
    ; Debug: Print where the kernel was loaded
    mov si, MSG_DEBUG_KERNEL_ADDR
    call print_string
    mov ax, 0x2000       ; ES value used during load_kernel
    call print_hex_word
    mov si, MSG_COLON
    call print_string
    mov ax, 0x0000       ; BX value used during load_kernel
    call print_hex_word
    mov si, MSG_NEWLINE
    call print_string
    
    ; Debug: Print first bytes of kernel to verify it loaded
    mov si, MSG_DEBUG_KERNEL_BYTES
    call print_string
    mov ax, 0x2000
    mov es, ax
    xor bx, bx
    mov cx, 16          ; Print first 16 bytes (increased from 4)
.print_kernel_bytes:
    mov al, [es:bx]
    call print_hex_byte
    mov al, ' '
    mov ah, 0x0E
    int 0x10
    inc bx
    loop .print_kernel_bytes
    mov si, MSG_NEWLINE
    call print_string
    
    ; Continue with normal flow
    call enable_a20
    cli
    lgdt [gdt32_pointer]
    
    mov eax, cr0
    or al, 1
    mov cr0, eax
    
    ; Jump to 32-bit code
    jmp 0x08:protected_mode_kernel

align 8
gdt32:
    dq 0                         ; Null descriptor
    dq 0x00CF9A000000FFFF       ; 32-bit code descriptor
    dq 0x00CF92000000FFFF       ; 32-bit data descriptor
gdt32_pointer:
    dw $ - gdt32 - 1            ; Size
    dd gdt32                    ; Address

[bits 32]
protected_mode_kernel:
    ; Set up segments
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    
    ; Set up stack
    mov esp, 0x90000
    
    ; Clear screen
    mov edi, 0xB8000
    mov ecx, 2000
    mov ax, 0x0F20
    rep stosw
    
    ; Jump to kernel at 0x20000
    jmp 0x20000

kernel_load_error:
    mov si, MSG_KERNEL_ERROR
    call print_string
    ; Debug: Display the error code from INT 13h
    mov si, MSG_DEBUG_DISK_ERROR
    call print_string
    mov al, ah          ; Error code is in AH after INT 13h
    call print_hex_byte
    mov si, MSG_NEWLINE
    call print_string
    jmp $

no_long_mode:
    mov si, MSG_NO_LONG_MODE
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

; Hex printing functions
print_hex_word:
    pusha
    mov bx, ax         ; Save the value
    mov al, bh
    call print_hex_byte
    mov al, bl
    call print_hex_byte
    popa
    ret

print_hex_byte:
    pusha
    mov cl, al
    shr al, 4
    call print_hex_digit
    mov al, cl
    and al, 0x0F
    call print_hex_digit
    popa
    ret

print_hex_digit:
    cmp al, 10
    jae .letter
    add al, '0'
    jmp .print
.letter:
    add al, 'A' - 10
.print:
    mov ah, 0x0E
    int 0x10
    ret

load_kernel:
    pusha
    mov si, MSG_LOADING_KERNEL
    call print_string
    
    ; Reset disk system
    xor ax, ax
    mov dl, KERNEL_DRIVE
    int 0x13
    jc .error
    
    ; Load kernel
    mov ah, 0x02           ; Read sectors
    mov al, KERNEL_SECTORS ; Number of sectors (should match actual kernel size)
    mov ch, 0              ; Cylinder 0
    mov cl, KERNEL_START_SECTOR ; Start from correct sector
    mov dh, 0              ; Head 0
    mov dl, KERNEL_DRIVE   ; Drive number

    ; Calculate correct load address
    mov bx, KERNEL_LOAD_SEG
    mov es, bx
    xor bx, bx            ; ES:BX = 0x20000
    
    ; Debug - show load parameters
    push ax
    mov si, MSG_DEBUG_DISK_PARAMS
    call print_string
    mov ax, cx            ; Print sector number
    call print_hex_word
    mov si, MSG_SECTORS_COUNT
    call print_string
    pop ax
    push ax
    call print_hex_byte   ; Print sectors to read
    mov si, MSG_DRIVE
    call print_string
    mov al, dl            ; Print drive number
    call print_hex_byte
    mov si, MSG_NEWLINE
    call print_string
    pop ax
    
    int 0x13
    jc .error
    
    ; Verify sectors read
    cmp al, KERNEL_SECTORS
    jne .sectors_error
    
    ; Success
    clc
    popa
    ret
    
.sectors_error:
    mov si, MSG_DEBUG_SECTOR_COUNT_ERROR
    call print_string
    mov ah, 0              ; Clear AH to avoid confusion
    call print_hex_byte    ; Print actual sectors read (in AL)
    mov si, MSG_NEWLINE
    call print_string
    stc                    ; Set carry flag to indicate error
    popa
    ret
    
.error:
    ; Save error code (in AH after INT 13h)
    push ax
    
    ; Display detailed error info
    mov si, MSG_DEBUG_DISK_OP
    call print_string
    pop ax
    push ax
    mov al, ah          ; Error code is in AH
    call print_hex_byte
    mov si, MSG_NEWLINE
    call print_string
    
    pop ax
    stc                 ; Set carry flag to indicate error
    popa
    ret

enable_a20:
    pusha
    mov si, MSG_ENABLE_A20
    call print_string
    mov ax, 0x2401
    int 0x15
    jnc .done
    cli
    call .wait_input
    mov al, 0xAD 
    out 0x64, al
    call .wait_input
    mov al, 0xD0 
    out 0x64, al
    call .wait_output
    in al, 0x60 
    push ax
    call .wait_input
    mov al, 0xD1 
    out 0x64, al
    call .wait_input
    pop ax
    or al, 2     
    out 0x60, al
    call .wait_input
    mov al, 0xAE  
    out 0x64, al
    call .wait_input
    sti
.done:
    popa
    ret
.wait_input:
    in al, 0x64
    test al, 2
    jnz .wait_input
    ret
.wait_output:
    in al, 0x64
    test al, 1
    jz .wait_output
    ret
    
check_long_mode:
    pushfd
    pop eax
    mov ecx, eax
    xor eax, 1 << 21  
    push eax
    popfd
    pushfd
    pop eax
    push ecx
    popfd
    xor eax, ecx
    jz .no_cpuid
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb .no_long_mode
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29
    jz .no_long_mode
    clc
    ret
.no_cpuid:
.no_long_mode:
    stc
    ret
    
enter_long_mode:
    hlt
    mov si, MSG_ENTER_LONG_MODE
    call print_string
    mov edi, 0x70000
    xor eax, eax
    mov ecx, 4096
    rep stosd
;valid
    mov dword [0x70000], 0
    mov dword [0x70000+4], 0
    mov dword [0x71000], 0x72003
    mov dword [0x71000+4], 0
;valid
    mov ecx, 512
    mov edi, 0x72000
    mov eax, 0x83 ; present|write|PS
    mov edx, 0
;valid
.map_pd:
    mov dword [edi], eax
    mov dword [edi+4], edx
    add eax, 0x200000
    add edi, 8
; infinite print here
    loop .map_pd
    mov eax, 0x70000
    mov cr3, eax
    mov eax, cr4
    or eax, 1 << 5        
    mov cr4, eax
    mov ecx, 0xC0000080    
    rdmsr
    or eax, 1 << 8         
    wrmsr
    lgdt [gdt64_pointer]
    mov eax, cr0
    or eax, 1 << 31        
    mov cr0, eax
    jmp 0x08:long_mode_entry

[bits 64]
long_mode_entry:
    cli
    mov si, MSG_ENTER_LONG_MODE_ENTRY
    call print_string
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov rdi, 0xB8000
    mov rcx, 2000
    mov rax, 0x0F200F20  ; White space on black
    rep stosw
    mov rdi, 0xB8000
    mov rax, 0x0F4C0F4F0F4E0F47 ; "LONG" in white
    mov [rdi], rax
    mov rax, 0x0F4D0F4F0F440F45 ; " MODE" in white
    mov [rdi+8], rax
    mov rax, 0x0F4B0F4F0F200F20 ; " OK" in white
    mov [rdi+16], rax
    mov rcx, 0x500000
.delay1:
    loop .delay1
    mov rdi, 0xB8000 + 160  ; Next line (80*2 bytes per line)
    mov rax, 0x0F4A0F550F4D0F50 ; "JUMP" in white
    mov [rdi], rax
    mov rax, 0x0F4E0F470F200F54 ; "ING " in white
    mov [rdi+8], rax
    mov rax, 0x0F4F0F200F4B0F54 ; "TO K" in white
    mov [rdi+16], rax
    mov rax, 0x0F520F4E0F450F45 ; "ERNE" in white
    mov [rdi+24], rax
    mov rax, 0x0F000F4C0F000F20 ; "L" in white
    mov [rdi+32], rax
    mov rcx, 0x500000
.delay2:
    loop .delay2
    mov rdi, 0xB8000 + 320  ; Third line
    mov rax, 0x0F410F440F440F52 ; "ADDR" in white
    mov [rdi], rax
    mov rax, 0x0F530F530F3A0F45 ; "ESS:" in white
    mov [rdi+8], rax
    mov rax, 0x0F300F300F300F32 ; "0x20" in white
    mov [rdi+16], rax
    mov rax, 0x0F300F300F300F30 ; "000" in white
    mov [rdi+24], rax
    mov rcx, 0x500000
.delay3:
    loop .delay3
    ; Ensure we jump to the correct address
    mov rax, 0x20000       ; Kernel load address
    ; Debug - output the first bytes of kernel to screen
    mov rdi, 0xB8000 + 480  ; Fourth line
    mov rbx, [rax]         ; Load first 8 bytes of kernel
    mov [rdi], rbx         ; Display on screen (just for debugging)
.clear_stack:
    mov rsp, 0x90000
    and rsp, -16
    cld
    jmp rax
align 8
gdt64:
    dq 0
    dq 0x00AF9A000000FFFF    ; 64-bit code segment                    
    dq 0x00AF92000000FFFF    ; 64-bit data segment
gdt64_pointer:
    dw $ - gdt64 - 1                             
    dq gdt64                                     

; Messages
MSG_STAGE2_LOADED          db 'Stage 2 loaded successfully!', 0x0D, 0x0A, 0
MSG_LOADING_KERNEL         db 'Loading kernel from disk...', 0x0D, 0x0A, 0
MSG_KERNEL_LOADED          db 'Kernel loaded successfully!', 0x0D, 0x0A, 0
MSG_KERNEL_ERROR           db 'ERROR: Failed to load kernel!', 0x0D, 0x0A, 0
MSG_ENABLE_A20             db 'Enabling A20 line...', 0x0D, 0x0A, 0
MSG_DEBUG_KERNEL_ADDR      db 'Kernel loaded at: ', 0
MSG_DEBUG_KERNEL_BYTES     db 'First bytes: ', 0
MSG_DEBUG_DISK_ERROR       db 'Disk error code: ', 0
MSG_DEBUG_DISK_OP          db 'Disk operation failed, code: ', 0
MSG_DEBUG_DISK_PARAMS      db 'Loading from sector: ', 0
MSG_SECTORS_COUNT          db ', sectors: ', 0
MSG_DRIVE                  db ', drive: ', 0
MSG_DEBUG_SECTOR_COUNT_ERROR db 'Sectors read mismatch. Actually read: ', 0
MSG_COLON                  db ':', 0
MSG_NEWLINE                db 0x0D, 0x0A, 0
MSG_DEBUG_LOAD_FROM db 'Loading kernel from sector: ', 0
times 2048 - ($ - $$) db 0
