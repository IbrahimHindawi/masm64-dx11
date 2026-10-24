;---------------------------------------------------------------------------------------------------
; 6.1 Coordinate systems
;---------------------------------------------------------------------------------------------------
; Three matrices take a vertex from the cube it belongs to all the way to the screen:
;
;   model       the cube's own space -> the world      (where this cube is)
;   view        the world -> the camera's space        (where the eye is)
;   projection  the camera's space -> clip space       (the lens: perspective)
;
;   clip = projection * view * model * position
;
; Ten cubes share one vertex buffer and differ only in their model matrix. A depth buffer, cleared
; every frame, keeps the nearest surface at each pixel so the cubes hide each other correctly.
; D3D's depth runs 0..1 where GL's runs -1..1, which is why m4_perspective differs from glm's in
; two entries.
;
; The cube's vertices are in includes/learn/cube.asm, where every later lesson finds them too.
include rt.inc
include d3d11.inc
include macros.asm
include math.asm
include learn\window.asm
include learn\shader.asm
include learn\gpu.asm
include learn\cube.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
align 4
view_offset vec3 <0.0, 0.0, -3.0>

; Mirrors `cbuffer object` in the shader.
object_constants struct
    model mat4 <>
    view mat4 <>
    projection mat4 <>
object_constants ends

align 16
c object_constants <>
translation mat4 <>
rotation mat4 <>
s shader <>
align 8
cube_vb qword 0
sampler qword 0
constants qword 0
textures qword 2 dup(0)
stride dword cube_stride
offset_ dword 0
current_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    USING rbx
    SaveRegs
    invoke window_create, "LearnD3D11"
    ; A depth buffer the size of the window: 24 bits of depth, 8 of stencil (window.asm).
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; build and compile our shader program
    ; ------------------------------------
    invoke shader_create, ADDR s, "src/1.getting_started/6.1.coordinate_systems/coordinate_systems.hlsl", ADDR cube_layout, cube_layout_count

    ; set up vertex data and textures
    ; -------------------------------
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke filesystem_path, "resources/textures/container.jpg"
    invoke load_texture, rax, 0
    mov textures[0], rax
    invoke filesystem_path, "resources/textures/awesomeface.png"
    invoke load_texture, rax, 0
    mov textures[8], rax
    invoke create_constant_buffer, sizeof object_constants
    mov constants, rax

    ; render loop
    ; -----------
    render_loop:
        call window_poll
        test eax, eax
        jz render_loop_done

        ; per-frame time logic
        ; --------------------
        call get_time
        movss current_frame, xmm0

        ; render
        ; ------
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR backbuffer_rtv, depth_dsv
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, backbuffer_rtv, floats(0.2, 0.3, 0.3, 1.0)
        ; The depth to clear to is a float: the fourth argument, counting `this`, so it travels in
        ; xmm3, and the 0 in its place on the vcall line is only a placeholder.
        movf xmm3, 1.0
        vcall context, ID3D11DeviceContext_ClearDepthStencilView, depth_dsv, D3D11_CLEAR_DEPTH or D3D11_CLEAR_STENCIL, 0, 0

        vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 2, ADDR textures
        invoke shader_use, ADDR s
        invoke bind_constants, 0, constants
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR cube_vb, ADDR stride, ADDR offset_

        ; view = translate(0, 0, -3): the world moves away from the eye
        invoke m4_translate, ADDR c.view, ADDR view_offset
        ; projection = perspective(45 degrees, width / height, 0.1, 100)
        movf xmm0, 100.0
        movss real4 ptr [rsp + 32], xmm0        ; z_far, the fifth argument, on the stack
        movf xmm0, 45.0
        call radians
        movaps xmm1, xmm0                       ; fovy
        cvtsi2ss xmm2, scr_width
        cvtsi2ss xmm0, scr_height
        divss xmm2, xmm0                        ; aspect
        movf xmm3, 0.1                          ; z_near
        lea rcx, c.projection
        call m4_perspective

        xor ebx, ebx
        cubes:
            ; angle = radians(20 * i), and every third cube spins with time
            cvtsi2ss xmm0, ebx
            movf xmm1, 20.0
            mulss xmm0, xmm1
            call radians
            mov eax, ebx
            xor edx, edx
            mov ecx, 3
            div ecx
            test edx, edx
            jnz still
                addss xmm0, current_frame
            still:
            ; model = translate(cube_positions[i]) * rotate(angle, (1, 0.3, 0.5))
            movaps xmm1, xmm0
            lea rcx, rotation
            lea r8, cube_rotation_axis
            call m4_rotate
            imul eax, ebx, sizeof vec3
            lea rdx, cube_positions
            add rdx, rax
            invoke m4_translate, ADDR translation, rdx
            invoke m4_mul, ADDR c.model, ADDR translation, ADDR rotation
            invoke update_buffer, constants, ADDR c, sizeof object_constants
            vcall context, ID3D11DeviceContext_Draw, 36, 0
            inc ebx
            cmp ebx, 10
            jb cubes

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
