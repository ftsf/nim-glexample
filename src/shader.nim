import opengl
import glm
import nre
import os
import times
import strutils
import tables

type
  UniformKind* = enum
    uFloat32
    uVec2f
    uVec3f
    uVec4f
    uMat4f
    uInt
    uBool
  Uniform* = object
    name: string
    case kind: UniformKind
    of uFloat32: floatVal: float32
    of uVec2f: vec2Val: Vec2f
    of uVec3f: vec3Val: Vec3f
    of uVec4f: vec4Val: Vec4f
    of uMat4f: mat4Val: Mat4f
    of uInt: intVal: GLint
    of uBool: boolVal: GLboolean
  Shader* = ref object
    id*: GLuint
    name*: string
    uniforms: seq[Uniform]
    vertexShaderFile: string
    fragmentShaderFile: string
    lastModified: Time
    uniformLocations: Table[string, GLint]

proc use*(self: Shader)
proc getUniformLocation*(self: Shader, name: string): GLint
proc setUniformVec4f*(self: Shader, name: string, v: Vec4f)
proc setUniformVec3f*(self: Shader, name: string, v: Vec3f)
proc setUniformVec2f*(self: Shader, name: string, v: Vec2f)
proc setUniformMat4f*(self: Shader, name: string, m: var Mat4f)
proc setUniformMat4f*(self: Shader, name: string, m: Mat4f)
proc setUniformFloat*(self: Shader, name: string, f: float32)
proc setUniformInt*(self: Shader, name: string, i: int)
proc setUniformBool*(self: Shader, name: string, b: bool)
proc getUniforms*(self: Shader): seq[Uniform]

var shaders = newSeq[Shader]()

proc use*(self: Shader) =
  assert(self.id != 0)
  glUseProgram(self.id)

proc getUniformLocation*(self: Shader, name: string): GLint =
  assert(self.id != 0)
  if self.uniformLocations.hasKey(name):
    return self.uniformLocations[name]
  result = glGetUniformLocation(self.id, name)
  self.uniformLocations[name] = result
  #if result == -1:
  #  #raise newException(Exception, "Uniform " & name & " not found")
  #  #echo "WARNING: Uniform " & name & " not found in shader: " & self.name

proc setUniformVec4f(self: Shader, name: string, v: Vec4f) =
  let loc = self.getUniformLocation(name)
  if loc != -1:
    glUniform4f(loc, v.x, v.y, v.z, v.w)

proc setUniformVec3f(self: Shader, name: string, v: Vec3f) =
  let loc = self.getUniformLocation(name)
  if loc != -1:
    glUniform3f(loc, v.x, v.y, v.z)

proc setUniformVec2f(self: Shader, name: string, v: Vec2f) =
  let loc = self.getUniformLocation(name)
  if loc != -1:
    glUniform2f(loc, v.x, v.y)

proc setUniformMat4f(self: Shader, name: string, m: var Mat4f) =
  let loc = self.getUniformLocation(name)
  if loc != -1:
    glUniformMatrix4fv(loc, 1, false, m[0].caddr)

proc setUniformMat4f(self: Shader, name: string, m: Mat4f) =
  var mcopy = m
  let loc = self.getUniformLocation(name)
  if loc != -1:
    glUniformMatrix4fv(loc, 1, false, mcopy.caddr)

proc setUniformFloat(self: Shader, name: string, f: float32) =
  let loc = self.getUniformLocation(name)
  if loc != -1:
    glUniform1f(loc, f)

proc setUniformInt(self: Shader, name: string, i: int) =
  let loc = self.getUniformLocation(name)
  if loc != -1:
    glUniform1i(loc, i.GLint)

proc setUniformBool(self: Shader, name: string, b: bool) =
  let loc = self.getUniformLocation(name)
  if loc != -1:
    glUniform1i(loc, b.GLint)

proc getUniformsInternal(self: Shader): seq[tuple[name: string, kind: GLenum]] =
  var count: GLint
  glGetProgramiv(self.id, GL_ACTIVE_UNIFORMS, count.addr)

  var bufSize = 16.GLsizei
  var kind: GLenum
  var size: GLint
  var name: array[16,char]
  var length: GLsizei

  result = newSeq[tuple[name: string, kind: GLenum]](count)

  for i in 0..<count:
    glGetActiveUniform(self.id, i.GLuint, bufSize, length.addr, size.addr, kind.addr, name[0].addr)
    result[i] = (name: $name, kind: kind)

proc linkShader(self: Shader, vertexShaderId, fragmentShaderId: GLuint) =
  self.id = glCreateProgram()

  glAttachShader(self.id, vertexShaderId)
  glAttachShader(self.id, fragmentShaderId)

  glBindAttribLocation(self.id, 0, "position")

  glLinkProgram(self.id)

  var res: GLint = 0
  var logLength: GLint
  glGetProgramiv(self.id, GL_LINK_STATUS, res.addr)

  glGetProgramiv(self.id, GL_INFO_LOG_LENGTH, logLength.addr)
  if logLength > 0:
    echo "linking: v: ", self.vertexShaderFile, " f: ", self.fragmentShaderFile
    var log = newString(logLength+1)
    glGetProgramInfoLog(self.id, logLength, nil, log[0].addr)
    echo log

  if res != GL_TRUE.GLint:
    raise newException(Exception, "Error linking shader: " & self.vertexShaderFile & " + " & self.fragmentShaderFile)

  glDetachShader(self.id, vertexShaderId)
  glDetachShader(self.id, fragmentShaderId)

  glDeleteShader(vertexShaderId)
  glDeleteShader(fragmentShaderId)

  assert(glIsProgram(self.id) == true)

proc compileShader*(filename: string, shaderType: GLenum): GLuint =
  result = glCreateShader(shaderType)

  proc reIncludeFile(match: RegexMatch): string =
    var fn = joinPath(filename.parentDir(), match.captures[0].extractFilename())
    result = readFile(fn)

  var shaderString = readFile(filename)
  shaderString = nre.replace(shaderString, re"""#include "(.*)"""", reIncludeFile)
  var shaderSource = allocCStringArray([
    shaderString
  ])
  glShaderSource(result, 1, shaderSource, nil)
  glCompileShader(result)

  var res: GLint = 0
  var logLength: GLint

  glGetShaderiv(result, GL_COMPILE_STATUS, res.addr)
  glGetShaderiv(result, GL_INFO_LOG_LENGTH, logLength.addr)
  if logLength > 0:
    var i = 1
    for line in shaderString.splitLines:
      echo i, ": ", line
      i += 1
    var log = newString(logLength+1)
    glGetShaderInfoLog(result, logLength, nil, log[0].addr)
    echo log

  if res != GL_TRUE.GLint:
    raise newException(Exception, "Error compling shader: " & filename)


proc loadShader*(vertexShader: string, fragmentShader: string): Shader =
  result = new(Shader)

  result.name = vertexShader & " + " & fragmentShader

  result.vertexShaderFile = vertexShader
  result.fragmentShaderFile = fragmentShader

  var vertexShaderId: GLuint
  var fragmentShaderId: GLuint
  try:
    vertexShaderId = compileShader(vertexShader, GL_VERTEX_SHADER)
    fragmentShaderId = compileShader(fragmentShader, GL_FRAGMENT_SHADER)
    result.linkShader(vertexShaderId, fragmentShaderId)
  except:
    echo "error loading shader: ", result.name
    vertexShaderId = compileShader("shaders/error.v.glsl", GL_VERTEX_SHADER)
    fragmentShaderId = compileShader("shaders/error.f.glsl", GL_FRAGMENT_SHADER)
    result.linkShader(vertexShaderId, fragmentShaderId)
    result.uniforms = newSeq[Uniform]()
    result.lastModified = max(getLastModificationTime(vertexShader), getLastModificationTime(fragmentShader))
    shaders.add(result)
    return result

  result.uniforms = newSeq[Uniform]()
  result.uniformLocations = initTable[string,GLint]()

  for v in result.getUniformsInternal():
    var u = Uniform(name: v.name, kind: case v.kind:
      of cGL_FLOAT: uFloat32
      of cGL_INT: uInt
      of GL_FLOAT_MAT4: uMat4f
      of GL_FLOAT_VEC2: uVec2f
      of GL_FLOAT_VEC3: uVec3f
      of GL_FLOAT_VEC4: uVec4f
      of GL_BOOL: uBool
      else: uFloat32
    )
    case u.kind:
    of uFloat32: u.floatVal = 0.0
    of uVec2f: u.vec2Val = vec2f(0,0)
    of uVec3f: u.vec3Val = vec3f(0,0,0)
    of uVec4f: u.vec4Val = vec4f(0,0,0,0)
    of uMat4f: u.mat4Val = mat4f()
    of uInt: u.intVal = 0
    of uBool: u.boolVal = false
    result.uniforms.add(u)

  result.lastModified = max(getLastModificationTime(vertexShader), getLastModificationTime(fragmentShader))
  shaders.add(result)

proc reloadShader*(self: Shader) =
  if getLastModificationTime(self.vertexShaderFile) <= self.lastModified and getLastModificationTime(self.fragmentShaderFile) <= self.lastModified:
    return

  var vertexShaderId: GLuint
  var fragmentShaderId: GLuint
  try:
    vertexShaderId = compileShader(self.vertexShaderFile, GL_VERTEX_SHADER)
    fragmentShaderId = compileShader(self.fragmentShaderFile, GL_FRAGMENT_SHADER)
    self.linkShader(vertexShaderId, fragmentShaderId)
  except:
    echo "error reloading shader: ", self.name
    vertexShaderId = compileShader("shaders/error.v.glsl", GL_VERTEX_SHADER)
    fragmentShaderId = compileShader("shaders/error.f.glsl", GL_FRAGMENT_SHADER)
    self.linkShader(vertexShaderId, fragmentShaderId)
    self.uniforms = newSeq[Uniform]()
    self.lastModified = max(getLastModificationTime(self.vertexShaderFile), getLastModificationTime(self.fragmentShaderFile))
    return

  self.lastModified = max(getLastModificationTime(self.vertexShaderFile), getLastModificationTime(self.fragmentShaderFile))

  echo "reloaded shader: v:", self.vertexShaderFile, " + f:", self.fragmentShaderFile, " = id: ", self.id

  self.uniforms = newSeq[Uniform]()

  for v in self.getUniformsInternal():
    var u = Uniform(name: v.name, kind: case v.kind:
      of cGL_FLOAT: uFloat32
      of cGL_INT: uInt
      of GL_FLOAT_MAT4: uMat4f
      of GL_FLOAT_VEC2: uVec2f
      of GL_FLOAT_VEC3: uVec3f
      of GL_FLOAT_VEC4: uVec4f
      of GL_BOOL: uBool
      else: uFloat32
    )
    case u.kind:
    of uFloat32: u.floatVal = 0.0
    of uVec2f: u.vec2Val = vec2f(0,0)
    of uVec3f: u.vec3Val = vec3f(0,0,0)
    of uVec4f: u.vec4Val = vec4f(0,0,0,0)
    of uMat4f: u.mat4Val = mat4f()
    of uInt: u.intVal = 0
    of uBool: u.boolVal = false
    self.uniforms.add(u)

proc getUniforms*(self: Shader): seq[Uniform] =
  return self.uniforms

proc reloadShaders*() =
  for shader in shaders:
    shader.reloadShader()
