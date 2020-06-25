import opengl
import stb_image/read as stbi
import stb_image/write as stbiw
import glm
import strutils
import strscans
import tables

type Texture* = object
  name*: string
  id*: GLuint
  w*,h*: int
  msaa*: bool
  aspect*: float32

var textureCache = initTable[string,Texture](64)

var currentTexture: ptr Texture

type Framebuffer* = distinct GLuint

converter toGLint(x: int): GLint =
  return x.GLint

proc isNil*(fb: Framebuffer): bool =
  return fb.GLint == 0

proc use*(fb: Framebuffer) =
  if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
    raise newException(Exception, "framebuffer incomplete")
  glBindFramebuffer(GL_FRAMEBUFFER, fb.GLuint)

proc useRead*(fb: Framebuffer) =
  if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
    raise newException(Exception, "framebuffer incomplete")
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fb.GLuint)

proc useDraw*(fb: Framebuffer) =
  if glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE:
    raise newException(Exception, "framebuffer incomplete")
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fb.GLuint)

proc blitFramebuffer*(sx,sy,sw,sh,dx,dy,dw,dh: int) =
  glBlitFramebuffer(sx,sy,sw,sh,dx,dy,dw,dh, GL_COLOR_BUFFER_BIT, GL_LINEAR.GLenum)

proc noFramebuffer*() =
  glBindFramebuffer(GL_FRAMEBUFFER, 0)

proc noFramebufferRead*() =
  glBindFramebuffer(GL_READ_FRAMEBUFFER, 0)

proc noFramebufferDraw*() =
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0)

type VBO* = distinct GLuint

proc use*(vbo: VBO) =
  glBindBuffer(GL_ARRAY_BUFFER, vbo.GLuint)
proc noVBO*() =
  glBindBuffer(GL_ARRAY_BUFFER, 0)
proc newVBO*(): VBO =
  var vbo: GLuint
  glGenBuffers(1, vbo.addr)
  return vbo.VBO

type VAO* = distinct GLuint

proc use*(vao: VAO) =
  glBindVertexArray(vao.GLuint)
proc noVAO*() =
  glBindVertexArray(0)
proc newVAO*(): VAO =
  var vao: GLuint
  glGenVertexArrays(1, vao.addr)
  return vao.VAO

type Mesh* = ref object
  vao*: VAO
  vbo*: VBO
  drawType*: GLenum
  elements*: int
  boundMin*,boundMax*: Vec2f
  uvBoundMin*,uvBoundMax*: Vec2f
  uvs*: seq[Vec2f]
  verts*: seq[Vec2f]

proc draw*(mesh: Mesh) =
  mesh.vao.use()
  glDrawArrays(mesh.drawType, 0, mesh.elements)
  noVAO()

proc loadObj*(filename: string): Mesh =
  var fp = open(filename, fmRead)

  var vertices = newSeq[Vec3f]()
  var uvs = newSeq[Vec2f]()
  var vertIndices = newSeq[int]()
  var uvIndices = newSeq[int]()

  var line: string
  while fp.readLine(line):
    if line.startsWith("v "):
      # vertex
      var x,y,z: float
      if scanf(line, "v $f $f $f", x,y,z):
        vertices.add(vec3f(x,y,z))
      else:
        raise newException(IOError, "invalid vertex: $1".format(line))
    elif line.startsWith("vt "):
      # texcoord
      var u,v: float
      if scanf(line, "vt $f $f", u,v):
        uvs.add(vec2f(u,1.0-v))
      else:
        echo "invalid uv: ", line
    elif line.startsWith("f "):
      # face
      var v1,v2,v3: int
      var uv1,uv2,uv3: int
      var n1,n2,n3: int
      if scanf(line, "f $i/$i/$i $i/$i/$i $i/$i/$i", v1,uv1,n1, v2,uv2,n2, v3,uv3,n3):
        # obj indexing is 1-based
        vertIndices.add([v1-1,v2-1,v3-1])
        uvIndices.add([uv1-1,uv2-1,uv3-1])
      elif scanf(line, "f $i/$i $i/$i $i/$i", v1,uv1, v2,uv2, v3,uv3):
        # obj indexing is 1-based
        vertIndices.add([v1-1,v2-1,v3-1])
        uvIndices.add([uv1-1,uv2-1,uv3-1])
      elif scanf(line, "f $i//$i $i//$i $i//$i", v1,n1, v2,n2, v3,n3):
        vertIndices.add([v1-1,v2-1,v3-1])
      else:
        echo "invalid face: ", line

  fp.close()

  for i in 0..<vertices.len:
    for j in i+1..<vertices.len:
      if vertices[i].xy == vertices[j].xy:
        continue
      let d = (vertices[i].xy - vertices[j].xy).length
      if d < 0.1'f:
        echo "nearby verts: ", vertices[i], " vs ", vertices[j], " d: ", d
        # merge verts
        #vertices[i] = (vertices[i] + vertices[j]) * 0.5'f
        #vertices[j] = vertices[i]

  for i in 0..<uvs.len:
    for j in i+1..<uvs.len:
      if uvs[i].xy == uvs[j].xy:
        continue
      let d = (uvs[i].xy - uvs[j].xy).length
      if d < 0.01'f:
        echo "nearby uvs: ", uvs[i], " vs ", uvs[j], " d: ", d
        # merge
        #uvs[i] = (uvs[i] + uvs[j]) * 0.5'f
        #uvs[j] = uvs[i]

  # data read, now process it for opengl
  var outVertices = newSeq[float32]()

  var boundMin = vec2f(Inf, Inf)
  var boundMax = vec2f(-Inf, -Inf)
  var uvBoundMin = vec2f(Inf, Inf)
  var uvBoundMax = vec2f(-Inf, -Inf)

  var mesh = new(Mesh)
  mesh.vao = newVao()
  mesh.vao.use()

  for i in 0..<vertIndices.len:
    outVertices.add(vertices[vertIndices[i]].x)
    outVertices.add(vertices[vertIndices[i]].y)
    outVertices.add(uvs[uvIndices[i]].x)
    outVertices.add(uvs[uvIndices[i]].y)

    mesh.uvs.add(vec2f(uvs[uvIndices[i]].x, uvs[uvIndices[i]].y))
    mesh.verts.add(vec2f(vertices[vertIndices[i]].x, vertices[vertIndices[i]].y))

    if vertices[vertIndices[i]].x < boundMin.x:
      boundMin.x = vertices[vertIndices[i]].x
    if vertices[vertIndices[i]].y < boundMin.y:
      boundMin.y = vertices[vertIndices[i]].y

    if vertices[vertIndices[i]].x > boundMax.x:
      boundMax.x = vertices[vertIndices[i]].x
    if vertices[vertIndices[i]].y > boundMax.y:
      boundMax.y = vertices[vertIndices[i]].y


    if uvs[uvIndices[i]].x < uvBoundMin.x:
      uvBoundMin.x = uvs[uvIndices[i]].x
    if uvs[uvIndices[i]].y < uvBoundMin.y:
      uvBoundMin.y = uvs[uvIndices[i]].y

    if uvs[uvIndices[i]].x > uvBoundMax.x:
      uvBoundMax.x = uvs[uvIndices[i]].x
    if uvs[uvIndices[i]].y > uvBoundMax.y:
      uvBoundMax.y = uvs[uvIndices[i]].y

  mesh.vbo = newVBO()
  mesh.vbo.use()

  mesh.boundMin = boundMin
  mesh.boundMax = boundMax
  mesh.uvBoundMin = uvBoundMin
  mesh.uvBoundMax = uvBoundMax

  mesh.drawType = GL_TRIANGLES
  mesh.elements = outVertices.len div 4

  glBufferData(GL_ARRAY_BUFFER, sizeof(float32) * outVertices.len, outVertices[0].addr, GL_STATIC_DRAW)
  glVertexAttribPointer(0.GLuint, 4.GLint, cGL_FLOAT, false, (4 * sizeof(float32)).GLsizei, cast[pointer](0))
  glEnableVertexAttribArray(0)

  noVAO()
  noVBO()

  return mesh

proc isNil*(texture: Texture): bool =
  return texture.id == 0

proc use*(texture: Texture) =
  glBindTexture(if texture.msaa: GL_TEXTURE_2D_MULTISAMPLE else: GL_TEXTURE_2D, texture.id)
  #glBindTexture(GL_TEXTURE_2D, texture.id)
  currentTexture = texture.unsafeAddr

proc noTexture*() =
  if currentTexture != nil:
    glBindTexture(if currentTexture.msaa: GL_TEXTURE_2D_MULTISAMPLE else: GL_TEXTURE_2D, 0)
  #glBindTexture(GL_TEXTURE_2D, 0)

proc deleteTexture*(texture: var Texture) =
  glDeleteTextures(1, texture.id.addr)

proc newFramebuffer*(): Framebuffer =
  var fbo: GLuint
  glGenFrameBuffers(1, fbo.addr)

  return fbo.Framebuffer

proc deleteFramebuffer*(fb: var Framebuffer) =
  glDeleteFramebuffers(1, fb.GLuint.addr)

proc createTexture*(name: string, w,h: int, msaa: int = 0): Texture =
  echo "createTexture ", name, " ", w,"x",h, (if msaa > 0: " msaa" else: "")
  result.name = name
  var textureID: GLuint
  let tu = if msaa > 0: GL_TEXTURE_2D_MULTISAMPLE else: GL_TEXTURE_2D
  glGenTextures(1, textureID.addr)
  glBindTexture(tu, textureID)

  if msaa > 0:
    glTexImage2DMultisample(GL_TEXTURE_2D_MULTISAMPLE, msaa, GL_RGBA.GLint, w.GLsizei, h.GLsizei, true)
  else:
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA.GLint, w.GLsizei, h.GLsizei, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)

  glBindTexture(tu, 0)

  result.msaa = msaa > 0
  result.id = textureID
  result.w = w
  result.h = h
  result.aspect = w.float32 / h.float32

proc attachTexture*(framebuffer: Framebuffer, texture: Texture) =
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer.GLuint)
  if texture.msaa:
    glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, texture.id)
  else:
    glBindTexture(GL_TEXTURE_2D, texture.id)

  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, if texture.msaa: GL_TEXTURE_2D_MULTISAMPLE else: GL_TEXTURE_2D, texture.id, 0)

  if texture.msaa:
    glBindTexture(GL_TEXTURE_2D_MULTISAMPLE, 0)
  else:
    glBindTexture(GL_TEXTURE_2D, 0)
  glBindFramebuffer(GL_FRAMEBUFFER, 0)

proc detachTexture*(framebuffer: Framebuffer) =
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer.GLuint)
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0)
  glBindFramebuffer(GL_FRAMEBUFFER, 0)

proc checkFramebuffer*(fbo: Framebuffer): bool =
  glBindFramebuffer(GL_FRAMEBUFFER, fbo.GLuint)
  return glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE

proc loadImage*(filename: string): Texture =
  if textureCache.hasKey(filename):
    return textureCache[filename]

  var w,h,channels: int
  var data = stbi.load(filename, w, h, channels, 0)
  echo "loaded image ", filename, " ", w, "x", h, " channels: ", channels

  var dataFlipped = newSeq[uint8](w*h*channels)
  let stride = w * channels
  for y in 0..<h:
    var sy = (h - 1) - y
    for x in 0..<w:
      for c in 0..<channels:
        dataFlipped[y * stride + x * channels + c] = data[sy * stride + x * channels + c]

  data = dataFlipped

  var textureID: GLuint
  glGenTextures(1, textureID.addr)
  glBindTexture(GL_TEXTURE_2D, textureID)

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)

  if channels == 4:
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA.GLint, w.GLsizei, h.GLsizei, 0, GL_RGBA, GL_UNSIGNED_BYTE, data[0].addr)
  elif channels == 3:
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB.GLint, w.GLsizei, h.GLsizei, 0, GL_RGB, GL_UNSIGNED_BYTE, data[0].addr)
  elif channels == 1:
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED.GLint, w.GLsizei, h.GLsizei, 0, GL_RED, GL_UNSIGNED_BYTE, data[0].addr)

  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR.GLint)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR.GLint)

  glBindTexture(GL_TEXTURE_2D, 0)

  result.name = filename
  result.id = textureID
  result.w = w
  result.h = h
  result.aspect = w.float32 / h.float32

  textureCache[filename] = result

proc createQuad*(w,h: float32, sx,sy: float32 = 1.0'f): Mesh =
  result = new(Mesh)
  result.vao = newVAO()
  result.vbo = newVBO()

  var hw = w * 0.5'f
  var hh = h * 0.5'f

  var vertices = [
    -hw,  hh, 0'f, 1'f*sy,
     hw,  hh, 1'f * sx, 1'f*sy,
    -hw, -hh, 0'f, 0'f,
     hw, -hh, 1'f * sx, 0'f,
  ]

  result.drawType = GL_TRIANGLE_STRIP
  result.elements = 4

  result.vao.use()
  result.vbo.use()
  glBufferData(GL_ARRAY_BUFFER, sizeof(float32) * vertices.len, vertices[0].addr, GL_STATIC_DRAW)
  glVertexAttribPointer(0.GLuint, 4.GLint, cGL_FLOAT, false, (4 * sizeof(float32)).GLsizei, cast[pointer](0))
  glEnableVertexAttribArray(0)
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  noVAO()

proc createLine*(points: seq[Vec2f]): Mesh =
  var points = points
  result = new(Mesh)
  result.vao = newVAO()
  result.vbo = newVBO()

  result.drawType = GL_LINE_STRIP
  result.elements = points.len

  result.vao.use()
  result.vbo.use()
  glBufferData(GL_ARRAY_BUFFER, sizeof(float32) * points.len * 2, points[0].addr, GL_STATIC_DRAW)
  glVertexAttribPointer(0.GLuint, 2.GLint, cGL_FLOAT, false, (2 * sizeof(float32)).GLsizei, cast[pointer](0))
  glEnableVertexAttribArray(0)
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  noVAO()

proc createLineLoop*(points: seq[Vec2f]): Mesh =
  var points = points
  result = new(Mesh)
  result.vao = newVAO()
  result.vbo = newVBO()

  result.drawType = GL_LINE_LOOP
  result.elements = points.len

  result.vao.use()
  result.vbo.use()
  glBufferData(GL_ARRAY_BUFFER, sizeof(float32) * points.len * 2, points[0].addr, GL_STATIC_DRAW)
  glVertexAttribPointer(0.GLuint, 2.GLint, cGL_FLOAT, false, (2 * sizeof(float32)).GLsizei, cast[pointer](0))
  glEnableVertexAttribArray(0)
  glBindBuffer(GL_ARRAY_BUFFER, 0)
  noVAO()

proc createLineRect*(w,h: float32): Mesh =
  result = new(Mesh)
  result.vao = newVAO()
  result.vbo = newVBO()

  var hw = w * 0.5'f
  var hh = h * 0.5'f

  var vertices = @[
    vec2f(-hw,  hh),
    vec2f(hw,  hh),
    vec2f(hw, -hh),
    vec2f(-hw, -hh),
  ]

  return createLineLoop(vertices)

proc savePNG*(texture: Texture, filename: string) =
  texture.use()
  var pixels = newSeq[uint8](texture.w * texture.h * 4)
  glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels[0].addr)
  if stbiw.writePNG(filename, texture.w, texture.h, 4, pixels):
    echo "exported png ", filename
  else:
    echo "error exporting png ", filename
  noTexture()

type RenderTexture* = object
  fb*: Framebuffer
  tex*: Texture

proc createRenderTexture*(name: string, x,y: int): RenderTexture =
  result.tex = createTexture(name, x,y)
  result.fb = newFramebuffer()
  result.fb.attachTexture(result.tex)
  if not result.fb.checkFramebuffer():
    echo "error creating Framebuffer"
  noFramebuffer()

proc startRenderTexture*(rt: RenderTexture) =
  rt.fb.useDraw()

proc stopRenderTexture*(rt: RenderTexture) =
  noFramebuffer()
  noFramebufferDraw()
