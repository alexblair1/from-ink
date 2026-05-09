# From Ink — Integration Matrix

## V1 — Native Apple

Zero OAuth. Zero server. Zero cost. Works for every user on day one.

| Integration | Framework | Permission Required | Use Case |
|---|---|---|---|
| **Reminders** | EventKit | `requestFullAccessToReminders` | Task routing from Dispatch |
| **Calendar** | EventKit | `requestFullAccessToEvents` | Meeting and event routing |
| **Mail** | MFMailComposeViewController | None | Email draft from extracted tasks |
| **Messages** | MFMessageComposeViewController | None | iMessage/SMS from extracted tasks |
| **Phone / FaceTime** | `tel://` `facetime://` `facetime-audio://` URL schemes | None | Call/FaceTime from detected names |
| **Contacts** | CNContactStore | NSContactsUsageDescription | Name-to-number resolution for Phone and Messages |
| **Share Sheet** | UIActivityViewController | None | Export to any installed app |
| **Files App** | UIDocumentPickerViewController | None (security-scoped resource) | Import PDF, images, .paper files |
| **Spotlight** | CoreSpotlight | None | Index all handwritten content for home screen search |
| **Document Scanning** | VNDocumentCameraViewController | Camera | Scan physical documents to searchable PDF |
| **Apple Pencil** | UIPencilInteraction | None | Double-tap + squeeze gestures |
| **WeatherKit** | WeatherKit | Location (when in use) | Daily Brief temperature + condition icon |
| **Siri / App Intents** | AppIntents | None | "Hey Siri, new note in From Ink" |

---

## V2 — OAuth PKCE Integrations

All confirmed PKCE. Zero server required. Zero cost per API call.

| Integration | PKCE | Audience | Use Case |
|---|---|---|---|
| **Linear** | ✅ Confirmed | Developers, PMs | Create issues from extracted tasks |
| **GitHub** | ✅ Confirmed — July 2025 | Developers | Create issues and bug reports |
| **Slack** | ✅ Confirmed — March 2026, required for custom URI schemes | Everyone with a team | Post session summaries, route DMs |
| **Canva** | ✅ Confirmed — S256 required | Designers, Marketers | Route design tasks, sketch export |
| **Asana** | ✅ Confirmed — S256 | PMs, Teams | Create tasks in Asana projects |
| **Todoist** | ✅ Confirmed — Dynamic Client Registration, no client secret | Knowledge workers | Personal task routing with due dates |
| **Airtable** | ✅ Confirmed — client secret optional for native apps | PMs, Operations, Data teams | Dynamic schema record creation |

---

## V2 — URL Scheme Integrations

No OAuth. No server. User must have the app installed.

| Integration | Scheme | Use Case |
|---|---|---|
| **Bear** | `bear://` | Create note from session output |
| **Things 3** | `things:///` | Create task from extracted items |
| **Obsidian** | `obsidian://` + Share Sheet | Export markdown to Obsidian vault |

---

## Dropped — No PKCE Support

The PKCE rule is absolute. If a third party does not support PKCE, it is not integrated.

| Integration | Reason |
|---|---|
| ~~Figma~~ | Requires Client Secret + external server — REST API does not support PKCE for third-party apps |
| ~~Notion~~ | No confirmed PKCE support for third-party OAuth clients |
| ~~Jira~~ | Jira Cloud requires Client Secret — no PKCE path for third-party apps |

---

## V2 Backlog — Special Features

| Feature | Technology | Notes |
|---|---|---|
| **Airtable Dynamic Schema** | Foundation Models + Airtable REST API | Fetches user's base/table/field schema — Foundation Models injects schema into prompt for field extraction. Most powerful integration — serves any workflow the user already has. |
| **Mermaid Diagram Client** | WKWebView + local Mermaid.js bundle | Mac and iPhone: create diagrams via direct syntax editing or Foundation Models natural language generation. iPad: view only. No network call — Mermaid.js ships in app bundle. |

---

## The PKCE Rule

> Every OAuth integration must confirm PKCE support before being added to this list.
> No client secrets in the app bundle. No server infrastructure for any V2 integration.
> If a third party does not support PKCE, the integration is dropped — no exceptions.

**Confirmed PKCE support:** Linear, GitHub, Slack, Canva, Asana, Todoist, Airtable

**Dropped for no PKCE:** Figma, Notion, Jira

---

## Coverage by Professional Role

| Role | Primary Integrations |
|---|---|
| Software Developer | Linear, GitHub, Slack |
| Product Manager | Linear, Asana, Airtable, Slack |
| Designer | Canva, Share Sheet |
| Marketing / Operations | Asana, Airtable, Canva, Slack |
| Executive / Knowledge Worker | Todoist, Reminders, Calendar, Slack |
| Researcher / Student | Obsidian (URL scheme), Bear, Share Sheet |

---

*From Ink — Blair Technologies LLC — May 2026*