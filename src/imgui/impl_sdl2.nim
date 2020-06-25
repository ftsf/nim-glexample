# Copyright 2018, NimGL contributors.

## ImGUI SDL2 Implementation
## ====
## Implementation based on the imgui examples implementations.
## Feel free to use and modify this implementation.
## This needs to be used along with a Renderer.

import ../imgui
import sdl2/sdl
import sdl2/sdl_syswm

var
  gWindow: Window
  gTime: uint64
  gMousePressed: array[5, bool]
  gMouseCursors: array[ImGuiMouseCursor.high.int32 + 1, Cursor]
  gClipboardTextData: cstring = nil
  gMouseCanUseGlobalState = true

proc igSDLGetClipboardText(userData: pointer): cstring {.cdecl.} =
  if gClipboardTextData != nil:
    free(gClipboardTextData)
  gClipboardTextData = getClipboardText()
  return gClipboardTextData

proc igSDLSetClipboardText(userData: pointer, text: cstring): void {.cdecl.} =
  discard setClipboardText(text)

proc igSDLProcessEvent*(event: ptr Event): bool =
  let io = igGetIO()

  case event.kind:
    of MouseWheel:
      if event.wheel.x > 0: io.mouseWheelH += 1
      if event.wheel.x < 0: io.mouseWheelH -= 1
      if event.wheel.y > 0: io.mouseWheel += 1
      if event.wheel.y < 0: io.mouseWheel -= 1
      return true
    of MouseButtonDown:
      if event.button.button == ButtonLeft: gMousePressed[0] = true
      if event.button.button == ButtonRight: gMousePressed[1] = true
      if event.button.button == ButtonMiddle: gMousePressed[2] = true
      return true
    of TextInput:
      io.addInputCharactersUTF8(event.text.text[0].addr)
      return true
    of KeyDown,KeyUp:
      let key = event.key.keysym.scancode
      io.keysDown[key.int] = event.kind == KeyDown
      io.keyShift = (event.key.keysym.mods.uint16 and KMOD_SHIFT.uint16) != 0
      io.keyCtrl = (event.key.keysym.mods.uint16 and KMOD_CTRL.uint16) != 0
      io.keyAlt = (event.key.keysym.mods.uint16 and KMOD_ALT.uint16) != 0
      io.keySuper = (event.key.keysym.mods.uint16 and KMOD_GUI.uint16) != 0
      return true
    else:
      discard
  return false

proc igSDLInit(window: Window): bool =
  gWindow = window
  gTime = 0

  let io = igGetIO()
  io.backendFlags = (io.backendFlags.int32 or ImGuiBackendFlags.HasMouseCursors.int32).ImGuiBackendFlags
  io.backendFlags = (io.backendFlags.int32 or ImGuiBackendFlags.HasSetMousePos.int32).ImGuiBackendFlags
  io.backendPlatformName = "imgui_impl_sdl2"

  io.keyMap[ImGuiKey.Tab.int32] = SCANCODE_TAB.int32
  io.keyMap[ImGuiKey.LeftArrow.int32] = SCANCODE_LEFT.int32
  io.keyMap[ImGuiKey.RightArrow.int32] = SCANCODE_RIGHT.int32
  io.keyMap[ImGuiKey.UpArrow.int32] = SCANCODE_UP.int32
  io.keyMap[ImGuiKey.DownArrow.int32] = SCANCODE_DOWN.int32
  io.keyMap[ImGuiKey.PageUp.int32] = SCANCODE_PAGEUP.int32
  io.keyMap[ImGuiKey.PageDown.int32] = SCANCODE_PAGEDOWN.int32
  io.keyMap[ImGuiKey.Home.int32] = SCANCODE_HOME.int32
  io.keyMap[ImGuiKey.End.int32] = SCANCODE_END.int32
  io.keyMap[ImGuiKey.Insert.int32] = SCANCODE_INSERT.int32
  io.keyMap[ImGuiKey.Delete.int32] = SCANCODE_DELETE.int32
  io.keyMap[ImGuiKey.Backspace.int32] = SCANCODE_BACKSPACE.int32
  io.keyMap[ImGuiKey.Space.int32] = SCANCODE_SPACE.int32
  io.keyMap[ImGuiKey.Enter.int32] = SCANCODE_RETURN.int32
  io.keyMap[ImGuiKey.Escape.int32] = SCANCODE_ESCAPE.int32
  io.keyMap[ImGuiKey.A.int32] = SCANCODE_a.int32
  io.keyMap[ImGuiKey.C.int32] = SCANCODE_c.int32
  io.keyMap[ImGuiKey.V.int32] = SCANCODE_v.int32
  io.keyMap[ImGuiKey.X.int32] = SCANCODE_x.int32
  io.keyMap[ImGuiKey.Y.int32] = SCANCODE_y.int32
  io.keyMap[ImGuiKey.Z.int32] = SCANCODE_z.int32

  # HELP: If you know how to convert char * to const char * through Nim pragmas
  # and types, I would love to know.
  when not defined(cpp):
    io.setClipboardTextFn = igSDLSetClipboardText
    io.getClipboardTextFn = igSDLGetClipboardText

  io.clipboardUserData = nil
  # when defined windows:
  #   io.imeWindowHandle = gWindow.getWin32Window()

  gMouseCursors[ImGuiMouseCursor.Arrow.int32] =       createSystemCursor(SYSTEM_CURSOR_ARROW)
  gMouseCursors[ImGuiMouseCursor.TextInput.int32] =   createSystemCursor(SYSTEM_CURSOR_IBEAM)
  gMouseCursors[ImGuiMouseCursor.ResizeAll.int32] =   createSystemCursor(SYSTEM_CURSOR_SIZEALL)
  gMouseCursors[ImGuiMouseCursor.ResizeNS.int32] =    createSystemCursor(SYSTEM_CURSOR_SIZENS)
  gMouseCursors[ImGuiMouseCursor.ResizeEW.int32] =    createSystemCursor(SYSTEM_CURSOR_SIZEWE)
  gMouseCursors[ImGuiMouseCursor.ResizeNESW.int32] =  createSystemCursor(SYSTEM_CURSOR_SIZENESW)
  gMouseCursors[ImGuiMouseCursor.ResizeNWSE.int32] =  createSystemCursor(SYSTEM_CURSOR_SIZENWSE)
  gMouseCursors[ImGuiMouseCursor.Hand.int32] =        createSystemCursor(SYSTEM_CURSOR_HAND)
  gMouseCursors[ImGuiMouseCursor.NotAllowed.int32] =  createSystemCursor(SYSTEM_CURSOR_NO)

  gMouseCanUseGlobalState = true

  return true

proc igSDLInitForOpenGL*(window: Window, sdlGLContext: pointer): bool =
  return igSDLInit(window)

# @TODO: Vulkan support

proc igSDLUpdateMousePosAndButtons() =
  let io = igGetIO()

  if io.wantSetMousePos:
    warpMouseInWindow(gWindow.addr, io.mousePos.x.cint, io.mousePos.y.cint)
  else:
    io.mousePos = ImVec2(x: -Inf, y: -Inf)

  var mx,my: cint
  let mouseButtons = getMouseState(mx.addr, my.addr)

  io.mousePos = ImVec2(x: mx.float32, y: my.float32)

  io.mouseDown[0] = gMousePressed[0] or (mouseButtons and button(BUTTON_LEFT)) != 0
  io.mouseDown[1] = gMousePressed[1] or (mouseButtons and button(BUTTON_RIGHT)) != 0
  io.mouseDown[2] = gMousePressed[2] or (mouseButtons and button(BUTTON_MIDDLE)) != 0
  gMousePressed[0] = false
  gMousePressed[1] = false
  gMousePressed[2] = false

  #TODO: ...

  if (io.configFlags.int and ImGuiConfigFlags.NoMouse.int) == 0:
    let anyMouseButtonDown = igIsAnyMouseDown()
    discard captureMouse(if anyMouseButtonDown: true else: false)

proc igSDLUpdateMouseCursor() =
  let io = igGetIO()
  if ((io.configFlags.int32 and ImGuiConfigFlags.NoMouseCursorChange.int32) == 1):
    return

  var igCursor = igGetMouseCursor()
  if io.mouseDrawCursor or igCursor == ImGuiMouseCursor.None:
    discard showCursor(0)
  else:
    #setCursor(gMouseCursors[igCursor.int])
    discard showCursor(1)

# TODO: gamepads

proc igSDLNewFrame*(window: Window) =
  let io = igGetIO()
  assert io.fonts.isBuilt()

  var w: int32
  var h: int32
  var displayW: int32
  var displayH: int32

  getWindowSize(window, w.addr, h.addr)
  glGetDrawableSize(window, displayW.addr, displayH.addr)
  io.displaySize = ImVec2(x: w.float32, y: h.float32)
  io.displayFramebufferScale = ImVec2(x: if w > 0: displayW.float32 / w.float32 else: 0.0f, y: if h > 0: displayH.float32 / h.float32 else: 0.0f)

  let currentTime = getPerformanceCounter()
  let freq = getPerformanceFrequency()
  io.deltaTime = float(currentTime - gTime) / float(freq)
  gTime = currentTime

  igSDLUpdateMousePosAndButtons()
  igSDLUpdateMouseCursor()

  # @TODO: gamepad mapping

proc igSDLShutdown*() =
  gWindow = nil

  if gClipboardTextData != nil:
    free(gClipboardTextData)
    gClipboardTextData = nil

  for i in 0 ..< ImGuiMouseCursor.high.int32 + 1:
    freeCursor(gMouseCursors[i])
    gMouseCursors[i] = nil
