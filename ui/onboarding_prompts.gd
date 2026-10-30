extends RefCounted
## TASK-053: nonblocking context hints; dismiss and reopen in same session.
const TIPS := {
	"combat":"Mouse aims. Left/right click cast the two starter spells; Space dashes. Water makes targets Wet; Lightning hitting Wet can arc to another Wet target.",
	"reward":"Runes are reusable knowledge, not consumable items. Choose a new rune to expand the editor or choose currency.",
	"editor":"A spell combines Essence (what), Manifestation (shape), optional Modifier (behavior). On Hit only works on Projectile and MUST include a Burst payload with its own Essence.",
	"workshop":"Edit your spell, Apply a valid draft, then test on dummies without changing run HP or currency. Prepare Wet targets and use Lightning to discover arcs.",
	"shop":"Spend boss currency to unlock a new reusable rune or a numeric HP upgrade; stock is fixed for this run seed.",
	"door":"After combat and pending waves are complete, approach the green EXIT marker and press E."
}
var dismissed := false
var shown: Dictionary = {}
func dismiss() -> void:
	dismissed = true
func reopen() -> void:
	dismissed = false
func message(context: String) -> String:
	if dismissed:
		return ""
	shown[context] = true
	return str(TIPS.get(context,""))
