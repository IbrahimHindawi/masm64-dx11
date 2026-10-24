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

endif
