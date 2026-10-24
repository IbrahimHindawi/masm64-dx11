;---------------------------------------------------------------------------------------------------
; 4. Normal mapping
;---------------------------------------------------------------------------------------------------
; Lighting depends on the normal, so a flat wall lit with its one flat normal looks flat whatever
; its texture shows. A normal map stores a normal per texel instead (the bluish image: xyz packed
; into rgb), so every brick and every mortar groove catches the light on its own.
;
; The map's normals are in tangent space: z out of the surface, x along u, y up the image. That
; keeps one map valid however the surface is turned. The vertex shader builds the three axes in
; world space, tangent, bitangent and normal (TBN), and the pixel shader turns the map's normal
; into world space through them before lighting as usual. create_wall (includes/learn/wall.asm)
; computes the tangent from how position and uv change along the triangle's edges.
;
;   Tab   normal map on / off
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
; Mirrors `cbuffer light` in normal_mapping.hlsl.
light_constants struct
    position vec3 <>
    use_map dword ?
light_constants ends

align 4
camera_start vec3 <0.0, 0.0, 3.0>
y_axis vec3 <0.0, 1.0, 0.0>

align 16
t transforms <>
light light_constants <>
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
maps qword 2 dup(0)
wall_vertex_stride dword wall_stride
wall_offset dword 0

; timing
current_frame real4 0.0
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    invoke window_create, "LearnD3D11  (Tab: normal map on / off)"
    ; The back buffer is viewed as sRGB: what the shaders write is linear, and the view
    ; gamma-encodes it on the way in (5.2).
    call window_use_srgb
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; build and compile shaders
    ; -------------------------
    invoke shader_create, ADDR s, "src/5.advanced_lighting/4.normal_mapping/normal_mapping.hlsl", ADDR wall_layout, wall_layout_count
    invoke shader_create, ADDR lamp_shader, "src/5.advanced_lighting/4.normal_mapping/light_cube.hlsl", ADDR cube_layout, cube_layout_count

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
    ; the bricks' colours (sRGB) and their normals (data, linear)
    invoke filesystem_path, "resources/textures/brickwall.jpg"
    invoke load_texture, rax, 1
    mov maps[0], rax
    invoke filesystem_path, "resources/textures/brickwall_normal.jpg"
    invoke load_texture, rax, 0
    mov maps[8], rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, 0.0
    call camera_create

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
        ; mode 0 uses the normal map, mode 1 the flat normal
        invoke window_mode, 2
        mov ecx, 1
        sub ecx, eax
        mov light.use_map, ecx

        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam

        ; the light wanders in front of the wall: (0.8 cos t, 0.8 sin 1.3t, 0.6)
        movss xmm0, current_frame
        call cosf
        movf xmm1, 0.8
        mulss xmm0, xmm1
        movss light.position.x, xmm0
        movss xmm0, current_frame
        movf xmm1, 1.3
        mulss xmm0, xmm1
        call sinf
        movf xmm1, 0.8
        mulss xmm0, xmm1
        movss light.position.y, xmm0
        storef light.position.z, 0.6
        invoke update_buffer, light_buffer, ADDR light, sizeof light_constants
        invoke shader_use, ADDR s
        invoke bind_constants, 1, light_buffer
        vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 2, ADDR maps

        ; the wall turns a little, back and forth: rotate(radians(-25) sin(0.4 t), y)
        movss xmm0, current_frame
        movf xmm1, 0.4
        mulss xmm0, xmm1
        call sinf
        movf xmm1, -25.0
        mulss xmm0, xmm1
        call radians
        movaps xmm1, xmm0
        lea rcx, t.model
        lea r8, y_axis
        call m4_rotate
        invoke m4_normal_matrix, ADDR t.normal_matrix, ADDR t.model
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
