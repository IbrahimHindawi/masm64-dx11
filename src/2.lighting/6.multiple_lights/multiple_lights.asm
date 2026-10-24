;---------------------------------------------------------------------------------------------------
; 6. Multiple lights
;---------------------------------------------------------------------------------------------------
; Light adds up. Each source is worked out on its own and the results are summed: one directional
; light, four coloured point lights and the camera's flashlight, all from the functions of 5.1.
;
; The point lights travel to the shader as an array inside a constant buffer. HLSL starts every
; array element on a 16-byte boundary, so `point_light` pads each vec3 to sixteen bytes to match.
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
point_light struct
    position vec3 <>
    pad0 real4 ?
    color vec3 <>
    pad1 real4 ?
point_light ends

; Mirrors `cbuffer lights` in multiple_lights.hlsl.
lights_constants struct
    sun_direction vec3 <>
    shininess real4 ?
    sun_color vec3 <>
    pad0 real4 ?
    spot_position vec3 <>
    spot_inner_cos real4 ?
    spot_direction vec3 <>
    spot_outer_cos real4 ?
    points point_light 4 dup(<>)
lights_constants ends

align 4
camera_start vec3 <0.0, 0.5, 4.0>

align 16
t transforms <>
lights lights_constants <>
; the sun, and the four point lights with where they are and their colour, copied into `lights` at
; startup (MASM cannot initialize an array of structures inside a structure)
sun_direction vec3 <-0.2, -1.0, -0.3>
sun_color vec3 <0.4, 0.4, 0.45>
point_lights point_light <<0.7, 0.2, 2.0>, 0.0, <1.0, 0.6, 0.0>, 0.0>
             point_light <<2.3, -3.3, -4.0>, 0.0, <1.0, 0.0, 0.0>, 0.0>
             point_light <<-4.0, 2.0, -12.0>, 0.0, <1.0, 1.0, 0.0>, 0.0>
             point_light <<0.0, 0.0, -3.0>, 0.0, <0.2, 0.2, 1.0>, 0.0>
lamp_color vec4 <0.0, 0.0, 0.0, 1.0>
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
    USING rbx, rsi
    SaveRegs
    invoke window_create, "LearnD3D11"
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    invoke shader_create, ADDR lighting_shader, "src/2.lighting/6.multiple_lights/multiple_lights.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR lamp_shader, "src/2.lighting/6.multiple_lights/light_cube.hlsl", ADDR cube_layout, cube_layout_count

    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof lights_constants
    mov light_buffer, rax
    invoke create_constant_buffer, sizeof vec4
    mov lamp_buffer, rax
    invoke filesystem_path, "resources/textures/container2.png"
    invoke load_texture, rax, 0
    mov maps[0], rax
    invoke filesystem_path, "resources/textures/container2_specular.png"
    invoke load_texture, rax, 0
    mov maps[8], rax

    v3load xmm0, sun_direction
    v3store lights.sun_direction, xmm0
    v3load xmm0, sun_color
    v3store lights.sun_color, xmm0
    storef lights.shininess, 32.0
    invoke mem_copy, ADDR lights.points, ADDR point_lights, 4 * sizeof point_light

    ; the flashlight's cone: 12.5 degrees fully lit, fading out by 15
    movf xmm0, 12.5
    call radians
    call cosf
    movss lights.spot_inner_cos, xmm0
    movf xmm0, 15.0
    call radians
    call cosf
    movss lights.spot_outer_cos, xmm0

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
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

        invoke window_begin, floats(0.05, 0.05, 0.05, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR cube_vb, ADDR stride, ADDR offset_
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam

        ; the flashlight goes where the camera does
        v3load xmm0, cam.position
        v3store lights.spot_position, xmm0
        v3load xmm0, cam.front
        v3store lights.spot_direction, xmm0
        invoke update_buffer, light_buffer, ADDR lights, sizeof lights_constants
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

        ; a lamp at each point light, in its colour
        invoke shader_use, ADDR lamp_shader
        invoke bind_constants, 1, lamp_buffer
        lea rsi, lights.points
        xor ebx, ebx
        lamps:
            v3load xmm0, [rsi].point_light.color
            v3store lamp_color, xmm0
            invoke update_buffer, lamp_buffer, ADDR lamp_color, sizeof vec4
            lea rcx, model
            lea rdx, [rsi].point_light.position
            movf xmm2, 0.2
            call m4_translate_scale
            invoke draw_cube, transforms_buffer, ADDR t, ADDR model
            add rsi, sizeof point_light
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
