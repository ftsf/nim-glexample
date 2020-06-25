{.experimental:"codeReordering".}

import opengl
import sdl2/sdl except Texture

import strformat

import glm
import glutil
import shader

import imgui
import imgui/impl_opengl
import imgui/impl_sdl2

var keepRunning = true
var projection: Mat4f
var window: Window
var glContext: GLContext
var time = 0.0'f
var texture: Texture

var shaderTextured2D: Shader
var quad: Mesh
var quadRotation: float32

proc glMessageCallback(source, king: GLenum, id: GLuint, severity: GLenum, length: GLsizei, message: ptr GLchar, userParam: pointer) {.stdcall.} =
  var msg = cast[cstring](message)
  echo fmt("GL: {msg}")

proc initGL() =
  discard sdl.init(INIT_EVERYTHING)


  window = createWindow("glExample", 64, 64, 512, 512, (WINDOW_OPENGL or WINDOW_RESIZABLE).uint32)
  showWindow(window)

  discard glSetAttribute(GLattr.GL_CONTEXT_PROFILE_MASK, GL_CONTEXT_PROFILE_CORE)
  discard glSetAttribute(GL_CONTEXT_MAJOR_VERSION, 3)
  discard glSetAttribute(GL_CONTEXT_MINOR_VERSION, 3)

  glContext = window.glCreateContext()

  discard glSetSwapInterval(1)

  loadExtensions()

  shaderTextured2D = loadShader("shaders/textured2d.v.glsl", "shaders/textured2d.f.glsl")
  quad = createQuad(500,500)
  texture = loadImage("textures/test.png")

proc initImgui() =
  igCreateContext()
  let io = igGetIO()

  #io.fonts.addFontFromFileTTF("fonts/Roboto-Regular.ttf", 12.0'f)

  io.configFlags = (
    io.configFlags.int32 or
    ImGuiConfigFlags.DockingEnable.int32
  ).ImGuiConfigFlags
  io.configWindowsResizeFromEdges = true
  io.configDockingNoSplit = false
  #io.configDockingWithShift = false

  #igStyleColorsCherry()
  igStyleColorsDark()

  discard igSDLInitForOpenGL(window.addr, glContext)
  discard igOpenGL3Init()


proc reshape(window: Window) =
  var w,h: cint
  getWindowSize(window, w.addr, h.addr)
  var aspect = w.float32 / h.float32
  echo "reshape ", w, "x", h, " aspect: ", aspect

  let hw = w.float32 * 0.5'f
  let hh = h.float32 * 0.5'f

  projection = ortho[float32](-hw, hw, -hh, hh, -1'f, 1'f)

  glViewport(0,0,w,h)

proc handleEvents() =
  var e: Event
  var io = igGetIO()
  while pollEvent(e.addr) == 1:

    discard igSDLProcessEvent(e.addr)

    if e.kind == Quit:
      keepRunning = false
    elif e.kind == WindowEvent:
      if e.window.event == WindowEvent_Resized:
        reshape(window)

    elif io.wantCaptureKeyboard == false and (e.kind == KeyDown or e.kind == KeyUp):
      let down = e.kind == KeyDown
      let sym = e.key.keysym.sym
      let mods = e.key.keysym.mods
      let repeat = e.key.repeat != 0

      let ctrl = (mods and uint16(KMOD_CTRL)) != 0
      let alt = (mods and uint16(KMOD_ALT)) != 0
      let shift = (mods and uint16(KMOD_SHIFT)) != 0
      let nomods = mods == 0

      if ctrl and sym == K_q:
        keepRunning = false
        continue

proc update(dt: float32) =
  quadRotation += dt * 0.1'f

proc renderGUI() =
  igBegin("test")
  if igButton("press me"):
    echo "pressed"
  igEnd()

proc render() =
  igOpenGL3NewFrame()
  igSDLNewFrame(window)
  igNewFrame()

  # clear the screen
  glClearColor(0,0,0,0)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

  var view = mat4f()
  var model = mat4f()

  model = model.rotate(vec3f(0,0,1), quadRotation)

  # draw a textured quad
  shaderTextured2D.use()
  shaderTextured2D.setUniformMat4f("projection", projection)
  shaderTextured2D.setUniformMat4f("view", view)
  shaderTextured2D.setUniformMat4f("model", model)
  shaderTextured2D.setUniformVec4f("objectColor", vec4f(1,1,1,1))
  shaderTextured2D.setUniformVec4f("layerColor", vec4f(1,1,1,1))

  texture.use()
  quad.draw()
  noTexture()

  # draw our gui
  renderGUI()

  # render gui to screen
  igRender()
  igOpenGL3RenderDrawData(igGetDrawData())

  # update the screen during vsync
  window.glSwapWindow()


proc main() =
  initGL()
  initImgui()

  reshape(window)

  glEnable(GL_DEBUG_OUTPUT)
  glDebugMessageCallback(glMessageCallback, nil)

  var timeAccum = 0.0'f
  while keepRunning:
    let next_time = getTicks().float32 / 1000.0'f
    let deltaTime = next_time - time
    timeAccum += deltaTime
    time = next_time

    if timeAccum > 1.0'f/60.0'f:
      timeAccum -= 1.0'f/60.0'f

      handleEvents()

      update(deltaTime)

      render()

  igOpenGL3Shutdown()
  igSDLShutdown()

main()
