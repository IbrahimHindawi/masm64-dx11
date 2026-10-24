;---------------------------------------------------------------------------------------------------
; pbr: what the PBR lessons (chapter 6) share
;---------------------------------------------------------------------------------------------------
;   create_sphere         a UV sphere of radius 1, indexed
;   draw_sphere           draw it with a model matrix
;   load_material         the five maps of one PBR material from a folder
;   create_cube_target    a float cubemap that can be drawn into
;   render_to_cube        draw the bound shader over all six faces of one of its mips
ifndef pbr_asm
pbr_asm = 0

include macros.asm
include math.asm
include saha.asm
include cstr.asm
include learn\window.asm
include learn\gpu.asm
include learn\filesystem.asm
include learn\transforms.asm
include learn\srgb.asm

; A UV sphere of radius 1, indexed: `segments` slices around and as many stacks from pole to pole.
; u runs around the equator and v from the top pole down, the way an equirectangular texture wraps
; it.
sphere struct
    vertices qword ?        ; ID3D11Buffer of 32-byte vertices: position, normal, uv
    indices qword ?         ; ID3D11Buffer of 32-bit indices
    index_count dword ?
    pad dword ?
sphere ends

; A cubemap of half floats that can be drawn into, face by face and mip by mip.
cube_target struct
    texture qword ?         ; ID3D11Texture2D, an array of six
    srv qword ?             ; ID3D11ShaderResourceView of it as a cube, every mip
    size_ dword ?           ; of a face at mip 0, in pixels
    pad dword ?
cube_target ends

.const
; the five maps of a material, in their registers' order t0..t4
pbr_map_albedo byte "albedo.png", 0
pbr_map_normal byte "normal.png", 0
pbr_map_metallic byte "metallic.png", 0
pbr_map_roughness byte "roughness.png", 0
pbr_map_ao byte "ao.png", 0
align 8
pbr_map_names qword offset pbr_map_albedo, offset pbr_map_normal, offset pbr_map_metallic
              qword offset pbr_map_roughness, offset pbr_map_ao

; the direction each cube face looks along, and which way is up in it: +x, -x, +y, -y, +z, -z
align 4
cube_face_targets vec3 <1.0, 0.0, 0.0>, <-1.0, 0.0, 0.0>, <0.0, 1.0, 0.0>, <0.0, -1.0, 0.0>, <0.0, 0.0, 1.0>, <0.0, 0.0, -1.0>
cube_face_ups vec3 <0.0, -1.0, 0.0>, <0.0, -1.0, 0.0>, <0.0, 0.0, 1.0>, <0.0, 0.0, -1.0>, <0.0, -1.0, 0.0>, <0.0, -1.0, 0.0>
cube_face_eye vec3 <0.0, 0.0, 0.0>

.code
; rcx: &sphere, rdx: segments
align 16
create_sphere proc out_ref:qword, segments:qword
    local ring:qword, vertices:qword, indices:qword, fsegments:real4
    local u:real4, v:real4, cos_u:real4, sin_u:real4, sin_v:real4, cos_v:real4
    USING rbx, rsi, rdi, r12, r13
    SaveRegs
    mov rax, segments
    inc rax
    mov ring, rax
    cvtsi2ss xmm0, dword ptr segments
    movss fsegments, xmm0

    ; the vertices: (segments + 1)^2 of them, the seam and the poles repeated so u and v reach 1
    mov rax, ring
    mul ring
    shl rax, 5
    invoke arenaPush, ADDR arena, rax, 16
    mov vertices, rax
    mov rsi, rax
    xor r12, r12                                ; y
    stacks:
        xor r13, r13                            ; x
        slices:
            cvtsi2ss xmm0, r13
            divss xmm0, fsegments
            movss u, xmm0
            cvtsi2ss xmm0, r12
            divss xmm0, fsegments
            movss v, xmm0
            movss xmm0, u
            addss xmm0, xmm0
            mulss xmm0, math_pi                 ; 2 pi u
            movss sin_u, xmm0
            call cosf
            movss cos_u, xmm0
            movss xmm0, sin_u
            call sinf
            movss sin_u, xmm0
            movss xmm0, v
            mulss xmm0, math_pi                 ; pi v
            movss sin_v, xmm0
            call cosf
            movss cos_v, xmm0
            movss xmm0, sin_v
            call sinf
            movss sin_v, xmm0
            ; p = (cos(2 pi u) sin(pi v), cos(pi v), sin(2 pi u) sin(pi v)), which is its normal too
            movss xmm0, cos_u
            mulss xmm0, sin_v
            movss real4 ptr [rsi + 0], xmm0
            movss real4 ptr [rsi + 12], xmm0
            movss xmm0, cos_v
            movss real4 ptr [rsi + 4], xmm0
            movss real4 ptr [rsi + 16], xmm0
            movss xmm0, sin_u
            mulss xmm0, sin_v
            movss real4 ptr [rsi + 8], xmm0
            movss real4 ptr [rsi + 20], xmm0
            movss xmm0, u
            movss real4 ptr [rsi + 24], xmm0
            movss xmm0, v
            movss real4 ptr [rsi + 28], xmm0
            add rsi, 32
            inc r13
            cmp r13, ring
            jb slices
        inc r12
        cmp r12, ring
        jb stacks

    ; two counter-clockwise triangles between each pair of stacks and slices
    mov rax, segments
    mul segments
    imul rax, rax, 6 * 4
    invoke arenaPush, ADDR arena, rax, 16
    mov indices, rax
    mov rdi, rax
    xor r12, r12                                ; y
    index_stacks:
        xor r13, r13                            ; x
        index_slices:
            mov rax, r12
            mul ring
            add rax, r13                        ; a: this stack, this slice
            mov rbx, rax
            add rbx, ring                       ; b: the stack below
            mov [rdi + 0], eax                  ; a, a + 1, b + 1
            lea ecx, [eax + 1]
            mov [rdi + 4], ecx
            lea ecx, [ebx + 1]
            mov [rdi + 8], ecx
            mov [rdi + 12], eax                 ; a, b + 1, b
            mov [rdi + 16], ecx
            mov [rdi + 20], ebx
            add rdi, 24
            inc r13
            cmp r13, segments
            jb index_slices
        inc r12
        cmp r12, segments
        jb index_stacks

    mov rbx, out_ref
    mov rax, rdi
    sub rax, indices
    shr rax, 2
    mov [rbx].sphere.index_count, eax
    mov rax, ring
    mul ring
    shl rax, 5
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, vertices, rax
    mov [rbx].sphere.vertices, rax
    mov rax, rdi
    sub rax, indices
    invoke create_buffer, D3D11_BIND_INDEX_BUFFER, indices, rax
    mov [rbx].sphere.indices, rax
    RestoreRegs
    ret
create_sphere endp

; rcx: constant buffer, rdx: &transforms, r8: &sphere, r9: model matrix
align 16
draw_sphere proc buffer:qword, t:qword, s:qword, model:qword
    local stride:dword, offset_:dword
    USING rbx
    SaveRegs
    mov rbx, s
    mov stride, 32
    mov offset_, 0
    lea rax, [rbx].sphere.vertices
    vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, rax, ADDR stride, ADDR offset_
    vcall context, ID3D11DeviceContext_IASetIndexBuffer, qword ptr [rbx].sphere.indices, DXGI_FORMAT_R32_UINT, 0
    mov rcx, t
    mov rdx, model
    for row, <0, 16, 32, 48>
        movups xmm0, [rdx + row]
        movups [rcx + row], xmm0
    endm
    lea rcx, [rcx].transforms.normal_matrix
    invoke m4_normal_matrix, rcx, model
    invoke update_buffer, buffer, t, sizeof transforms
    vcall context, ID3D11DeviceContext_DrawIndexed, dword ptr [rbx].sphere.index_count, 0, 0
    RestoreRegs
    ret
draw_sphere endp

; rcx: folder relative to the repository root (ending in a slash), rdx: where to put the five views
; (albedo, normal, metallic, roughness, ao)
;
; Only albedo is a colour, decoded from sRGB when sampled; the other maps are data.
align 16
load_material proc folder:qword, out_ref:qword
    local path[260]:byte
    USING rbx, rsi
    SaveRegs
    invoke filesystem_path, folder
    mov rsi, rax
    xor ebx, ebx
    maps:
        invoke cstr_copy, ADDR path, rsi
        lea rax, pbr_map_names
        mov rdx, [rax + rbx * 8]
        invoke cstr_append, ADDR path, rdx
        xor edx, edx
        test ebx, ebx
        setz dl                                 ; srgb for the first, albedo
        invoke load_texture, ADDR path, rdx
        mov rcx, out_ref
        mov [rcx + rbx * 8], rax
        inc ebx
        cmp ebx, 5
        jb maps
    RestoreRegs
    ret
load_material endp

; rcx: &cube_target, rdx: face size, r8: mip levels (0: all of them), r9: 1 to let the GPU
; generate the mips
align 16
create_cube_target proc out_ref:qword, face_size:qword, mips:qword, generate_mips:qword
    local desc:D3D11_TEXTURE2D_DESC, view:D3D11_SHADER_RESOURCE_VIEW_DESC
    USING rbx
    SaveRegs
    mov rbx, out_ref
    mov eax, dword ptr face_size
    mov [rbx].cube_target.size_, eax
    invoke mem_zero, ADDR desc, sizeof D3D11_TEXTURE2D_DESC
    mov eax, dword ptr face_size
    mov desc._Width, eax
    mov desc.Height, eax
    mov eax, dword ptr mips
    mov desc.MipLevels, eax
    mov desc.ArraySize, 6
    mov desc.Format, DXGI_FORMAT_R16G16B16A16_FLOAT
    mov desc.SampleDesc.Count, 1
    mov desc.BindFlags, D3D11_BIND_RENDER_TARGET or D3D11_BIND_SHADER_RESOURCE
    mov desc.MiscFlags, D3D11_RESOURCE_MISC_TEXTURECUBE
    cmp generate_mips, 0
    je no_generate
        mov desc.MiscFlags, D3D11_RESOURCE_MISC_TEXTURECUBE or D3D11_RESOURCE_MISC_GENERATE_MIPS
    no_generate:
    lea rax, [rbx].cube_target.texture
    vcall device, ID3D11Device_CreateTexture2D, ADDR desc, 0, rax
    AssertHr
    invoke mem_zero, ADDR view, sizeof D3D11_SHADER_RESOURCE_VIEW_DESC
    mov view.Format, DXGI_FORMAT_R16G16B16A16_FLOAT
    mov view.ViewDimension, D3D11_SRV_DIMENSION_TEXTURECUBE
    mov view.TextureCube.MipLevels, -1              ; all of them
    lea rax, [rbx].cube_target.srv
    vcall device, ID3D11Device_CreateShaderResourceView, qword ptr [rbx].cube_target.texture, ADDR view, rax
    AssertHr
    RestoreRegs
    ret
create_cube_target endp

; rcx: &cube_target, rdx: mip, r8: transforms constant buffer, r9: the unit cube's vertex buffer
;
; Draws the unit cube around the origin once per face, through a 90-degree view looking out of
; that face, with whatever shader is bound: each face's pixels see the directions that face covers.
; A cubemap's faces are laid out left-handed, which no right-handed look-at produces; flipping the
; projection's y fixes that, as GL's bottom-up framebuffer does for free there.
align 16
render_to_cube proc target:qword, mip:qword, constants:qword, cube_vb:qword
    local t:transforms, model:mat4, rtv_desc:D3D11_RENDER_TARGET_VIEW_DESC, rtv:qword
    USING rbx, rsi
    SaveRegs
    invoke mem_zero, ADDR t, sizeof transforms
    ; projection = scale(1, -1, 1) * perspective(90 degrees, 1, 0.1, 10)
    movf xmm0, 10.0
    movss real4 ptr [rsp + 32], xmm0
    movf xmm0, 90.0
    call radians
    movaps xmm1, xmm0
    movss xmm2, math_one
    movf xmm3, 0.1
    lea rcx, t.projection
    call m4_perspective
    movups xmm0, xmmword ptr t.projection.m[16]
    xorps xmm0, math_sign_mask
    movups xmmword ptr t.projection.m[16], xmm0
    invoke m4_identity, ADDR model

    ; the face's size at this mip
    mov rbx, target
    mov ecx, dword ptr mip
    mov eax, [rbx].cube_target.size_
    shr eax, cl
    invoke set_viewport, rax, rax

    xor esi, esi                                ; face
    faces:
        invoke mem_zero, ADDR rtv_desc, sizeof D3D11_RENDER_TARGET_VIEW_DESC
        mov rtv_desc.Format, DXGI_FORMAT_R16G16B16A16_FLOAT
        mov rtv_desc.ViewDimension, D3D11_RTV_DIMENSION_TEXTURE2DARRAY
        mov eax, dword ptr mip
        mov rtv_desc.Texture2DArray.MipSlice, eax
        mov rtv_desc.Texture2DArray.FirstArraySlice, esi
        mov rtv_desc.Texture2DArray.ArraySize, 1
        vcall device, ID3D11Device_CreateRenderTargetView, qword ptr [rbx].cube_target.texture, ADDR rtv_desc, ADDR rtv
        AssertHr
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR rtv, 0
        imul eax, esi, sizeof vec3
        lea r8, cube_face_targets
        add r8, rax
        lea r9, cube_face_ups
        add r9, rax
        lea rdx, cube_face_eye
        lea rcx, t.view
        call m4_look_at
        invoke draw_vertices, constants, ADDR t, cube_vb, 36, ADDR model
        release rtv
        inc esi
        cmp esi, 6
        jb faces
    RestoreRegs
    ret
render_to_cube endp

endif
