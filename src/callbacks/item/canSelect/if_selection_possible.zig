const main = @import("main");
const ZonElement = main.ZonElement;

pub fn init(_: ZonElement) ?*@This() {
	return main.worldArena.create(@This());
}

pub fn run(_: *@This(), params: main.callbacks.ItemCanSelectCallback.Params) main.callbacks.Result {
	if (params.block.selectionCapabilities().makesSelectionPossible()) return .handled;
	return .ignored;
}
