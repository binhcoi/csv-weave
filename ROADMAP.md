# CSVWeave Roadmap

CSVWeave is a Ruby on Rails application for defining CSV formats, validating their data, and transforming files between formats. It is for anyone who needs to validate CSV data or convert CSV files between formats. This roadmap covers the backend already built, the remaining file-processing API, and the planned web interface.

## Completed

### Configuration and data model

- [x] PostgreSQL models for file types, ordered columns, validation rules, transformation maps, and their processor catalogs.
- [x] REST APIs for configuration management, including nested creation and transactional bulk edits.
- [x] JSON Schema and processor-specific configuration validation, with database constraints and reference checks.
- [x] Safeguards for referenced columns, including automatic updates to transformation source references when a column is renamed.

### Validators and transformers

- [x] Extensible Ruby processor implementations for required, length, regex, numeric, date, and same-row comparison validations.
- [x] Nine transformers: copy, integer parse, decimal parse, concatenate, format string, arithmetic, substring, truncate, and date parse.
- [x] Focused processor tests and integration coverage for saved configurations.

### File storage and processing services

- [x] CSV uploads, metadata, and downloads through `DataFile` and Active Storage.
- [x] Configuration loaders for standalone validation and mapped conversion.
- [x] Streaming CSV validation and conversion services, including input/output rules and ordered output columns.
- [x] Streaming JSON Lines error reports with record, stage, column, operation, and reason.
- [x] Valid rows continue through conversion; rejected rows are omitted and reported.

### File-processing API

- [x] Review and finalize the shared validation/conversion runner implementation.
- [x] Add `ValidationRun` and `ConversionRun` records for status, counts, input file, map, error report, and conversion output.
- [x] Run validation and conversion as background jobs using Active Job / Solid Queue, without automatic retries.
- [x] Expose APIs to start operations, check status, and download outputs and error reports.
- [x] Enforce input-file/map compatibility and revalidate saved configuration at execution time.
- [x] Reuse existing runs for an unchanged file and configuration; recover stale runs.
- [x] Handle failed runs and partial output cleanup; add model, job, and request-level coverage.
- [x] Add end-to-end coverage with synthetic test data: seeded E2E-TEST scenarios, API-level RSpec flows, and a Postman/Newman collection.

**Outcome:** Users can upload a CSV, validate it independently, convert it with a saved map, and retrieve the results through the API.

## In progress

The next major phase is a browser-based interface for creating configurations and running CSV operations without manually constructing API requests.

**Estimated UI work: 30–45 hours**, excluding the remaining backend processing endpoints. These are planning estimates, not logged hours.

### 1. UI foundation (4–6 hours)

- [ ] Choose and integrate a frontend approach with the Rails API. React with TypeScript on Vite, in a separate frontend folder; see [UI.md](UI.md).
- [ ] Add navigation and shared components for forms, loading states, and API errors.

**Outcome:** A usable application shell connected to the backend.

## Planned: Web interface

### 2. File type and validation editor (8–10 hours)

- [ ] Create, browse, edit, and delete file types.
- [ ] Manage ordered columns and configure multiple validations per column.
- [ ] Generate validation settings forms from the validator catalog and its input schemas.
- [ ] Surface server-side errors while preserving unsaved form values.

**Outcome:** Users can manage input and output CSV schemas through the browser.

### 3. Transformation map editor (8–12 hours)

- [ ] Create and edit maps between existing file types.
- [ ] Show input and output columns together, with clear source-to-target relationships.
- [ ] Configure transformations and their parameters using the transformer catalog.
- [ ] Support unmapped output columns and display configuration errors clearly.

**Outcome:** Users can configure and revise a conversion map without editing JSON.

### 4. File validation and conversion workflow (6–9 hours)

- [ ] Upload CSV files and associate them with a file type.
- [ ] Start standalone validation or conversion using an appropriate saved map.
- [ ] Show background processing status and accepted/rejected row counts.
- [ ] Download converted CSV files and inspect or download rejection reports.

**Dependency:** The file-processing API must be completed first.

**Outcome:** The full CSV workflow is accessible in the UI.

### 5. UI testing and documentation (4–8 hours)

- [ ] Test key configuration and file-processing workflows.
- [ ] Improve keyboard accessibility, responsive layouts, and complex form usability.
- [ ] Add setup instructions and a short demonstration using synthetic CSV files.

**Outcome:** A coherent, locally runnable application with documented workflows.

## Later considerations

Configuration versioning, additional file formats, AI-assisted mappings, authentication, and multi-user hosting are outside this roadmap. The initial UI targets local, single-user use.
