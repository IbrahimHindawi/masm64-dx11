;---------------------------------------------------------------------------------------------------
; 4.1 Lighting maps
;---------------------------------------------------------------------------------------------------
; One colour per material is too coarse for anything real: a crate is wood in one place and steel
; in another. So the material moves into textures.
;
;   diffuse map    the surface colour, per texel (also used for ambient)
;   specular map   how strongly each texel reflects highlights: the steel rim is bright, the wood
;                  is black and never shines
;
; The lighting barely changes; it reads its material from the textures at the pixel's texture
; coordinate instead of from constants.
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
; Mirrors `cbuffer light` in lighting_maps.hlsl.
light_constants struct
    position vec3 <>
    shininess real4 ?
    ambient vec3 <>
    pad1 real4 ?
    diffuse vec3 <>
    pad2 real4 ?
    specular vec3 <>
    pad3 real4 ?
light_constants ends

align 4
camera_start vec3 <-1.0, 1.0, 4.0>
y_axis vec3 <0.0, 1.0, 0.0>

align 16
t transforms <>
light light_constants <<1.2, 1.0, 2.0>, 64.0, <0.2, 0.2, 0.2>, 0.0, <0.5, 0.5, 0.5>, 0.0, <1.0, 1.0, 1.0>, 0.0>
lamp_color vec4 <1.0, 1.0, 1.0, 1.0>
model mat4 <>
lighting_shader shader <>
lamp_shader shader <>
cam camera <>
align 8
cube_vb qword 0
transforms_buffer qword 0
light_buffer qword 0
lamp_buffer qword 0
sampler qword 0
maps qword 2 dup(0)
stride dword cube_stride
offset_ dword 0

; timing
current_frame real4 0.0
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    invoke window_create, "LearnD3D11"
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    invoke shader_create, ADDR lighting_shader, "src/2.lighting/4.1.lighting_maps/lighting_maps.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR lamp_shader, "src/2.lighting/4.1.lighting_maps/light_cube.hlsl", ADDR cube_layout, cube_layout_count

    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof light_constants
    mov light_buffer, rax
    invoke create_constant_buffer, sizeof vec4
    mov lamp_buffer, rax
    ; the diffuse and specular maps, in t0 and t1
    invoke filesystem_path, "resources/textures/container2.png"
    invoke load_texture, rax, 0
    mov maps[0], rax
    invoke filesystem_path, "resources/textures/container2_specular.png"
    invoke load_texture, rax, 0
    mov maps[8], rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -75.0
    movf xmm3, -10.0
    call camera_create

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

        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR cube_vb, ADDR stride, ADDR offset_
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam

        invoke update_buffer, light_buffer, ADDR light, sizeof light_constants
        invoke shader_use, ADDR lighting_shader
        invoke bind_constants, 1, light_buffer
        vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 2, ADDR maps
        ; the crate turns slowly, so the steel rim catches the light
        movss xmm1, current_frame
        movf xmm0, 0.3
        mulss xmm1, xmm0
        lea rcx, model
        lea r8, y_axis
        call m4_rotate
        invoke draw_cube, transforms_buffer, ADDR t, ADDR model

        invoke update_buffer, lamp_buffer, ADDR lamp_color, sizeof vec4
        invoke shader_use, ADDR lamp_shader
        invoke bind_constants, 1, lamp_buffer
        lea rcx, model
        lea rdx, light.position
        movf xmm2, 0.2
        call m4_translate_scale
        invoke draw_cube, transforms_buffer, ADDR t, ADDR model

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
