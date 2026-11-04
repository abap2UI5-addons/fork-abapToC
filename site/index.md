---
layout: home

hero:
  name: "ABAP Transport of Copies"
  text: "Create, release and import Transports of Copies with one click."
  image:
    src: /logo.svg
    alt: abap2UI5 addons
  actions:
    - theme: brand
      text: Get started
      link: /guide
    - theme: alt
      text: GitHub
      link: https://github.com/abap2UI5-addons/fork-abapToC
    - theme: alt
      text: All addons
      link: https://abap2ui5-addons.github.io/

features:
  - title: "Create, release and import a Transport of Copies with one click"
  - title: "Mass action on all selected ToCs"
  - title: "Three kinds of ToC descriptions: request number, request description or custom"
  - title: "Retries the import while the ToC is not yet visible in the target system"
  - title: "Support for sub transports, transport groups and choosing a different target system"
  - title: "Transaction ZTOC in SAP GUI and an abap2UI5 app in the browser"
---

## What it does

A fork of Kaszub09/abapToC with an abap2UI5 front end. It brings the transaction ZTOC and the app zcl_zabap_toc_ui5, from which a developer creates, releases and imports Transports of Copies from one list, one click per transport or as a mass action on all selected ones. The Transport of Copies logic is the upstream one; changes to it belong upstream first.

## Requirements

- Standard ABAP 7.50 or higher
- abap2UI5 for the browser front end

## Installation

With [abapGit](https://abapgit.org), from [the repository](https://github.com/abap2UI5-addons/fork-abapToC):

- Install with abapGit in this order: abap2UI5, then this repository (branch main)
- Import or transport the project to the target system
- In SM59 create a connection for each possible transport target with exactly the same name as the target (for example ZZZ.999 for system ZZZ client 999, or ZZZ without client)
- Optional: set the development system as trusted in SMT1 at the target system and use Trust Relationship with Current User to avoid logging in on every import
- Start with transaction ZTOC in SAP GUI or ?app_start=zcl_zabap_toc_ui5 in the browser

The [Guide](/guide) has every step.

## A first app

```abap
?app_start=zcl_zabap_toc_ui5
```

## Links

- [Kaszub09/abapToC (upstream)](https://github.com/Kaszub09/abapToC)
- [abap2UI5](https://github.com/abap2UI5/abap2UI5)
- [The repository](https://github.com/abap2UI5-addons/fork-abapToC) - issues and pull requests welcome
