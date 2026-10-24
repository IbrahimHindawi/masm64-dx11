;---------------------------------------------------------------------------------------------------
; 8. Advanced HLSL
;---------------------------------------------------------------------------------------------------
; LearnOpenGL's "advanced GLSL", in HLSL terms.
;
;   one buffer, many shaders   The four cubes are drawn by four different pixel shaders, compiled
;                              from one file by entry name, and none of them is handed the camera:
;                              it is a constant buffer bound to b0 once per frame, and every
;                              shader that declares `cbuffer transforms : register(b0)` reads it.
;                              (GL: a uniform buffer object at a binding point.)
;   system values              SV_Position in a pixel shader is the pixel's own coordinates
;                              (gl_FragCoord): the left half of the window is drawn darker.
;                              SV_IsFrontFace (gl_FrontFacing) says which side of a triangle is
;                              showing: the cubes' near faces are cut away, and their insides
;                              drawn as a dark checker.
;   packing                    A cbuffer packs into 16-byte registers, and a float3 followed by a
;                              float shares one. The structs that mirror cbuffers pad to match
;                              (std140, in GL).
include rt.inc
include d3d11.inc
include macros.asm
include math.asm
include learn\window.asm
include learn\shader.asm
include learn\gpu.asm
include learn\cube.asm
include learn\camera.asm
include learn\transforms.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
shader_path byte "src/4.advanced_d3d11/8.advanced_hlsl/advanced_hlsl.hlsl", 0
entry_red byte "ps_main", 0
entry_green byte "ps_green", 0
entry_blue byte "ps_blue", 0
entry_yellow byte "ps_yellow", 0
align 8
entries qword entry_red, entry_green, entry_blue, entry_yellow

align 4
camera_start vec3 <0.0, 0.0, 5.0>
corners vec3 <-0.75, 0.75, 0.0>
        vec3 <0.75, 0.75, 0.0>
        vec3 <-0.75, -0.75, 0.0>
        vec3 <0.75, -0.75, 0.0>
spin_axis vec3 <0.3, 1.0, 0.2>

align 16
t transforms <>
model mat4 <>
rotation mat4 <>
turned mat4 <>
base shader <>
cam camera <>
align 8
pixel_shaders qword 4 dup(0)
cube_vb qword 0
transforms_buffer qword 0

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    local path:qword, source:qword, source_size:qword, blob:qword, code_size:qword
    USING rbx, rsi, rdi, r12
    SaveRegs
    invoke window_create, "LearnD3D11"
    call window_create_depth

    ; the vertex shader and layout as usual; then four pixel shaders from the same file
    invoke shader_create, ADDR base, ADDR shader_path, ADDR cube_layout, cube_layout_count
    invoke filesystem_path, ADDR shader_path
    mov path, rax
    invoke filesystem_read, path, ADDR source_size
    mov source, rax
    lea rsi, entries
    lea rdi, pixel_shaders
    xor ebx, ebx
    entry_points:
        invoke shader_compile, path, source, source_size, qword ptr [rsi + rbx * 8], "ps_5_0"
        mov blob, rax
        vcall blob, ID3D10Blob_GetBufferPointer
        mov r12, rax
        vcall blob, ID3D10Blob_GetBufferSize
        mov code_size, rax
        lea rax, [rdi + rbx * 8]
        vcall device, ID3D11Device_CreatePixelShader, r12, code_size, 0, rax
        release blob
        inc ebx
        cmp ebx, 4
        jb entry_points

    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, 0.0
    call camera_create

    render_loop:
        call window_poll
        test eax, eax
        jz render_loop_done

        call get_time
        movss xmm1, xmm0
        subss xmm0, last_frame
        movss delta_time, xmm0
        movss last_frame, xmm1

        invoke camera_process_input, ADDR cam, ADDR delta_time

        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke shader_use, ADDR base

        lea rsi, corners
        lea rdi, pixel_shaders
        xor ebx, ebx
        cubes:
            vcall context, ID3D11DeviceContext_PSSetShader, qword ptr [rdi + rbx * 8], 0, 0
            ; model = translate(corner) * rotate(0.6 + 0.3 i, (0.3, 1, 0.2)) * scale(0.8)
            cvtsi2ss xmm1, ebx
            movf xmm0, 0.3
            mulss xmm1, xmm0
            movf xmm0, 0.6
            addss xmm1, xmm0
            lea rcx, rotation
            lea r8, spin_axis
            call m4_rotate
            invoke m4_identity, ADDR model
            movf xmm0, 0.8
            movss model.m[0], xmm0
            movss model.m[20], xmm0
            movss model.m[40], xmm0
            invoke m4_mul, ADDR turned, ADDR rotation, ADDR model
            invoke m4_translate, ADDR model, rsi
            invoke m4_mul, ADDR model, ADDR model, ADDR turned
            invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model
            add rsi, sizeof vec3
            inc ebx
            cmp ebx, 4
            jb cubes

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
