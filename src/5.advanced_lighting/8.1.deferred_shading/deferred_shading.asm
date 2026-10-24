;---------------------------------------------------------------------------------------------------
; 8.1 Deferred shading
;---------------------------------------------------------------------------------------------------
; Forward rendering lights every pixel of every object as it is drawn, even the ones later covered:
; with many lights that is a lot of wasted lighting. Deferred rendering splits it in two:
;
;   geometry pass  draw everything once, storing what lighting needs rather than the lit colour:
;                  world position, normal, albedo and specular strength, in three targets at once
;                  (the G-buffer)
;   lighting pass  one full-screen pass reads the G-buffer and lights each visible pixel exactly
;                  once, here by 32 lights
;
; What deferred cannot do is blend, so anything transparent (or, here, the light cubes) is drawn
; forward afterwards. Those still need the depth the geometry pass left behind, so the G-buffer's
; depth buffer is bound together with the back buffer for them; GL has to copy it across with a
; blit.
;
; The albedo target is an _SRGB format: linear colour stored with the sRGB curve, so its eight bits
; go where the eye can tell the difference.
;
;   Tab   lit / positions / normals / albedo / specular
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
include learn\model.asm
include learn\srgb.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
light_count equ 32

point_light struct
    position vec4 <>
    color vec4 <>
point_light ends

align 4
camera_start vec3 <0.0, 4.0, 9.0>
backpack_place vec3 <>

align 16
; Mirrors `cbuffer lights` in deferred_shading.hlsl: the lights, then which view to show. (Laid out
; by hand: MASM cannot initialize an array of structures inside a structure.)
lights label byte
light_array point_light light_count dup(<>)
view_mode dword 0
          dword 3 dup(0)
lights_size equ light_count * sizeof point_light + 16
.erre ($ - lights) eq lights_size

align 16
t transforms <>
lamp_color vec4 <>
lamp_model mat4 <>
geometry_shader shader <>
lighting_shader shader <>
lamp_shader shader <>
cam camera <>
backpack model <>
positions render_target <>
normals render_target <>
albedo render_target <>
align 8
g_targets qword 3 dup(0)
g_views qword 3 dup(0)
g_depth qword 0
cube_vb qword 0
transforms_buffer qword 0
lights_buffer qword 0
lamp_buffer qword 0
sampler qword 0

; timing
current_frame real4 0.0
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; xmm1: scale, xmm2: offset -> xmm0: (rand() % 1000) / 1000 * scale + offset
align 16
random_in proc
    local scale:real4, offset_:real4
    movss scale, xmm1
    movss offset_, xmm2
    call rand
    xor edx, edx
    mov ecx, 1000
    div ecx
    cvtsi2ss xmm0, edx
    movf xmm1, 1000.0
    divss xmm0, xmm1
    mulss xmm0, scale
    addss xmm0, offset_
    ret
random_in endp

align 16
main proc
    USING rbx, rsi, rdi
    SaveRegs
    invoke window_create, "LearnD3D11  (Tab: lit / position / normal / albedo / specular)"
    ; The back buffer is viewed as sRGB: what the shaders write is linear, and the view
    ; gamma-encodes it on the way in (5.2).
    call window_use_srgb
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; build and compile shaders
    ; -------------------------
    invoke shader_create, ADDR geometry_shader, "src/5.advanced_lighting/8.1.deferred_shading/g_buffer.hlsl", ADDR model_layout, model_layout_count
    invoke shader_create, ADDR lighting_shader, "src/5.advanced_lighting/8.1.deferred_shading/deferred_shading.hlsl", 0, 0
    invoke shader_create, ADDR lamp_shader, "src/5.advanced_lighting/8.1.deferred_shading/light_cube.hlsl", ADDR cube_layout, cube_layout_count

    ; load models
    ; -----------
    invoke model_load, ADDR backpack, "resources/objects/backpack/", "backpack.obj", 0
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, lights_size
    mov lights_buffer, rax
    invoke create_constant_buffer, sizeof vec4
    mov lamp_buffer, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, -25.0
    call camera_create

    ; configure g-buffer framebuffer
    ; ------------------------------
    invoke create_render_target, ADDR positions, scr_width, scr_height, DXGI_FORMAT_R16G16B16A16_FLOAT, 1
    invoke create_render_target, ADDR normals, scr_width, scr_height, DXGI_FORMAT_R16G16B16A16_FLOAT, 1
    invoke create_render_target, ADDR albedo, scr_width, scr_height, DXGI_FORMAT_R8G8B8A8_UNORM_SRGB, 1
    invoke create_depth_buffer, scr_width, scr_height, 1
    mov g_depth, rax
    mov rax, positions.rtv
    mov g_targets[0], rax
    mov rax, normals.rtv
    mov g_targets[8], rax
    mov rax, albedo.rtv
    mov g_targets[16], rax
    mov rax, positions.srv
    mov g_views[0], rax
    mov rax, normals.srv
    mov g_views[8], rax
    mov rax, albedo.srv
    mov g_views[16], rax

    ; lighting info: 32 lights scattered around the backpacks, in pale random colours
    ; -------------
    invoke srand, 13
    lea rsi, light_array
    xor ebx, ebx
    place_lights:
        ; The rin original draws these as v4(random(), random(), random(), 0), whose arguments its
        ; compiler (clang-cl, like MSVC) evaluates right to left: z first, then y, then x. Doing the
        ; same here puts every light where rin's are.
        movf xmm1, 9.0
        movf xmm2, -4.5
        call random_in
        movss [rsi].point_light.position.z, xmm0
        movf xmm1, 3.0
        movf xmm2, -0.5
        call random_in
        movss [rsi].point_light.position.y, xmm0
        movf xmm1, 9.0
        movf xmm2, -4.5
        call random_in
        movss [rsi].point_light.position.x, xmm0
        mov dword ptr [rsi].point_light.position.w, 0
        movss xmm1, math_half
        movss xmm2, math_half
        call random_in
        movss [rsi].point_light.color.z, xmm0
        movss xmm1, math_half
        movss xmm2, math_half
        call random_in
        movss [rsi].point_light.color.y, xmm0
        movss xmm1, math_half
        movss xmm2, math_half
        call random_in
        movss [rsi].point_light.color.x, xmm0
        mov dword ptr [rsi].point_light.color.w, 0
        add rsi, sizeof point_light
        inc ebx
        cmp ebx, light_count
        jb place_lights

    render_loop:
        call window_poll
        test eax, eax
        jz render_loop_done

        call get_time
        movss current_frame, xmm0
        movss xmm1, xmm0
        subss xmm0, last_frame
        movss delta_time, xmm0
        movss last_frame, xmm1

        invoke camera_process_input, ADDR cam, ADDR delta_time
        invoke window_mode, 5
        mov view_mode, eax

        ; 1. geometry pass: render scene's geometry/colour data into the g-buffer
        ; -----------------------------------------------------------------------
        call unbind_textures
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 3, ADDR g_targets, g_depth
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, positions.rtv, floats(0.0, 0.0, 0.0, 0.0)
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, normals.rtv, floats(0.0, 0.0, 0.0, 0.0)
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, albedo.rtv, floats(0.0, 0.0, 0.0, 0.0)
        movf xmm3, 1.0                          ; the depth, a float: xmm3
        vcall context, ID3D11DeviceContext_ClearDepthStencilView, g_depth, D3D11_CLEAR_DEPTH, 0, 0
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke shader_use, ADDR geometry_shader
        ; nine backpacks, three by three: translate(3x, 0, 3z) * scale(0.6)
        mov esi, -1                             ; z
        rows_z:
            mov edi, -1                         ; x
            rows_x:
                movf xmm1, 3.0
                cvtsi2ss xmm0, edi
                mulss xmm0, xmm1
                movss backpack_place.x, xmm0
                mov dword ptr backpack_place.y, 0
                cvtsi2ss xmm0, esi
                mulss xmm0, xmm1
                movss backpack_place.z, xmm0
                lea rcx, t.model
                lea rdx, backpack_place
                movf xmm2, 0.6
                call m4_translate_scale
                invoke m4_normal_matrix, ADDR t.normal_matrix, ADDR t.model
                invoke update_buffer, transforms_buffer, ADDR t, sizeof transforms
                invoke model_draw, ADDR backpack
                inc edi
                cmp edi, 1
                jle rows_x
            inc esi
            cmp esi, 1
            jle rows_z

        ; 2. lighting pass: light every visible pixel once, from the g-buffer
        ; -------------------------------------------------------------------
        call unbind_textures
        invoke window_begin, floats(0.0, 0.0, 0.0, 1.0)
        ; the lights drift in small circles: (0.6 cos(t + i), 0, 0.6 sin(t + i)) a second
        lea rsi, light_array
        xor ebx, ebx
        drift:
            cvtsi2ss xmm0, ebx
            addss xmm0, current_frame
            call cosf
            movf xmm1, 0.6
            mulss xmm0, xmm1
            mulss xmm0, delta_time
            addss xmm0, [rsi].point_light.position.x
            movss [rsi].point_light.position.x, xmm0
            cvtsi2ss xmm0, ebx
            addss xmm0, current_frame
            call sinf
            movf xmm1, 0.6
            mulss xmm0, xmm1
            mulss xmm0, delta_time
            addss xmm0, [rsi].point_light.position.z
            movss [rsi].point_light.position.z, xmm0
            add rsi, sizeof point_light
            inc ebx
            cmp ebx, light_count
            jb drift
        invoke update_buffer, lights_buffer, ADDR lights, lights_size
        invoke shader_use, ADDR lighting_shader
        invoke bind_constants, 1, lights_buffer
        vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 3, ADDR g_views
        vcall context, ID3D11DeviceContext_Draw, 3, 0

        ; 3. render lights on top of the scene, depth tested against the g-buffer's depth
        ; -------------------------------------------------------------------------------
        cmp view_mode, 0
        jne no_lamps
            vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR backbuffer_rtv, g_depth
            invoke shader_use, ADDR lamp_shader
            invoke bind_constants, 1, lamp_buffer
            lea rsi, light_array
            xor ebx, ebx
            lamps:
                movups xmm0, xmmword ptr [rsi].point_light.color
                movups xmmword ptr lamp_color, xmm0
                storef lamp_color.w, 1.0
                invoke update_buffer, lamp_buffer, ADDR lamp_color, sizeof vec4
                lea rcx, lamp_model
                lea rdx, [rsi].point_light.position
                movf xmm2, 0.12
                call m4_translate_scale
                invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR lamp_model
                add rsi, sizeof point_light
                inc ebx
                cmp ebx, light_count
                jb lamps
        no_lamps:

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
