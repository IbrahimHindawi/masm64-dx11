;---------------------------------------------------------------------------------------------------
; 5.1 Light casters
;---------------------------------------------------------------------------------------------------
; Three kinds of light, which differ only in how each pixel finds the direction to the light and
; how much of it arrives:
;
;   1 directional  infinitely far, like the sun: one direction for every pixel, no falloff
;   2 point        a position, light spreading out from it and fading with distance:
;                  1 / (constant + linear * d + quadratic * d^2)
;   3 spot         a point light inside a cone, here a flashlight held by the camera. Between an
;                  inner and an outer angle the edge fades, so the circle is soft rather than cut
;                  out
;
; Keys 1, 2 and 3 (or Tab) switch between them.
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
; Mirrors `cbuffer light` in light_casters.hlsl.
light_constants struct
    position vec3 <>
    mode dword ?            ; 1 directional, 2 point, 3 spot
    direction vec3 <>
    inner_cos real4 ?       ; cosines, so the shader compares without an acos
    ambient vec3 <>
    outer_cos real4 ?
    diffuse vec3 <>
    shininess real4 ?
    specular vec3 <>
    pad real4 ?
light_constants ends

align 4
camera_start vec3 <0.0, 0.0, 3.0>
point_position vec3 <1.2, 1.0, 2.0>
sun_direction vec3 <-0.2, -1.0, -0.3>

align 16
t transforms <>
light light_constants <<>, 0, <>, 0.0, <0.1, 0.1, 0.1>, 0.0, <0.8, 0.8, 0.8>, 32.0, <1.0, 1.0, 1.0>, 0.0>
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
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    USING rbx
    SaveRegs
    invoke window_create, "LearnD3D11"
    call window_create_depth
    invoke window_mode_default, 2               ; starts as the flashlight

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    invoke shader_create, ADDR lighting_shader, "src/2.lighting/5.1.light_casters/light_casters.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR lamp_shader, "src/2.lighting/5.1.light_casters/light_cube.hlsl", ADDR cube_layout, cube_layout_count

    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof light_constants
    mov light_buffer, rax
    invoke create_constant_buffer, sizeof vec4
    mov lamp_buffer, rax
    invoke filesystem_path, "resources/textures/container2.png"
    invoke load_texture, rax, 0
    mov maps[0], rax
    invoke filesystem_path, "resources/textures/container2_specular.png"
    invoke load_texture, rax, 0
    mov maps[8], rax

    ; the spot's cone: 12.5 degrees fully lit, fading out by 17.5
    movf xmm0, 12.5
    call radians
    call cosf
    movss light.inner_cos, xmm0
    movf xmm0, 17.5
    call radians
    call cosf
    movss light.outer_cos, xmm0

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, 0.0
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
        invoke window_mode, 3
        inc eax
        mov light.mode, eax

        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR cube_vb, ADDR stride, ADDR offset_
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam

        ; the point light sits still; the sun shines one way; the flashlight is the camera
        v3load xmm0, point_position
        v3store light.position, xmm0
        v3load xmm0, sun_direction
        v3store light.direction, xmm0
        cmp light.mode, 3
        jne not_spot
            v3load xmm0, cam.position
            v3store light.position, xmm0
            v3load xmm0, cam.front
            v3store light.direction, xmm0
        not_spot:
        invoke update_buffer, light_buffer, ADDR light, sizeof light_constants
        invoke shader_use, ADDR lighting_shader
        invoke bind_constants, 1, light_buffer
        vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 2, ADDR maps
        xor ebx, ebx
        cubes:
            invoke cube_model, ADDR model, rbx
            invoke draw_cube, transforms_buffer, ADDR t, ADDR model
            inc ebx
            cmp ebx, 10
            jb cubes

        ; only the point light is somewhere to draw a lamp
        cmp light.mode, 2
        jne no_lamp
            invoke update_buffer, lamp_buffer, ADDR lamp_color, sizeof vec4
            invoke shader_use, ADDR lamp_shader
            invoke bind_constants, 1, lamp_buffer
            lea rcx, model
            lea rdx, point_position
            movf xmm2, 0.2
            call m4_translate_scale
            invoke draw_cube, transforms_buffer, ADDR t, ADDR model
        no_lamp:

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
