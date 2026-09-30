extends Node
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Global game state + state machine (autoload "Game"). Spec section 2.

enum State { MENU, GENERATING, PLACEMENT, BATTLE, GAME_OVER }

const PLAYER_COLORS: Array[String] = ["#e74c3c", "#3498db", "#2ecc71", "#f1c40f", "#9b59b6", "#e67e22", "#1abc9c", "#ff6fb5"]
const HUMAN_NAMES: Array[String] = [
	"Sir Reginald von Bumblebutt", "Lady Guinevere Flatulence", "Baron Von Kaboom", "Duke Dudley Doomsday",
	"Lord Fluffington", "Countess Cheesewheel", "Prince Pumpernickel", "Dame Doreen Dungpile",
	"Sir Loin of Beef", "Lord Percival Pickle", "Earl of Hamburg", "Baroness Butterfingers",
	"Sir Cumference", "Squire Squishy", "Queen Mildred the Moist", "King Kevin the Kinda Okay"]
const CPU_NAMES: Dictionary = {
	"peasant": ["Gary the Peasant", "Old Man Hobbs", "Bertha the Baffled", "Dim Dave", "Wobbly Wilf", "Turnip Tom", "Clumsy Clara", "Peasant Pete"],
	"squire": ["Squire Steve", "Squire Sheila", "Junior Knight Jim", "Apprentice Alfred", "Shieldbearer Sally", "Trainee Trevor", "Bucket-Head Bob", "Squire Sue"],
	"knight": ["Sir Lancelot-ish", "Sir Bash-a-Lot", "Dame Dragonbane", "Sir Reads-a-Lot", "Sir Robin the Not-So-Brave", "Sir Galahad Gains", "Dame Gwendolyn Grimm", "Sir Kills-a-Lot"],
	"king": ["King Kaboom I", "King Cruelbeard", "King Mad-Ness the Magnificent", "Emperor Explosion", "Kaiser Chaos", "King Arthur's Evil Twin", "Queen Catastrophe", "His Royal Highness Rick"],
}
const SETTLER_NAMES: Array[String] = ["Bob", "Hilda", "Wat", "Agnes", "Ethelred", "Mabel", "Godric", "Petronella", "Ned", "Wulfric", "Beatrix", "Cuthbert", "Gertrude", "Osric", "Winifred", "Alaric", "Sybil", "Egbert", "Millicent", "Thaddeus"]

var state: int = State.MENU
var players: Array[PlayerData] = []
var seed_str: String = ""
var rng_battle: Rng = Rng.new(1)

# match options (copied from Settings at START)
var turn_timer: int = 30
var weather_on: bool = true
var events_on: bool = true
var catapults_per_player: int = 5
var palisades_per_player: int = 4
var arsenal: Dictionary = {}
var layout_nonce: String = ""       # decides the village layout together with the seed (new for every fresh match)
var terrain_hills: int = 2           # 0 flat .. 4 very hilly

# battle state
var wind: Vector2 = Vector2.ZERO
var weather: String = "clear"
var weather_turns_left: int = 0
var turn_number: int = 0
var current_player: int = 0
var elimination_count: int = 0
var last_winner: int = -1
var time_scale_user: float = 1.0     # spectator fast-forward toggle (x3)
var world: Node = null                # GameWorld (set by main)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func set_state(s: int) -> void:
	if state == s:
		return
	state = s
	Events.state_changed.emit(s)

func player(id: int) -> PlayerData:
	if id < 0 or id >= players.size():
		return null
	return players[id]

func cur() -> PlayerData:
	return player(current_player)

## The human whose marker / overview we show: the current player if human, else the first living human (CPU turns)
func viewer() -> PlayerData:
	var c: PlayerData = cur()
	if c != null and c.is_human():
		return c
	for p in players:
		if p.is_human() and not p.eliminated:
			return p
	return null

func living_players() -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for p in players:
		if not p.eliminated:
			out.append(p)
	return out

func all_cpu() -> bool:
	for p in players:
		if p.is_human():
			return false
	return true

func wind_speed() -> float:
	return wind.length()

func color_of(i: int) -> Color:
	return Color.html(PLAYER_COLORS[i % PLAYER_COLORS.size()])

## Build the default player list for the menu (pool order shuffled by the seed)
func default_players(count: int, seed_text: String) -> Array:
	var rng := Rng.from_string(seed_text + "-names")
	var pool: Array = HUMAN_NAMES.duplicate()
	rng.shuffle(pool)
	var out: Array = []
	for i in count:
		out.append({"name": str(pool[i % pool.size()]), "color": i, "type": "human" if i == 0 else "peasant"})
	return out

func cpu_name(type: String, used: Array, rng: Rng) -> String:
	var pool: Array = (CPU_NAMES[type] as Array).duplicate() if CPU_NAMES.has(type) else HUMAN_NAMES.duplicate()
	rng.shuffle(pool)
	for n in pool:
		if not used.has(n):
			return str(n)
	return str(pool[0])
