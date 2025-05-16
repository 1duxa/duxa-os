@echo off
setlocal EnableDelayedExpansion
REM === Build script for DuxaOS ===

REM Ensure build directory exists
if not exist build mkdir build

echo [1/6] Building kernel...
cargo +nightly build --release --target=duxa32.json

echo [2/6] Converting kernel to binary format...
cargo +nightly objcopy --release -- -O binary build\kernel.bin

echo Verifying kernel binary...
if not exist build\kernel.bin (
    echo ERROR: Kernel binary not found!
    exit /b 1
)
for %%I in (build\kernel.bin) do set KERNEL_SIZE=%%~zI
if !KERNEL_SIZE! LSS 64 (
    echo ERROR: Kernel binary seems too small
    exit /b 1
)

echo [3/6] Padding kernel...
REM Get kernel size and calculate sectors needed
for %%I in (build\kernel.bin) do set KERNEL_SIZE=%%~zI
set /a "KERNEL_SECTORS=(%KERNEL_SIZE% + 511) / 512"
echo Kernel requires !KERNEL_SECTORS! sectors

REM Now pad the kernel
set /a "PADDED_SIZE=!KERNEL_SECTORS! * 512"
set /a "PADDING_SIZE=!PADDED_SIZE! - !KERNEL_SIZE!"

if %PADDING_SIZE% GTR 0 (
    echo Padding kernel with %PADDING_SIZE% bytes
    powershell -Command "[IO.File]::WriteAllBytes('build\kernel-pad.bin', (0..(%PADDING_SIZE%-1) | ForEach-Object { 0 }))"
    copy /b build\kernel.bin + build\kernel-pad.bin build\kernel-padded.bin >nul
) else (
    echo Kernel is already a multiple of 512 bytes, no padding needed.
    copy /b build\kernel.bin build\kernel-padded.bin >nul
)

echo [4/6] Assembling bootloader...
"C:\Users\User\AppData\Local\bin\NASM\nasm.exe" -f bin boot\stage1.asm -o build\stage1.bin
"C:\Users\User\AppData\Local\bin\NASM\nasm.exe" -f bin boot\stage2.asm -o build\stage2.bin

echo [5/6] Padding stage2...
for %%I in ("build\stage2.bin") do set "STAGE2_SIZE=%%~zI"
set /a "STAGE2_PADDED_SIZE=(STAGE2_SIZE + 511) / 512 * 512"
set /a "STAGE2_PADDING_SIZE=STAGE2_PADDED_SIZE - STAGE2_SIZE"

if %STAGE2_PADDING_SIZE% GTR 0 (
    echo Padding stage2 with %STAGE2_PADDING_SIZE% bytes
    powershell -Command "[IO.File]::WriteAllBytes('build\stage2-pad.bin', (0..(%STAGE2_PADDING_SIZE%-1) | ForEach-Object { 0 }))"
    copy /b build\stage2.bin + build\stage2-pad.bin build\stage2-padded.bin >nul
) else (
    copy /b build\stage2.bin build\stage2-padded.bin >nul
)

REM Calculate correct offsets and sectors
set /a "STAGE1_SIZE=512"
set /a "BOOTLOADER_SIZE=STAGE1_SIZE + STAGE2_PADDED_SIZE"
set /a "KERNEL_OFFSET=BOOTLOADER_SIZE"
set /a "KERNEL_START_SECTOR=KERNEL_OFFSET / 512 + 1"

echo Creating final disk image...
copy /b build\stage1.bin + build\stage2-padded.bin + build\kernel-padded.bin build\os-image.bin >nul

REM Verify kernel position in image
echo Verifying kernel position...
powershell -Command "$bytes = [System.IO.File]::ReadAllBytes('build\os-image.bin'); if ($bytes[%KERNEL_OFFSET%] -eq 0) { Write-Host 'WARNING: Kernel start contains zeros'; exit 1 } else { Write-Host ('Kernel header at 0x{0:X4}: 0x{1:X2} 0x{2:X2} 0x{3:X2} 0x{4:X2}' -f %KERNEL_OFFSET%, $bytes[%KERNEL_OFFSET%], $bytes[%KERNEL_OFFSET%+1], $bytes[%KERNEL_OFFSET%+2], $bytes[%KERNEL_OFFSET%+3]) }"

REM Update stage2.asm with correct values
powershell -Command "(Get-Content boot\stage2.asm) | ForEach-Object { $_ -replace 'KERNEL_SECTORS equ \d+', 'KERNEL_SECTORS equ %KERNEL_SECTORS%' -replace 'KERNEL_START_SECTOR equ \d+', 'KERNEL_START_SECTOR equ %KERNEL_START_SECTOR%' } | Set-Content boot\stage2.asm.tmp"
move /y boot\stage2.asm.tmp boot\stage2.asm >nul

echo.
echo Final image details:
echo Stage1 size: %STAGE1_SIZE% bytes
echo Stage2 size: %STAGE2_PADDED_SIZE% bytes
echo Kernel size: %KERNEL_SIZE% bytes
echo Kernel offset: 0x%KERNEL_OFFSET% ^(sector %KERNEL_START_SECTOR%^)
echo Total image size:
for %%I in (build\os-image.bin) do echo %%~zI bytes

echo [6/6] Booting OS in QEMU...
"C:\Program Files\qemu\qemu-system-x86_64.exe" -drive format=raw,file=build\os-image.bin,index=0,media=disk -boot c -m 64M -no-shutdown -no-reboot 
pause