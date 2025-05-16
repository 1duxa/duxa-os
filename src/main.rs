#![no_std]
#![no_main]

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    loop {}
}

#[no_mangle]
pub extern "C" fn _start() -> ! {
    // Your kernel code here
    unsafe {
        // Write "K" to screen to show we made it
        *((0xB8000) as *mut u16) = 0x0F4B;
    }

    loop {}
}
