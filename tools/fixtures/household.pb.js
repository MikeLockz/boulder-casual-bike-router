// Disposable integration fixture. Never copied into a production image.
if ($os.getenv("BOULDER_TEST_FIXTURE") !== "1") throw new Error("Fixture-only hook refused");
onBootstrap((e) => {
    e.next();
    const collection = e.app.findCollectionByNameOrId("users");
    for (const pair of [["fixtureexisting", "existing@fixture.invalid"],
                        ["fixtureanother1", "another@fixture.invalid"],
                        ["fixturefailed01", "failed@fixture.invalid"]]) {
        try { e.app.findRecordById("users", pair[0]); continue; } catch {}
        const record = new Record(collection);
        record.id = pair[0];
        record.set("email", pair[1]);
        record.set("verified", true);
        record.set("password", "fixture-password-for-local-tests");
        e.app.save(record);
    }
});
onRecordUpdateExecute((e) => {
    if (e.record.getString("household_subject") === "storage-fail") throw new Error("Fixture metadata storage failure");
    e.next();
}, "users");
routerAdd("POST", "/__fixture/expire", (event) => {
        const record = event.app.findRecordById("users", event.requestInfo().body.id);
        if (!record.getString("email").endsWith("@fixture.invalid")) throw new ForbiddenError("Fixture records only");
        record.set("household_authenticated_at", "2020-01-01 00:00:00.000Z");
        record.set("household_recovery_authenticated_at", "");
        event.app.save(record);
        return event.json(200, {ok: true});
});
routerAdd("GET", "/__fixture/collections", (event) => {
    return event.json(200, {
        routes: event.app.findCollectionByNameOrId("navigation_routes").id,
        ticks: event.app.findCollectionByNameOrId("navigation_ticks").id
    });
});
