import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../frontend/app.js', import.meta.url), 'utf8');
const start = source.indexOf('async function initHouseholdSSO()');
const end = source.indexOf('async function detectPocketBaseUrl()', start);

async function setup(passwordEnabled = true) {
    const buttons = Object.fromEntries(['household-sso', 'household-link', 'tab-btn-signup', 'auth-form', 'auth-tabs', 'household-link-instructions'].map(id =>
        [id, {id, hidden: false, classList: {add() { buttons[id].hidden = true; }, remove() { buttons[id].hidden = false; }}, addEventListener(_, fn) { this.click = fn; }}]));
    const state = {session: null, errors: [], completed: [], current: null};
    class PocketBase {
        authStore = {save: (token, record) => { state.current = {token, record}; }, clear: () => { state.current = null; }};
        collection() { return {
            listAuthMethods: async () => ({oauth2: {providers: [{name: 'oidc'}]}, password: {enabled: passwordEnabled}}),
            authWithOAuth2: async () => {
                state.atExchange = state.current;
                return state.result ?? {token: 'new-token', record: {id: 'existing'}};
            }
        }; }
    }
    const sandbox = {PocketBase, URL, PB_URL: '/pb', window: {location: {origin: 'https://boulder.lockdev.com'}},
        document: {getElementById: id => buttons[id]}, localStorage: {getItem: () => JSON.stringify(state.session)},
        showAuthError: message => state.errors.push(message), hideAuthMessages() {},
        completeLogin: async data => state.completed.push(data)};
    vm.runInNewContext(source.slice(start, end), sandbox);
    await sandbox.initHouseholdSSO();
    return {buttons, state};
}

test('signed-in linking reads the latest password session at click time', async () => {
    const {buttons, state} = await setup();
    state.session = {token: 'password-token', record: {id: 'existing'}};
    await buttons['household-link'].click();
    assert.equal(state.atExchange.token, 'password-token');
    assert.equal(state.completed[0].record.id, 'existing');
    assert.equal(buttons['household-link'].disabled, false);
});

test('linking another profile restores the old session and reports the failure', async () => {
    const {buttons, state} = await setup();
    state.session = {token: 'password-token', record: {id: 'existing'}};
    state.result = {token: 'wrong-token', record: {id: 'another'}};
    await buttons['household-link'].click();
    assert.equal(state.current.token, 'password-token');
    assert.equal(state.completed.length, 0);
    assert.match(state.errors[0], /another Boulder profile/);
});

test('linking requires an existing session; ordinary sign-in clears stale SDK auth', async () => {
    const {buttons, state} = await setup();
    await buttons['household-link'].click();
    assert.equal(state.completed.length, 0);
    assert.match(state.errors[0], /existing Boulder profile/);
    state.current = {token: 'stale-token', record: {id: 'stale'}};
    await buttons['household-sso'].click();
    assert.equal(state.atExchange, null);
    assert.equal(state.completed.length, 1);
});

test('closing server password recovery hides the retained password controls', async () => {
    const {buttons} = await setup(false);
    assert.equal(buttons['auth-form'].hidden, true);
    assert.equal(buttons['auth-tabs'].hidden, true);
    assert.equal(buttons['household-sso'].hidden, false);
});
