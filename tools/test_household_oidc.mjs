import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const hooks = {};
const sandbox = {Date, ForbiddenError: Error, UnauthorizedError: Error,
    onBootstrap: fn => { hooks.bootstrap = fn; },
    onRecordAuthWithOAuth2Request: fn => { hooks.oauth = fn; },
    onRecordUpdateRequest: fn => { hooks.update = fn; },
    onRecordAuthRefreshRequest: fn => { hooks.refresh = fn; }};
vm.runInNewContext(readFileSync(new URL('../pb_hooks/household.pb.js', import.meta.url), 'utf8'), sandbox);

function record(subject = '', timestamp = '') {
    const values = {household_subject: subject, household_authenticated_at: timestamp};
    return {id: 'existing-profile', getString: key => values[key] || '',
        set: (key, value) => { values[key] = value; },
        collection: () => ({name: 'users'}), original() { return this; }};
}

function event() {
    const e = {providerName: 'oidc',
        oAuth2User: {id: 'directory-subject', email: 'household@example.invalid',
            rawUser: {groups: ['family'], email_verified: true}},
        createData: {}, saved: false, proceeded: false, record: null,
        app: {save: () => { e.saved = true; }},
        next: () => { e.proceeded = true; e.record ??= record(); }};
    return e;
}

test('authorized household signup binds a trusted subject', () => {
    const e = event();
    hooks.oauth(e);
    assert.equal(e.record.getString('household_subject'), 'directory-subject');
    assert.equal(e.saved, true);
});

test('email fallback cannot link an existing profile without its authenticated session', () => {
    const e = event();
    e.record = record();
    assert.throws(() => hooks.oauth(e), /existing Boulder profile/);
    assert.equal(e.proceeded, false);
    e.auth = record();
    hooks.oauth(e);
    assert.equal(e.record.id, 'existing-profile');
});

test('another user or directory subject cannot take over a linked profile', () => {
    const e = event();
    e.record = record();
    e.auth = {...record(), id: 'different-profile'};
    assert.throws(() => hooks.oauth(e));
    e.record = record('another-subject');
    e.auth = record();
    assert.throws(() => hooks.oauth(e), /another identity/);
});

test('denied groups and unverified email never reach token issuance', () => {
    for (const groups of [[], ['unknown'], 'family']) {
        const e = event();
        e.oAuth2User.rawUser.groups = groups;
        assert.throws(() => hooks.oauth(e), /membership/);
        assert.equal(e.proceeded, false);
    }
    const e = event();
    e.oAuth2User.rawUser.email_verified = false;
    assert.throws(() => hooks.oauth(e), /verified email/);
});

test('household refresh cannot indefinitely extend a removed member session', () => {
    const e = event();
    e.record = record('subject', '2020-01-01 00:00:00.000Z');
    assert.throws(() => hooks.refresh(e), /sign in/);
    e.record = record('subject', new Date().toISOString());
    hooks.refresh(e);
    assert.equal(e.proceeded, true);
});

test('normal API updates cannot set identity metadata', () => {
    const e = event();
    e.record = record();
    e.requestInfo = () => ({body: {household_subject: 'forged'}});
    assert.throws(() => hooks.update(e), /metadata/);
    assert.equal(e.proceeded, false);
});
