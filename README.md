# Salesforce Utils

Personal collection of reusable Salesforce utilities, as a Salesforce DX project. Each utility gets its own doc under [`docs/`](docs/) explaining what it is and how to use it.

## Utilities

- **Trigger Handler Framework** — metadata-driven Apex trigger dispatch, with a built-in recursion guard. See [`docs/TriggerHandlerFramework.md`](docs/TriggerHandlerFramework.md) for how it works and how to use it. Standalone deployable project: [Trigger-Handler-Framework](https://github.com/geronimo-olivera/Trigger-Handler-Framework).
- **Field Transition Framework** — metadata-driven field transition validator (blocks a field from changing to a configured value until its conditions are met) plus a companion Lightning checklist component. See [`docs/FieldTransitionFramework.md`](docs/FieldTransitionFramework.md) for the full operator/field-type reference and how to configure it. Standalone deployable project: [Field-Transition-Framework](https://github.com/geronimo-olivera/Field-Transition-Framework).
- **HttpCalloutService** — centralized service for outbound HTTP callouts (GET/POST/PUT/PATCH/DELETE, JSON helpers, consistent error handling). See [`docs/HttpCalloutService.md`](docs/HttpCalloutService.md) for usage examples.
- **EmailService** — centralized service for outbound emails (templated, ad-hoc, attachments, CC/BCC/reply-to, consistent error handling). See [`docs/EmailService.md`](docs/EmailService.md) for usage examples and how to configure its `Email_Service_Setting__mdt` default.
- **NotificationService** — centralized service for custom notifications (the bell icon), with helpers to notify a record's followers, its owner, or explicit users, and consistent error handling. See [`docs/NotificationService.md`](docs/NotificationService.md) for usage examples and how to set up a Custom Notification Type.
- **Async Apex Framework** — metadata-driven base classes for Batch and Queueable Apex (active flag, retry, batch size, failure email, all via `Async_Job_Configuration__mdt`), with retry/completion logic that's deliberately different between the two. See [`docs/AsyncApexFramework.md`](docs/AsyncApexFramework.md) for easy and advanced examples for both, and why they retry differently. Standalone deployable project: [Async-Apex-Framework](https://github.com/geronimo-olivera/Async-Apex-Framework).

## Deploy to an org

You need [VS Code with the Salesforce Extension Pack](https://developer.salesforce.com/tools/vscode/) and an authenticated org.

1. Clone this repo and open it in VS Code.
2. Authenticate to your target org (`SFDX: Authorize an Org`, or `sf org login web` from the CLI).
3. Right-click [`manifest/package.xml`](manifest/package.xml) and choose **SFDX: Deploy Source in Manifest to Org**.

[`manifest/package.xml`](manifest/package.xml) lists every utility's components together. As more utilities are added, either extend this manifest or give each utility its own.
