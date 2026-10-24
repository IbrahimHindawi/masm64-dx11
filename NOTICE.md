# Notice

## The lessons

These lessons follow the structure and techniques of
[LearnOpenGL](https://learnopengl.com/) by Joey de Vries. The code and text
here were written anew for Direct3D 11 and x64 assembly rather than translated
line by line, but they are derived from that work.

LearnOpenGL's code samples are licensed under
[CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). This
repository is offered under the same license: credit LearnOpenGL and Joey de
Vries, and do not use it commercially.

## The resources

Everything under `resources/` was copied unchanged from the `resources` folder
of the [LearnOpenGL repository](https://github.com/JoeyDeVries/LearnOpenGL).
Each file keeps the terms its author released it under; the LearnOpenGL
repository is the place to check them. The notes shipped with the models are
kept beside them:

- `resources/objects/backpack/source_attribution.txt`: the backpack, by Berk
  Gedik (Sketchfab), with material changes by Joey de Vries
- `resources/objects/planet/source.txt`: the planet, by Gerhald3D
  (TurboSquid), modified by Joey de Vries

## The MASM64 SDK

The macros (`invoke`, the stack frame and register-saving macros) and the
Windows include files the lessons build with come from the
[MASM64 SDK](https://masm32.com), copyright The MASM32 SDK. They are not
redistributed here: install the SDK separately (see the README).
