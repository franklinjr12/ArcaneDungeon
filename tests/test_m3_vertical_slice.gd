extends RefCounted
## TASK-038-048 real-command end-to-end smoke: no direct damage or privileged combat action.
const Flow = preload("res://world/run_flow.gd")
const Driver = preload("res://tests/m3_run_driver.gd")
const Runner = preload("res://magic/runtime/spell_runner.gd")

func run(t) -> void:
	var flow = Flow.new(20261022)
	var earned: Array = []
	for index in 4:
		var name: String = str(flow.room.values["id"])
		var result: Dictionary = Driver.fight(flow,4600)
		t.equal(result["state"],"cleared","TASK-048 gameplay commands actually clear "+name)
		t.check(result["casts"]>0,"TASK-048 "+name+" requires real spell casts")
		t.check(flow.session.alive_enemies()==0,"TASK-048 "+name+" has no living required enemies")
		if index < 3:
			var grant: Dictionary = flow.choose_reward(0)
			t.check(grant["ok"],"TASK-041 "+name+" rune choice grants one reward")
			t.equal(grant["kind"],"unlock","TASK-040 "+name+" rewards rune knowledge")
			earned.append(str(grant["rune"]))
			t.equal(flow.choose_reward(0)["reason"],"REWARD_NOT_AVAILABLE","TASK-041 no reward duplication "+name)
		var previous: int = flow.run.sequence_index
		var exit_result: Dictionary = Driver.reach_exit(flow)
		t.check(exit_result["ok"],"TASK-036 physically navigating to door advances "+name)
		t.equal(flow.run.sequence_index,previous+1,"TASK-038 one room transition "+name)
		t.equal(flow.session.sim.queue.active_effect_count(),0,"TASK-038 "+name+" transition cleans effects")
		t.equal(flow.session.enemy_shots.size(),0,"TASK-038 "+name+" transition clears hostile projectiles")
	t.equal(flow.room.values["id"],"workshop","TASK-038 three combats + boss lead to workshop")
	t.equal(flow.state,"workshop","TASK-043 workshop safe state")
	t.equal(flow.boss_defeated_events,1,"TASK-042 boss defeated exactly once")
	t.check(flow.run.currency>=int(flow.config["boss_currency"]),"TASK-046 boss grants spendable currency")
	t.equal(flow.run.collected.size(),3,"TASK-041 exactly one pickup per regular stage-one room")
	t.equal(flow.session.alive_enemies(),0,"TASK-043 no hostile enemies in workshop")
	t.equal(flow.session.sim.queue.active_effect_count(),0,"TASK-043 no carried old effect in workshop")
	var gain: String = str(earned[0])
	t.check(gain in flow.run.unlocked,"TASK-048 first-time rune carried into workshop")
	var shop_before: Array = flow.merchant.stock.duplicate(true)
	var duplicate_shop = Flow.new(20261022)
	duplicate_shop.run = flow.run
	duplicate_shop.merchant = preload("res://world/merchant.gd").new(duplicate_shop.config)
	t.equal(duplicate_shop.merchant.build(flow.run,flow.session.sim.registry.get_ids()),shop_before,
		"TASK-046 same seed/inventory produces identical stock and prices")
	var rich: int = flow.run.currency
	var insufficient: Dictionary = flow.buy(11)
	t.equal(insufficient["reason"],"STOCK_INVALID","TASK-046 nonexistent stock rejected")
	t.equal(flow.run.currency,rich,"TASK-046 invalid purchase cannot spend money")
	var item: Dictionary = flow.merchant.stock[0]
	var pricey: int = int(item["price"])
	flow.run.currency = pricey-1
	t.equal(flow.buy(0)["reason"],"INSUFFICIENT_CURRENCY","TASK-046 cannot buy when unaffordable")
	t.equal(flow.run.currency,pricey-1,"TASK-046 currency never goes negative")
	flow.run.currency = rich
	var bought: Dictionary = flow.buy(0)
	t.check(bought["ok"],"TASK-046 first purchase succeeds")
	t.check(str(item["rune_id"]) in flow.run.unlocked,"TASK-046 purchased rune immediately unlocked")
	t.equal(flow.buy(0)["reason"],"ALREADY_BOUGHT","TASK-046 cannot buy identical stock twice")
	var run_after_rune: Dictionary = flow.run.snapshot()
	t.check(flow.open_editor(0)["ok"],"TASK-044 workshop editor opens")
	var original: Dictionary = flow.run.formulas[0].duplicate(true)
	var editor = flow.editor
	var unlocked_mod := ""
	for item_id in earned:
		if item_id.begins_with("mod."):
			unlocked_mod = item_id
			break
	editor.set_root("essence.water","form.projectile")
	if not unlocked_mod.is_empty():
		editor.toggle_modifier(unlocked_mod)
	t.check(editor.validate()["ok"],"TASK-044 valid unlocked rune can be composed into spell")
	var before_cancel: Dictionary = flow.run.formulas[0].duplicate(true)
	t.check(flow.close_editor(false,1.5)["ok"],"TASK-044 editor cancel")
	t.equal(flow.run.formulas[0],before_cancel,"TASK-044 cancel restores exact formula")
	t.check(flow.open_editor(0)["ok"],"TASK-044 edit starts again")
	flow.editor.set_root("essence.water","form.projectile")
	if not unlocked_mod.is_empty():
		flow.editor.toggle_modifier(unlocked_mod)
	t.check(flow.close_editor(true,3.0)["ok"],"TASK-044 editor apply")
	t.equal(flow.run.formulas[0]["formula_id"],"custom.slot_1","TASK-044 custom formula gets stable ID")
	t.equal(flow.run.formulas[0]["root"]["essence_id"],"essence.water","TASK-048 edited rune used post boss")
	t.check(flow.range_sim.loadout.check_slot(1)=="READY","TASK-045 range recompiles applied formula immediately")
	var currency_before_test: int = flow.run.currency
	var hp_before_test: float = flow.run.hp
	var count_before_test: int = flow.run.sequence_index
	flow.enter_test_range()
	var fresh = Runner.new(flow.run.seed)
	fresh.loadout.unlocked = flow.run.unlocked.duplicate(true)
	fresh.equip_starter_loadout(flow.run.formulas)
	fresh.fill_targets()
	var test_spell: Dictionary = flow.test_cast(1,Vector2.RIGHT)
	var sandbox_spell: Dictionary = fresh.try_cast(1,fresh.actor.position,Vector2.RIGHT)
	t.equal(test_spell["accepted"],sandbox_spell["accepted"],"TASK-045 workshop casts same validated M1 plan")
	for i in 60:
		flow.range_sim.step()
		fresh.step()
	t.equal(flow.range_sim.trace_json(),fresh.trace_json(),"TASK-045 identical setup produces identical M1 trace")
	t.equal(flow.run.currency,currency_before_test,"TASK-043 range cannot farm currency")
	t.equal(flow.run.hp,hp_before_test,"TASK-043 range damage never affects dungeon HP")
	t.equal(flow.run.sequence_index,count_before_test,"TASK-043 testing does not advance encounter")
	t.check(flow.range_sim.total_hit_count>0,"TASK-045 workshop spells deal normal target damage")
	flow.enter_test_range()
	var prep: Dictionary = flow.prepare_wet_cluster()
	t.equal(prep["count"],2,"TASK-045 wet cluster preset prepares two statuses")
	t.check(flow.range_sim.targets.get_target(2).status.has("wet"),"TASK-045 wet setup inspectable")
	flow.test_cast(1,Vector2.RIGHT)
	for i in 5:
		flow.range_sim.step()
	flow.refill_test_mana()
	t.equal(flow.range_sim.mana,float(flow.config["workshop_restore_mana"]),"TASK-045 test-only refill")
	t.equal(flow.run.hp,hp_before_test,"TASK-043 refill cannot restore or damage run HP")
	t.equal(flow.session.state,"cleared","TASK-043 no workshop encounter event can spawn")
	var health_offer: Dictionary = flow.merchant.stock[1]
	var max_before: float = flow.run.max_hp
	t.check(flow.buy(1)["ok"],"TASK-046 numeric upgrade purchased")
	t.equal(flow.run.max_hp,max_before+float(health_offer["amount"]),"TASK-046 HP upgrade atomically updates RunState")
	var after_boss: Dictionary = flow.run.snapshot()
	var restored = Flow.new(20261022)
	t.check(restored.recover(after_boss)["ok"],"TASK-039 valid workshop snapshot can reload")
	t.equal(restored.run.purchases,flow.run.purchases,"TASK-039 purchases persist")
	t.equal(restored.run.unlocked,flow.run.unlocked,"TASK-039 rune inventory persists")
	t.equal(restored.run.formulas,flow.run.formulas,"TASK-039 custom spell survives state restore")
	t.equal(restored.room.values["id"],"workshop","TASK-039 restoring saved sequence recreates workshop")
	t.equal(restored.merchant.bought.size(),2,"TASK-046 purchased stock remains exhausted after restore")
	var advance: Dictionary = Driver.reach_exit(flow)
	t.check(advance["ok"],"TASK-048 workshop exit leads to next stage")
	t.equal(flow.room.values["id"],"s2_r1","TASK-038 stage 2 first room reached")
	t.equal(flow.run.sequence_index,5,"TASK-038 correct stage-two sequence index")
	t.equal(flow.run.purchases.size(),2,"TASK-046 purchases persist into next stage")
	t.check(flow.run.unlocked.has(str(item["rune_id"])),"TASK-040 merchant rune persists into next stage")
	t.equal(flow.session.sim.loadout.preview(1)["formula_id"],"custom.slot_1","TASK-048 custom formula equipped at next stage")
	t.equal(flow.session.sim.actor.health.maximum,max_before+float(health_offer["amount"]),"TASK-046 HP upgrade persists")
	t.equal(flow.session.sim.queue.active_effect_count(),0,"TASK-048 no effects cross workshop transition")
	t.equal(flow.session.enemy_shots.size(),0,"TASK-048 no bullets cross workshop transition")
	var next_fight: Dictionary = Driver.fight(flow,4600)
	t.equal(next_fight["state"],"cleared","TASK-048 next-stage room remains playable after workshop")
	var again = Flow.new(20261022)
	again.session.enemies[0].target.receive_damage(1000,"fire",1,100)
	again.step()
	again.start_new(20261022)
	t.equal(again.run.currency,int(again.config["initial_currency"]),"TASK-039 restart clears acquired money")
	t.equal(again.run.unlocked,again.config["initial_unlocked"],"TASK-039 restart resets rune licenses")
	t.equal(again.session.sim.clock.tick,0,"TASK-039 restart clears old tick/effect state")
