;---------------------------------------------------------------------------------------------------
; 3.2 Point shadows
;---------------------------------------------------------------------------------------------------
; A point light shines in every direction, so one shadow map is not enough: it gets a cubemap of
; them, one face per axis. Each pixel looks up the face in the direction from the light to itself.
;
; Two changes from 3.1:
;
;   * one pass fills all six faces. The depth cubemap is bound as a six-slice array, and a geometry
;     shader copies every triangle six times, sending each copy to its slice with
;     SV_RenderTargetArrayIndex, through that face's view
;   * the map stores distance from the light, divided by the far plane, written by the pixel shader
;     through SV_Depth, rather than the projected depth. Comparing distances is the same in every
;     face
;
; The six face views are LearnOpenGL's, with one difference: a cubemap's faces are laid out
; left-handed, which a right-handed look-at cannot produce. GL's bottom-up framebuffer flips every
; rendered image and so fixes that for free; D3D's is top-down, so the face projection flips y
; instead (cube_face_matrices, includes/learn/shadow.asm). That flip reverses the winding, which is
; why culling stays off.
;
; The room is a large cube seen from inside, so its normals are flipped.
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
include learn\shadow.asm
include learn\srgb.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
; Mirror `cbuffer shadow` and `cbuffer surface` in point_shadows.hlsl.
shadow_constants struct
    faces mat4 6 dup(<>)        ; view-projection of each cube face
    light_position vec3 <>
    far_plane real4 ?
shadow_constants ends

surface_constants struct
    flip_normals real4 ?        ; -1 inside the room
    pad real4 3 dup(?)
surface_constants ends

shadow_size equ 1024

align 4
camera_start vec3 <3.0, 0.0, 2.0>
tilt_axis vec3 <1.0, 0.0, 1.0>
cube_place_a vec3 <4.0, -3.5, 0.0>
cube_place_b vec3 <2.0, 3.0, 1.0>
cube_place_c vec3 <-3.0, -1.0, 0.0>
cube_place_d vec3 <-1.5, 1.0, 1.5>
cube_place_e vec3 <-1.5, 2.0, -3.0>
room_size vec3 <10.0, 10.0, 10.0>
light_position vec3 <>

align 16
t transforms <>
sh shadow_constants <>
surface surface_constants <>
cubes mat4 5 dup(<>)
room mat4 <>
model mat4 <>
scratch mat4 <>
lamp_color vec4 <1.0, 1.0, 1.0, 1.0>
s shader <>
depth_shader shader <>
lamp_shader shader <>
cam camera <>
depth_map shadow_map <>
align 8
cube_vb qword 0
transforms_buffer qword 0
shadow_buffer qword 0
surface_buffer qword 0
lamp_buffer qword 0
wood qword 0
sampler qword 0
compare_sampler qword 0

; timing
current_frame real4 0.0
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; The five cubes inside the room, with whatever shader is bound.
align 16
draw_cubes proc
    USING rbx, rsi
    SaveRegs
    lea rsi, cubes
    xor ebx, ebx
    each_cube:
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, rsi
        add rsi, sizeof mat4
        inc ebx
        cmp ebx, 5
        jb each_cube
    RestoreRegs
    ret
draw_cubes endp

align 16
main proc
    invoke window_create, "LearnD3D11"
    ; The back buffer is viewed as sRGB: what the shaders write is linear, and the view
    ; gamma-encodes it on the way in (5.2).
    call window_use_srgb
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; build and compile shaders
    ; -------------------------
    invoke shader_create, ADDR s, "src/5.advanced_lighting/3.2.point_shadows/point_shadows.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR depth_shader, "src/5.advanced_lighting/3.2.point_shadows/point_shadows_depth.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR lamp_shader, "src/5.advanced_lighting/3.2.point_shadows/light_cube.hlsl", ADDR cube_layout, cube_layout_count

    ; set up vertex data and textures
    ; -------------------------------
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof shadow_constants
    mov shadow_buffer, rax
    invoke create_constant_buffer, sizeof surface_constants
    mov surface_buffer, rax
    invoke create_constant_buffer, sizeof vec4
    mov lamp_buffer, rax
    invoke filesystem_path, "resources/textures/wood.png"
    invoke load_texture, rax, 1
    mov wood, rax
    invoke create_depth_cube, ADDR depth_map, shadow_size
    call create_shadow_sampler
    mov compare_sampler, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -165.0
    movf xmm3, 0.0
    call camera_create

    ; five cubes around the room, and the room itself
    invoke m4_translate, ADDR cubes[0 * sizeof mat4], ADDR cube_place_a
    lea rcx, cubes[1 * sizeof mat4]
    lea rdx, cube_place_b
    movf xmm2, 1.5
    call m4_translate_scale
    invoke m4_translate, ADDR cubes[2 * sizeof mat4], ADDR cube_place_c
    invoke m4_translate, ADDR cubes[3 * sizeof mat4], ADDR cube_place_d
    ; translate(-1.5, 2, -3) * rotate(60 degrees, (1, 0, 1)) * scale(1.5)
    movf xmm0, 60.0
    call radians
    movaps xmm1, xmm0
    lea rcx, model
    lea r8, tilt_axis
    call m4_rotate
    invoke m4_identity, ADDR scratch
    storef scratch.m[0], 1.5
    storef scratch.m[20], 1.5
    storef scratch.m[40], 1.5
    invoke m4_mul, ADDR scratch, ADDR model, ADDR scratch
    invoke m4_translate, ADDR model, ADDR cube_place_e
    invoke m4_mul, ADDR cubes[4 * sizeof mat4], ADDR model, ADDR scratch
    invoke m4_scale, ADDR room, ADDR room_size
    storef sh.far_plane, 25.0

    render_loop:
        call window_poll
        test eax, eax
        jz render_loop_done

        ; per-frame time logic
        call get_time
        movss current_frame, xmm0
        movss xmm1, xmm0
        subss xmm0, last_frame
        movss delta_time, xmm0
        movss last_frame, xmm1

        invoke camera_process_input, ADDR cam, ADDR delta_time

        ; move light position over time: (0, 0, 3 sin(t / 2))
        movss xmm0, current_frame
        mulss xmm0, math_half
        call sinf
        movf xmm1, 3.0
        mulss xmm0, xmm1
        mov dword ptr light_position.x, 0
        mov dword ptr light_position.y, 0
        movss light_position.z, xmm0
        lea rcx, sh.faces
        lea rdx, light_position
        movf xmm2, 0.1
        movf xmm3, 25.0
        call cube_face_matrices
        v3load xmm0, light_position
        v3store sh.light_position, xmm0
        invoke update_buffer, shadow_buffer, ADDR sh, sizeof shadow_constants
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke bind_constants, 1, shadow_buffer

        ; 1. render scene to depth cubemap: all six faces in one pass
        ; -----------------------------------------------------------
        call unbind_textures
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 0, 0, depth_map.dsv
        movf xmm3, 1.0                          ; the depth, a float: xmm3
        vcall context, ID3D11DeviceContext_ClearDepthStencilView, depth_map.dsv, D3D11_CLEAR_DEPTH, 0, 0
        invoke set_viewport, shadow_size, shadow_size
        invoke shader_use, ADDR depth_shader
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR room
        call draw_cubes

        ; 2. render scene as normal
        ; -------------------------
        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke shader_use, ADDR s
        invoke bind_constants, 2, surface_buffer
        invoke bind_texture, 0, wood
        invoke bind_texture, 1, depth_map.srv
        vcall context, ID3D11DeviceContext_PSSetSamplers, 1, 1, ADDR compare_sampler
        ; the room, seen from inside, then the cubes
        storef surface.flip_normals, -1.0
        invoke update_buffer, surface_buffer, ADDR surface, sizeof surface_constants
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR room
        storef surface.flip_normals, 1.0
        invoke update_buffer, surface_buffer, ADDR surface, sizeof surface_constants
        call draw_cubes

        ; the lamp
        invoke update_buffer, lamp_buffer, ADDR lamp_color, sizeof vec4
        invoke shader_use, ADDR lamp_shader
        invoke bind_constants, 1, lamp_buffer
        lea rcx, model
        lea rdx, light_position
        movf xmm2, 0.2
        call m4_translate_scale
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
