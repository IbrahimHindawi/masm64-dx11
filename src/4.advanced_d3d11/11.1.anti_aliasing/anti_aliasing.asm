;---------------------------------------------------------------------------------------------------
; 11.1 Anti-aliasing
;---------------------------------------------------------------------------------------------------
; A pixel is either inside a triangle or not, so edges come out as stairs. Multisampling (MSAA)
; tests coverage at several points per pixel (four here) while still running the pixel shader once,
; and stores a colour per sample. Resolving averages the samples: a pixel half covered by the cube
; ends up half green, and the stairs soften into a slope.
;
; The swap chain cannot be multisampled itself (flip-model swap chains never are), which is
; LearnOpenGL's offscreen setup anyway: the cube is drawn into a 4x MSAA target with a matching 4x
; depth buffer, then ResolveSubresource averages it straight into the back buffer.
;
;   Tab   MSAA on / off
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

samples equ 4

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
align 4
camera_start vec3 <0.0, 0.0, 3.0>
tilt_axis vec3 <0.4, 1.0, 0.2>

align 16
t transforms <>
model mat4 <>
s shader <>
cam camera <>
msaa render_target <>
align 8
msaa_depth qword 0
target qword 0
target_depth qword 0
cube_vb qword 0
transforms_buffer qword 0
msaa_off dword 0

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    invoke window_create, "LearnD3D11"
    call window_create_depth

    invoke shader_create, ADDR s, "src/4.advanced_d3d11/11.1.anti_aliasing/anti_aliasing.hlsl", ADDR cube_layout, cube_layout_count
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, 0.0
    call camera_create

    ; a 4x multisampled colour target, and a depth buffer with the same sample count
    invoke create_render_target, ADDR msaa, scr_width, scr_height, DXGI_FORMAT_R8G8B8A8_UNORM, samples
    invoke create_depth_buffer, scr_width, scr_height, samples
    mov msaa_depth, rax

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
        invoke window_mode, 2
        mov msaa_off, eax

        ; into the MSAA target, or with it off straight into the window
        mov rax, msaa.rtv
        mov rdx, msaa_depth
        cmp msaa_off, 0
        je chosen
            mov rax, backbuffer_rtv
            mov rdx, depth_dsv
        chosen:
        mov target, rax
        mov target_depth, rdx
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR target, target_depth
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, target, floats(0.1, 0.1, 0.1, 1.0)
        movf xmm3, 1.0                          ; the depth, a float: xmm3
        vcall context, ID3D11DeviceContext_ClearDepthStencilView, target_depth, D3D11_CLEAR_DEPTH, 0, 0
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke shader_use, ADDR s
        movf xmm1, 0.6
        lea rcx, model
        lea r8, tilt_axis
        call m4_rotate
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model

        ; average each pixel's four samples into the back buffer
        cmp msaa_off, 0
        jne no_resolve
            vcall context, ID3D11DeviceContext_ResolveSubresource, backbuffer, 0, msaa.texture, 0, DXGI_FORMAT_R8G8B8A8_UNORM
        no_resolve:

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
