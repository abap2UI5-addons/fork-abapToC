# fork-abapToC

[![abap2UI5-addons](https://img.shields.io/badge/abap2UI5--addons-app-1873b4)](https://github.com/abap2UI5-addons)
[![ABAP](https://img.shields.io/badge/ABAP-Standard%20%E2%89%A5%207.50-blue)](#installation)
[![abap2UI5](https://img.shields.io/badge/requires-abap2UI5-blue)](https://github.com/abap2UI5/abap2UI5)
[![License](https://img.shields.io/github/license/abap2UI5-addons/fork-abapToC)](LICENSE)
<br>
[![ABAP Standard](https://img.shields.io/github/actions/workflow/status/abap2UI5-addons/fork-abapToC/abap-standard.yaml?branch=main&label=ABAP%20Standard)](https://github.com/abap2UI5-addons/fork-abapToC/actions/workflows/abap-standard.yaml)
[![check-abap2UI5](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fabap2UI5-addons%2Ffork-abapToC%2Fmain%2F.github%2Fbadges%2Fcheck-abap2ui5.json)](https://github.com/abap2UI5-addons/fork-abapToC/actions/workflows/check-abap2ui5.yaml)
[![abap2UI5](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fabap2UI5-addons%2Ffork-abapToC%2Fmain%2F.github%2Fbadges%2Fabap2ui5.json)](https://github.com/abap2UI5-addons/fork-abapToC/actions/workflows/check-abap2ui5.yaml)

**Create, release and import Transport of Copies with one click.** ABAP
Transport of Copies (abapToC) brings the transaction `ZTOC` and, in this fork,
an abap2UI5 front end for it. For SAP developers who work with Transports of
Copies.

> Part of [abap2UI5-addons](https://github.com/abap2UI5-addons) - addons and apps for [abap2UI5](https://github.com/abap2UI5/abap2UI5), installed with [abapGit](https://abapgit.org).

<img width="1015" height="593" alt="obraz" src="https://github.com/user-attachments/assets/b9ba4d10-0db1-4b93-9d67-ff1f9017a716" />

## Why

Creating, releasing and importing a Transport of Copies by hand means several
steps per transport. abapToC does it from one list - with one click per
transport, or as a mass action on all selected ToCs.

This repository is the abap2UI5 port of
[Kaszub09/abapToC](https://github.com/Kaszub09/abapToC): the Transport of
Copies logic is the upstream one, and the abap2UI5 app `zcl_zabap_toc_ui5`
adds a browser front end next to the classic report. Changes about the
Transport of Copies logic itself belong upstream first.

## Installation

**Requirements**

- Standard ABAP 7.50 or higher
- [abap2UI5](https://github.com/abap2UI5/abap2UI5) - for the browser front end

**Steps** - with [abapGit](https://abapgit.org):

1. [abap2UI5](https://github.com/abap2UI5/abap2UI5)
2. this repository (branch `main`)
3. In order for import to work, you must:
   1. Import/Transport project to target system
   2. Create connection for target system in SM59 - for each possible target in transport (e.g. 'SYSTEM', 'SYSTEM.MANDANT' ) create connection with exact same name - will be used to call RFC which unpacks transport. So ZZZ.999 for system ZZZ and mandant 999, or just ZZZ if you don't specify mandant in transports.
   3. [Optional] Set developer system as trusted (via transaction SMT1) at target system. Set Trust Relationship to yes in connections and use Current User. This way you won't have to log into target system everytime you wan't to import transport - you will be automatically logged with current user.

**Start** - run the transaction `ZTOC` in SAP GUI, or the abap2UI5 app in the
browser with `?app_start=zcl_zabap_toc_ui5`.

## Usage

1. New Transaction *ZTOC* which allows for easy creation/release/import of Transport of Copies

![report](https://github.com/Kaszub09/abapToC/assets/34368953/9942d528-7b71-4db8-bcf1-82906ed1aa90)

2. Create, release and import Transport of Copies with one click:

![obraz](https://github.com/Kaszub09/abapToC/assets/34368953/7cc59ec7-5fe2-439b-8771-9051b78d0197)

## Notes

1. Written in ABAP 7.50

## Changelog

- v1.1 - allow user to choose between 3 types of descriptions - ToC + original request number, original request description, or custom / numbered description
- v1.2 - allow user mass action on all selected ToCs
- v1.2.1 - add STMS button
- v1.3 - retry importing ToC for a specified amount of time if not yet visible in target system (apparently, release funciton isn't fully synchronous?)
- v1.4 - add support for sub transport, minor enhancements
- 11.09.2025 - add support for selecting different target system (thanks for idea [jrgkraus](https://github.com/jrgkraus)
- 17.09.2025 - add support for transport groups
- 11.02.2026 - read variant with current username on report initialization

## Development

```sh
npm ci
npm run check
```

`npm run check` runs exactly what CI runs: abaplint (`abap-standard.yaml`) and
the abap2UI5-linter (`check-abap2ui5.yaml`).

## Contributing

Issues and pull requests are welcome - see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT - see [LICENSE](LICENSE).

A fork of [Kaszub09/abapToC](https://github.com/Kaszub09/abapToC) by Marcin
Kaszuba - all credit for ABAP Transport of Copies goes upstream.
