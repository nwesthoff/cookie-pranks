// JXA helper: safely read-modify-write a Claude scheduled-tasks.json index.
// Never touches a file that isn't valid JSON shaped like { scheduledTasks: [...] } —
// prints a status word to stdout instead, so the caller can skip that index rather
// than risk corrupting state a real Claude session depends on.
//
//   osascript -l JavaScript task-index.js check  <indexPath> <id>
//   osascript -l JavaScript task-index.js upsert <indexPath> <id> <displayName> <cronExpression> <filePath> <approveTool>
//   osascript -l JavaScript task-index.js remove <indexPath> <id>

function run(argv) {
	ObjC.import("Foundation");

	var mode = argv[0];
	var indexPath = argv[1];
	var id = argv[2];

	var fm = $.NSFileManager.defaultManager;
	var nsPath = $(indexPath);

	var data = { scheduledTasks: [] };
	if (fm.fileExistsAtPath(nsPath)) {
		var err = $();
		var nsStr = $.NSString.alloc.initWithContentsOfFileEncodingError(
			nsPath, $.NSUTF8StringEncoding, err);
		if (nsStr.isNil()) { return "UNREADABLE"; }
		try {
			data = JSON.parse(ObjC.unwrap(nsStr));
		} catch (e) { return "UNPARSEABLE"; }
		if (!data || typeof data !== "object" || !Array.isArray(data.scheduledTasks)) {
			return "UNEXPECTED_SHAPE";
		}
	}

	var index = -1;
	for (var i = 0; i < data.scheduledTasks.length; i++) {
		if (data.scheduledTasks[i] && data.scheduledTasks[i].id === id) { index = i; break; }
	}

	if (mode === "check") {
		return index >= 0 ? "PRESENT" : "ABSENT";
	}

	if (mode === "upsert") {
		if (index >= 0) { return "ALREADY_PRESENT"; }
		var displayName = argv[3];
		var cronExpression = argv[4];
		var filePath = argv[5];
		var approveTool = argv[6];
		data.scheduledTasks.push({
			id: id,
			displayName: displayName,
			cronExpression: cronExpression,
			enabled: true,
			filePath: filePath,
			createdAt: Date.now(),
			approvedPermissions: [{ toolName: approveTool }]
		});
	} else if (mode === "remove") {
		if (index < 0) { return "NOT_PRESENT"; }
		data.scheduledTasks.splice(index, 1);
	} else {
		return "UNKNOWN_MODE";
	}

	var parentPath = $(indexPath).stringByDeletingLastPathComponent;
	fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(
		parentPath, true, $(), $());

	var out = $(JSON.stringify(data, null, 2));
	var ok = out.writeToFileAtomicallyEncodingError(nsPath, true, $.NSUTF8StringEncoding, $());
	return ok ? (mode === "upsert" ? "INSTALLED" : "REMOVED") : "WRITE_FAILED";
}
