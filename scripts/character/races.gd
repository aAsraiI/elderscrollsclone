class_name Races
extends RefCounted
## The playable peoples. Each has skill bonuses (extra starting levels), lasting traits (Stats
## modifiers: resistances, magicka...) and a once-a-day racial power (Z, see Powers).
##   id: {name, desc, skills {id: levels}, stats {stat: amount}, power, power_desc, skin [colors]}

const LIST := {
	"northlander": {"name": "Northlander", "desc": "Tall, hardy folk of the frozen north. Born warriors who shrug off the cold.",
		"skills": {"two_handed": 10, "heavy_armor": 5, "block": 5, "athletics": 5},
		"stats": {"resist_frost": 0.5, "max_health": 10.0}, "height": 1.06,
		"power": "battle_cry", "power_desc": "Battle Cry: nearby foes up to your level flee for 20 s.",
		"skin": [Color(0.96, 0.84, 0.74), Color(0.93, 0.78, 0.65)]},
	"heartlander": {"name": "Heartlander", "desc": "Citizens of the old empire: diplomats, merchants and disciplined soldiers.",
		"skills": {"speech": 10, "one_handed": 5, "block": 5, "restoration": 5},
		"stats": {"charisma": 5.0, "buy_price_mult": -0.05}, "height": 1.0,
		"power": "voice_of_command", "power_desc": "Voice of Command: calms everyone around you for 30 s.",
		"skin": [Color(0.93, 0.78, 0.65), Color(0.85, 0.66, 0.5)]},
	"sandwalker": {"name": "Sandwalker", "desc": "Desert swordmasters, quick and tough, hard to poison.",
		"skills": {"one_handed": 10, "athletics": 5, "block": 5, "alteration": 5},
		"stats": {"resist_poison": 0.5, "max_stamina": 15.0}, "height": 1.02,
		"power": "adrenaline_rush", "power_desc": "Adrenaline Rush: stamina comes back ten times faster for 60 s.",
		"skin": [Color(0.5, 0.35, 0.24), Color(0.36, 0.25, 0.18)]},
	"marchborn": {"name": "Marchborn", "desc": "Half-elven folk of the western marches with a gift for spells and a skin that turns them.",
		"skills": {"conjuration": 10, "restoration": 5, "alteration": 5, "speech": 5},
		"stats": {"resist_magic": 0.25, "max_magicka": 15.0}, "height": 0.98,
		"power": "dragonskin", "power_desc": "Dragonskin: absorbs half of the spells cast at you for 60 s.",
		"skin": [Color(0.96, 0.84, 0.74), Color(0.93, 0.78, 0.65)]},
	"highborn": {"name": "Highborn", "desc": "Tall, proud elves born to magic. Great reserves of magicka, but the elements bite them harder.",
		"skills": {"destruction": 10, "alteration": 5, "illusion": 5, "enchanting": 5},
		"stats": {"max_magicka": 50.0, "resist_fire": -0.1, "resist_frost": -0.1, "resist_shock": -0.1}, "height": 1.08,
		"power": "highborn", "power_desc": "Highborn: magicka comes back five times faster for 60 s.",
		"skin": [Color(0.95, 0.88, 0.62), Color(0.9, 0.82, 0.55)]},
	"ashborn": {"name": "Ashborn", "desc": "Grey-skinned elves of the volcanic east. Fire hardly touches them.",
		"skills": {"destruction": 10, "light_armor": 5, "one_handed": 5, "sneak": 5},
		"stats": {"resist_fire": 0.5}, "height": 1.0,
		"power": "ancestors_wrath", "power_desc": "Ancestor's Wrath: a burst of fire burns everything around you.",
		"skin": [Color(0.45, 0.48, 0.52), Color(0.38, 0.4, 0.45)]},
	"woodborn": {"name": "Woodborn", "desc": "Small, quick elves of the deep forests. The best archers and sneaks alive.",
		"skills": {"archery": 10, "sneak": 5, "alchemy": 5, "light_armor": 5},
		"stats": {"resist_poison": 0.5, "resist_disease": 0.5, "agility": 5.0}, "height": 0.92,
		"power": "command_animal", "power_desc": "Command Animal: a beast near you fights at your side for 60 s.",
		"skin": [Color(0.68, 0.49, 0.35), Color(0.6, 0.45, 0.3)]},
	"sandcat": {"name": "Sandcat", "desc": "Feline folk of the southern deserts. They see in the dark and strike with claws.",
		"skills": {"sneak": 10, "security": 5, "archery": 5, "one_handed": 5},
		"stats": {"agility": 5.0, "unarmed_damage": 12.0}, "height": 0.98,
		"power": "night_eye_power", "power_desc": "Night Eye: see in the dark for 90 s.",
		"skin": [Color(0.75, 0.6, 0.38), Color(0.55, 0.45, 0.3)]},
	"marshfolk": {"name": "Marshfolk", "desc": "Scaled folk of the swamps. Disease can't touch them and they breathe water.",
		"skills": {"alteration": 10, "security": 5, "light_armor": 5, "restoration": 5},
		"stats": {"resist_disease": 1.0, "resist_poison": 0.5, "water_breathing": 1.0}, "height": 1.0,
		"power": "histskin", "power_desc": "Histskin: health comes back ten times faster for 60 s.",
		"skin": [Color(0.35, 0.5, 0.35), Color(0.4, 0.45, 0.3)]},
	"ironblood": {"name": "Ironblood", "desc": "Green-skinned mountain folk: smiths and berserkers, the toughest of all.",
		"skills": {"heavy_armor": 10, "smithing": 5, "two_handed": 5, "block": 5},
		"stats": {"max_health": 20.0, "strength": 5.0}, "height": 1.05,
		"power": "berserker_rage", "power_desc": "Berserker Rage: for 60 s you take half damage and deal more.",
		"skin": [Color(0.45, 0.55, 0.35), Color(0.38, 0.5, 0.32)]},
}


static func get_race(id: String) -> Dictionary:
	return LIST.get(id, LIST["heartlander"])


static func ids() -> Array:
	return LIST.keys()


## The power as a list of magic effects (what Powers casts)
static func power_effects(power: String) -> Dictionary:
	match power:
		"battle_cry":
			return {"form": SpellData.Form.NOVA, "area": 12.0, "effects": [["fear", 60, 20]]}
		"voice_of_command":
			return {"form": SpellData.Form.NOVA, "area": 15.0, "effects": [["calm", 60, 30]]}
		"adrenaline_rush":
			return {"form": SpellData.Form.SELF, "effects": [["regenerate_stamina", 900, 60]]}
		"dragonskin":
			return {"form": SpellData.Form.SELF, "effects": [["spell_absorption", 50, 60]]}
		"highborn":
			return {"form": SpellData.Form.SELF, "effects": [["regenerate_magicka", 400, 60]]}
		"ancestors_wrath":
			return {"form": SpellData.Form.NOVA, "area": 6.0, "effects": [["fire_damage", 40, 0]]}
		"command_animal":
			return {"form": SpellData.Form.SELF, "effects": [["summon_wolf", 0, 60]]}
		"night_eye_power":
			return {"form": SpellData.Form.SELF, "effects": [["night_eye", 0, 90]]}
		"histskin":
			return {"form": SpellData.Form.SELF, "effects": [["regenerate_health", 200, 60]]}
		"berserker_rage":
			return {"form": SpellData.Form.SELF, "effects": [["fortify_attack", 50, 60], ["shield", 80, 60]]}
	return {}
