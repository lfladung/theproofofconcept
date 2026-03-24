extends Label

var score = 0


func _ready() -> void:
	add_to_group(&"score_ui")


func add_score(amount: int = 1) -> void:
	score += amount
	text = "Coins: %s" % score


func reset_score() -> void:
	score = 0
	text = "Coins: 0"


func _on_mob_squashed() -> void:
	add_score(1)
