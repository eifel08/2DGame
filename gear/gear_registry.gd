class_name GearRegistry
extends RefCounted
## Every tool and pouch in the game. Add new ones here (or load .tres files
## made in the editor and add them with GearManager.add_tool / add_pouch).
## Lore and curse texts never state a number: the exact effects are hidden
## in the GearEffects (see the comments for the values).

const W := GearTier.Tier.WEAK
const M := GearTier.Tier.MEDIUM
const S := GearTier.Tier.STRONG


static func create_tools() -> Array[ToolData]:
	return [
		# Weak: normal attack range +10 %.
		ToolData.make("longreach_ribbon", "Longreach Ribbon", W,
			"A frayed ribbon knotted around the wrist. Every swing carries a little farther than the arm that makes it.",
			[StatGearEffect.make("attack_range_mul", 1.1)]),
		# Weak: movement (running) speed +5 %. Jumps and dashes are untouched.
		ToolData.make("wayfarer_anklet", "Wayfarer's Anklet", W,
			"A thin chain of river stones. The stride grows lighter, though the leap stays just as it was.",
			[StatGearEffect.make("run_speed_mul", 1.05)]),
		# Medium: 15 % of the damage taken comes back as energy.
		ToolData.make("scar_lantern", "Scar Lantern", M,
			"A cracked lantern that drinks the light of fresh wounds. The pain is not lost; it is kept, and burns again as power.",
			[DamageToEnergyEffect.make(0.15)]),
		# Medium: dash and hook recovery 15 % shorter.
		ToolData.make("quickening_hourglass", "Quickening Hourglass", M,
			"Its sand falls upward. Whatever must rest between uses rests a little less.",
			[StatGearEffect.make("cooldown_mul", 0.85)]),
		# Strong: with full energy, basic attacks send a shockwave for +30 % damage.
		ToolData.make("brimming_crest", "Brimming Crest", S,
			"A crest that hums when the vessel within is full to the brim. Then every strike spills over into a wave of its own.",
			[FullEnergyShockwaveEffect.make(0.3)]),
	]


static func create_pouches() -> Array[PouchData]:
	return [
		# Weak + Weak. Curse: spell and heal energy cost +5 %. Energy only:
		# jumps, gravity and all other platforming stay exactly the same.
		PouchData.make("patched_satchel", "Patched Satchel", [W, W],
			"A traveller's satchel sewn from old cloaks. Room for two small charms.",
			"Its seams fray around every spell and every mend: casting and healing ask a little more of you.",
			[StatGearEffect.make("energy_cost_mul", 1.05)]),
		# Medium + Medium. Curse: passive energy leak +12 % (Config.vitals.energy_leak_rate).
		PouchData.make("hollow_reliquary", "Hollow Reliquary", [M, M],
			"A twin-chambered reliquary of hammered tin, still warm from some forgotten shrine.",
			"Its hollow chambers are never quite sealed: stored energy seeps away faster than it should.",
			[StatGearEffect.make("energy_leak_mul", 1.12)]),
		# Strong + Medium + Weak. Curse: damage from enemies (contact and projectiles) +20 %.
		PouchData.make("bloodbound_coffer", "Bloodbound Coffer", [S, M, W],
			"An iron coffer with three locks of different sizes. Each opens only for what it was forged to hold.",
			"It bound itself with your blood: the blows of creatures cut deeper while you carry it.",
			[StatGearEffect.make("damage_taken_mul", 1.2)]),
	]
