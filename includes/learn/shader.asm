;---------------------------------------------------------------------------------------------------
; shader: a shader program from one .hlsl file, LearnOpenGL's Shader class
;---------------------------------------------------------------------------------------------------
; The file holds `vs_main` and `ps_main`, and optionally `gs_main`. They are compiled with
; D3DCompile, and the input layout is created against the vertex shader, which is the one place
; D3D checks that they match. A compile error prints the file, line and message, and exits.
;
;     invoke shader_create, ADDR s, "src/1.getting_started/3.1.shaders/shaders.hlsl", ADDR layout, 2
;     ...
;     invoke shader_use, ADDR s
;
; 2.1 hello triangle does all of this by hand, once.
ifndef shader_asm
shader_asm = 0

include macros.asm
include cstr.asm
include print.asm
include learn\window.asm
include learn\filesystem.asm

D3D_COMPILE_STANDARD_FILE_INCLUDE equ 1     ; #include relative to the file being compiled

shader struct
    vertex qword ?      ; ID3D11VertexShader
    geometry qword ?    ; ID3D11GeometryShader, 0 unless the file has a gs_main
    pixel qword ?       ; ID3D11PixelShader
    layout qword ?      ; ID3D11InputLayout, 0 for shaders that make their own vertices
shader ends

.code
; rcx: path, rdx: source, r8: size, r9: entry point, [rsp+32]: target -> rax: ID3DBlob
align 16
shader_compile proc path:qword, source:qword, source_size:qword, entry:qword, target:qword
    local bytecode:qword, errors:qword
    mov bytecode, 0
    mov errors, 0
    invoke D3DCompile, source, source_size, path, 0, D3D_COMPILE_STANDARD_FILE_INCLUDE, entry, target, \
                       D3DCOMPILE_ENABLE_STRICTNESS or D3DCOMPILE_DEBUG, 0, ADDR bytecode, ADDR errors
    test eax, eax
    jns compiled
        cmp errors, 0
        je no_message
            vcall errors, ID3D10Blob_GetBufferPointer
            print "shader: %s\n", rax
            invoke ExitProcess, 1
        no_message:
        print "shader: %s\n", path
        invoke ExitProcess, 1
    compiled:
    cmp errors, 0
    je done
        release errors
    done:
    mov rax, bytecode
    ret
shader_compile endp

; rcx: &shader, rdx: path relative to the repository root, r8: input layout (D3D11_INPUT_ELEMENT_DESC
; array, or 0), r9: how many elements it has
align 16
shader_create proc out_ref:qword, relative:qword, layout:qword, layout_count:qword
    local path:qword, source:qword, source_size:qword, blob:qword
    USING rbx, rsi
    SaveRegs

    invoke filesystem_path, relative
    mov path, rax
    invoke filesystem_read, path, ADDR source_size
    test rax, rax
    jnz have_source
        print "shader: cannot read %s\n", path
        invoke ExitProcess, 1
    have_source:
    mov source, rax
    mov rbx, out_ref
    invoke mem_zero, rbx, sizeof shader

    invoke shader_compile, path, source, source_size, "vs_main", "vs_5_0"
    mov blob, rax
    vcall blob, ID3D10Blob_GetBufferPointer
    mov rsi, rax
    vcall blob, ID3D10Blob_GetBufferSize
    mov rbx, rax
    mov rax, out_ref
    lea rax, [rax].shader.vertex
    vcall device, ID3D11Device_CreateVertexShader, rsi, rbx, 0, rax
    cmp layout_count, 0
    je no_layout
        mov rax, out_ref
        lea rax, [rax].shader.layout
        vcall device, ID3D11Device_CreateInputLayout, layout, layout_count, rsi, rbx, rax
        test eax, eax
        jns no_layout
            print "shader: the input layout does not match vs_main in %s\n", path
            invoke ExitProcess, 1
    no_layout:
    release blob

    invoke cstr_find, source, "gs_main"
    cmp rax, -1
    je no_geometry
        invoke shader_compile, path, source, source_size, "gs_main", "gs_5_0"
        mov blob, rax
        vcall blob, ID3D10Blob_GetBufferPointer
        mov rsi, rax
        vcall blob, ID3D10Blob_GetBufferSize
        mov rbx, rax
        mov rax, out_ref
        lea rax, [rax].shader.geometry
        vcall device, ID3D11Device_CreateGeometryShader, rsi, rbx, 0, rax
        release blob
    no_geometry:

    invoke shader_compile, path, source, source_size, "ps_main", "ps_5_0"
    mov blob, rax
    vcall blob, ID3D10Blob_GetBufferPointer
    mov rsi, rax
    vcall blob, ID3D10Blob_GetBufferSize
    mov rbx, rax
    mov rax, out_ref
    lea rax, [rax].shader.pixel
    vcall device, ID3D11Device_CreatePixelShader, rsi, rbx, 0, rax
    release blob

    RestoreRegs
    ret
shader_create endp

; rcx: &shader. Binds its stages and input layout.
align 16
shader_use proc s:qword
    USING rbx
    SaveRegs
    mov rbx, s
    vcall context, ID3D11DeviceContext_IASetInputLayout, qword ptr [rbx].shader.layout
    vcall context, ID3D11DeviceContext_VSSetShader, qword ptr [rbx].shader.vertex, 0, 0
    vcall context, ID3D11DeviceContext_GSSetShader, qword ptr [rbx].shader.geometry, 0, 0
    vcall context, ID3D11DeviceContext_PSSetShader, qword ptr [rbx].shader.pixel, 0, 0
    RestoreRegs
    ret
shader_use endp

endif
