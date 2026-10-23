class_name DialogueTopic
extends Resource
## A hand-written topic in a DialogueData: its name in the topic list and its possible answers.

## The name shown in the topic list. Using the name of a generated topic ("latest rumors",
## a town, a person) replaces what the game would have said.
@export var topic := ""
## Tried in order: the first answer whose conditions pass is spoken. None pass = the speaker's
## normal answer (or nothing, for a new topic).
@export var responses: Array[DialogueResponse] = []
## The player learns this topic as soon as they greet someone who has it
@export var learn_on_greeting := false


func pick(disposition: int) -> DialogueResponse:
	for r in responses:
		if r != null and r.passes(disposition):
			return r
	return null
