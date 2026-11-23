class_name Combat
## Tipi e utility condivise dal sistema di combattimento.
##
## Convenzione per il danno: qualsiasi nodo colpibile implementa
##     func take_damage(amount: float, source: Node3D) -> HitResult
## (player, nemici, in futuro oggetti distruttibili). Chi colpisce usa il risultato
## per reagire: per esempio un nemico parato va in stordimento.

enum HitResult {
	HIT,       ## colpo a segno
	BLOCKED,   ## parato con lo scudo (danno ridotto)
	PARRIED,   ## parry riuscito (nessun danno, l'attaccante resta scoperto)
	IGNORED,   ## il bersaglio non può essere colpito (già morto, invulnerabile...)
}

static var _active_hitstops := 0


## Congela il gioco per qualche centesimo di secondo: dà "peso" ai colpi.
## Più hitstop sovrapposti si sommano: il tempo riparte quando finisce l'ultimo.
static func hitstop(node: Node, duration: float, time_scale := 0.03) -> void:
	_active_hitstops += 1
	Engine.time_scale = time_scale
	# Timer che ignora il time_scale, altrimenti durerebbe 30 volte di più.
	await node.get_tree().create_timer(duration, true, false, true).timeout
	_active_hitstops -= 1
	if _active_hitstops <= 0:
		_active_hitstops = 0
		Engine.time_scale = 1.0
