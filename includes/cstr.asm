;---------------------------------------------------------------------------------------------------
; cstr: zero-terminated strings and raw memory
;---------------------------------------------------------------------------------------------------
; What the C library would otherwise provide: lengths, copies, comparisons, and reading numbers out
; of text (for the command line, and later for .obj files). All Win64 calling convention.
ifndef cstr_asm
cstr_asm = 0

include macros.asm

.code
; rcx: string -> rax: its length
align 16
cstr_length proc
    mov rax, rcx
    scan:
        cmp byte ptr [rax], 0
        je done
        inc rax
        jmp scan
    done:
    sub rax, rcx
    ret
cstr_length endp

; rcx: destination, rdx: source. Copies the terminator too.
align 16
cstr_copy proc
    copy:
        mov al, [rdx]
        mov [rcx], al
        inc rcx
        inc rdx
        test al, al
        jnz copy
    ret
cstr_copy endp

; rcx: destination, rdx: source appended to it
align 16
cstr_append proc
    scan:
        cmp byte ptr [rcx], 0
        je copy
        inc rcx
        jmp scan
    copy:
        mov al, [rdx]
        mov [rcx], al
        inc rcx
        inc rdx
        test al, al
        jnz copy
    ret
cstr_append endp

; rcx: a, rdx: b -> rax: 1 when they are the same
align 16
cstr_equals proc
    compare:
        mov al, [rcx]
        cmp al, [rdx]
        jne different
        inc rcx
        inc rdx
        test al, al
        jnz compare
    mov eax, 1
    ret
    different:
    xor eax, eax
    ret
cstr_equals endp

; rcx: string, rdx: prefix -> rax: 1 when the string starts with it
align 16
cstr_starts_with proc
    compare:
        mov al, [rdx]
        test al, al
        jz yes
        cmp al, [rcx]
        jne no
        inc rcx
        inc rdx
        jmp compare
    yes:
    mov eax, 1
    ret
    no:
    xor eax, eax
    ret
cstr_starts_with endp

; rcx: string, rdx: what to look for -> rax: where it starts, or -1
align 16
cstr_find proc
    mov r8, rcx
    outer:
        xor r9, r9
        inner:
            mov al, [rdx + r9]
            test al, al
            jz found
            cmp al, [r8 + r9]
            jne next
            inc r9
            jmp inner
        next:
        cmp byte ptr [r8], 0
        je missing
        inc r8
        jmp outer
    found:
    mov rax, r8
    sub rax, rcx
    ret
    missing:
    mov rax, -1
    ret
cstr_find endp

; rcx: destination, rdx: source, r8: byte count
align 16
mem_copy proc
    USING rsi, rdi
    SaveRegs
    mov rdi, rcx
    mov rsi, rdx
    mov rcx, r8
    rep movsb
    RestoreRegs
    ret
mem_copy endp

; rcx: destination, rdx: byte count
align 16
mem_zero proc
    USING rdi
    SaveRegs
    mov rdi, rcx
    mov rcx, rdx
    xor eax, eax
    rep stosb
    RestoreRegs
    ret
mem_zero endp

;---------------------------------------------------------------------------------------------------
; numbers from text
;---------------------------------------------------------------------------------------------------
; rcx: text -> rax: the integer at its start (an optional sign, then digits), rdx: just past it
align 16
parse_int proc
    xor eax, eax
    xor r8d, r8d                    ; negative?
    cmp byte ptr [rcx], '-'
    jne digits
        mov r8d, 1
        inc rcx
    digits:
        movzx edx, byte ptr [rcx]
        sub edx, '0'
        cmp edx, 9
        ja done
        imul rax, rax, 10
        add rax, rdx
        inc rcx
        jmp digits
    done:
    test r8d, r8d
    jz positive
        neg rax
    positive:
    mov rdx, rcx
    ret
parse_int endp

; rcx: text -> xmm0: the float at its start, rax: just past it
;
; Digits are gathered into one integer and the decimal point and exponent become a power of ten,
; applied once in double precision: "0.123456" is exactly 123456 / 10^6 before rounding to float.
align 16
parse_float proc
    xor eax, eax                    ; mantissa
    xor r8d, r8d                    ; negative?
    xor r9d, r9d                    ; power of ten
    xor r10d, r10d                  ; seen the point?
    cmp byte ptr [rcx], '-'
    jne sign_done
        mov r8d, 1
        inc rcx
        jmp digits
    sign_done:
    cmp byte ptr [rcx], '+'
    jne digits
        inc rcx
    digits:
        movzx edx, byte ptr [rcx]
        cmp edx, '.'
        jne not_point
            mov r10d, 1
            inc rcx
            jmp digits
        not_point:
        sub edx, '0'
        cmp edx, 9
        ja digits_done
        ; past 18 digits the mantissa would overflow; further digits do not matter for a float
        mov r11, 100000000000000000
        cmp rax, r11
        jae skip_digit
            imul rax, rax, 10
            add rax, rdx
            sub r9d, r10d           ; each digit after the point is one more division by 10
            jmp next_digit
        skip_digit:
            test r10d, r10d
            jnz next_digit
            inc r9d
        next_digit:
        inc rcx
        jmp digits
    digits_done:
    movzx edx, byte ptr [rcx]
    or edx, 20h
    cmp edx, 'e'
    jne exponent_done
        inc rcx
        xor r11d, r11d              ; negative exponent?
        cmp byte ptr [rcx], '-'
        jne exponent_plus
            mov r11d, 1
            inc rcx
            jmp exponent_digits_start
        exponent_plus:
        cmp byte ptr [rcx], '+'
        jne exponent_digits_start
            inc rcx
        exponent_digits_start:
        xor r10d, r10d
        exponent_digits:
            movzx edx, byte ptr [rcx]
            sub edx, '0'
            cmp edx, 9
            ja exponent_digits_done
            imul r10d, r10d, 10
            add r10d, edx
            inc rcx
            jmp exponent_digits
        exponent_digits_done:
        test r11d, r11d
        jz exponent_add
            neg r10d
        exponent_add:
        add r9d, r10d
    exponent_done:

    cvtsi2sd xmm0, rax
    mov rax, 3FF0000000000000h      ; 1.0
    movq xmm1, rax
    mov rax, 4024000000000000h      ; 10.0
    movq xmm2, rax
    mov edx, r9d
    test edx, edx
    jns power_loop
        neg edx
    power_loop:
        test edx, edx
        jz power_done
        mulsd xmm1, xmm2
        dec edx
        jmp power_loop
    power_done:
    test r9d, r9d
    js divide
        mulsd xmm0, xmm1
        jmp scaled
    divide:
        divsd xmm0, xmm1
    scaled:
    cvtsd2ss xmm0, xmm0
    test r8d, r8d
    jz positive
        mov edx, 80000000h
        movd xmm1, edx
        xorps xmm0, xmm1
    positive:
    mov rax, rcx
    ret
parse_float endp

endif
