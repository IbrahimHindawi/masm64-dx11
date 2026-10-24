;---------------------------------------------------------------------------------------------------
; 3.1 Blending
;---------------------------------------------------------------------------------------------------
; Two kinds of see-through:
;
;   grass    each texel is either fully there or fully not. The pixel shader throws away (clip)
;            pixels whose alpha is low, and what is left is ordinary opaque geometry: order does
;            not matter
;   windows  partly transparent. The blend state mixes each new pixel with what is already in the
;            target: src * a + dst * (1 - a)
;
; Blending reads what is behind, so the windows are drawn after everything opaque, from the
; farthest to the nearest. Drawn in the wrong order, a near window would be in the depth buffer
; first and hide the ones behind it.
;
; The grass and windows are sampled with clamp rather than wrap, so the top row of each image is
; not blended with its bottom row. In D3D a sampler is an object of its own, bound to a slot like a
; texture: this is a matter of binding a different one into s0 for those draws.
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

; A unit square standing on its bottom edge, facing +z: one blade of grass or one window.
quad_vertices real4 -0.5, 0.0, 0.0,   0.0, 0.0, 1.0,   0.0, 1.0
              real4  0.5, 0.0, 0.0,   0.0, 0.0, 1.0,   1.0, 1.0
              real4  0.5, 1.0, 0.0,   0.0, 0.0, 1.0,   1.0, 0.0
              real4 -0.5, 0.0, 0.0,   0.0, 0.0, 1.0,   0.0, 1.0
              real4  0.5, 1.0, 0.0,   0.0, 0.0, 1.0,   1.0, 0.0
              real4 -0.5, 1.0, 0.0,   0.0, 0.0, 1.0,   0.0, 0.0
quad_vertices_size equ 6 * 32

window_positions vec3 <-1.5, -0.5, -0.48>
                 vec3 <1.5, -0.5, 0.51>
                 vec3 <0.0, -0.5, 0.7>
                 vec3 <-0.3, -0.5, -2.3>
                 vec3 <0.5, -0.5, -0.6>
grass_positions vec3 <-2.2, -0.5, 0.4>
                vec3 <2.6, -0.5, 1.2>
                vec3 <0.6, -0.5, 1.4>
                vec3 <-0.6, -0.5, -1.8>

camera_start vec3 <0.0, 0.5, 4.5>
cube_a vec3 <-1.0, 0.0, -1.0>
cube_b vec3 <2.0, 0.0, 0.0>

align 16
t transforms <>
model mat4 <>
s shader <>
cam camera <>
offset_to_window vec3 <>
window_order dword 5 dup(?)     ; the windows, farthest first
window_distance real4 5 dup(?)
align 8
cube_vb qword 0
plane_vb qword 0
quad_vb qword 0
transforms_buffer qword 0
cube_texture qword 0
floor_texture qword 0
grass qword 0
glass qword 0
sampler qword 0
clamp_sampler qword 0
alpha_blend qword 0

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; -> rax: a blend state for transparency: out = src * src_alpha + dst * (1 - src_alpha)
align 16
create_alpha_blend proc
    local desc:D3D11_BLEND_DESC, state:qword
    invoke mem_zero, ADDR desc, sizeof D3D11_BLEND_DESC
    mov desc.RenderTarget.BlendEnable, 1
    mov desc.RenderTarget.SrcBlend, D3D11_BLEND_SRC_ALPHA
    mov desc.RenderTarget.DestBlend, D3D11_BLEND_INV_SRC_ALPHA
    mov desc.RenderTarget.BlendOp, D3D11_BLEND_OP_ADD
    mov desc.RenderTarget.SrcBlendAlpha, D3D11_BLEND_ONE
    mov desc.RenderTarget.DestBlendAlpha, D3D11_BLEND_INV_SRC_ALPHA
    mov desc.RenderTarget.BlendOpAlpha, D3D11_BLEND_OP_ADD
    mov desc.RenderTarget.RenderTargetWriteMask, D3D11_COLOR_WRITE_ENABLE_ALL
    vcall device, ID3D11Device_CreateBlendState, ADDR desc, ADDR state
    AssertHr
    mov rax, state
    ret
create_alpha_blend endp

; Puts the windows in window_order from the farthest from the camera to the nearest.
align 16
sort_windows proc
    USING rbx, rsi, rdi, r12
    SaveRegs
    ; A global indexed by a register needs its address in a register too: [label + rbx * 4] would
    ; be a 32-bit absolute address, which a 64-bit program loaded above 4 GB cannot use.
    lea rdi, window_order
    lea r12, window_distance
    xor ebx, ebx
    distances:
        mov [rdi + rbx * 4], ebx
        imul eax, ebx, sizeof vec3
        lea rdx, window_positions
        add rdx, rax
        invoke v3_sub, ADDR offset_to_window, rdx, ADDR cam.position
        invoke v3_length, ADDR offset_to_window
        movss real4 ptr [r12 + rbx * 4], xmm0
        inc ebx
        cmp ebx, 5
        jb distances
    ; selection sort on the distances, carrying the order along
    xor ebx, ebx
    outer:
        lea esi, [ebx + 1]
        inner:
            cmp esi, 5
            jae inner_done
            movss xmm0, real4 ptr [r12 + rsi * 4]
            comiss xmm0, real4 ptr [r12 + rbx * 4]
            jbe in_order
                movss xmm1, real4 ptr [r12 + rbx * 4]
                movss real4 ptr [r12 + rbx * 4], xmm0
                movss real4 ptr [r12 + rsi * 4], xmm1
                mov eax, [rdi + rbx * 4]
                mov edx, [rdi + rsi * 4]
                mov [rdi + rbx * 4], edx
                mov [rdi + rsi * 4], eax
            in_order:
            inc esi
            jmp inner
        inner_done:
        inc ebx
        cmp ebx, 4
        jb outer
    RestoreRegs
    ret
sort_windows endp

align 16
main proc
    USING rbx, rsi
    SaveRegs
    invoke window_create, "LearnD3D11"
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_CLAMP
    mov clamp_sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler
    call create_alpha_blend
    mov alpha_blend, rax

    invoke shader_create, ADDR s, "src/4.advanced_d3d11/3.1.blending/blending.hlsl", ADDR cube_layout, cube_layout_count

    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR plane_vertices, plane_vertices_size
    mov plane_vb, rax
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR quad_vertices, quad_vertices_size
    mov quad_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke filesystem_path, "resources/textures/marble.jpg"
    invoke load_texture, rax, 0
    mov cube_texture, rax
    invoke filesystem_path, "resources/textures/metal.png"
    invoke load_texture, rax, 0
    mov floor_texture, rax
    invoke filesystem_path, "resources/textures/grass.png"
    invoke load_texture, rax, 0
    mov grass, rax
    invoke filesystem_path, "resources/textures/window.png"
    invoke load_texture, rax, 0
    mov glass, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, -10.0
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
        invoke shader_use, ADDR s

        ; everything opaque first: the floor and two cubes
        invoke bind_texture, 0, floor_texture
        invoke m4_identity, ADDR model
        invoke draw_vertices, transforms_buffer, ADDR t, plane_vb, 6, ADDR model
        invoke bind_texture, 0, cube_texture
        invoke m4_translate, ADDR model, ADDR cube_a
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model
        invoke m4_translate, ADDR model, ADDR cube_b
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model

        ; grass: clipped, so in any order
        vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR clamp_sampler
        invoke bind_texture, 0, grass
        lea rsi, grass_positions
        xor ebx, ebx
        blades:
            invoke m4_translate, ADDR model, rsi
            invoke draw_vertices, transforms_buffer, ADDR t, quad_vb, 6, ADDR model
            add rsi, sizeof vec3
            inc ebx
            cmp ebx, 4
            jb blades

        ; windows: blended, so the farthest first
        call sort_windows
        vcall context, ID3D11DeviceContext_OMSetBlendState, alpha_blend, 0, D3D11_DEFAULT_SAMPLE_MASK
        invoke bind_texture, 0, glass
        xor ebx, ebx
        windows:
            lea rax, window_order
            mov eax, [rax + rbx * 4]
            imul eax, eax, sizeof vec3
            lea rsi, window_positions
            add rsi, rax
            invoke m4_translate, ADDR model, rsi
            invoke draw_vertices, transforms_buffer, ADDR t, quad_vb, 6, ADDR model
            inc ebx
            cmp ebx, 5
            jb windows
        vcall context, ID3D11DeviceContext_OMSetBlendState, 0, 0, D3D11_DEFAULT_SAMPLE_MASK
        vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
