;---------------------------------------------------------------------------------------------------
; 7. Bloom
;---------------------------------------------------------------------------------------------------
; Very bright light seems to spill over its edges, in eyes and cameras alike. Faking it takes three
; steps, all on HDR values:
;
;   1. draw the scene into two targets at once (multiple render targets): the colour, and only the
;      parts brighter than 1
;   2. blur the bright parts: a Gaussian, done as a horizontal pass then a vertical one, back and
;      forth between two targets (ping-pong), five times each way. Two 1D blurs equal one 2D blur,
;      at a fraction of the samples. The blur targets are half the window's size: the glow spreads
;      twice as far for a quarter of the work
;   3. add the blur back onto the colour, then tone map as in 6
;
; The light cubes are drawn far brighter than 1, so they glow; the lit crates mostly stay under the
; threshold and do not.
;
;   Tab   bloom on / off
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
align 4
plane_vertices label byte
    real4 -12.5, -1.0,  12.5,   0.0, 1.0, 0.0,    0.0, 12.0
    real4  12.5, -1.0,  12.5,   0.0, 1.0, 0.0,   12.0, 12.0
    real4  12.5, -1.0, -12.5,   0.0, 1.0, 0.0,   12.0,  0.0
    real4 -12.5, -1.0,  12.5,   0.0, 1.0, 0.0,    0.0, 12.0
    real4  12.5, -1.0, -12.5,   0.0, 1.0, 0.0,   12.0,  0.0
    real4 -12.5, -1.0, -12.5,   0.0, 1.0, 0.0,    0.0,  0.0
plane_vertices_size equ 6 * 32

; Mirror the cbuffers of bloom.hlsl, blur.hlsl and bloom_final.hlsl.
lights_constants struct
    positions vec4 4 dup(<>)
    colors vec4 4 dup(<>)
lights_constants ends

emit_constants struct
    color vec4 <>               ; w = 1: draw this colour unlit (a light cube)
emit_constants ends

blur_constants struct
    direction vec2 <>           ; one texel, along x or along y
    pad vec2 <>
blur_constants ends

combine_constants struct
    exposure real4 ?
    bloom dword ?
    pad dword 2 dup(?)
combine_constants ends

; where each crate is: position, then turned this many degrees about (1, 0, 1), then this size
crate_placement struct
    position vec3 <>
    degrees real4 ?
    size_ real4 ?
crate_placement ends

align 4
camera_start vec3 <0.0, 1.5, 6.0>
tilt_axis vec3 <1.0, 0.0, 1.0>
crate_places crate_placement <<0.0, 1.5, 0.0>, 0.0, 1.0>
             crate_placement <<2.0, 0.0, 1.0>, 0.0, 1.0>
             crate_placement <<-1.0, -1.0, 2.0>, 60.0, 1.0>
             crate_placement <<0.0, 2.7, 4.0>, 23.0, 1.25>
             crate_placement <<-2.0, 1.0, -3.0>, 124.0, 1.0>
             crate_placement <<-3.0, 0.0, 0.0>, 0.0, 1.0>

align 16
t transforms <>
lights lights_constants <>
; lighting info: four lights, far brighter than 1
light_positions vec4 <0.0, 0.5, 1.5, 0.0>, <-4.0, 0.5, -3.0, 0.0>, <3.0, 0.5, 1.0, 0.0>, <-0.8, 2.4, -1.0, 0.0>
light_colors vec4 <5.0, 5.0, 5.0, 0.0>, <10.0, 0.0, 0.0, 0.0>, <0.0, 0.0, 15.0, 0.0>, <0.0, 5.0, 0.0, 0.0>
emit emit_constants <>
blur blur_constants <>
combine combine_constants <1.0, 1>
crates mat4 6 dup(<>)
model mat4 <>
scratch mat4 <>
s shader <>
blur_shader shader <>
final_shader shader <>
cam camera <>
color_target render_target <>
bright_target render_target <>
pingpong render_target 2 dup(<>)
align 8
scene_targets qword 2 dup(0)
scene_depth qword 0
blur_source qword 0
cube_vb qword 0
plane_vb qword 0
transforms_buffer qword 0
lights_buffer qword 0
emit_buffer qword 0
blur_buffer qword 0
combine_buffer qword 0
wood qword 0
crate qword 0
sampler qword 0
clamp_sampler qword 0
half_w dword 0
half_h dword 0

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; rcx: out mat4, rdx: &crate_placement -> translate(position) * rotate(degrees, (1, 0, 1)) * scale
align 16
crate_model proc out_ref:qword, place:qword
    local rotation:mat4
    mov rdx, place
    movss xmm0, [rdx].crate_placement.degrees
    call radians
    movaps xmm1, xmm0
    lea rcx, rotation
    lea r8, tilt_axis
    call m4_rotate
    invoke m4_identity, ADDR scratch
    mov rdx, place
    mov eax, [rdx].crate_placement.size_
    mov dword ptr scratch.m[0], eax
    mov dword ptr scratch.m[20], eax
    mov dword ptr scratch.m[40], eax
    invoke m4_mul, ADDR scratch, ADDR rotation, ADDR scratch
    mov rdx, place
    lea rdx, [rdx].crate_placement.position
    invoke m4_translate, out_ref, rdx
    invoke m4_mul, out_ref, out_ref, ADDR scratch
    ret
crate_model endp

align 16
main proc
    USING rbx, rsi, rdi
    SaveRegs
    invoke window_create, "LearnD3D11  (Tab: bloom on / off)"
    ; The back buffer is viewed as sRGB: what the shaders write is linear, and the view
    ; gamma-encodes it on the way in (5.2).
    call window_use_srgb

    ; s0 for textures; s1, linear and clamped, for the blur, which must not wrap round the edges
    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler
    invoke create_sampler, D3D11_FILTER_MIN_MAG_MIP_LINEAR, D3D11_TEXTURE_ADDRESS_CLAMP
    mov clamp_sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 1, 1, ADDR clamp_sampler

    ; build and compile shaders
    ; -------------------------
    invoke shader_create, ADDR s, "src/5.advanced_lighting/7.bloom/bloom.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR blur_shader, "src/5.advanced_lighting/7.bloom/blur.hlsl", 0, 0
    invoke shader_create, ADDR final_shader, "src/5.advanced_lighting/7.bloom/bloom_final.hlsl", 0, 0

    ; set up vertex data and textures
    ; -------------------------------
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR plane_vertices, plane_vertices_size
    mov plane_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof lights_constants
    mov lights_buffer, rax
    invoke create_constant_buffer, sizeof emit_constants
    mov emit_buffer, rax
    invoke create_constant_buffer, sizeof blur_constants
    mov blur_buffer, rax
    invoke create_constant_buffer, sizeof combine_constants
    mov combine_buffer, rax
    invoke filesystem_path, "resources/textures/wood.png"
    invoke load_texture, rax, 1
    mov wood, rax
    invoke filesystem_path, "resources/textures/container2.png"
    invoke load_texture, rax, 1
    mov crate, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, -15.0
    call camera_create

    ; configure floating point framebuffers: two colour targets for the scene, and two half-size
    ; ones to ping-pong the blur between
    ; ------------------------------------------------------------------------------------------
    invoke create_render_target, ADDR color_target, scr_width, scr_height, DXGI_FORMAT_R16G16B16A16_FLOAT, 1
    invoke create_render_target, ADDR bright_target, scr_width, scr_height, DXGI_FORMAT_R16G16B16A16_FLOAT, 1
    invoke create_depth_buffer, scr_width, scr_height, 1
    mov scene_depth, rax
    mov eax, scr_width
    shr eax, 1
    mov half_w, eax
    mov eax, scr_height
    shr eax, 1
    mov half_h, eax
    invoke create_render_target, ADDR pingpong[0], half_w, half_h, DXGI_FORMAT_R16G16B16A16_FLOAT, 1
    invoke create_render_target, ADDR pingpong[sizeof render_target], half_w, half_h, DXGI_FORMAT_R16G16B16A16_FLOAT, 1
    mov rax, color_target.rtv
    mov scene_targets[0], rax
    mov rax, bright_target.rtv
    mov scene_targets[8], rax

    ; lighting info
    ; -------------
    invoke mem_copy, ADDR lights.positions, ADDR light_positions, 4 * sizeof vec4
    invoke mem_copy, ADDR lights.colors, ADDR light_colors, 4 * sizeof vec4
    invoke update_buffer, lights_buffer, ADDR lights, sizeof lights_constants

    lea rsi, crate_places
    lea rdi, crates
    xor ebx, ebx
    place_crates:
        invoke crate_model, rdi, rsi
        add rsi, sizeof crate_placement
        add rdi, sizeof mat4
        inc ebx
        cmp ebx, 6
        jb place_crates

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
        ; mode 0 with bloom, mode 1 without
        invoke window_mode, 2
        mov ecx, 1
        sub ecx, eax
        mov combine.bloom, ecx

        ; 1. render scene into floating point framebuffer: colour and bright parts at once
        ; --------------------------------------------------------------------------------
        call unbind_textures
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 2, ADDR scene_targets, scene_depth
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, color_target.rtv, floats(0.0, 0.0, 0.0, 0.0)
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, bright_target.rtv, floats(0.0, 0.0, 0.0, 0.0)
        movf xmm3, 1.0                          ; the depth, a float: xmm3
        vcall context, ID3D11DeviceContext_ClearDepthStencilView, scene_depth, D3D11_CLEAR_DEPTH, 0, 0
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke shader_use, ADDR s
        invoke bind_constants, 1, lights_buffer
        invoke bind_constants, 2, emit_buffer
        invoke mem_zero, ADDR emit, sizeof emit_constants
        invoke update_buffer, emit_buffer, ADDR emit, sizeof emit_constants
        invoke bind_texture, 0, wood
        invoke m4_identity, ADDR model
        invoke draw_vertices, transforms_buffer, ADDR t, plane_vb, 6, ADDR model
        invoke bind_texture, 0, crate
        lea rsi, crates
        xor ebx, ebx
        draw_crates:
            invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, rsi
            add rsi, sizeof mat4
            inc ebx
            cmp ebx, 6
            jb draw_crates
        ; the lights themselves: no lighting, just their own HDR colour
        xor ebx, ebx
        draw_lights:
            mov eax, ebx
            shl eax, 4                          ; * sizeof vec4
            lea rsi, light_colors
            movups xmm0, [rsi + rax]
            movups emit.color, xmm0
            storef emit.color.w, 1.0
            invoke update_buffer, emit_buffer, ADDR emit, sizeof emit_constants
            mov eax, ebx
            shl eax, 4
            lea rdx, light_positions
            add rdx, rax
            lea rcx, model
            movf xmm2, 0.25
            call m4_translate_scale
            invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model
            inc ebx
            cmp ebx, 4
            jb draw_lights

        ; 2. blur bright fragments with two-pass Gaussian blur
        ; ----------------------------------------------------
        invoke shader_use, ADDR blur_shader
        invoke bind_constants, 1, blur_buffer
        invoke set_viewport, half_w, half_h
        mov rax, bright_target.srv
        mov blur_source, rax
        xor ebx, ebx
        blur_passes:
            ; even passes blur along x, odd ones along y, one texel at a time
            mov dword ptr blur.direction.x, 0
            mov dword ptr blur.direction.y, 0
            movss xmm0, math_one
            test ebx, 1
            jnz along_y
                cvtsi2ss xmm1, half_w
                divss xmm0, xmm1
                movss blur.direction.x, xmm0
                jmp along_done
            along_y:
                cvtsi2ss xmm1, half_h
                divss xmm0, xmm1
                movss blur.direction.y, xmm0
            along_done:
            invoke update_buffer, blur_buffer, ADDR blur, sizeof blur_constants
            call unbind_textures
            ; the target: pingpong[i % 2]
            mov eax, ebx
            and eax, 1
            imul eax, eax, sizeof render_target
            lea rsi, pingpong
            add rsi, rax
            lea rax, [rsi].render_target.rtv
            vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, rax, 0
            invoke bind_texture, 0, blur_source
            vcall context, ID3D11DeviceContext_Draw, 3, 0
            mov rax, [rsi].render_target.srv
            mov blur_source, rax
            inc ebx
            cmp ebx, 10
            jb blur_passes

        ; 3. now render floating point colour buffer to the screen, adding the blur and tone mapping
        ; ------------------------------------------------------------------------------------------
        call unbind_textures
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR backbuffer_rtv, 0
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        invoke update_buffer, combine_buffer, ADDR combine, sizeof combine_constants
        invoke shader_use, ADDR final_shader
        invoke bind_constants, 1, combine_buffer
        invoke bind_texture, 0, color_target.srv
        invoke bind_texture, 1, blur_source
        vcall context, ID3D11DeviceContext_Draw, 3, 0

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
