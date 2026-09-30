local V = ...
local FirstPerson = V.require("FirstPerson")
local TouchControls = require("src.core.TouchControls")
local NativeCamera = {}
local axes = { x = 0, y = 0 }

local function response(value)
  local magnitude = math.abs(value)
  if magnitude <= FirstPerson.STICK_DEAD then return 0 end
  magnitude = (magnitude - FirstPerson.STICK_DEAD) / (1 - FirstPerson.STICK_DEAD)
  return (value < 0 and -1 or 1) * magnitude * magnitude
end

function NativeCamera.update(dt)
  FirstPerson.update(dt)
  if FirstPerson.driving() then
    FirstPerson.lookBy(-response(axes.x) * FirstPerson.STICK_YAW * dt,
      response(axes.y) * FirstPerson.STICK_PITCH * dt)
  end
end

function NativeCamera.install(game, gate)
  FirstPerson.captureAllowed = gate
  local mousemoved = game.mousemoved
  game.mousemoved = function(self, x, y, dx, dy, istouch)
    if gate() and FirstPerson.driving() and not istouch then
      FirstPerson.lookBy(-(dx or 0) * FirstPerson.MOUSE_SENS,
        (dy or 0) * FirstPerson.MOUSE_SENS)
      return
    end
    return mousemoved(self, x, y, dx, dy, istouch)
  end
  local gamepadaxis = game.gamepadaxis
  game.gamepadaxis = function(self, joystick, axis, value)
    if axis == "rightx" then axes.x = value
    elseif axis == "righty" then axes.y = value end
    return gamepadaxis(self, joystick, axis, value)
  end
  local pressed, released = game.mousepressed, game.mousereleased
  local held, buttons = {}, { [1] = "a", [2] = "b" }
  game.mousepressed = function(self, x, y, button, istouch)
    if gate() and FirstPerson.driving() and not istouch and buttons[button] then
      held[button] = buttons[button]
      self.input:overlayPressed(buttons[button])
      return
    end
    return pressed(self, x, y, button, istouch)
  end
  game.mousereleased = function(self, x, y, button, istouch)
    if held[button] then
      self.input:overlayReleased(held[button])
      held[button] = nil
      return
    end
    return released(self, x, y, button, istouch)
  end
  local touch
  local touchpressed, touchmoved, touchreleased = game.touchpressed, game.touchmoved, game.touchreleased
  game.touchpressed = function(self, id, x, y, ...)
    if gate() and FirstPerson.driving() and not touch and not TouchControls:hitTest(x, y) then
      touch = { id = id, x = x, y = y }
      return
    end
    return touchpressed(self, id, x, y, ...)
  end
  game.touchmoved = function(self, id, x, y, ...)
    if touch and touch.id == id then
      if gate() and FirstPerson.driving() then
        local scale = FirstPerson.TOUCH_TURN / math.max(320, love.graphics.getWidth())
        FirstPerson.lookBy(-(x - touch.x) * scale, (y - touch.y) * scale)
      end
      touch.x, touch.y = x, y
      return
    end
    return touchmoved(self, id, x, y, ...)
  end
  game.touchreleased = function(self, id, ...)
    if touch and touch.id == id then touch = nil return end
    return touchreleased(self, id, ...)
  end
end

return NativeCamera