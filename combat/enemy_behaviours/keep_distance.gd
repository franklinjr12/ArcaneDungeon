extends "res://combat/enemy_behaviours/behaviour.gd"
## Movement: hold a band around preferred_range; optional lateral strafe (side from target.id % 2).
## Approach when beyond preferred+approach_margin (or sight is blocked, if approach_without_sight);
## retreat when inside preferred-retreat_margin. Weights of exactly 1.0 and strafe_factor 0 take the
## unweighted path so traces stay bit-identical with the pre-v2 adept.
const ROLE := "movement"

func movement(enemy, session, ctx: Dictionary) -> Vector2:
	var toward: Vector2 = ctx["toward"]
	var distance: float = ctx["distance"]
	var preferred: float = float(param(enemy,"preferred_range"))
	var strafe_factor: float = float(param(enemy,"strafe_factor",0.0))
	var approach_weight: float = float(params.get("approach_weight",1.0))
	var retreat_weight: float = float(params.get("retreat_weight",1.0))
	var approach: bool = distance > preferred+float(params["approach_margin"]) or (bool(params.get("approach_without_sight",false)) and not ctx["sight"])
	var retreat: bool = not approach and distance < preferred-float(params["retreat_margin"])
	if strafe_factor == 0.0:
		if approach:
			var nav: Vector2 = nav_direction(enemy,session,ctx)
			return nav if approach_weight == 1.0 else nav*approach_weight
		if retreat:
			return -toward.normalized() if retreat_weight == 1.0 else -(toward.normalized()*retreat_weight)
		return Vector2.ZERO
	var sign_side := 1.0 if enemy.target.id % 2 == 0 else -1.0
	var movement := toward.normalized().rotated(sign_side*PI/2.0)*strafe_factor
	if approach:
		movement += nav_direction(enemy,session,ctx)*approach_weight
	elif retreat:
		movement -= toward.normalized()*retreat_weight
	return movement

static func validate(params: Dictionary) -> Array:
	return check("keep_distance",params,["approach_margin","retreat_margin"],
		["approach_margin","retreat_margin","approach_weight","retreat_weight","strafe_factor","preferred_range"],["approach_without_sight"])
