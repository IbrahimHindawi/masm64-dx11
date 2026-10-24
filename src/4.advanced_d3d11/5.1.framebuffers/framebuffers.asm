;---------------------------------------------------------------------------------------------------
; 5.1 Framebuffers
;---------------------------------------------------------------------------------------------------
; Drawing into a texture instead of the screen. The scene is rendered into a colour target of the
; window's size, with a depth buffer of its own, and then a second pass draws one full-screen
; triangle that reads that texture and writes the screen. Whatever the second pixel shader does to
; the colour applies to the whole frame at once: post-processing.
;
;   1 plain   2 inverted   3 greyscale   4 sharpen   5 blur   6 edges
;
; The last three are kernels: each pixel becomes a weighted sum of its neighbours, the weights in a
; 3x3 grid.
;
; GL calls the pair a framebuffer object with attachments. In D3D it is views of resources: a
; render target view to draw into the texture, a shader resource view to read it; one texture
; cannot be bound as both at once. create_render_target and create_depth_buffer
; (includes/learn/gpu.asm) make them.
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

; Mirrors `cbuffer post` in framebuffers_screen.hlsl.
post_constants struct
    mode dword ?
    pad dword 3 dup(?)
post_constants ends

camera_start vec3 <-1.0, 1.0, 4.0>
cube_a vec3 <-1.0, 0.0, -1.0>
cube_b vec3 <2.0, 0.0, 0.0>

align 16
t transforms <>
post post_constants <>
model mat4 <>
s shader <>
screen_shader shader <>
cam camera <>
scene_target render_target <>
align 8
scene_depth qword 0
cube_vb qword 0
plane_vb qword 0
transforms_buffer qword 0
post_buffer qword 0
cube_texture qword 0
floor_texture qword 0
sampler qword 0
clamp_sampler qword 0

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    invoke window_create, "LearnD3D11"
    invoke window_mode_default, 5               ; edges

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    invoke create_sampler, D3D11_FILTER_MIN_MAG_MIP_LINEAR, D3D11_TEXTURE_ADDRESS_CLAMP
    mov clamp_sampler, rax

    invoke shader_create, ADDR s, "src/4.advanced_d3d11/5.1.framebuffers/framebuffers.hlsl", ADDR cube_layout, cube_layout_count
    ; The screen pass makes its own triangle from SV_VertexID: no vertices, no input layout.
    invoke shader_create, ADDR screen_shader, "src/4.advanced_d3d11/5.1.framebuffers/framebuffers_screen.hlsl", 0, 0

    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR plane_vertices, plane_vertices_size
    mov plane_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof post_constants
    mov post_buffer, rax
    invoke filesystem_path, "resources/textures/marble.jpg"
    invoke load_texture, rax, 0
    mov cube_texture, rax
    invoke filesystem_path, "resources/textures/metal.png"
    invoke load_texture, rax, 0
    mov floor_texture, rax

    ; the scene's own colour target and depth buffer, the window's size
    invoke create_render_target, ADDR scene_target, scr_width, scr_height, DXGI_FORMAT_R8G8B8A8_UNORM, 1
    invoke create_depth_buffer, scr_width, scr_height, 1
    mov scene_depth, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -75.0
    movf xmm3, -15.0
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
        invoke window_mode, 6
        inc eax
        mov post.mode, eax

        ; first pass: the scene, into the texture
        ; ---------------------------------------
        call unbind_textures                    ; the texture was being read last frame
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR scene_target.rtv, scene_depth
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, scene_target.rtv, floats(0.1, 0.1, 0.1, 1.0)
        movf xmm3, 1.0                          ; the depth, a float: xmm3
        vcall context, ID3D11DeviceContext_ClearDepthStencilView, scene_depth, D3D11_CLEAR_DEPTH, 0, 0
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke shader_use, ADDR s
        vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler
        invoke bind_texture, 0, floor_texture
        invoke m4_identity, ADDR model
        invoke draw_vertices, transforms_buffer, ADDR t, plane_vb, 6, ADDR model
        invoke bind_texture, 0, cube_texture
        invoke m4_translate, ADDR model, ADDR cube_a
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model
        invoke m4_translate, ADDR model, ADDR cube_b
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model

        ; second pass: one triangle over the screen, reading the texture
        ; --------------------------------------------------------------
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR backbuffer_rtv, 0
        invoke update_buffer, post_buffer, ADDR post, sizeof post_constants
        invoke shader_use, ADDR screen_shader
        invoke bind_constants, 1, post_buffer
        invoke bind_texture, 0, scene_target.srv
        vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR clamp_sampler
        vcall context, ID3D11DeviceContext_Draw, 3, 0

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
