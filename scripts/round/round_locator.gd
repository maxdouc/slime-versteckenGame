extends RefCounted
## Locator for the round-state node (Phase 5, feature/round-phases).
##
## No class_name on purpose (repo convention — consumers preload by path).
##
## Gameplay code never references the GameState autoload by its compile-time
## identifier. Instead it walks UP from its own node and returns the first
## ancestor's direct child named "GameState":
##
##   * Real game: the walk ends at /root, whose child "GameState" is the
##     autoload — same behavior as the identifier, no coupling.
##   * Headless tests: each isolated SceneMultiplayer world branch carries its
##     own GameState node directly under the branch root, so every simulated
##     "machine" resolves ITS OWN round state — and because the relative path
##     from the branch root ("GameState") matches the autoload's relative path
##     from /root, @rpc calls route identically in both setups.
##
## Returns null when no round state exists (e.g. focused tests that spawn a
## bare capsule) — callers must treat round features as absent then.

static func locate(from: Node) -> Node:
	var node := from.get_parent()
	while node != null:
		var found := node.get_node_or_null(^"GameState")
		if found != null:
			return found
		node = node.get_parent()
	return null
