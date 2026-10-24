;---------------------------------------------------------------------------------------------------
; 5.1 Parallax mapping
;---------------------------------------------------------------------------------------------------
; Normal mapping changes how a flat surface is lit, but not where its texture appears: seen at an
; angle, the bricks still look painted on. A depth map (how far below the surface each texel is)
; lets the pixel shader shift the texture coordinate to where the eye ray would really have hit the
; sunken surface. Near bricks then hide the mortar behind them.
;
;   1 normal mapping only
;   2 parallax           one shift, by the depth at the original point. Cheap; falls apart at
;                        steep angles
;   3 steep parallax     walk along the eye ray in layers until it goes below the surface.
;                        Correct, but shows the layers
;   4 occlusion          as 3, then interpolate between the last two layers
;
; Everything happens in tangent space, where the surface is the xy plane and depth is -z, so the
; eye direction is turned into it first. The wall is 4. normal mapping's, from includes/learn/wall.asm.
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
include learn\wall.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
; Mirrors `cbuffer light` in parallax_mapping.hlsl.
light_constants struct
    position vec3 <>
    mode dword ?            ; 1 normal only, 2 parallax, 3 steep, 4 occlusion
light_constants ends

align 4
camera_start vec3 <1.3, 0.2, 2.2>

align 16
t transforms <>
light light_constants <<0.5, 1.0, 0.3>, 4>
lamp_color vec4 <1.0, 1.0, 1.0, 1.0>
model mat4 <>
s shader <>
lamp_shader shader <>
cam camera <>
align 8
cube_vb qword 0
wall_vb qword 0
transforms_buffer qword 0
light_buffer qword 0
lamp_buffer qword 0
sampler qword 0
maps qword 3 dup(0)
wall_vertex_stride dword wall_stride
wall_offset dword 0

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    invoke window_create, "LearnD3D11  (1 normal, 2 parallax, 3 steep, 4 occlusion)"
    ; The back buffer is viewed as sRGB: what the shaders write is linear, and the view
    ; gamma-encodes it on the way in (5.2).
    call window_use_srgb
    call window_create_depth
    invoke window_mode_default, 3               ; parallax occlusion

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; build and compile shaders
    ; -------------------------
    invoke shader_create, ADDR s, "src/5.advanced_lighting/5.1.parallax_mapping/parallax_mapping.hlsl", ADDR wall_layout, wall_layout_count
    invoke shader_create, ADDR lamp_shader, "src/5.advanced_lighting/5.1.parallax_mapping/light_cube.hlsl", ADDR cube_layout, cube_layout_count

    ; set up vertex data and textures
    ; -------------------------------
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    call create_wall
    mov wall_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof light_constants
    mov light_buffer, rax
    invoke create_constant_buffer, sizeof vec4
    mov lamp_buffer, rax
    ; colour (sRGB), normals and depth (data, linear)
    invoke filesystem_path, "resources/textures/bricks2.jpg"
    invoke load_texture, rax, 1
    mov maps[0], rax
    invoke filesystem_path, "resources/textures/bricks2_normal.jpg"
    invoke load_texture, rax, 0
    mov maps[8], rax
    invoke filesystem_path, "resources/textures/bricks2_disp.jpg"
    invoke load_texture, rax, 0
    mov maps[16], rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -120.0
    movf xmm3, -5.0
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
        invoke window_mode, 4
        inc eax
        mov light.mode, eax

        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam

        invoke update_buffer, light_buffer, ADDR light, sizeof light_constants
        invoke shader_use, ADDR s
        invoke bind_constants, 1, light_buffer
        vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 3, ADDR maps

        ; the wall, where it was made
        invoke m4_identity, ADDR t.model
        invoke m4_identity, ADDR t.normal_matrix
        invoke update_buffer, transforms_buffer, ADDR t, sizeof transforms
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR wall_vb, ADDR wall_vertex_stride, ADDR wall_offset
        vcall context, ID3D11DeviceContext_Draw, 6, 0

        ; the lamp
        invoke update_buffer, lamp_buffer, ADDR lamp_color, sizeof vec4
        invoke shader_use, ADDR lamp_shader
        invoke bind_constants, 1, lamp_buffer
        lea rcx, model
        lea rdx, light.position
        movf xmm2, 0.05
        call m4_translate_scale
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
