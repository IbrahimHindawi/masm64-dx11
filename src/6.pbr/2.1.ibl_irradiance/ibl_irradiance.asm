;---------------------------------------------------------------------------------------------------
; 2.1 IBL: diffuse irradiance
;---------------------------------------------------------------------------------------------------
; Real objects are lit by everything around them, not by four points. Image based lighting takes
; "everything around" from an HDR photograph of a real place, and lets every pixel be lit by all of
; it.
;
; For diffuse light that means: for each normal, the cosine-weighted average of the whole
; hemisphere it faces. That is far too much to sum per pixel per frame, but it depends only on the
; normal, so it is computed once at startup into a small cubemap, the irradiance map, and looked up
; by normal:
;
;   1. the photo, stored equirectangular (a world map of directions), is drawn onto the six faces
;      of a cubemap
;   2. that cubemap is convolved into a 32x32 irradiance cubemap
;
; The spheres keep the four point lights of 1.1 and add the environment as their ambient term; the
; photo itself is drawn behind them. (LearnOpenGL's 2.1.1 conversion step is the first half of
; this program.)
;
; Both steps are render_to_cube (includes/learn/pbr.asm): the unit cube drawn once per face of the
; target, through a 90-degree view out of that face, with the step's shader.
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
light_start vec4 <-10.0, 10.0, 10.0, 0.0>, <10.0, 10.0, 10.0, 0.0>, <-10.0, -10.0, 10.0, 0.0>, <10.0, -10.0, 10.0, 0.0>
light_color vec4 <300.0, 300.0, 300.0, 0.0>

align 16
t transforms <>
lights lights_constants <>
material material_constants <<0.5, 0.0, 0.0>, 0.0, 0.0, 1.0, 0, 0.0>
model_matrix mat4 <>
sphere_position vec3 <>
pbr_shader shader <>
equirect_shader shader <>
irradiance_shader shader <>
background_shader shader <>
cam camera <>
ball sphere <>
env_cubemap cube_target <>
irradiance_map cube_target <>
align 8
cube_vb qword 0
transforms_buffer qword 0
material_buffer qword 0
lights_buffer qword 0
wrap_sampler qword 0
clamp_sampler qword 0
sky_depth qword 0
hdr_texture qword 0

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    local sky_depth_desc:D3D11_DEPTH_STENCIL_DESC
    USING rbx, rsi
    SaveRegs
    invoke window_create, "LearnD3D11"
    call window_create_depth
    call window_use_srgb

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov wrap_sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR wrap_sampler

    ; build and compile shaders
    ; -------------------------
    invoke shader_create, ADDR pbr_shader, "src/6.pbr/2.1.ibl_irradiance/pbr.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR equirect_shader, "src/6.pbr/2.1.ibl_irradiance/equirectangular_to_cubemap.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR irradiance_shader, "src/6.pbr/2.1.ibl_irradiance/irradiance_convolution.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR background_shader, "src/6.pbr/2.1.ibl_irradiance/background.hlsl", ADDR cube_layout, cube_layout_count

    ; pbr: the samplers the precomputation passes and the spheres share
    invoke create_sampler, D3D11_FILTER_MIN_MAG_MIP_LINEAR, D3D11_TEXTURE_ADDRESS_CLAMP
    mov clamp_sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 1, 1, ADDR clamp_sampler
    ; The sky is drawn last, at the far plane: it passes where nothing else was drawn, and leaves the
    ; depth buffer alone.
    invoke mem_zero, ADDR sky_depth_desc, sizeof D3D11_DEPTH_STENCIL_DESC
    mov sky_depth_desc.DepthEnable, 1
    mov sky_depth_desc.DepthWriteMask, D3D11_DEPTH_WRITE_MASK_ZERO
    mov sky_depth_desc.DepthFunc, D3D11_COMPARISON_LESS_EQUAL
    vcall device, ID3D11Device_CreateDepthStencilState, ADDR sky_depth_desc, ADDR sky_depth

    ; set up vertex data
    ; ------------------
    invoke create_sphere, ADDR ball, 64
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof material_constants
    mov material_buffer, rax
    invoke create_constant_buffer, sizeof lights_constants
    mov lights_buffer, rax
    vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
    invoke bind_constants, 0, transforms_buffer

    ; pbr: load the HDR environment map
    ; ---------------------------------
    invoke filesystem_path, "resources/textures/hdr/newport_loft.hdr"
    invoke load_hdr, rax
    mov hdr_texture, rax

    ; pbr: convert the equirectangular map to a cubemap, with mipmaps (the prefilter reads them to
    ; avoid sparkle from small, very bright spots)
    ; --------------------------------------------------------------------------------------------
    invoke create_cube_target, ADDR env_cubemap, 512, 0, 1
    invoke shader_use, ADDR equirect_shader
    invoke bind_texture, 0, hdr_texture
    invoke render_to_cube, ADDR env_cubemap, 0, transforms_buffer, cube_vb
    call unbind_textures
    vcall context, ID3D11DeviceContext_GenerateMips, env_cubemap.srv

    ; pbr: an irradiance cubemap, by convolving the environment
    ; ---------------------------------------------------------
    invoke create_cube_target, ADDR irradiance_map, 32, 1, 0
    invoke shader_use, ADDR irradiance_shader
    invoke bind_texture, 0, env_cubemap.srv
    invoke render_to_cube, ADDR irradiance_map, 0, transforms_buffer, cube_vb
    call unbind_textures

    ; lights
    ; ------
    invoke mem_copy, ADDR lights.positions, ADDR light_start, 4 * sizeof vec4
    movups xmm0, xmmword ptr light_color
    movups xmmword ptr lights.colors[0], xmm0
    movups xmmword ptr lights.colors[16], xmm0
    movups xmmword ptr lights.colors[32], xmm0
    movups xmmword ptr lights.colors[48], xmm0
    invoke update_buffer, lights_buffer, ADDR lights, sizeof lights_constants

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
        movss xmm1, xmm0
        subss xmm0, last_frame
        movss delta_time, xmm0
        movss last_frame, xmm1

        ; input
        invoke camera_process_input, ADDR cam, ADDR delta_time

        ; render
        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke shader_use, ADDR pbr_shader
        invoke bind_constants, 1, material_buffer
        invoke bind_constants, 2, lights_buffer
        invoke bind_texture, 0, irradiance_map.srv

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

        ; render skybox (render as last to prevent overdraw)
        invoke shader_use, ADDR background_shader
        invoke bind_texture, 0, env_cubemap.srv
        vcall context, ID3D11DeviceContext_OMSetDepthStencilState, sky_depth, 0
        invoke m4_identity, ADDR model_matrix
        invoke draw_vertices, transforms_buffer, ADDR t, cube_vb, 36, ADDR model_matrix
        vcall context, ID3D11DeviceContext_OMSetDepthStencilState, 0, 0

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
