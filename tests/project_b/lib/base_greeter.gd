class_name BaseGreeter
extends RefCounted
## Greeter が class_name で継承する。継承元のスクリプトも書き出しに残る。

static func prefix() -> String:
	return "project_b: "
