;---------------------------------------------------------------------------------------------------
; 6. HDR
;---------------------------------------------------------------------------------------------------
; A render target of 8-bit colour clamps everything to 0..1, so a light two hundred times brighter
; than another can only reach "white", and the detail around it is gone. Rendering into a 16-bit
; float target keeps the real values; a last pass then squeezes them into what the screen can show.
; That squeeze is tone mapping:
;
;   exposure   1 - exp(-color * exposure): like a camera's exposure, low values show the bright end
;              of the tunnel, high values the dark end
;
; The tunnel has one very bright white light at the far end and three dim coloured ones near the
; camera. Without tone mapping the far end is a flat white wall; with it the wood grain shows there
; too.
;
;   Tab         tone mapping on / off (off: values clamped at 1)
;   Up / Down   exposure
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
include learn\srgb.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
; Mirror `cbuffer lights` in lighting.hlsl and `cbuffer tone` in hdr.hlsl.
lights_constants struct
    positions vec4 4 dup(<>)
    colors vec4 4 dup(<>)
lights_constants ends

tone_constants struct
    exposure real4 ?
    enabled dword ?
    pad dword 2 dup(?)
tone_constants ends

align 4
camera_start vec3 <0.0, 0.0, 1.0>
tunnel_center vec3 <0.0, 0.0, -25.0>
tunnel_size vec3 <5.0, 5.0, 55.0>

align 16
t transforms <>
lights lights_constants <>
; lighting info: one bright light at the far end, three dim coloured ones near the camera
light_positions vec4 <0.0, 0.0, -49.5, 0.0>, <-1.4, -1.9, -9.0, 0.0>, <0.0, -1.8, -4.0, 0.0>, <0.8, -1.7, -6.0, 0.0>
light_colors vec4 <200.0, 200.0, 200.0, 0.0>, <0.1, 0.0, 0.0, 0.0>, <0.0, 0.0, 0.2, 0.0>, <0.0, 0.1, 0.0, 0.0>
tone tone_constants <1.0, 1>
tunnel mat4 <>
scratch mat4 <>
s shader <>
hdr_shader shader <>
cam camera <>
hdr_target render_target <>
align 8
hdr_depth qword 0
cube_vb qword 0
transforms_buffer qword 0
lights_buffer qword 0
tone_buffer qword 0
wood qword 0
sampler qword 0

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    invoke window_create, "LearnD3D11  (Tab: tone mapping on / off, Up / Down: exposure)"
    ; The back buffer is viewed as sRGB: what the shaders write is linear, and the view
    ; gamma-encodes it on the way in (5.2).
    call window_use_srgb

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; build and compile shaders
    ; -------------------------
    invoke shader_create, ADDR s, "src/5.advanced_lighting/6.hdr/lighting.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR hdr_shader, "src/5.advanced_lighting/6.hdr/hdr.hlsl", 0, 0

    ; set up vertex data and textures
    ; -------------------------------
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof lights_constants
    mov lights_buffer, rax
    invoke create_constant_buffer, sizeof tone_constants
    mov tone_buffer, rax
    invoke filesystem_path, "resources/textures/wood.png"
    invoke load_texture, rax, 1
    mov wood, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, 0.0
    call camera_create

    ; configure floating point framebuffer
    ; ------------------------------------
    invoke create_render_target, ADDR hdr_target, scr_width, scr_height, DXGI_FORMAT_R16G16B16A16_FLOAT, 1
    invoke create_depth_buffer, scr_width, scr_height, 1
    mov hdr_depth, rax

    ; lighting info
    ; -------------
    invoke mem_copy, ADDR lights.positions, ADDR light_positions, 4 * sizeof vec4
    invoke mem_copy, ADDR lights.colors, ADDR light_colors, 4 * sizeof vec4
    invoke update_buffer, lights_buffer, ADDR lights, sizeof lights_constants

    ; the tunnel: a long box around the camera, seen from inside
    invoke m4_translate, ADDR tunnel, ADDR tunnel_center
    invoke m4_scale, ADDR scratch, ADDR tunnel_size
    invoke m4_mul, ADDR tunnel, ADDR tunnel, ADDR scratch

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
        ; mode 0 tone maps, mode 1 shows the values clamped
        invoke window_mode, 2
        mov ecx, 1
        sub ecx, eax
        mov tone.enabled, ecx
        invoke key_down, VK_UP
        test eax, eax
        jz not_up
            movss xmm0, tone.exposure
            addss xmm0, delta_time
            movss tone.exposure, xmm0
        not_up:
        invoke key_down, VK_DOWN
        test eax, eax
        jz not_down
            movss xmm0, tone.exposure
            subss xmm0, delta_time
            movf xmm1, 0.01
            maxss xmm0, xmm1
            movss tone.exposure, xmm0
        not_down:

        ; 1. render scene into floating point framebuffer
        ; -----------------------------------------------
        call unbind_textures
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR hdr_target.rtv, hdr_depth
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, hdr_target.rtv, floats(0.0, 0.0, 0.0, 1.0)
        movf xmm3, 1.0                          ; the depth, a float: xmm3
        vcall context, ID3D11DeviceContext_ClearDepthStencilView, hdr_depth, D3D11_CLEAR_DEPTH, 0, 0
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke shader_use, ADDR s
        invoke bind_constants, 1, lights_buffer
        invoke bind_texture, 0, wood
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR tunnel

        ; 2. render floating point colour buffer to the screen, tone mapped
        ; -----------------------------------------------------------------
        ; One triangle covering the screen, made by the vertex shader from SV_VertexID alone.
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR backbuffer_rtv, 0
        invoke update_buffer, tone_buffer, ADDR tone, sizeof tone_constants
        invoke shader_use, ADDR hdr_shader
        invoke bind_constants, 1, tone_buffer
        invoke bind_texture, 0, hdr_target.srv
        vcall context, ID3D11DeviceContext_Draw, 3, 0

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
