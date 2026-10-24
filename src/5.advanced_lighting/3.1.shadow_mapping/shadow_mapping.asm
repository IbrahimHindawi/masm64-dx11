;---------------------------------------------------------------------------------------------------
; 3.1 Shadow mapping
;---------------------------------------------------------------------------------------------------
; A point is in shadow if something nearer to the light covers it. So: draw the scene once from the
; light, keeping only depth. That depth texture, the shadow map, records the nearest surface the
; light sees in every direction. Then draw normally, and for each pixel ask: transformed into the
; light's view, is this point farther than what the map recorded? Then it is behind something, and
; only ambient light reaches it.
;
; The sun is directional, so its view uses an orthographic projection: a box around the scene
; rather than a frustum.
;
; What D3D does for us here:
;
;   * the shadow map is one typeless texture seen two ways: as a depth buffer while it is drawn,
;     as a float texture while it is read (includes/learn/shadow.asm)
;   * shadow acne, a surface shadowing itself because the map's texels are coarser than the
;     screen's, is fixed by the rasterizer's slope-scaled depth bias during the shadow pass, not by
;     a constant in the shader
;   * the comparison sampler does the depth test and blends four texels of results inside
;     SampleCmp; 3x3 of those give soft edges (PCF)
;
;   Tab   the scene / the shadow map itself
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
align 4
plane_vertices label byte
    real4 -12.5, -0.5,  12.5,   0.0, 1.0, 0.0,    0.0, 12.0
    real4  12.5, -0.5,  12.5,   0.0, 1.0, 0.0,   12.0, 12.0
    real4  12.5, -0.5, -12.5,   0.0, 1.0, 0.0,   12.0,  0.0
    real4 -12.5, -0.5,  12.5,   0.0, 1.0, 0.0,    0.0, 12.0
    real4  12.5, -0.5, -12.5,   0.0, 1.0, 0.0,   12.0,  0.0
    real4 -12.5, -0.5, -12.5,   0.0, 1.0, 0.0,    0.0,  0.0
plane_vertices_size equ 6 * 32

; Mirrors `cbuffer shadow` in shadow_mapping.hlsl.
shadow_constants struct
    light_space mat4 <>
    light_direction vec3 <>     ; where the sunlight travels
    pad real4 ?
shadow_constants ends

shadow_size equ 2048

align 4
camera_start vec3 <-2.5, 3.0, 6.5>
origin vec3 <0.0, 0.0, 0.0>
up_axis vec3 <0.0, 1.0, 0.0>
tilt_axis vec3 <1.0, 0.0, 1.0>
cube_place_a vec3 <0.0, 1.5, 0.0>
cube_place_b vec3 <2.0, 0.0, 1.0>
cube_place_c vec3 <-1.0, 0.0, 2.0>
half_size vec3 <0.5, 0.5, 0.5>
light_position vec3 <>

align 16
t transforms <>
sh shadow_constants <>
cubes mat4 3 dup(<>)
light_view mat4 <>
light_projection mat4 <>
model mat4 <>
scratch mat4 <>
s shader <>
depth_shader shader <>
debug_shader shader <>
cam camera <>
depth_map shadow_map <>
align 8
cube_vb qword 0
plane_vb qword 0
transforms_buffer qword 0
shadow_buffer qword 0
wood qword 0
sampler qword 0
compare_sampler qword 0
bias_state qword 0

; timing
current_frame real4 0.0
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
; The floor and the three cubes, with whatever shader and view are bound.
align 16
draw_scene proc
    USING rbx, rsi
    SaveRegs
    invoke m4_identity, ADDR model
    invoke draw_vertices, transforms_buffer, ADDR t, plane_vb, 6, ADDR model
    lea rsi, cubes
    xor ebx, ebx
    each_cube:
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, rsi
        add rsi, sizeof mat4
        inc ebx
        cmp ebx, 3
        jb each_cube
    RestoreRegs
    ret
draw_scene endp

align 16
main proc
    invoke window_create, "LearnD3D11  (Tab: scene / shadow map)"
    ; The back buffer is viewed as sRGB: what the shaders write is linear, and the view
    ; gamma-encodes it on the way in (5.2).
    call window_use_srgb
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; The shadow pass's rasterizer: push depth away from the light, more on slopes seen at a
    ; grazing angle.
    call shadow_bias_state
    mov bias_state, rax

    ; build and compile shaders
    ; -------------------------
    invoke shader_create, ADDR s, "src/5.advanced_lighting/3.1.shadow_mapping/shadow_mapping.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR depth_shader, "src/5.advanced_lighting/3.1.shadow_mapping/shadow_mapping_depth.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR debug_shader, "src/5.advanced_lighting/3.1.shadow_mapping/debug_quad.hlsl", 0, 0

    ; set up vertex data and textures
    ; -------------------------------
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR plane_vertices, plane_vertices_size
    mov plane_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof shadow_constants
    mov shadow_buffer, rax
    invoke filesystem_path, "resources/textures/wood.png"
    invoke load_texture, rax, 1
    mov wood, rax
    invoke create_shadow_map, ADDR depth_map, shadow_size
    call create_shadow_sampler
    mov compare_sampler, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -65.0
    movf xmm3, -25.0
    call camera_create

    ; three cubes: one floating, one on the floor, one small and tilted
    invoke m4_translate, ADDR cubes[0], ADDR cube_place_a
    invoke m4_translate, ADDR cubes[sizeof mat4], ADDR cube_place_b
    invoke m4_scale, ADDR scratch, ADDR half_size
    movf xmm0, 60.0
    call radians
    movaps xmm1, xmm0
    lea rcx, model
    lea r8, tilt_axis
    call m4_rotate
    invoke m4_mul, ADDR scratch, ADDR model, ADDR scratch
    invoke m4_translate, ADDR model, ADDR cube_place_c
    invoke m4_mul, ADDR cubes[2 * sizeof mat4], ADDR model, ADDR scratch

    ; The sun's view never changes shape: a 20 x 20 box, 1 to 20 units from it.
    movf xmm0, 10.0
    movss real4 ptr [rsp + 32], xmm0        ; top
    movf xmm0, 1.0
    movss real4 ptr [rsp + 40], xmm0        ; z_near
    movf xmm0, 20.0
    movss real4 ptr [rsp + 48], xmm0        ; z_far
    lea rcx, light_projection
    movf xmm1, -10.0                        ; left
    movf xmm2, 10.0                         ; right
    movf xmm3, -10.0                        ; bottom
    call m4_ortho

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
        invoke window_mode, 2
        mov ebx, eax                            ; 1: show the shadow map

        ; the sun circles slowly, so the shadows sweep across the floor:
        ; (-4 cos(0.3 t), 8, -2 - 2 sin(0.3 t))
        movss xmm0, current_frame
        movf xmm1, 0.3
        mulss xmm0, xmm1
        call cosf
        movf xmm1, -4.0
        mulss xmm0, xmm1
        movss light_position.x, xmm0
        storef light_position.y, 8.0
        movss xmm0, current_frame
        movf xmm1, 0.3
        mulss xmm0, xmm1
        call sinf
        movf xmm1, -2.0
        mulss xmm0, xmm1
        addss xmm0, xmm1
        movss light_position.z, xmm0
        invoke m4_look_at, ADDR light_view, ADDR light_position, ADDR origin, ADDR up_axis
        invoke m4_mul, ADDR sh.light_space, ADDR light_projection, ADDR light_view
        ; light_direction = normalize(-light_position)
        lea rcx, sh.light_direction
        lea rdx, light_position
        movf xmm2, -1.0
        call v3_scale
        lea rcx, sh.light_direction
        mov rdx, rcx
        call v3_normalize
        invoke update_buffer, shadow_buffer, ADDR sh, sizeof shadow_constants
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer

        ; 1. render depth of scene to texture (from light's perspective)
        ; --------------------------------------------------------------
        call unbind_textures
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 0, 0, depth_map.dsv
        movf xmm3, 1.0                          ; the depth, a float: xmm3
        vcall context, ID3D11DeviceContext_ClearDepthStencilView, depth_map.dsv, D3D11_CLEAR_DEPTH, 0, 0
        invoke set_viewport, shadow_size, shadow_size
        vcall context, ID3D11DeviceContext_RSSetState, bias_state
        invoke mem_copy, ADDR t.view, ADDR light_view, sizeof mat4
        invoke mem_copy, ADDR t.projection, ADDR light_projection, sizeof mat4
        invoke shader_use, ADDR depth_shader
        call draw_scene
        vcall context, ID3D11DeviceContext_RSSetState, raster_state

        ; 2. render scene as normal using the generated depth/shadow map
        ; --------------------------------------------------------------
        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        test ebx, ebx
        jz scene
            invoke shader_use, ADDR debug_shader
            invoke bind_texture, 0, depth_map.srv
            vcall context, ID3D11DeviceContext_Draw, 3, 0
            jmp drawn
        scene:
            invoke transforms_from_camera, ADDR t, ADDR cam
            invoke shader_use, ADDR s
            invoke bind_constants, 1, shadow_buffer
            invoke bind_texture, 0, wood
            invoke bind_texture, 1, depth_map.srv
            vcall context, ID3D11DeviceContext_PSSetSamplers, 1, 1, ADDR compare_sampler
            call draw_scene
        drawn:

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
