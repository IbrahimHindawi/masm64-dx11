;---------------------------------------------------------------------------------------------------
; filesystem: paths under the repository root, wherever the executable was run from
;---------------------------------------------------------------------------------------------------
; LearnOpenGL's FileSystem::getPath. The root is found by walking up from the executable until a
; directory holds `resources`.
;
;     invoke filesystem_path, "resources/textures/container.jpg"     ; rax = the full path
;
; Paths and file contents live in the arena for as long as the program runs.
ifndef filesystem_asm
filesystem_asm = 0

include macros.asm
include saha.asm
include cstr.asm
include print.asm

.data
filesystem_root byte 260 dup(0)
filesystem_probe byte 260 dup(0)

.code
align 16
filesystem_find_root proc
    USING rbx, rsi
    SaveRegs
    cmp arena.base, 0
    jne have_arena
        invoke arenaInit, ADDR arena
    have_arena:
    invoke GetModuleFileNameA, 0, ADDR filesystem_root, 260
    mov ebx, 8                          ; levels to try
    up:
        ; cut the path at its last slash
        lea rsi, filesystem_root
        xor ecx, ecx
        mov rdx, -1
        scan:
            mov al, [rsi + rcx]
            test al, al
            jz scanned
            cmp al, '\'
            je slash
            cmp al, '/'
            jne not_slash
            slash:
                mov rdx, rcx
            not_slash:
            inc rcx
            jmp scan
        scanned:
        cmp rdx, -1
        je missing
        mov byte ptr [rsi + rdx], 0
        invoke cstr_copy, ADDR filesystem_probe, ADDR filesystem_root
        invoke cstr_append, ADDR filesystem_probe, "/resources"
        invoke GetFileAttributesA, ADDR filesystem_probe
        cmp eax, -1                     ; INVALID_FILE_ATTRIBUTES
        je not_here
        test eax, FILE_ATTRIBUTE_DIRECTORY
        jnz found
        not_here:
        dec ebx
        jnz up
    missing:
    print "filesystem: no resources directory above the executable\n"
    invoke ExitProcess, 1
    found:
    RestoreRegs
    ret
filesystem_find_root endp

; rcx: path relative to the repository root -> rax: the full path
align 16
filesystem_path proc relative:qword
    USING rbx
    SaveRegs
    cmp filesystem_root, 0
    jne have_root
        call filesystem_find_root
    have_root:
    invoke cstr_length, ADDR filesystem_root
    mov rbx, rax
    invoke cstr_length, relative
    lea rax, [rbx + rax + 2]
    invoke arenaPush, ADDR arena, rax, 1
    mov rbx, rax
    invoke cstr_copy, rbx, ADDR filesystem_root
    invoke cstr_append, rbx, "/"
    invoke cstr_append, rbx, relative
    mov rax, rbx
    RestoreRegs
    ret
filesystem_path endp

; rcx: path, rdx: where to write the size (or 0) -> rax: the whole file, followed by a zero byte
; so text can be read in place; 0 if it cannot be opened
align 16
filesystem_read proc path:qword, out_size:qword
    local file:qword, file_size:LARGE_INTEGER, got:dword
    USING rbx
    SaveRegs
    cmp filesystem_root, 0
    jne have_root
        call filesystem_find_root
    have_root:
    invoke CreateFileA, path, GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0
    cmp rax, INVALID_HANDLE_VALUE
    jne opened
        xor eax, eax
        jmp done
    opened:
    mov file, rax
    invoke GetFileSizeEx, file, ADDR file_size
    mov rax, file_size.QuadPart
    inc rax
    invoke arenaPush, ADDR arena, rax, 16
    mov rbx, rax
    invoke ReadFile, file, rbx, file_size.LowPart, ADDR got, 0
    invoke CloseHandle, file
    mov rax, file_size.QuadPart
    mov byte ptr [rbx + rax], 0
    mov rdx, out_size
    test rdx, rdx
    jz no_size
        mov [rdx], rax
    no_size:
    mov rax, rbx
    done:
    RestoreRegs
    ret
filesystem_read endp

endif
