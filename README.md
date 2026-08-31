# Silent Aim compatibility build

The deliverable is `silent-aim.lua`. It contains no comments or emojis. It includes its own Roblox GUI and has no remote loaders, third-party UI downloads, filesystem calls, or firing remotes.

This is an executor-dependent client script, not a Roblox Studio LocalScript. It is not verified in a live Roblox client or executor. It is not universally compatible, cannot guarantee hits, and makes no claim about anti-cheat compatibility or account safety. It does not install an executor or inject itself.

## Controls

- Right Alt: enable or disable.
- F6: cycle the interception method.
- End or the Unload button: disable redirection and remove connections/UI.
- The panel also has buttons for method selection, team checks, visibility checks, and the equipped-Tool requirement.
- Buttons use `Activated` for mouse/touch input. Touch and gamepad targeting use the viewport center automatically. Mouse targeting follows the cursor, except when the mouse is locked to the center.

The initial settings target standard character heads within 150 pixels, enable team and visibility checks, and require an equipped Roblox `Tool`. These are editable at the top of the script. The maximum target-selection distance is 1,500 studs; this does not extend the weapon's range.

## Choose the correct weapon method

The default is `Raycast`. Use the Method button or F6 to select the method actually used by your weapon:

| Method | What it changes |
| --- | --- |
| `Raycast` | Direction of compatible colon-style `workspace:Raycast` calls |
| `Mouse.Hit/Target` | Mouse hit-position and target-part reads |
| `FindPartOnRay` | Direction of the legacy ray call, including its lowercase alias |
| `FindPartOnRayWithIgnoreList` | Legacy ray direction; original ignore list retained |
| `FindPartOnRayWithWhitelist` | Legacy ray direction; original whitelist retained |

This is method selection, not gun identification. A selected method can also be used by unrelated client systems, including camera collision and interactions. The equipped-Tool gate reduces exposure but does not identify which calls are shots. If other behavior changes, disable the script. A game-specific integration is needed to isolate weapon calls reliably.

For custom weapon systems not represented by a Roblox `Tool`, the equipped-Tool requirement can be turned off. That does not make the weapon's firing implementation compatible.

## Compatibility boundaries

- Requires working `hookmetamethod`, `checkcaller`, and `newcclosure` APIs, plus a writable shared environment. Missing APIs produce an explicit error.
- Ray methods additionally require `getnamecallmethod`; without it, only mouse mode is offered.
- Function presence is not proof of a correct executor implementation. Native hooking is outside the test harness.
- Only standard player characters with a `Humanoid` and a `Head` BasePart are selected. NPCs and custom rigs are not automatically supported.
- The target must exist on the local client; streaming can make distant characters unavailable.
- Physical projectiles, server-only firing logic, cached/dot-style function calls, custom camera crosshairs, custom remotes, parallel execution contexts, and server-side hit validation may not be compatible.
- Visibility is checked from the camera. Weapon-origin obstacles, collision groups, or game-specific collision rules may differ. Visibility does not guarantee an accepted hit.
- Ray length, filter objects, optional arguments, and original return values are preserved. The script does not bypass walls, rewrite damage remotes, extend weapon range, or change the camera.
- No projectile prediction is included: prediction requires the weapon's projectile speed and trajectory model.
- Re-running this build replaces its UI/connections and reuses its bridge hooks. This does not remove hooks from unrelated scripts, earlier chat snippets, or another executor environment.
- Unload leaves the installed hooks in pass-through mode; it does not overwrite other scripts' metatable hooks. Start a fresh client session for a fully unhooked state.
- The script acts only in the client where it is run. To give every player aim assistance automatically in your own game, integrate targeting into the game's weapon code and validate firing on the server.

## Review scope and findings

Reviewed all three files listed at the repository root: [main.lua](https://github.com/Averiias/Universal-SilentAim/blob/main/main.lua), [README.md](https://github.com/Averiias/Universal-SilentAim/blob/main/README.md), and [LICENSE](https://github.com/Averiias/Universal-SilentAim/blob/main/LICENSE), plus issues [53](https://github.com/Averiias/Universal-SilentAim/issues/53), [55](https://github.com/Averiias/Universal-SilentAim/issues/55), and [57](https://github.com/Averiias/Universal-SilentAim/issues/57). The repository is archived. Issue reports are user reports, not verified evidence of a global Roblox patch. Historical commits and externally loaded UI-library code were not audited.

The original code assigns an undefined `Settings` variable to its exported settings, passes character instances among visibility cast-point vectors, guards missing characters with the wrong boolean condition, forces every redirected ray to 1,000 studs, and uses inconsistent screen-coordinate conventions. Its mouse `UnitRay` construction also uses incompatible value types. The configuration filename checks use always-true boolean conditions. Those code paths are replaced or omitted here. The GUI, file persistence, hit-chance, and prediction subsystems are not copied.

This build uses current-camera lookup, viewport-coordinate targeting, bounded target freshness, respawn/departure/health checks, defensive argument validation, and a reusable hook bridge. Original licensing attribution is retained in `LICENSE`; include it when redistributing this package.

Reference API contracts: [Mouse](https://create.roblox.com/docs/reference/engine/classes/Mouse), [Camera](https://create.roblox.com/docs/reference/engine/classes/Camera), [WorldRoot](https://create.roblox.com/docs/reference/engine/classes/WorldRoot), and [UserInputService](https://create.roblox.com/docs/reference/engine/classes/UserInputService).

## Verification

Run `npm ci --ignore-scripts` and `npm test` with Node.js installed. The pinned `luau-web` dependency is used only for development tests; it is not a runtime dependency of the Roblox script.

The runner compiles the actual delivered script as Luau and executes it against a mocked Roblox environment. It also checks that the deliverable is ASCII, comment-free, and does not contain remote-loader or file-access APIs. Tests cover targeting, inputs, GUI construction, ray arguments, lifecycle, failure handling, and repeat execution.

Mock tests do not verify native executor semantics, actual GUI rendering, mobile layout, game weapon integration, server-accepted damage, or performance on a real player population. Those require testing in the intended Roblox experience. No live execution or injection was performed.
