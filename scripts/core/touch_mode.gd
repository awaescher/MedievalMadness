class_name TouchMode
extends RefCounted
## Is the player using a touch screen (phone / tablet) right now? Then the HUD shows touch buttons instead of key caps.
## Start value: the browser reports a coarse primary pointer (`pointer: coarse`) or the OS is a mobile one. After that the
## game follows the player: a touch switches touch mode on, a real key press switches it off (a tablet with a keyboard).

## `InputEvent.device` of the key events the touch buttons make themselves (they must not count as a keyboard)
const DEVICE := 7001

static var on: bool = false

static func detect() -> void:
	if OS.has_feature("web"):
		on = bool(JavaScriptBridge.eval("window.matchMedia('(pointer: coarse)').matches", true))
	else:
		on = OS.has_feature("mobile")

## Called with every input event; returns true when the mode changed
static func note(ev: InputEvent) -> bool:
	var was: bool = on
	if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
		on = true
	elif ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).device != DEVICE:
		on = false
	return on != was

## A key press / release made by a touch button (reaches `Input.is_key_pressed` and the key handlers like the real key)
static func key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	ev.device = DEVICE
	Input.parse_input_event(ev)
