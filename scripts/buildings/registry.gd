class_name Buildings
extends RefCounted
@warning_ignore_start("unsafe_cast", "unsafe_call_argument", "unsafe_method_access", "unsafe_property_access")
## Registry of building builders (spec 9). Every builder file exports DEF + static build(ctx, rng, opts).

static func def(id: String) -> Dictionary:
	match id:
		"farmhouse":
			return BFarmhouse.DEF
		"barn":
			return BBarn.DEF
		"tavern":
			return BTavern.DEF
		"church":
			return BChurch.DEF
		"watchtower":
			return BWatchtower.DEF
		"well":
			return BWell.DEF
		"stall":
			return BStall.DEF
		"stable":
			return BStable.DEF
		"granary":
			return BGranary.DEF
		"powderstore":
			return BPowderStore.DEF
		"watertower":
			return BWaterTower.DEF
		"windmill":
			return BWindmill.DEF
		"blacksmith":
			return BBlacksmith.DEF
		"outhouse":
			return BOuthouse.DEF
		"palisade":
			return BPalisade.DEF
		"stonewall":
			return BStoneWall.DEF
		"tree":
			return BTree.DEF
		"ruin":
			return BRuin.DEF
	return BFarmhouse.DEF

static func build(id: String, ctx: BuildContext, rng: Rng, opts: Dictionary = {}) -> BuildResult:
	match id:
		"farmhouse":
			return BFarmhouse.build(ctx, rng, opts)
		"barn":
			return BBarn.build(ctx, rng, opts)
		"tavern":
			return BTavern.build(ctx, rng, opts)
		"church":
			return BChurch.build(ctx, rng, opts)
		"watchtower":
			return BWatchtower.build(ctx, rng, opts)
		"well":
			return BWell.build(ctx, rng, opts)
		"stall":
			return BStall.build(ctx, rng, opts)
		"stable":
			return BStable.build(ctx, rng, opts)
		"granary":
			return BGranary.build(ctx, rng, opts)
		"powderstore":
			return BPowderStore.build(ctx, rng, opts)
		"watertower":
			return BWaterTower.build(ctx, rng, opts)
		"windmill":
			return BWindmill.build(ctx, rng, opts)
		"blacksmith":
			return BBlacksmith.build(ctx, rng, opts)
		"outhouse":
			return BOuthouse.build(ctx, rng, opts)
		"palisade":
			return BPalisade.build(ctx, rng, opts)
		"stonewall":
			return BStoneWall.build(ctx, rng, opts)
		"tree":
			return BTree.build(ctx, rng, opts)
		"ruin":
			return BRuin.build(ctx, rng, opts)
	return BFarmhouse.build(ctx, rng, opts)

static func all_ids() -> Array[String]:
	return ["farmhouse", "barn", "tavern", "church", "watchtower", "well", "stall", "stable", "granary",
		"powderstore", "watertower", "windmill", "blacksmith", "outhouse", "palisade", "stonewall"]
