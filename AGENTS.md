# AGENTS.md

Single source of truth for agents working on **fork-abapToC**.

Transport of Copies, with an abap2UI5 front end. A fork of Kaszub09/abapToC.

## What this repository is

A **source** repository in the abap2UI5 ecosystem: humans and agents edit here,
and CI gates every change. It is installed with abapGit and depends on the
[abap2UI5](https://github.com/abap2UI5/abap2UI5) core at runtime.

## Layout

| Path | Contents |
| --- | --- |
| `src/` | Transport of Copies: the transaction, the report and the abap2UI5 front end |

**This is a fork** of [Kaszub09/abapToC](https://github.com/Kaszub09/abapToC).
Keep changes that are about the abap2UI5 front end here; anything about the
Transport of Copies logic itself belongs upstream first.

## Dependencies

- [abap2UI5](https://github.com/abap2UI5/abap2UI5) — the framework, for the UI only

There is no version pin on any of them — abaplint resolves each from its `main`
branch (`"branch": "main"` in `abaplint.json`, declared rather than left off -
abap2UI5 CONVENTIONS §9). That is why `ci` also runs on a weekly schedule: a rename
upstream breaks this repository silently, and with no pull request open nothing
else would notice.

## Build and verify

```sh
npm ci
npm run check
```

`npm run check` runs exactly what CI runs. See [CONTRIBUTING.md](CONTRIBUTING.md)
for what each gate proves and how the abap2UI5-linter baseline works.

## CI

CI comes from the shared CI template of abap2UI5-addons (reusable workflows in
[rap-ext](https://github.com/abap2UI5-addons/rap-ext/blob/main/.github/ci/README.md),
pinned by commit in the `uses:` lines and moved by `bump-deps`):

* `ci` - on every push to `main`, every pull request, weekly and by hand,
  one job per check: `check / abaplint (./abaplint.json)` (Standard ABAP,
  v750) and `check / abap2ui5lint` (the front end and its views, render gate
  on; on `main` the two README badges are published to the branch `badges`).
  These are the required status checks of the branch protection.
* `deploy-pages` (the site) and `bump-deps` (monthly, one pull request: npm,
  the pinned actions and the template pin - the last two only with the
  `DEPS_TOKEN` secret - via `.github/scripts/update-deps.mjs`, the same file
  as in every other repository).

**No ABAP Cloud lint, on purpose.** Transport of Copies is classic ABAP: the
report `ZTOC` with its selection screen, function groups and the `TR_*`
function modules. abaplint for ABAP Cloud reports 64 issues on it (every
`SELECTION-SCREEN`/`PARAMETERS`/`AT SELECTION-SCREEN`, unreleased function
modules) - nothing a small change can fix without changing what the tool is.
There is no 702 branch, no ABAP Unit suite and no rename script either.

## Views

Views are built with **`z2ui5_cl_ui5_view_builder`**, the core's generic builder
in `src/02`: `ele` (add a child and descend), `tag` (add a child and stay), `a`
(set an attribute on the element the chain points at), `end` (ascend),
`stringify` (render from the root).

Three rules that are easy to get wrong:

1. **`a( )` targets the last child** once a node has children, so a control's
   attributes belong immediately after the `ele( )`/`tag( )` that opened it.
2. **An ABAP boolean goes into `b =`.** Through `v =` an `abap_false` renders as
   an empty string, and UI5 reads an empty string as true.
3. **The root declares its own namespaces.** The frozen builder collected them
   and wrote the `xmlns` attributes itself; this one does not, and a prefix that
   is used but not declared makes the whole view fail to parse — a blank screen,
   not a bad layout. An aggregation tag takes the namespace of *its own control*:
   under `<form:SimpleForm>` it is `<form:content>`, never `<content>`.

The frozen `z2ui5_cl_xml_view` is gone from here and must not come back. It sits
in the core's `src/99`, outside the released API, and the view gate can read
nothing built with it.

## Conventions

- ABAP object names follow ``zcl_zabap_toc_*``, enforced by `abaplint.jsonc`.
- English for code, comments, commit messages, pull requests and issues.
- All text files are LF-only (`.gitattributes`).
- The ecosystem-wide rules — workflow and npm-script naming, toolchain versions,
  which documentation files exist, commit style — live in
  [CONVENTIONS.md](https://github.com/abap2UI5/abap2UI5/blob/main/.github/shared/CONVENTIONS.md)
  and bind this repository too.
