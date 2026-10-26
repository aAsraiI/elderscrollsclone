# Quests, dialogue and the journal

How the quest, dialogue and journal systems work (Alpha 1.12), and where to change things.

## Kinds of quest

| Kind | Where it lives | Made by | Handed in |
| --- | --- | --- | --- |
| Guild jobs, bounties, notice-board jobs | `scripts/quests/quest_manager.gd`, `radiant.gd` | generated from the world seed, worded by `data/radiant/*.tres` | "report back" to a guild leader (or the shopkeeper, or the board) |
| Written quests (336, the lore bible) | `scripts/quests/quest_book.gd`, `quest_defs_*.gd` | code (QD builders) | their last talk step |
| Handmade quests | `data/quests/*.tres` (QuestData) | the Inspector, no code | "report back" to the turn-in person |
| The main quest | `scripts/quests/story.gd` | code | the temple priest |

`QuestLog` puts all four in one list for the journal, the tracker and the pause screen.

## Making a handmade quest (no code)

1. Copy one of `data/quests/template_*.tres` (kill, fetch, multi-stage, branching).
2. Untick **Template**, give it a new **Id**, set the **Giver** (`custom/<id>`, `npc/<building id>` or `Name@Town`) and the **Hook** topic.
3. Add **Stages**; each has **Objectives** (Kill, Collect, Deliver, Talk, Reach, Steal, Persuade, Use Item, Discover) and optional **Choices** (branches).
4. Set the rewards (gold, items, a pick-one choice, skill XP, reputation, a flag, a follow-up quest).
5. Run the game: `quest.check` in the debug console (`) lists anything wrong.

States: unavailable, available, active, ready (to turn in), completed, failed, abandoned, expired. Only the allowed changes happen; any other is refused and printed as a `[Quest]` warning.

## Making a person (no code)

`data/npcs/custom/*.tres` (CustomNpcData): name, role, look, place (town and offset, a POI or building id), work hours and home spot, what they carry and wear, a DialogueData with their topics, their own DialogueProfile, and the QuestData they give. Or drop a **CustomNpcSpot** node into any scene. Example: Old Maudrey in Kingsreach (`example_hermit.tres`).

## Dialogue

* Who talks about what: `data/dialogue/profiles/*.tres` (DialogueProfile): general topics, kinds of named topic, how many towns they know, the cap, service buttons, what they train. Roles stack (a guild officer gets the officer profile on top).
* Hand-written lines: DialogueData `.tres` in `data/dialogue/`, or rows in a `.csv` / `.json` there (see `DialogueImport` for the columns; `example_lines.csv`). Answers can have conditions, set flags, give items and offer **choices** (branching).
* Placeholders: `{name}` `{town}` `{guild}` `{nearest_poi}` `{nearest_town}`.
* Rumors (`Rumors`) come from real events and spread a few hundred meters a day.
* Service buttons (`Services`): Barter, Train, Rent Room, Duties, Travel, Repair, Enchant.

## The journal

One entry per topic; small talk is not written down; quests, places, people, rumors and the game's own notes are. Tabs: Quests, Topics, Places, People, Notes, All. Your notes: title, words, pin, colour, a link to a quest or place; Shift+J writes one from anywhere; Export writes them to a text file.

## Debug console (`)

`quest.list`, `quest.why`, `quest.start`, `quest.setstage`, `quest.complete`, `quest.fail`, `quest.reset`, `quest.check`, `quest.overlay`, `dialogue.audit`, `dialogue.report`, `dialogue.lint`, `dialogue.dupes`, `talk <name>`.

## Tests

`test/test_alpha112.gd` plays all of this in the real world: every kind of job end to end, a 100-job soak, saving at every quest state, the journal, notes, dialogue and the tools.

## Changelog

* **Alpha 1.12.15**: phases 1.12.2 to 1.12.15 (everything above), and the fix for the main quest's priest having no topics.
* **Alpha 1.12**: the hand-in fix for guild jobs, role-based topics, one journal entry per topic, player notes, custom NPCs.
