class_name QD
extends RefCounted
## Builders for quest data (see QuestBook): each quest of the design bible is a few lines of
## these instead of a hand-written dictionary. Everything returns plain Dictionaries/Arrays.
##
##   QD.q("S-KR01", "False Crowns", "Kingsreach", QD.cast("Watch Captain Bertil Ames", "Kingsreach"), 2,
##       "false crowns", "Fake crowns are everywhere...", [steps...], QD.reward(300))
##
## People (who): QD.giver(), QD.lord(town), QD.cast(name, town, at), QD.guild(faction),
##   QD.leader(faction), QD.spawn(place, name, body)
## Places: QD.town(town), QD.dun(near, k), QD.camp(near, k), QD.wild(near, dist, angle),
##   where `near` is a town name or a biome key
## Steps: talk, choice, clear, fetch, fight, visit, collect, wait, realm


# ---------------------------------------------------------------- the quest

static func q(id: String, name: String, group: String, giver: Dictionary, level: int, hook: String, intro: String,
		steps: Array, reward: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "name": name, "group": group, "giver": giver, "level": level, "hook": hook,
		"intro": intro, "steps": steps, "reward": reward, "after": [], "faction": "", "rank": 0, "affliction": ""}
	d.merge(extra, true)
	return d


## Extra quest settings, merged into q(): QD.req(["S-KR04"]), QD.fac("valcourt", 2)
static func req(after: Array) -> Dictionary:
	return {"after": after}


static func fac(faction: String, rank: int = 1, after: Array = []) -> Dictionary:
	return {"faction": faction, "rank": rank, "after": after}


# ---------------------------------------------------------------- people

static func giver() -> Dictionary:
	return {"giver": true}


static func lord(town: String) -> Dictionary:
	return {"lord": town}


## A named person living in a town; `at` is where they live: house, inn, temple, smithy, shop,
## guild:<id> or seat (they share the lord's hall)
static func cast(name: String, town: String, at: String = "house") -> Dictionary:
	return {"cast": name, "town": town, "at": at}


## Whoever leads a guild's hall (any town)
static func guild(faction: String) -> Dictionary:
	return {"guild": faction}


## The leader of a house, clan or pack (FactionData.leader_name)
static func leader(faction: String) -> Dictionary:
	return {"leader": faction}


## Someone met out in the world, who appears when you come near the place
static func spawn(place: Dictionary, name: String, body: String = "pilgrim") -> Dictionary:
	return {"spawn": place, "name": name, "body": body}


# ---------------------------------------------------------------- places

static func town(t: String) -> Dictionary:
	return {"town": t}


## The k-th nearest dungeon with a master in its deepest hall
static func dun(near: String, k: int = 0) -> Dictionary:
	return {"dungeon": near, "k": k}


## The k-th nearest camp or ruin with a garrison
static func camp(near: String, k: int = 0) -> Dictionary:
	return {"camp": near, "k": k}


## A spot out in the land, `dist` meters from the town (or biome middle) at `ang` degrees
static func wild(near: String, dist: float = 350.0, ang: float = 0.0) -> Dictionary:
	return {"wild": near, "dist": dist, "ang": ang}


# ---------------------------------------------------------------- steps

static func talk(who: Dictionary, topic: String, say: String, text: String, extra: Dictionary = {}) -> Dictionary:
	var d := {"do": "talk", "who": who, "topic": topic, "say": say, "text": text}
	d.merge(extra, true)
	return d


## Pick one of several answers (each a topic); the flag is remembered (QuestBook.flag)
static func choice(who: Dictionary, text: String, options: Array) -> Dictionary:
	return {"do": "choice", "who": who, "text": text, "options": options}


static func opt(topic: String, say: String, flag: String) -> Dictionary:
	return {"topic": topic, "say": say, "flag": flag}


static func clear(place: Dictionary, text: String) -> Dictionary:
	return {"do": "clear", "at": place, "text": text}


## A quest item waiting in the deepest chest of a dungeon
static func fetch(place: Dictionary, item: String, text: String) -> Dictionary:
	return {"do": "fetch", "at": place, "item": item, "text": text}


## Foes that appear at a place when you come near: [[body, count, name], ...] (see QD.f)
static func fight(place: Dictionary, foes: Array, text: String) -> Dictionary:
	return {"do": "fight", "at": place, "foes": foes, "text": text}


static func f(body: String, count: int = 1, name: String = "") -> Array:
	return [body, count, name]


static func visit(place: Dictionary, text: String, radius: float = 40.0) -> Dictionary:
	return {"do": "visit", "at": place, "radius": radius, "text": text}


## Carry `count` of a real item (a resource path under res://scripts/Resources/)
static func collect(item: String, count: int, text: String) -> Dictionary:
	return {"do": "collect", "item": item, "count": count, "text": text}


static func wait(hours: float, text: String) -> Dictionary:
	return {"do": "wait", "hours": hours, "text": text}


## Enter an instanced realm (R1..R12) and defeat what rules its heart
static func realm(id: String, text: String) -> Dictionary:
	return {"do": "realm", "realm": id, "text": text}


## Defeat the guards of one of a realm's sites (its number in RealmManager.REALMS[id]["sites"])
static func site(id: String, k: int, text: String) -> Dictionary:
	return {"do": "site", "realm": id, "site": k, "text": text}


## Someone who lives in a realm's hub (a name from RealmManager.REALMS[id]["npcs"])
static func realm_npc(id: String, name: String) -> Dictionary:
	return {"realm_npc": name, "realm": id}


# ---------------------------------------------------------------- rewards

## gold, plus any of: "items" [paths], "named" [named()], "perk" {stat: amount}, "title", "home"
## (a town whose house for sale becomes yours), "spell", "join" (a faction), "xp" (deed weight)
static func reward(gold: int, extra: Dictionary = {}) -> Dictionary:
	var d := {"gold": gold}
	d.merge(extra, true)
	return d


## A unique named item made from a base item: fx = [[effect id, magnitude], ...]
static func named(name: String, base: String, fx: Array = [], quality: int = 3) -> Dictionary:
	return {"name": name, "base": base, "fx": fx, "q": quality}
