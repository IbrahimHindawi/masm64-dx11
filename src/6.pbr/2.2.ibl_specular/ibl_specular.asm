;---------------------------------------------------------------------------------------------------
; 2.2 IBL: specular
;---------------------------------------------------------------------------------------------------
; The other half of image based light: reflections. The specular integral depends on the view
; direction as well as the surface, which is too much to tabulate, so it is split into two parts
; that can be ("split sum"):
;
;   prefiltered environment   the environment blurred by the GGX lobe, one mip level per roughness,
;                             looked up along the reflection vector. Built by importance sampling:
;                             1024 directions per texel, put where the lobe is
;   BRDF table                a 2D texture over (n.v, roughness) giving a scale and a bias for the
;                             surface's F0
;
;   specular = prefiltered(R, roughness) * (F0 * scale + bias)
;
; With the diffuse irradiance of 2.1 that is the full lighting model: smooth metals now mirror the
; room, rough ones blur it, and plastics pick up a faint reflection at grazing angles. Tab shows
; five textured materials (LearnOpenGL's 2.2.2 ibl_specular_textured).
;
;   Tab   uniform grid / five textured materials
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
; Mirror `cbuffer material` and `cbuffer lights` in pbr.hlsl, and `cbuffer prefilter` in
; prefilter.hlsl.
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

prefilter_constants struct
    roughness real4 ?
    env_size real4 ?        ; of the environment's top mip, per face
    pad real4 2 dup(?)
prefilter_constants ends

align 4
light_start vec4 <-10.0, 10.0, 10.0, 0.0>, <10.0, 10.0, 10.0, 0.0>, <-10.0, -10.0, 10.0, 0.0>, <10.0, -10.0, 10.0, 0.0>
light_color vec4 <300.0, 300.0, 300.0, 0.0>
camera_grid vec3 <0.0, 0.0, 22.0>       ; far enough back for the grid
camera_row vec3 <0.0, 0.0, 9.0>         ; closer, for the row of five

; the five materials of the textured view
folder_rusted_iron byte "resources/textures/pbr/rusted_iron/", 0
folder_gold byte "resources/textures/pbr/gold/", 0
folder_grass byte "resources/textures/pbr/grass/", 0
folder_plastic byte "resources/textures/pbr/plastic/", 0
folder_wall byte "resources/textures/pbr/wall/", 0
align 8
material_folders qword offset folder_rusted_iron, offset folder_gold, offset folder_grass
                 qword offset folder_plastic, offset folder_wall

align 16
t transforms <>
lights lights_constants <>
material material_constants <<0.5, 0.0, 0.0>, 0.0, 0.0, 1.0, 0, 0.0>
settings prefilter_constants <0.0, 512.0, {0.0, 0.0}>
model_matrix mat4 <>
sphere_position vec3 <>
pbr_shader shader <>
equirect_shader shader <>
irradiance_shader shader <>
prefilter_shader shader <>
brdf_shader shader <>
background_shader shader <>
cam camera <>
ball sphere <>
env_cubemap cube_target <>
irradiance_map cube_target <>
prefilter_map cube_target <>
align 8
cube_vb qword 0
transforms_buffer qword 0
material_buffer qword 0
lights_buffer qword 0
prefilter_buffer qword 0
wrap_sampler qword 0
clamp_sampler qword 0
sky_depth qword 0
hdr_texture qword 0
lut_texture qword 0
lut_rtv qword 0
ibl_views qword 3 dup(0)                ; irradiance, prefiltered, BRDF table: t5, t6, t7
materials qword 25 dup(0)               ; five maps for each of the five materials
framed_mode dword -1                    ; the mode the camera was last framed for

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    local sky_depth_desc:D3D11_DEPTH_STENCIL_DESC, lut_desc:D3D11_TEXTURE2D_DESC
    USING rbx, rsi
    SaveRegs
    invoke window_create, "LearnD3D11  (Tab: uniform grid / textured)"
    call window_create_depth
    call window_use_srgb

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov wrap_sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR wrap_sampler

    ; build and compile shaders
    ; -------------------------
    invoke shader_create, ADDR pbr_shader, "src/6.pbr/2.2.ibl_specular/pbr.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR equirect_shader, "src/6.pbr/2.2.ibl_specular/equirectangular_to_cubemap.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR irradiance_shader, "src/6.pbr/2.2.ibl_specular/irradiance_convolution.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR prefilter_shader, "src/6.pbr/2.2.ibl_specular/prefilter.hlsl", ADDR cube_layout, cube_layout_count
    ; the BRDF table's shader makes its own triangle: no input layout
    invoke shader_create, ADDR brdf_shader, "src/6.pbr/2.2.ibl_specular/brdf.hlsl", 0, 0
    invoke shader_create, ADDR background_shader, "src/6.pbr/2.2.ibl_specular/background.hlsl", ADDR cube_layout, cube_layout_count

    ; pbr: the samplers the precomputation passes and the spheres share
    invoke create_sampler, D3D11_FILTER_MIN_MAG_MIP_LINEAR, D3D11_TEXTURE_ADDRESS_CLAMP
    mov clamp_sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 1, 1, ADDR clamp_sampler
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

    ; pbr: a prefiltered environment cubemap, roughness rising one step per mip
    ; -------------------------------------------------------------------------
    invoke create_cube_target, ADDR prefilter_map, 128, 5, 0
    invoke create_constant_buffer, sizeof prefilter_constants
    mov prefilter_buffer, rax
    invoke shader_use, ADDR prefilter_shader
    invoke bind_constants, 1, prefilter_buffer
    invoke bind_texture, 0, env_cubemap.srv
    xor ebx, ebx                                ; mip
    prefilter_mips:
        ; roughness = mip / 4
        cvtsi2ss xmm0, ebx
        movf xmm1, 0.25
        mulss xmm0, xmm1
        movss settings.roughness, xmm0
        invoke update_buffer, prefilter_buffer, ADDR settings, sizeof prefilter_constants
        invoke render_to_cube, ADDR prefilter_map, rbx, transforms_buffer, cube_vb
        inc ebx
        cmp ebx, 5
        jb prefilter_mips
    call unbind_textures

    ; pbr: the 2D lookup table of the BRDF, drawn with one full-screen triangle
    ; -------------------------------------------------------------------------
    invoke mem_zero, ADDR lut_desc, sizeof D3D11_TEXTURE2D_DESC
    mov lut_desc._Width, 512
    mov lut_desc.Height, 512
    mov lut_desc.MipLevels, 1
    mov lut_desc.ArraySize, 1
    mov lut_desc.Format, DXGI_FORMAT_R16G16_FLOAT
    mov lut_desc.SampleDesc.Count, 1
    mov lut_desc.BindFlags, D3D11_BIND_RENDER_TARGET or D3D11_BIND_SHADER_RESOURCE
    vcall device, ID3D11Device_CreateTexture2D, ADDR lut_desc, 0, ADDR lut_texture
    AssertHr
    vcall device, ID3D11Device_CreateRenderTargetView, lut_texture, 0, ADDR lut_rtv
    vcall device, ID3D11Device_CreateShaderResourceView, lut_texture, 0, ADDR ibl_views[16]
    vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR lut_rtv, 0
    invoke set_viewport, 512, 512
    invoke shader_use, ADDR brdf_shader
    vcall context, ID3D11DeviceContext_Draw, 3, 0
    mov rax, irradiance_map.srv
    mov ibl_views[0], rax
    mov rax, prefilter_map.srv
    mov ibl_views[8], rax

    ; the five materials of the textured view
    ; ---------------------------------------
    xor ebx, ebx
    lea rsi, materials
    load_materials:
        lea rax, material_folders
        mov rcx, [rax + rbx * 8]
        invoke load_material, rcx, rsi
        add rsi, 5 * 8
        inc ebx
        cmp ebx, 5
        jb load_materials

    ; lights
    ; ------
    invoke mem_copy, ADDR lights.positions, ADDR light_start, 4 * sizeof vec4
    movups xmm0, xmmword ptr light_color
    movups xmmword ptr lights.colors[0], xmm0
    movups xmmword ptr lights.colors[16], xmm0
    movups xmmword ptr lights.colors[32], xmm0
    movups xmmword ptr lights.colors[48], xmm0
    invoke update_buffer, lights_buffer, ADDR lights, sizeof lights_constants

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

        ; input: switching views frames the camera anew, back for the grid, close for the row
        invoke window_mode, 2
        mov material.textured, eax
        cmp eax, framed_mode
        je framed
            mov framed_mode, eax
            lea rcx, cam
            lea rdx, camera_grid
            test eax, eax
            jz frame_grid
                lea rdx, camera_row
            frame_grid:
            movf xmm2, -90.0
            movf xmm3, 0.0
            call camera_create
        framed:
        invoke camera_process_input, ADDR cam, ADDR delta_time

        ; render
        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke shader_use, ADDR pbr_shader
        invoke bind_constants, 1, material_buffer
        invoke bind_constants, 2, lights_buffer
        vcall context, ID3D11DeviceContext_PSSetShaderResources, 5, 3, ADDR ibl_views

        cmp material.textured, 0
        je grid
            ; one sphere per material, in a row: ((i - 2) * 2.5, 0, 0)
            xor ebx, ebx
            lea rsi, materials
            row_of_five:
                vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 5, rsi
                invoke update_buffer, material_buffer, ADDR material, sizeof material_constants
                lea eax, [ebx - 2]
                cvtsi2ss xmm0, eax
                movf xmm1, 2.5
                mulss xmm0, xmm1
                movss sphere_position.x, xmm0
                mov dword ptr sphere_position.y, 0
                mov dword ptr sphere_position.z, 0
                invoke m4_translate, ADDR model_matrix, ADDR sphere_position
                invoke draw_sphere, transforms_buffer, ADDR t, ADDR ball, ADDR model_matrix
                add rsi, 5 * 8
                inc ebx
                cmp ebx, 5
                jb row_of_five
            jmp drawn
        grid:
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
        drawn:

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
