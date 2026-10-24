;---------------------------------------------------------------------------------------------------
; image: loading images, what stb_image is to LearnOpenGL
;---------------------------------------------------------------------------------------------------
;   image_load       .png / .jpg through WIC, Windows' own codecs, as RGBA8
;   image_load_hdr   Radiance .hdr, as linear float RGBA
;
; Pixels come back top row first, which is how D3D lays out a texture, so nothing is flipped. They
; live in the arena as long as the program.
ifndef image_asm
image_asm = 0

include macros.asm
include saha.asm
include cstr.asm

image struct
    pixels qword ?      ; RGBA8, width * height * 4 bytes (image_load_hdr: 4 floats a pixel)
    _width dword ?
    height dword ?
image ends

.data
align 8
image_wic qword 0       ; IWICImagingFactory

.code
align 16
image_init proc
    cmp image_wic, 0
    jne done
    cmp arena.base, 0
    jne have_arena
        invoke arenaInit, ADDR arena
    have_arena:
    invoke CoInitializeEx, 0, COINIT_MULTITHREADED
    invoke CoCreateInstance, ADDR CLSID_WICImagingFactory, 0, CLSCTX_INPROC_SERVER, ADDR IID_IWICImagingFactory, ADDR image_wic
    AssertHr
    done:
    ret
image_init endp

; rcx: &image, rdx: path -> rax: the pixels, 0 when the file cannot be read or decoded
align 16
image_load proc out_ref:qword, path:qword
    local wide[520]:word, decoder:qword, wic_frame:qword, converter:qword, w:dword, h:dword, byte_count:qword
    USING rbx
    SaveRegs
    call image_init
    mov rbx, out_ref
    invoke mem_zero, rbx, sizeof image

    invoke MultiByteToWideChar, CP_UTF8, 0, path, -1, ADDR wide, 520
    vcall image_wic, IWICImagingFactory_CreateDecoderFromFilename, ADDR wide, 0, GENERIC_READ, WICDecodeMetadataCacheOnDemand, ADDR decoder
    test eax, eax
    jns opened
        xor eax, eax
        jmp done
    opened:
    vcall decoder, IWICBitmapDecoder_GetFrame, 0, ADDR wic_frame
    vcall image_wic, IWICImagingFactory_CreateFormatConverter, ADDR converter
    ; Whatever the file holds, convert it to 8-bit RGBA. The sixth argument is a double, 0.0.
    vcall converter, IWICFormatConverter_Initialize, wic_frame, ADDR GUID_WICPixelFormat32bppRGBA, \
                     WICBitmapDitherTypeNone, 0, 0, WICBitmapPaletteTypeCustom
    vcall converter, IWICFormatConverter_GetSize, ADDR w, ADDR h
    mov eax, w
    mul h
    shl rax, 2
    mov byte_count, rax
    invoke arenaPush, ADDR arena, byte_count, 16
    mov rbx, out_ref
    mov [rbx].image.pixels, rax
    mov eax, w
    mov [rbx].image._width, eax
    mov eax, h
    mov [rbx].image.height, eax
    mov eax, w
    shl eax, 2
    vcall converter, IWICFormatConverter_CopyPixels, 0, rax, byte_count, qword ptr [rbx].image.pixels
    release converter
    release wic_frame
    release decoder
    mov rax, [rbx].image.pixels
    done:
    RestoreRegs
    ret
image_load endp

; rcx: text, rdx: position -> eax: the decimal number there, rdx: just past it
align 16
image_number proc
    xor eax, eax
    digits:
        movzx r8d, byte ptr [rcx + rdx]
        sub r8d, '0'
        cmp r8d, 9
        ja done
        imul eax, eax, 10
        add eax, r8d
        inc rdx
        jmp digits
    done:
    ret
image_number endp

; rcx: &image, rdx: path -> rax: the pixels (four floats each: linear RGB, a = 1), 0 if the file
; cannot be read
;
; Radiance .hdr stores each pixel as RGBE: three 8-bit mantissas sharing one 8-bit exponent. The
; header is text up to a blank line, then the size ("-Y height +X width", rows from the top). Each
; row is run-length encoded one channel at a time: a count above 128 repeats the next byte
; (count - 128) times, any other count is followed by that many bytes.
align 16
image_load_hdr proc out_ref:qword, path:qword
    local file:qword, file_size:LARGE_INTEGER, got:dword, row:qword, w:qword, h:qword
    USING rbx, rsi, rdi, r12, r13, r14, r15
    SaveRegs
    call image_init
    mov rbx, out_ref
    invoke mem_zero, rbx, sizeof image

    ; the whole file
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
    mov rsi, rax                                ; the data
    invoke ReadFile, file, rsi, file_size.LowPart, ADDR got, 0
    invoke CloseHandle, file
    mov rax, file_size.QuadPart
    mov byte ptr [rsi + rax], 0
    cmp word ptr [rsi], '?#'                    ; "#?", little-endian
    je header
        xor eax, eax
        jmp done
    header:

    ; past the header's blank line, then "-Y height +X width"
    xor edx, edx
    blank:
        cmp byte ptr [rsi + rdx], 10
        jne not_blank
        cmp byte ptr [rsi + rdx + 1], 10
        je found_blank
        not_blank:
        inc rdx
        jmp blank
    found_blank:
    add rdx, 5                                  ; the blank line and "-Y "
    mov rcx, rsi
    call image_number
    mov [rbx].image.height, eax
    mov h, rax
    add rdx, 4                                  ; " +X "
    mov rcx, rsi
    call image_number
    mov [rbx].image._width, eax
    mov w, rax
    inc rdx
    mov rdi, rdx                                ; rdi: where the pixels start

    mov rax, w
    mul h
    shl rax, 4
    invoke arenaPush, ADDR arena, rax, 16
    mov [rbx].image.pixels, rax
    mov r15, rax                                ; next pixel out
    mov rax, w
    shl rax, 2
    invoke arenaPush, ADDR arena, rax, 16
    mov row, rax

    xor r12, r12                                ; y
    rows:
        add rdi, 4                              ; 2, 2, then the width again
        xor r13, r13                            ; channel
        channels:
            xor r14, r14                        ; x
            runs:
                cmp r14, w
                jae channel_done
                movzx ecx, byte ptr [rsi + rdi]
                inc rdi
                mov r8, row
                lea r8, [r8 + r14 * 4]
                add r8, r13                     ; &row[x * 4 + channel]
                add r14, rcx
                cmp ecx, 128
                jbe literal
                    sub ecx, 128
                    sub r14, 128
                    mov al, [rsi + rdi]
                    inc rdi
                    repeat_byte:
                        mov [r8], al
                        add r8, 4
                        dec ecx
                        jnz repeat_byte
                    jmp runs
                literal:
                    test ecx, ecx
                    jz runs
                    copy_byte:
                        mov al, [rsi + rdi]
                        mov [r8], al
                        inc rdi
                        add r8, 4
                        dec ecx
                        jnz copy_byte
                    jmp runs
            channel_done:
            inc r13
            cmp r13, 4
            jb channels

        ; mantissa / 256 * 2^(e - 128) = mantissa * 2^(e - 136), and e = 0 means black. 2^(e - 136)
        ; is built straight from its bits: a float's exponent field holds e - 136 + 127.
        mov r8, row
        xor r14, r14
        pixels:
            movzx eax, byte ptr [r8 + r14 * 4 + 3]
            sub eax, 9
            jg normal_scale
                xor eax, eax                    ; too small for a normal float: black
                jmp have_scale
            normal_scale:
                shl eax, 23
            have_scale:
            movd xmm1, eax
            shufps xmm1, xmm1, 0
            pmovzxbd xmm0, dword ptr [r8 + r14 * 4]
            cvtdq2ps xmm0, xmm0
            mulps xmm0, xmm1
            movups [r15], xmm0
            mov dword ptr [r15 + 12], 3F800000h ; a = 1
            add r15, 16
            inc r14
            cmp r14, w
            jb pixels
        inc r12
        cmp r12, h
        jb rows

    mov rax, [rbx].image.pixels
    done:
    RestoreRegs
    ret
image_load_hdr endp

endif
