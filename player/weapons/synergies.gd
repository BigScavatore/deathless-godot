class_name Synergies
extends Node
## Sinergie tra le armi delle due mani: certe coppie sbloccano un effetto in più.
## Il Viewmodel crea questo nodo e lo aggiorna quando cambi arma; le armi lo chiamano nei
## momenti chiave (vedi i metodi on_*). Ogni arma ha un "kind" (Weapon.kind) che la identifica.
##
##   GLOBI ARCANI  bastone nella SINISTRA + spada nella DESTRA
##       il bastone, invece dell'incantesimo, evoca globi arcani (fino a max_orbs) che girano
##       attorno al player; ogni fendente della spada ne lancia uno verso il mirino, che esplode
##       colpendo il bersaglio e i nemici vicini.
##   LAMA ARCANA   spada nella SINISTRA + bastone nella DESTRA
##       ogni fendente della spada che va a segno carica il cristallo (fino a max_charges);
##       il prossimo incantesimo del bastone consuma le cariche e parte moltiplicato a ventaglio
##       (le schegge in più sono gratis).
##   ASSALTO       spada + brocchiero (in qualunque mano)
##       tenendo premuto il tasto della spada la si carica; rilasciandolo dopo hold_time parte un
##       affondo in dash (usa una carica del dash) che trafigge tutti i nemici sulla traiettoria.
##       Un tocco breve resta un fendente normale.
##   SPECCHIO ARCANO  bastone + brocchiero (in qualunque mano)
##       le schegge del bastone rimbalzano sui muri (fino a bounces volte); se tornano verso di te
##       e le respingi con lo scudo (parata, o meglio ancora parry) ripartono verso il mirino più
##       veloci e più forti, con i rimbalzi ricaricati.
##
## Per aggiungerne una: una costante qui, il riconoscimento della coppia in refresh(), i suoi
## effetti negli on_* e una voce in NAMES (la HUD mostra nome e contatore da hud_info()).

signal changed(synergy: StringName)
signal counter_changed(count: int)

enum CastResult { NONE, OK, NO_MANA }

const ORBS := &"orbs"
const CHARGE := &"charge"
const ASSAULT := &"assault"
const MIRROR := &"mirror"
const NAMES := {ORBS: "Globi arcani", CHARGE: "Lama arcana", ASSAULT: "Assalto", MIRROR: "Specchio arcano"}
## Spiegazione breve, mostrata dalla HUD quando la sinergia si attiva.
const HINTS := {
	ORBS: "il bastone evoca globi, la spada li scaglia",
	CHARGE: "i colpi di spada caricano il bastone",
	ASSAULT: "tieni premuto il tasto della spada: affondo in dash",
	MIRROR: "le schegge rimbalzano: respingile con lo scudo",
}

@export_group("Globi arcani")
@export var orb_cost := 12.0
@export var max_orbs := 3
## Secondi tra due evocazioni.
@export var orb_cooldown := 0.55
@export var orb_damage := 30.0
@export var orb_blast_damage := 18.0
@export var orb_blast_radius := 2.6
@export var orbit_radius := 1.0
@export var orbit_height := 1.25

@export_group("Lama arcana")
@export var max_charges := 3
## Apertura del ventaglio tra una scheggia e l'altra (gradi).
@export var fan_spread_deg := 6.0

@export_group("Assalto")
## Secondi da tenere premuto per caricare l'affondo.
@export var assault_hold_time := 0.3
@export var assault_speed := 32.0
@export var assault_duration := 0.28
@export var assault_damage := 45.0
## Raggio (m) attorno alla punta della spada in cui l'affondo colpisce.
@export var assault_radius := 1.3

@export_group("Specchio arcano")
@export var mirror_bounces := 3

## La sinergia attiva (vuota = nessuna).
var active := &""
var player: Node3D

var _orbs: Array[ArcaneOrb] = []
var _charges := 0
var _orbit_time := 0.0
var _color := Color(0.62, 0.42, 1.0)


## Ricalcola la sinergia in base alle armi in mano.
func refresh(right: Weapon, left: Weapon) -> void:
	var r := right.kind if right else &""
	var l := left.kind if left else &""
	var next := &""
	var pair := [r, l]
	if l == &"staff" and r == &"sword":
		next = ORBS
	elif r == &"staff" and l == &"sword":
		next = CHARGE
	elif pair.has(&"sword") and pair.has(&"shield"):
		next = ASSAULT
	elif pair.has(&"staff") and pair.has(&"shield"):
		next = MIRROR
	for weapon in [right, left]:
		if weapon and weapon.has_method("current_spell") and weapon.current_spell():
			_color = weapon.current_spell().color
	if next == active:
		return
	_clear()
	active = next
	changed.emit(active)


func display_name() -> String:
	return NAMES.get(active, "")


func hint() -> String:
	return HINTS.get(active, "")


## Per la HUD: nome, contatore (globi o cariche), massimo e colore. Vuoto se nessuna sinergia.
func hud_info() -> Dictionary:
	match active:
		ORBS:
			return {"name": NAMES[ORBS], "count": _orbs.size(), "max": max_orbs, "color": _color}
		CHARGE:
			return {"name": NAMES[CHARGE], "count": _charges, "max": max_charges, "color": _color}
		ASSAULT:
			return {"name": NAMES[ASSAULT], "count": 0, "max": 0, "color": Color(0.9, 0.75, 0.5)}
		MIRROR:
			return {"name": NAMES[MIRROR], "count": 0, "max": 0, "color": _color}
	return {}


## 0..1: quanto è carico il cristallo (Lama arcana), per farlo brillare di più.
func charge_level() -> float:
	return float(_charges) / float(max_charges) if active == CHARGE else 0.0


# --- Chiamate dalle armi -----------------------------------------------------

## Il bastone sta per lanciare. Con "Globi arcani" (bastone a sinistra) evoca un globo invece
## dell'incantesimo: OK = gestito (il globo compare in on_staff_release), NO_MANA = mana insufficiente.
func on_staff_try_cast(staff: Weapon) -> CastResult:
	if active != ORBS or staff.hand != Weapon.Hand.LEFT:
		return CastResult.NONE
	if _orbs.size() >= max_orbs:
		return CastResult.NO_MANA  # già pieno: il bastone "sfrigola"
	if player == null or not player.has_method("use_mana") or not player.use_mana(orb_cost):
		return CastResult.NO_MANA
	return CastResult.OK


## Il bastone scatta in avanti dopo un on_staff_try_cast() == OK: compare un globo.
func on_staff_release(staff: Weapon) -> void:
	if active != ORBS or player == null:
		return
	var orb := ArcaneOrb.new()
	orb.color = _color
	orb.damage = orb_damage
	orb.blast_damage = orb_blast_damage
	orb.blast_radius = orb_blast_radius
	orb.caster = player
	var root := get_tree().current_scene
	orb.position = _orbit_point(_orbs.size(), _orbs.size() + 1)
	if root is Node3D:
		orb.position = (root as Node3D).global_transform.affine_inverse() * orb.position
	root.add_child(orb)
	_orbs.append(orb)
	Sfx.play(staff, &"orb_summon", -2.0, 0.08)
	counter_changed.emit(_orbs.size())


## Un fendente della spada (nel frame dell'impatto). `landed` = ha colpito qualcuno.
func on_sword_slash(sword: Weapon, landed: bool) -> void:
	match active:
		ORBS:
			if sword.hand != Weapon.Hand.RIGHT or _orbs.is_empty():
				return
			var orb: ArcaneOrb = _orbs.pop_front()
			if is_instance_valid(orb):
				orb.launch(_aim_point())
			counter_changed.emit(_orbs.size())
		CHARGE:
			if sword.hand != Weapon.Hand.LEFT or not landed or _charges >= max_charges:
				return
			_charges += 1
			Sfx.play(sword, &"charge_gain", -4.0, 0.05)
			counter_changed.emit(_charges)


## Modifiche per gli incantesimi del bastone (vedi Spell.cast): "Specchio arcano" li fa rimbalzare.
func spell_mods(_staff: Weapon) -> Dictionary:
	if active == MIRROR:
		return {"bounces": mirror_bounces, "reflectable": true}
	return {}


## true se la spada può caricare l'affondo ("Assalto").
func can_assault(sword: Weapon) -> bool:
	return active == ASSAULT and sword.kind == &"sword"


## Il bastone lancia il suo incantesimo: con "Lama arcana" (bastone a destra) consuma le cariche
## e restituisce quante schegge in più lanciare.
func take_extra_casts(staff: Weapon) -> int:
	if active != CHARGE or staff.hand != Weapon.Hand.RIGHT or _charges == 0:
		return 0
	var extra := _charges
	_charges = 0
	counter_changed.emit(0)
	return extra


# --- Interno ----------------------------------------------------------------

func _process(delta: float) -> void:
	if _orbs.is_empty() or player == null:
		return
	_orbit_time += delta
	var alive: Array[ArcaneOrb] = []
	for orb in _orbs:
		if is_instance_valid(orb) and not orb.flying:
			alive.append(orb)
	_orbs = alive
	for i in _orbs.size():
		var orb := _orbs[i]
		orb.global_position = orb.global_position.lerp(_orbit_point(i, _orbs.size()), 1.0 - exp(-12.0 * delta))


## Dove sta il globo i-esimo (su n) nell'orbita attorno al player.
func _orbit_point(i: int, n: int) -> Vector3:
	var angle := _orbit_time * 1.8 + TAU * float(i) / float(maxi(n, 1))
	var bob := sin(_orbit_time * 3.0 + i) * 0.08
	return player.global_position + Vector3(cos(angle) * orbit_radius, orbit_height + bob, sin(angle) * orbit_radius)


## Il punto sotto il mirino (fino a 100 m).
func _aim_point() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var from := camera.global_position
	var to := from - camera.global_basis.z * 100.0
	var exclude: Array[RID] = []
	if player is CollisionObject3D:
		exclude.append((player as CollisionObject3D).get_rid())
	var hit := player.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to, 1, exclude))
	return to if hit.is_empty() else hit.position


func _clear() -> void:
	for orb in _orbs:
		if is_instance_valid(orb):
			orb.dissipate()
	_orbs.clear()
	_charges = 0
	counter_changed.emit(0)
