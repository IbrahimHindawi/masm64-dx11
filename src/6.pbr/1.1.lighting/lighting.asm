;---------------------------------------------------------------------------------------------------
; 1.1 PBR lighting
;---------------------------------------------------------------------------------------------------
; Physically based rendering replaces Phong's hand-tuned terms with a model of how light actually
; reflects off a rough surface: Cook-Torrance. A material is no longer "diffuse colour, specular
; colour, shininess" but:
;
;   albedo     the base colour
;   metallic   0 for dielectrics (plastic, wood), 1 for metals
;   roughness  0 a mirror, 1 completely matte
;   ao         how much ambient light reaches it, baked in
;
; Energy is conserved: whatever a surface reflects as specular it cannot also scatter as diffuse.
; The lights are given as radiance in real units, far above 1, so the result is tone mapped
; (Reinhard) and gamma encoded on the way out.
;
; The grid runs metallic 0 -> 1 from bottom to top, roughness 0 -> 1 from left to right. Tab swaps
; in a textured material, where every one of those numbers comes from a map per texel: rusted iron
; (LearnOpenGL's 1.2 lighting_textured). The normal map is read without stored tangents: the
; tangent frame is rebuilt per pixel from screen-space derivatives.
;
;   Tab   uniform grid / textured spheres
;
; The sphere, the material loader and the sRGB backbuffer view are in includes/learn/pbr.asm,
; which the rest of the chapter shares.
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
include learn\pbr.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
; Mirror `cbuffer material` and `cbuffer lights` in pbr.hlsl.
material_constants struct
    albedo vec3 <>
    metallic real4 ?
    roughness real4 ?
    ao real4 ?
    textured dword ?
    pad real4 ?
material_constants ends

lights_constants struct
    positions vec4 4 dup(<>)
    colors vec4 4 dup(<>)
lights_constants ends

align 4
camera_start vec3 <0.0, 0.0, 22.0>
; four lights at the corners of a square in front of the grid, far brighter than 1
light_start vec4 <-10.0, 10.0, 10.0, 0.0>, <10.0, 10.0, 10.0, 0.0>, <-10.0, -10.0, 10.0, 0.0>, <10.0, -10.0, 10.0, 0.0>
light_color vec4 <300.0, 300.0, 300.0, 0.0>

align 16
t transforms <>
lights lights_constants <>
material material_constants <<0.5, 0.0, 0.0>, 0.0, 0.0, 1.0, 0, 0.0>
model_matrix mat4 <>
sphere_position vec3 <>
s shader <>
cam camera <>
ball sphere <>
align 8
transforms_buffer qword 0
material_buffer qword 0
lights_buffer qword 0
sampler qword 0
rusted_iron qword 5 dup(0)

; timing
current_frame real4 0.0
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    USING rbx, rsi
    SaveRegs
    invoke window_create, "LearnD3D11  (Tab: uniform grid / textured)"
    call window_create_depth
    call window_use_srgb

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; build and compile shaders
    ; -------------------------
    invoke shader_create, ADDR s, "src/6.pbr/1.1.lighting/pbr.hlsl", ADDR cube_layout, cube_layout_count

    ; set up vertex data and textures
    ; -------------------------------
    invoke create_sphere, ADDR ball, 64
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof material_constants
    mov material_buffer, rax
    invoke create_constant_buffer, sizeof lights_constants
    mov lights_buffer, rax
    invoke load_material, "resources/textures/pbr/rusted_iron/", ADDR rusted_iron

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, 0.0
    call camera_create

    ; lights
    ; ------
    invoke mem_copy, ADDR lights.positions, ADDR light_start, 4 * sizeof vec4
    movups xmm0, xmmword ptr light_color
    movups xmmword ptr lights.colors[0], xmm0
    movups xmmword ptr lights.colors[16], xmm0
    movups xmmword ptr lights.colors[32], xmm0
    movups xmmword ptr lights.colors[48], xmm0

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

        ; input
        invoke camera_process_input, ADDR cam, ADDR delta_time
        invoke window_mode, 2
        mov material.textured, eax

        ; render
        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam

        ; the lights wander a little, so the highlights move across the spheres:
        ; x = -10 or 10, + 5 sin(t)
        movss xmm0, current_frame
        call sinf
        movf xmm1, 5.0
        mulss xmm0, xmm1
        lea rax, lights.positions
        lea rdx, light_start
        xor ecx, ecx
        wander:
            movss xmm1, real4 ptr [rdx]
            addss xmm1, xmm0
            movss real4 ptr [rax], xmm1
            add rax, sizeof vec4
            add rdx, sizeof vec4
            inc ecx
            cmp ecx, 4
            jb wander
        invoke update_buffer, lights_buffer, ADDR lights, sizeof lights_constants
        invoke shader_use, ADDR s
        invoke bind_constants, 1, material_buffer
        invoke bind_constants, 2, lights_buffer
        vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 5, ADDR rusted_iron

        ; render rows*column number of spheres with varying metallic/roughness values:
        ; metallic from bottom to top, roughness from left to right
        xor ebx, ebx                            ; row
        grid_rows:
            xor esi, esi                        ; column
            grid_columns:
                cvtsi2ss xmm0, ebx
                movf xmm1, 6.0
                divss xmm0, xmm1
                movss material.metallic, xmm0
                ; perfectly smooth reflects one point of light, which looks wrong for a point
                ; light: start just above zero
                cvtsi2ss xmm0, esi
                movf xmm1, 6.0
                divss xmm0, xmm1
                movf xmm1, 0.05
                movss xmm2, math_one
                call clampf
                movss material.roughness, xmm0
                invoke update_buffer, material_buffer, ADDR material, sizeof material_constants
                ; at ((column - 3) * 2.5, (row - 3) * 2.5, 0)
                movf xmm1, 2.5
                lea eax, [esi - 3]
                cvtsi2ss xmm0, eax
                mulss xmm0, xmm1
                movss sphere_position.x, xmm0
                lea eax, [ebx - 3]
                cvtsi2ss xmm0, eax
                mulss xmm0, xmm1
                movss sphere_position.y, xmm0
                mov dword ptr sphere_position.z, 0
                invoke m4_translate, ADDR model_matrix, ADDR sphere_position
                invoke draw_sphere, transforms_buffer, ADDR t, ADDR ball, ADDR model_matrix
                inc esi
                cmp esi, 7
                jb grid_columns
            inc ebx
            cmp ebx, 7
            jb grid_rows

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
