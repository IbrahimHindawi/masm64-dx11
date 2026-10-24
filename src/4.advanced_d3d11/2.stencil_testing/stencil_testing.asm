;---------------------------------------------------------------------------------------------------
; 2. Stencil testing
;---------------------------------------------------------------------------------------------------
; The stencil buffer is eight bits per pixel, beside the depth, that shaders never see. Draws can
; write to it and be masked by it. Here it draws an outline around each cube:
;
;   1. draw the cubes normally, and write 1 into the stencil wherever they land
;   2. draw them again a little larger, in one flat colour, only where the stencil is NOT 1, so
;      only the rim that sticks out past the originals
;
; The second pass ignores depth, so the outline shows through everything: the selected-object look
; of an editor. In D3D all of this is one immutable depth-stencil state object per configuration,
; and the reference value (1) is given when it is bound.
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
align 4
plane_vertices real4 -5.0, -0.5,  5.0,   0.0, 1.0, 0.0,   0.0, 2.0
               real4  5.0, -0.5,  5.0,   0.0, 1.0, 0.0,   2.0, 2.0
               real4  5.0, -0.5, -5.0,   0.0, 1.0, 0.0,   2.0, 0.0
               real4 -5.0, -0.5,  5.0,   0.0, 1.0, 0.0,   0.0, 2.0
               real4  5.0, -0.5, -5.0,   0.0, 1.0, 0.0,   2.0, 0.0
               real4 -5.0, -0.5, -5.0,   0.0, 1.0, 0.0,   0.0, 0.0
plane_vertices_size equ 6 * 32

align 4
camera_start vec3 <-1.0, 1.0, 4.0>
positions vec3 <-1.0, 0.0, -1.0>
          vec3 <2.0, 0.0, 0.0>

align 16
t transforms <>
model mat4 <>
s shader <>
single_color shader <>
cam camera <>
align 8
cube_vb qword 0
plane_vb qword 0
transforms_buffer qword 0
cube_texture qword 0
floor_texture qword 0
sampler qword 0
plain_state qword 0          ; ID3D11DepthStencilState: depth as usual, stencil untouched
mark_state qword 0           ; depth as usual, and the reference value written into the stencil
outside_state qword 0        ; no depth, and only where the stencil is not the reference value

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; rcx: stencil comparison, rdx: 1 to write the stencil, r8: 1 to test depth -> rax: the state
align 16
create_stencil_state proc func:qword, write:qword, depth:qword
    local desc:D3D11_DEPTH_STENCIL_DESC, state:qword
    invoke mem_zero, ADDR desc, sizeof D3D11_DEPTH_STENCIL_DESC
    mov eax, dword ptr depth
    mov desc.DepthEnable, eax
    mov desc.DepthWriteMask, D3D11_DEPTH_WRITE_MASK_ALL
    mov desc.DepthFunc, D3D11_COMPARISON_LESS
    mov desc.StencilEnable, 1
    mov desc.StencilReadMask, D3D11_DEFAULT_STENCIL_READ_MASK
    mov desc.StencilWriteMask, 0
    cmp write, 0
    je no_write
        mov desc.StencilWriteMask, D3D11_DEFAULT_STENCIL_WRITE_MASK
    no_write:
    mov eax, dword ptr func
    mov desc.FrontFace.StencilFunc, eax
    mov desc.FrontFace.StencilPassOp, D3D11_STENCIL_OP_REPLACE
    mov desc.FrontFace.StencilFailOp, D3D11_STENCIL_OP_KEEP
    mov desc.FrontFace.StencilDepthFailOp, D3D11_STENCIL_OP_KEEP
    ; the back faces the same
    mov rax, qword ptr desc.FrontFace
    mov qword ptr desc.BackFace, rax
    mov rax, qword ptr desc.FrontFace[8]
    mov qword ptr desc.BackFace[8], rax
    vcall device, ID3D11Device_CreateDepthStencilState, ADDR desc, ADDR state
    AssertHr
    mov rax, state
    ret
create_stencil_state endp

align 16
main proc
    USING rbx, rsi
    SaveRegs
    invoke window_create, "LearnD3D11"
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    invoke shader_create, ADDR s, "src/4.advanced_d3d11/2.stencil_testing/stencil_testing.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR single_color, "src/4.advanced_d3d11/2.stencil_testing/single_color.hlsl", ADDR cube_layout, cube_layout_count

    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR plane_vertices, plane_vertices_size
    mov plane_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke filesystem_path, "resources/textures/marble.jpg"
    invoke load_texture, rax, 0
    mov cube_texture, rax
    invoke filesystem_path, "resources/textures/metal.png"
    invoke load_texture, rax, 0
    mov floor_texture, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -75.0
    movf xmm3, -15.0
    call camera_create

    invoke create_stencil_state, D3D11_COMPARISON_ALWAYS, 0, 1
    mov plain_state, rax
    invoke create_stencil_state, D3D11_COMPARISON_ALWAYS, 1, 1
    mov mark_state, rax
    invoke create_stencil_state, D3D11_COMPARISON_NOT_EQUAL, 0, 0
    mov outside_state, rax

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
        invoke shader_use, ADDR s

        ; the floor, leaving the stencil alone
        vcall context, ID3D11DeviceContext_OMSetDepthStencilState, plain_state, 0
        invoke bind_texture, 0, floor_texture
        invoke m4_identity, ADDR model
        invoke draw_vertices, transforms_buffer, ADDR t, plane_vb, 6, ADDR model

        ; 1. the cubes, writing 1 into the stencil
        vcall context, ID3D11DeviceContext_OMSetDepthStencilState, mark_state, 1
        invoke bind_texture, 0, cube_texture
        lea rsi, positions
        xor ebx, ebx
        cubes:
            invoke m4_translate, ADDR model, rsi
            invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model
            add rsi, sizeof vec3
            inc ebx
            cmp ebx, 2
            jb cubes

        ; 2. a little larger, flat, only where the stencil is not 1: the rim
        vcall context, ID3D11DeviceContext_OMSetDepthStencilState, outside_state, 1
        invoke shader_use, ADDR single_color
        lea rsi, positions
        xor ebx, ebx
        outlines:
            lea rcx, model
            mov rdx, rsi
            movf xmm2, 1.1
            call m4_translate_scale
            invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model
            add rsi, sizeof vec3
            inc ebx
            cmp ebx, 2
            jb outlines
        vcall context, ID3D11DeviceContext_OMSetDepthStencilState, 0, 0

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
