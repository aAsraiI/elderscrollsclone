class_name SignatureTrials
extends RefCounted
## Alpha 1.27.4: when a skill reaches 50 and again at 100, a master of it sends word: prove
## yourself by raising it three more levels, and their amulet is yours, one of a kind, made for
## that skill (a Master's Amulet at 50, a Grandmaster's at 100). The trial and its end are in
## the journal. Kept in WorldState "sig/<skill>/<level>" {"state", "goal"}.
## Tutorial hears Skills.skill_leveled_up and calls on_level.

const AT := [50, 100]
const MORE := 3
## skill -> the worn enchantment its amulet carries (the rest: fortify health)
const ENCHANT := {
	"one_handed": "fortify_attack", "two_handed": "fortify_attack", "archery": "fortify_attack", "hand_to_hand": "fortify_attack",
	"dual_wielding": "fortify_attack", "block": "fortify_block", "heavy_armor": "shield", "light_armor": "shield", "unarmored": "shield",
	"sneak": "fortify_sneak", "security": "fortify_lockpicking", "speech": "fortify_speech", "mercantile": "fortify_speech",
	"destruction": "fortify_magicka", "restoration": "regenerate_magicka", "alteration": "fortify_magicka", "conjuration": "fortify_magicka",
	"illusion": "regenerate_magicka", "mysticism": "regenerate_magicka", "acrobatics": "jump", "athletics": "haste",
	"swimming": "fortify_stamina", "riding": "fortify_stamina", "survival": "resist_frost", "hunting": "fortify_agility",
	"herbalism": "regenerate_health", "mining": "feather", "smithing": "fortify_strength", "alchemy": "resist_poison",
	"enchanting": "regenerate_magicka", "leadership": "fortify_charisma", "devotion": "resist_magic", "lore": "fortify_wisdom",
}


static func key(skill: StringName, at: int) -> String:
	return "sig/%s/%d" % [skill, at]


static func state(skill: StringName, at: int) -> String:
	return String(WorldState.get_record(key(skill, at)).get("state", ""))


static func on_level(tree: SceneTree, skills: Skills, skill: StringName, level: int) -> void:
	var def := SkillDatabase.get_skill(skill)
	if def == null:
		return
	for at in AT:
		var rec := WorldState.get_record(key(skill, at))
		if rec.is_empty() and level >= at and level < at + MORE:
			WorldState.set_record(key(skill, at), {"state": "active", "goal": at + MORE})
			var who := "A master" if at == 50 else "A grandmaster"
			DialogueState.system_entry("Knowledge", "%s of %s has heard of me, and sent word: raise my %s to %d to prove it was no fluke, and their amulet is mine." % [who, def.display_name, def.display_name, at + MORE], "")
			Notices.quest(tree, "Trial", "%s: reach %d" % [def.display_name, at + MORE])
		elif String(rec.get("state", "")) == "active" and level >= int(rec.get("goal", at + MORE)):
			_reward(tree, skills, def, at)


static func _reward(tree: SceneTree, skills: Skills, def: SkillData, at: int) -> void:
	WorldState.set_record(key(def.id, at), {"state": "done"})
	var base := load("res://data/jewelry/%s_amulet_vigor.tres" % ("gold" if at == 50 else "starstone")) as ItemData
	var player := skills.get_parent()
	var inv := player.get_node_or_null("Inventory") as Inventory if player != null else null
	if base == null or inv == null:
		return
	var fx := StringName(ENCHANT.get(String(def.id), "fortify_health"))
	var mag := float(Enchanting.WORN.get(fx, 10.0)) * (1.0 if at == 50 else 2.0)
	var title := "%s %s Amulet" % [def.display_name, "Master's" if at == 50 else "Grandmaster's"]
	var item := CraftedItems.gear(base, 3 if at == 50 else 6, [{"id": String(fx), "mag": mag}], 0.0, title)
	inv.add_item(item, 1)
	Achievements.note("trial")
	DialogueState.system_entry("Knowledge", "The trial of %s is done. A courier found me with the %s." % [def.display_name, title], "")
	Notices.quest(tree, "Trial Complete", title)
