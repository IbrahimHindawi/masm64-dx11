;---------------------------------------------------------------------------------------------------
; print: formatted text to the console and the debugger
;---------------------------------------------------------------------------------------------------
; The `print` macro (macros.asm) lands here. wsprintfA does the formatting; \n in the format is
; turned into a line break first, since nothing else would.
ifndef print_asm
print_asm = 0

include macros.asm

.data
align 16
print_pattern byte 1024 dup(?)
print_buffer byte 1024 dup(?)

.code
; rcx: format, then up to seven arguments for it
align 16
print_format proc format:qword, a1:qword, a2:qword, a3:qword, a4:qword, a5:qword, a6:qword, a7:qword
    local written:dword
    USING rsi, rdi
    SaveRegs

    mov rsi, format
    lea rdi, print_pattern
    copy:
        mov al, [rsi]
        cmp al, '\'
        jne plain
        cmp byte ptr [rsi + 1], 'n'
        jne plain
            mov word ptr [rdi], 0A0Dh   ; \r\n
            add rdi, 2
            add rsi, 2
            jmp copy
        plain:
        mov [rdi], al
        inc rdi
        inc rsi
        test al, al
        jnz copy

    ; The arguments are passed on whether the format uses them or not: wsprintfA only reads what
    ; the format asks for.
    invoke wsprintfA, ADDR print_buffer, ADDR print_pattern, a1, a2, a3, a4, a5, a6, a7
    mov rsi, rax
    invoke GetStdHandle, STD_OUTPUT_HANDLE
    invoke WriteFile, rax, ADDR print_buffer, rsi, ADDR written, 0
    invoke OutputDebugStringA, ADDR print_buffer

    RestoreRegs
    ret
print_format endp

endif
