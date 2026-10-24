;---------------------------------------------------------------------------------------------------
; saha: arena allocator
;---------------------------------------------------------------------------------------------------
; vulkasm's arena, with the bugs listed in its docs/bugz.md fixed:
;
;   * `used` grows by exactly what each push asks for, plus its alignment padding. The pages to
;     commit are worked out separately, so growing no longer inflates `used`
;   * alignment is applied to `cursor`, and `cursor == base + used` always holds
;   * nothing here touches rsi or rdi without saving them, and state lives in the arena, not in
;     globals, so arenas can nest
;   * arenaPushZero zeroes nothing for a zero-sized push
;   * arenaPushArray / arenaPushArrayZero load the count themselves, from any operand
;
; One reservation of address space, committed a page at a time as pushes reach it. Freeing is
; moving the cursor back: arenaGetPos before some temporary work, arenaSetPos after it.
ifndef saha_asm
saha_asm = 0

include macros.asm

;---------------------------------------------------------------------------------------------------
; structs
;---------------------------------------------------------------------------------------------------
Arena struct
    base qword ?        ; start of the reservation
    cursor qword ?      ; next free byte; always base + used
    previous qword ?    ; cursor before the last push
    used qword ?        ; bytes handed out, padding included
    pagesize qword ?
    npages qword ?      ; pages committed so far
Arena ends

; Address space only: nothing is committed until a push reaches it.
max_alloc_size equ 100000000h   ; 4 GB

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
align 16
arena Arena <>

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; rcx: value -> rax: 1 if it is a power of two
align 16
memoryIsPowerOfTwo proc
    xor eax, eax
    test rcx, rcx
    jz done
    lea rdx, [rcx - 1]
    test rdx, rcx
    sete al
    done:
    ret
memoryIsPowerOfTwo endp

; rcx: pointer, rdx: alignment (a power of two) -> rax: pointer rounded up to it
align 16
memoryAlignForward proc
    lea rax, [rcx + rdx - 1]
    neg rdx
    and rax, rdx
    ret
memoryAlignForward endp

; rcx: &arena -> rax: arena.base
align 16
arenaInit proc arena_ref:qword
    local info:SYSTEM_INFO
    invoke GetSystemInfo, ADDR info
    mov rcx, arena_ref
    mov eax, info.dwPageSize
    mov [rcx].Arena.pagesize, rax
    mov [rcx].Arena.npages, 0
    mov [rcx].Arena.used, 0
    invoke VirtualAlloc, 0, max_alloc_size, MEM_RESERVE, PAGE_NOACCESS
    AssertNotEq rax, 0
    mov rcx, arena_ref
    mov [rcx].Arena.base, rax
    mov [rcx].Arena.cursor, rax
    mov [rcx].Arena.previous, rax
    ret
arenaInit endp

; rcx: &arena, rdx: size, r8: alignment (a power of two) -> rax: the memory
align 16
arenaPush proc arena_ref:qword, alloc_size:qword, alignment:qword
    local aligned:qword, new_used:qword

    mov rcx, alignment
    call memoryIsPowerOfTwo
    AssertNotEq rax, 0

    ; the aligned start, and where the cursor ends up
    mov rcx, arena_ref
    mov rax, [rcx].Arena.cursor
    mov rdx, alignment
    lea rax, [rax + rdx - 1]
    neg rdx
    and rax, rdx
    mov aligned, rax
    add rax, alloc_size
    sub rax, [rcx].Arena.base
    mov new_used, rax

    ; commit more pages when the push runs past the committed ones
    mov rax, [rcx].Arena.npages
    mul [rcx].Arena.pagesize
    cmp new_used, rax
    jbe committed
        mov rax, new_used
        mov r8, [rcx].Arena.pagesize
        lea rax, [rax + r8 - 1]
        xor edx, edx
        div r8                          ; pages = ceil(new_used / pagesize)
        mov [rcx].Arena.npages, rax
        mul r8
        mov rdx, max_alloc_size
        cmp rax, rdx
        jbe fits
        int 3                           ; out of reserved address space
        fits:
        mov rdx, rax
        mov rcx, [rcx].Arena.base
        invoke VirtualAlloc, rcx, rdx, MEM_COMMIT, PAGE_READWRITE
        AssertNotEq rax, 0
        mov rcx, arena_ref
    committed:

    mov rax, [rcx].Arena.cursor
    mov [rcx].Arena.previous, rax
    mov rax, new_used
    mov [rcx].Arena.used, rax
    add rax, [rcx].Arena.base
    mov [rcx].Arena.cursor, rax
    mov rax, aligned
    ret
arenaPush endp

; arenaPush, then zeroes the memory: memory given back by arenaSetPos still holds old data.
align 16
arenaPushZero proc arena_ref:qword, alloc_size:qword, alignment:qword
    USING rdi
    SaveRegs
    invoke arenaPush, arena_ref, alloc_size, alignment
    mov rdi, rax
    mov rcx, alloc_size
    mov rdx, rax
    xor eax, eax
    rep stosb
    mov rax, rdx
    RestoreRegs
    ret
arenaPushZero endp

; rcx: &arena, rdx: a cursor from arenaGetPos -> rax: the cursor
align 16
arenaSetPos proc
    mov [rcx].Arena.cursor, rdx
    mov [rcx].Arena.previous, rdx
    mov rax, rdx
    sub rax, [rcx].Arena.base
    mov [rcx].Arena.used, rax
    mov rax, rdx
    ret
arenaSetPos endp

arenaGetPos macro arenaref:req, posref:req
    mov rax, arenaref.Arena.cursor
    mov posref, rax
endm

; rax = count, from a register or memory of any size, or a constant
arenaLoadCount macro __count:req
    if (opattr(__count)) and 4                  ;; a constant
        mov rax, __count
    elseif type(__count) eq 8
        ifdifi <__count>, <rax>
            mov rax, __count
        endif
    elseif type(__count) eq 4
        mov eax, __count
    else
        movzx eax, __count
    endif
endm

; __arena is ADDR arena, __type the element type, __count how many, __align the element alignment
arenaPushArray macro __arena:req, __type:req, __count:req, __align:req
    arenaLoadCount __count
    mov rdx, sizeof __type
    mul rdx
    invoke arenaPush, __arena, rax, __align
endm

arenaPushArrayZero macro __arena:req, __type:req, __count:req, __align:req
    arenaLoadCount __count
    mov rdx, sizeof __type
    mul rdx
    invoke arenaPushZero, __arena, rax, __align
endm

endif
