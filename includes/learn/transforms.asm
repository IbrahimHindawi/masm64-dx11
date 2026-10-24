;---------------------------------------------------------------------------------------------------
; transforms: the per-draw matrices most lessons send in register b0
;---------------------------------------------------------------------------------------------------
; From 2.1 colors on, shaders start with
;
;     cbuffer transforms : register(b0)
;     {
;         float4x4 model;
;         float4x4 normal_matrix;
;         float4x4 view;
;         float4x4 projection;
;         float3 view_position;
;     };
;
; and `transforms` below mirrors it register for register. Once a frame, transforms_from_camera
; fills in the camera's part; draw_cube then sets the model matrix for one cube and draws it.
ifndef transforms_asm
transforms_asm = 0

include macros.asm
include math.asm
include learn\window.asm
include learn\gpu.asm
include learn\camera.asm

transforms struct
    model mat4 <>
    normal_matrix mat4 <>       ; inverse transpose of model, for normals
    view mat4 <>
    projection mat4 <>
    view_position vec3 <>       ; the eye, in world space
    pad real4 ?
transforms ends

.code
; rcx: &transforms, rdx: &camera
;
; view from the camera, projection with its zoom as the field of view (0.1 to 100 units), and
; where the eye is.
align 16
transforms_from_camera proc t:qword, cam:qword
    mov rcx, t
    lea rcx, [rcx].transforms.view
    invoke camera_view, rcx, cam
    mov rcx, t
    lea rcx, [rcx].transforms.projection
    invoke camera_projection, rcx, cam
    mov rcx, t
    mov rdx, cam
    v3load xmm0, [rdx].camera.position
    v3store [rcx].transforms.view_position, xmm0
    ret
transforms_from_camera endp

; rcx: constant buffer, rdx: &transforms, r8: model matrix
;
; The model matrix and its normal matrix, sent; then the 36 vertices of the cube already bound.
; HLSL has no inverse(), so the normal matrix is worked out here, for every draw.
align 16
draw_cube proc buffer:qword, t:qword, model:qword
    mov rcx, t
    mov rdx, model
    for row, <0, 16, 32, 48>
        movups xmm0, [rdx + row]
        movups [rcx + row], xmm0
    endm
    lea rcx, [rcx].transforms.normal_matrix
    invoke m4_normal_matrix, rcx, model
    invoke update_buffer, buffer, t, sizeof transforms
    vcall context, ID3D11DeviceContext_Draw, 36, 0
    ret
draw_cube endp

; rcx: constant buffer, rdx: &transforms, r8: vertex buffer (32-byte vertices: position, normal,
; uv), r9: vertex count, [rsp+32]: model matrix
;
; draw_cube for any vertex buffer: bind it, send the model and normal matrices, draw.
align 16
draw_vertices proc buffer:qword, t:qword, vb:qword, count:qword, model:qword
    local stride:dword, offset_:dword
    mov stride, 32
    mov offset_, 0
    vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR vb, ADDR stride, ADDR offset_
    mov rcx, t
    mov rdx, model
    for row, <0, 16, 32, 48>
        movups xmm0, [rdx + row]
        movups [rcx + row], xmm0
    endm
    lea rcx, [rcx].transforms.normal_matrix
    invoke m4_normal_matrix, rcx, model
    invoke update_buffer, buffer, t, sizeof transforms
    vcall context, ID3D11DeviceContext_Draw, count, 0
    ret
draw_vertices endp

endif
