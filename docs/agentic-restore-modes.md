# agentic.nvim: modes and models are empty after restoring a session

Why `lua/plugin/ai.lua` points at `WhereIsW4ldo/agentic.nvim` on branch
`fix/restore-config-options` instead of upstream.

- Issue: <https://github.com/carlos-algms/agentic.nvim/issues/310>
- PR: <https://github.com/carlos-algms/agentic.nvim/pull/311>

The branch is upstream `main` plus a one-line change in `_bootstrap_session`: send the
bootstrap `session/new` in `restore_mode` rather than skipping it while a restore is in
flight. Restore the spec to `"carlos-algms/agentic.nvim"`, drop the `branch` field, and
delete this file once the PR lands.

The filed report follows.

---

**Title:** Restored sessions have no modes or models — `_bootstrap_session` skips the
`session/new` that carries them (regression of #277 / #180)

## Summary

Restoring a session leaves `config_options` empty, so:

- `<S-Tab>` (the `change_mode` keymap) reports
  **"This provider does not support mode switching"**
- the chat header shows no current mode
- `<localleader>m` (`switch_model`) and `<localleader>t` (`change_thought_level`) have
  nothing to offer either

A newly created session is fine. This is the same failure as #180 and #277, reached
through a third route.

## Environment

- agentic.nvim `9945381` (`main`, 2026-08-09)
- Neovim 0.12.4, Linux
- provider `claude-agent-acp` 0.66.0

## Reproduce

1. Open a chat, confirm mode switching works.
2. Restart Neovim.
3. Restore a previous session (`SessionRestore.show_picker` → pick one).
4. Press `<S-Tab>` to switch mode.

## Root cause

`session/load` does not re-send modes/models — the code says so at
`agent_config_options.lua:107` and `session_manager.lua:848` ("On a restore-first path
this response is the only source of these"). PR #280 fixed #277 by adopting them from
the throwaway `session/new` that the restore path fires alongside the load.

That `session/new` no longer happens:

1. `session_restore.lua:106` builds a fresh `SessionManager`, then **synchronously**
   calls `load_acp_session` at line 117, setting `_is_restoring_session = true`
   (`session_manager.lua:1088`).
2. The constructor queued `_bootstrap_session()` for the next tick
   (`session_manager.lua:101`). When it runs it hits the early return added in
   `10f9bab` (#298):

   ```lua
   function SessionManager:_bootstrap_session()
       if self._destroyed or self._is_restoring_session then
           return
       end
       self:new_session()
   end
   ```

3. No create is sent, so the adoption branch at `session_manager.lua:844-865` never
   runs and `config_options` stays empty.
4. `_show_mode_selector` finds neither modern nor legacy modes and warns
   (`agent_config_options.lua:387`); `get_mode_id()` returns nil so
   `_set_mode_to_chat_header` is skipped (`session_manager.lua:1157`).

`default_mode` / `initial_model` do not work around it: `set_initial_mode` looks the
value up in the same empty table (`agent_config_options.lua:187`) and only runs on the
create path anyway.

## The two fixes are in direct conflict

The guard is deliberate — without it the bootstrap create reaches `_cancel_session`,
which clears `_is_restoring_session` and leaves two requests racing for `session_id`.
`session_restore_race.test.lua:313` asserts exactly that, on exactly the ordering
`SessionRestore` produces:

```lua
it("load before the bootstrap sends no competing create", function()
    ...
    assert.is_nil(create_cb_ref.cb)
```

So the suite now encodes "no create on restore", while #280's fix needs that create to
exist. Any fix that only moves the guard will trade one bug for the other.

## Suggested direction

Modes/models are agent-level, not session-level — `agent_config_options.lua:106-108`
says so outright — but they are cached per `SessionManager`, so every new manager starts
blank and needs a `session/new` to refill. Hoisting the cache onto `AgentInstance` (fill
on first create, read by subsequent managers) would let the restore path stay
create-free and keep the #298 race closed, instead of alternating between the two.

## Regression history

- #180 (2026-04) — fixed
- #277 (2026-07) — same symptom, regressed by #266's early-return guard; fixed by #280
- now — same symptom, regressed by #298's early-return guard in `_bootstrap_session`

Last good commit: `7fc7590` (2026-07-31), where the constructor called `new_session()`
unconditionally.
