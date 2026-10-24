# masm64-dx11

[LearnOpenGL](https://learnopengl.com/)'s lessons, from the first window to
image based PBR, rewritten for Windows and Direct3D 11 in x64 assembly:
Microsoft's assembler, ml64, with the macros of the
[MASM64 SDK](https://masm32.com). It is the assembly twin of `rin-dx11`, the
same lessons in [rin](https://github.com/IbrahimHindawi/rin), and follows it
lesson for lesson, down to the shaders, which are shared unchanged.

Nothing third-party is linked and the C runtime is not used: the window and
input are Win32, images are decoded by WIC (Windows Imaging Component), shaders
are compiled by `D3DCompile`, and the maths, the `.obj` reader and the `.hdr`
reader are written in assembly, in `includes/`.

## Build and run

Needs Visual Studio (2022 or later) with the C++ x64 tools, for `ml64` and
`link`, the Windows SDK, and the [MASM64 SDK](https://masm32.com) for its
macros and Windows include files. The SDK is not part of this repository:
install it into `C:\masm64`, or set `MASM64_HOME` to wherever it is.

    scripts\build.bat
    build\hello_window.exe

`scripts\build.bat hello` builds only the lessons whose names contain `hello`.
The script finds Visual Studio by itself when it is not run from a developer
prompt. Each lesson is its own executable, named after its file, and is one
unity build: a single `.asm` that includes everything it uses, so building it
is one `ml64` and one `link`. Lessons find `resources/` and their shaders by
walking up from the executable, so they can be run from anywhere.

| key | does |
|---|---|
| W A S D, Space, Shift | fly (from 1.7 on) |
| right mouse + drag | look around |
| wheel | zoom |
| Tab, 1..6 | each lesson's modes |
| Esc | quit |

From 1.3 on, `--shot out.png` renders a few frames with the clock stopped,
saves the backbuffer as a PNG and exits, without showing the window; `--time t`
picks the time (1 second by default) and `--mode n` the mode, counted from 0.
`scripts\shots.bat` does that for every lesson, into `shots/`. That is how each
lesson here was checked against the rin version.

## How to read it

Read each lesson's `.asm` first: it opens with what the lesson is about and
stays close to the code. The `.hlsl` beside it holds its shaders. The guides in
`docs/` give the background a single file does not have room for, starting with
how D3D11's conventions differ from GL's (`docs/0_from_gl_to_d3d11.md`) and how
the assembly is written (`docs/0_masm64.md`).

Early lessons spell out every D3D11 call. Once a call has been explained it
moves into `includes/`, and later lessons use the procedure:

| file | holds | first explained in |
|---|---|---|
| `learn/window.asm` | window, input, device, swap chain, frame loop, `--shot`: GLFW's part | 1.1, 2.1 |
| `learn/shader.asm` | one `.hlsl` file compiled into a shader program | 2.1 |
| `learn/gpu.asm` | buffers, constants, textures, samplers, render targets, cubemaps | 2.1 to 6.1 |
| `math.asm` | vectors and row-major `mat4`, in SSE | 5.1 |
| `learn/cube.asm` | the cube, and where the ten cubes stand | 6.1 |
| `learn/camera.asm` | the fly camera | 1.7 |
| `learn/transforms.asm` | the per-draw matrices in `b0`, `draw_cube`, `draw_vertices` | 2.1 |
| `learn/model.asm` | Wavefront `.obj` models | 3.1 |
| `image.asm` | `.png` / `.jpg` through WIC, and Radiance `.hdr` | 1.4 |
| `learn/srgb.asm`, `shadow.asm`, `wall.asm` | an sRGB view of the backbuffer, shadow maps, a wall with tangents | 5.x |
| `learn/pbr.asm` | the sphere, PBR materials, drawing into cubemap faces | 6.1 to 6.3 |
| `macros.asm`, `saha.asm`, `cstr.asm`, `print.asm`, `rt.inc` | COM calls, float constants, the arena allocator, strings, `print`, the MASM64 SDK includes | 1.1 |
| `d3d11.inc` | D3D11, DXGI, D3DCompiler and WIC: structs, constants, vtables, GUIDs | generated |

`includes/d3d11.inc` is generated from the Windows SDK's headers by
`tools/gen_d3d11.py` (libclang). Every struct is laid out at the offsets the C
compiler uses and checked against its size when it is assembled.

## The lessons

| | lesson | about |
|---|---|---|
| **1** | [getting started](docs/1_getting_started.md) | |
| 1.1 | hello window | a window, a device, a clear colour |
| 2.1 | hello triangle | buffers, shaders, input layouts, indexed drawing |
| 3.1 | shaders | per-vertex data and constant buffers |
| 4.1 | textures | WIC images, mipmaps, samplers |
| 5.1 | transformations | matrices and their order |
| 6.1 | coordinate systems | model, view, projection; the depth buffer |
| 7.1 | camera | a fly camera from yaw and pitch |
| **2** | [lighting](docs/2_lighting.md) | |
| 1 | colors | light colour times surface colour |
| 2.1 | basic lighting | Phong: ambient, diffuse, specular |
| 3.1 | materials | per-term material and light colours |
| 4.1 | lighting maps | diffuse and specular textures |
| 5.1 | light casters | directional, point and spot lights |
| 6 | multiple lights | summing them |
| **3** | [model loading](docs/3_model_loading.md) | |
| 1 | model loading | an `.obj` backpack and its materials |
| **4** | [advanced D3D11](docs/4_advanced.md) | |
| 1.1 | depth testing | the depth buffer, and linear depth |
| 2 | stencil testing | outlines through the stencil buffer |
| 3.1 | blending | clipped grass, sorted transparent windows |
| 4 | face culling | winding and back faces |
| 5.1 | framebuffers | render to texture, post-processing |
| 6.1 | cubemaps | skybox, reflection, refraction |
| 7 | advanced data | dynamic and split vertex buffers |
| 8 | advanced HLSL | shared constant buffers, system values |
| 9.1 | geometry shader | exploding a model, drawing its normals |
| 10.1 | instancing | twenty thousand asteroids in one draw |
| 11.1 | anti-aliasing | MSAA and resolving it |
| **5** | [advanced lighting](docs/5_advanced_lighting.md) | |
| 1 | advanced lighting | Blinn-Phong: the halfway vector |
| 2 | gamma correction | sRGB textures and backbuffer, linear lighting |
| 3.1 | shadow mapping | directional shadows, hardware PCF |
| 3.2 | point shadows | a depth cubemap in one pass |
| 4 | normal mapping | tangent space |
| 5.1 | parallax mapping | parallax occlusion mapping |
| 6 | hdr | float targets and tone mapping |
| 7 | bloom | bright pass, ping-pong blur |
| 8.1 | deferred shading | the G-buffer, many lights |
| 9 | ssao | screen-space ambient occlusion |
| **6** | [pbr](docs/6_pbr.md) | |
| 1.1 | lighting | Cook-Torrance, metallic and roughness |
| 2.1 | ibl irradiance | lighting by an HDR environment |
| 2.2 | ibl specular | prefiltered reflections, the BRDF table |

## Credits

The lessons follow LearnOpenGL by Joey de Vries, rewritten rather than
translated; its code is CC BY-NC 4.0, and so is this. The textures, models and
HDR environment come from the LearnOpenGL repository. See
[NOTICE.md](NOTICE.md). The macros and Windows include files come from the
MASM64 SDK, which is installed separately.
