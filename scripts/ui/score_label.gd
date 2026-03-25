extends Label

var score = 0


func _ready() -> void:
	add_to_group(&"score_ui")


func add_score(amount: int = 1) -> void:
	set_score(score + amount)


func set_score(value: int) -> void:
	score = maxi(0, value)
	text = "Coins: %s" % score


func reset_score() -> void:
	set_score(0)


func _on_mob_squashed() -> void:
	add_score(1)
