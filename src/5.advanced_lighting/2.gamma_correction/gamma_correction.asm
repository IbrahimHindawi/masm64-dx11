;---------------------------------------------------------------------------------------------------
; 2. Gamma correction
;---------------------------------------------------------------------------------------------------
; Monitors do not show a pixel value of 0.5 as half the light of 1.0, but as about a fifth:
; brightness follows roughly value^2.2. Images are stored with the inverse curve applied (sRGB), so
; they look right on screen. Lighting, though, is maths on physical light and only adds up in
; linear space.
;
; Done properly, the round trip is:
;
;   1. texture -> linear   the texture is created as an _SRGB format, so sampling it decodes to
;                          linear for free
;   2. lighting in linear  where two lights really are twice one light
;   3. linear -> screen    the back buffer is written through an _SRGB render target view, which
;                          encodes on the way in
;
; GL switches this with GL_FRAMEBUFFER_SRGB; in D3D it is a format, chosen per view. With gamma
; correction the four lights fall off physically, as 1/d^2. Without it that looks far too steep,
; which is why uncorrected code fell back on a linear 1/d that is wrong but looks closer.
;
;   Tab   gamma corrected (1/d^2) / uncorrected (1/d)
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
plane_vertices label byte
    real4 -10.0, -0.5,  10.0,   0.0, 1.0, 0.0,    0.0, 10.0
    real4  10.0, -0.5,  10.0,   0.0, 1.0, 0.0,   10.0, 10.0
    real4  10.0, -0.5, -10.0,   0.0, 1.0, 0.0,   10.0,  0.0
    real4 -10.0, -0.5,  10.0,   0.0, 1.0, 0.0,    0.0, 10.0
    real4  10.0, -0.5, -10.0,   0.0, 1.0, 0.0,   10.0,  0.0
    real4 -10.0, -0.5, -10.0,   0.0, 1.0, 0.0,    0.0,  0.0
plane_vertices_size equ 6 * 32

; Mirrors `cbuffer lights` in gamma_correction.hlsl: four lights in a row along x, each brighter
; than the last.
lights_constants struct
    positions vec4 4 dup(<>)
    colors vec4 4 dup(<>)
    gamma dword ?
    pad dword 3 dup(?)
lights_constants ends

align 4
camera_start vec3 <0.0, 1.0, 4.0>

align 16
t transforms <>
lights lights_constants <>
light_positions vec4 <-3.0, -0.4, 0.0, 0.0>, <-1.0, -0.4, 0.0, 0.0>, <1.0, -0.4, 0.0, 0.0>, <3.0, -0.4, 0.0, 0.0>
light_colors vec4 <0.25, 0.25, 0.25, 0.0>, <0.5, 0.5, 0.5, 0.0>, <0.75, 0.75, 0.75, 0.0>, <1.0, 1.0, 1.0, 0.0>
lamp_color vec4 <1.0, 1.0, 1.0, 1.0>
model mat4 <>
s shader <>
lamp_shader shader <>
cam camera <>
align 8
cube_vb qword 0
plane_vb qword 0
transforms_buffer qword 0
light_buffer qword 0
lamp_buffer qword 0
wood_linear qword 0
wood_srgb qword 0
backbuffer_srgb_rtv qword 0
target qword 0
sampler qword 0

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    local srgb_view:D3D11_RENDER_TARGET_VIEW_DESC
    USING rbx, rsi
    SaveRegs
    invoke window_create, "LearnD3D11  (Tab: corrected / uncorrected)"
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; A second view of the same back buffer, as sRGB, for the corrected mode.
    invoke mem_zero, ADDR srgb_view, sizeof D3D11_RENDER_TARGET_VIEW_DESC
    mov srgb_view.Format, DXGI_FORMAT_R8G8B8A8_UNORM_SRGB
    mov srgb_view.ViewDimension, D3D11_RTV_DIMENSION_TEXTURE2D
    vcall device, ID3D11Device_CreateRenderTargetView, backbuffer, ADDR srgb_view, ADDR backbuffer_srgb_rtv
    AssertHr

    ; build and compile shaders
    ; -------------------------
    invoke shader_create, ADDR s, "src/5.advanced_lighting/2.gamma_correction/gamma_correction.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR lamp_shader, "src/5.advanced_lighting/2.gamma_correction/light_cube.hlsl", ADDR cube_layout, cube_layout_count

    ; set up vertex data and textures: the same image, read two ways
    ; --------------------------------------------------------------
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR plane_vertices, plane_vertices_size
    mov plane_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof lights_constants
    mov light_buffer, rax
    invoke create_constant_buffer, sizeof vec4
    mov lamp_buffer, rax
    invoke filesystem_path, "resources/textures/wood.png"
    mov rbx, rax
    invoke load_texture, rbx, 0
    mov wood_linear, rax
    invoke load_texture, rbx, 1
    mov wood_srgb, rax

    invoke mem_copy, ADDR lights.positions, ADDR light_positions, 4 * sizeof vec4
    invoke mem_copy, ADDR lights.colors, ADDR light_colors, 4 * sizeof vec4

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
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
        ; mode 0 corrected, mode 1 uncorrected
        invoke window_mode, 2
        mov ecx, 1
        sub ecx, eax
        mov lights.gamma, ecx

        ; render, through the sRGB view when correcting
        ; ------
        mov rax, backbuffer_rtv
        cmp lights.gamma, 0
        je plain_target
            mov rax, backbuffer_srgb_rtv
        plain_target:
        mov target, rax
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR target, depth_dsv
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, target, floats(0.0, 0.0, 0.0, 1.0)
        movf xmm3, 1.0                          ; the depth, a float: xmm3
        vcall context, ID3D11DeviceContext_ClearDepthStencilView, depth_dsv, D3D11_CLEAR_DEPTH, 0, 0
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam

        invoke update_buffer, light_buffer, ADDR lights, sizeof lights_constants
        invoke shader_use, ADDR s
        invoke bind_constants, 1, light_buffer
        mov rax, wood_linear
        cmp lights.gamma, 0
        je plain_wood
            mov rax, wood_srgb
        plain_wood:
        invoke bind_texture, 0, rax
        invoke m4_identity, ADDR model
        invoke draw_vertices, transforms_buffer, ADDR t, plane_vb, 6, ADDR model

        ; a small lamp at each light
        invoke update_buffer, lamp_buffer, ADDR lamp_color, sizeof vec4
        invoke shader_use, ADDR lamp_shader
        invoke bind_constants, 1, lamp_buffer
        lea rsi, light_positions
        xor ebx, ebx
        lamps:
            lea rcx, model
            mov rdx, rsi
            movf xmm2, 0.05
            call m4_translate_scale
            invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model
            add rsi, sizeof vec4
            inc ebx
            cmp ebx, 4
            jb lamps

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
