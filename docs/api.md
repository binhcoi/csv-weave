# API reference

The current API creates and manages CSV file formats, their column rules, and transformation maps. File upload and conversion execution are not available yet.

Start the application using the [README setup instructions](../README.md#run-locally). The local base URL is `http://localhost:3000`.

[File types](#file-types) · [Columns](#columns) · [Validations](#validation-rules) · [Maps](#transformation-maps) · [Transformations](#transformation-rules) · [Catalogs](#operation-catalogs) · [Bulk edits](#bulk-edits) · [Errors](#errors)

## Connecting a client

Requests with a body use `Content-Type: application/json`. Single-record writes wrap attributes in a resource key, such as `file_type` or `transformation`. Updates accept only the fields you want to change; `PATCH` and `PUT` both preserve omitted fields.

For example, this request creates a file type:

```sh
curl --fail-with-body -sS http://localhost:3000/file_types \
  -H 'Content-Type: application/json' \
  --data '{"file_type":{"name":"Customer import"}}'
```

A successful response is HTTP 201 with the saved object's public fields:

```json
{
  "id": 10,
  "name": "Customer import",
  "description": null
}
```

Save the returned `id` when your application needs to read, update, or reference that record. IDs in this document are illustrative; your database will assign its own.

### Integration order

To configure a conversion between two formats:

1. Read the validator and transformer catalogs to obtain the IDs of the operations you need.
2. Create the source file type with its columns and any validation rules.
3. Create the destination file type with its columns and validation rules.
4. Read the destination file type to obtain its column IDs.
5. Create a transformation map using both file-type IDs. Its transformations reference destination column IDs and identify source columns through their operation settings.
6. Read the map to retrieve the saved transformations. Keep its ID for later reads and edits.

The sections below describe each resource independently, including the request fields, returned fields, and relevant restrictions.

## File types

A file type describes the columns expected in a CSV format. The same type can be reused by several maps.

| Method | Path | Result |
| --- | --- | --- |
| `GET` | `/file_types` | Array of file types in ID order, including columns and validations. |
| `GET` | `/file_types/:id` | One file type, including columns and validations. |
| `POST` | `/file_types` | Create a type, optionally with columns and validations; return its metadata. |
| `PATCH` / `PUT` | `/file_types/:id` | Update name or description; return its metadata. |
| `DELETE` | `/file_types/:id` | Delete an unused type, its columns, and their validations. |

**Request key:** `file_type`

| Field | Type | Create | Update |
| --- | --- | --- | --- |
| `name` | String | Required, nonblank. | Optional; must remain nonblank. |
| `description` | String or null | Optional. | Optional; null clears it. |
| `columns` | Array of column objects | Optional; omitted or empty is allowed. | Not accepted; use the column endpoints. |

Each nested column accepts `name`, `description`, `position`, and an optional `validations` array. Each nested validation accepts `column_validator_id` and optional `input_json`. The API assigns the parent relationships; nested IDs and ownership fields are not write fields.

For example, `POST /file_types` can create an email column and its required-value rule in one request:

```json
{
  "file_type": {
    "name": "Customer import",
    "description": "Source customer records",
    "columns": [
      {
        "name": "email",
        "position": 0,
        "validations": [{ "column_validator_id": 1 }]
      }
    ]
  }
}
```

Use the ID of `RequiredValidator` from the catalog in place of `1`. All records in this request are created together; an invalid column or rule prevents the entire creation.

Create and update responses contain `id`, `name`, and `description`. List and individual reads also contain `columns`. For example, a destination format might return:

```json
{
  "id": 20,
  "name": "Customer export",
  "description": null,
  "columns": [
    {
      "id": 201,
      "name": "contact_email",
      "description": null,
      "position": 0,
      "validations": []
    }
  ]
}
```

Columns are ordered by position. Each column's `validations` is an array ordered by rule ID, containing `id`, `column_validator_id`, and `input_json`. Empty arrays mean no columns or no validation rules.

Deleting a file type returns HTTP 422 while any map uses it as input or output. Update its columns or rules through their own endpoints, including the [scoped bulk endpoints](#bulk-edits).

## Columns

A column belongs to one file type. Its name identifies a CSV header; its position determines its order within that format.

| Method | Path | Result |
| --- | --- | --- |
| `GET` | `/columns` | Array ordered by file type, position, and ID. Optional query: `file_type_id`. |
| `GET` | `/columns/:id` | One column. |
| `POST` | `/columns` | Create a column. |
| `PATCH` / `PUT` | `/columns/:id` | Update a column. |
| `DELETE` | `/columns/:id` | Delete the column and its validations if no transformation uses it. |

**Request key:** `column`

| Field | Type | Requirement |
| --- | --- | --- |
| `file_type_id` | Integer | Required on create; must identify an existing file type. |
| `name` | String | Required on create; nonblank and unique within the type. |
| `position` | Integer | Required on create; zero or greater and unique within the type. |
| `description` | String or null | Optional. |

All four fields can be supplied on update. Position gaps are allowed; deletion does not renumber the remaining columns. Moving a column to another type is rejected if that would invalidate its use as a transformation target.

Example body for `POST /columns`:

```json
{
  "column": {
    "file_type_id": 20,
    "name": "note",
    "position": 1
  }
}
```

Returned fields are `id`, `file_type_id`, `name`, `description`, and `position`. This resource does not embed validations; use a file-type read or filter `/validations?column_id=:id` to retrieve them.

Deleting a column returns HTTP 422 if a transformation reads it as a source or targets it as output. Shared validator catalog records are retained when a column and its rules are deleted.

## Validation rules

A validation rule selects a validator from the catalog and attaches it to a column. It describes how to check a value; creating the rule does not process any CSV data.

| Method | Path | Result |
| --- | --- | --- |
| `GET` | `/validations` | Array in ID order. Optional query: `column_id`. |
| `GET` | `/validations/:id` | One validation rule. |
| `POST` | `/validations` | Create a rule. |
| `PATCH` / `PUT` | `/validations/:id` | Update a rule. |
| `DELETE` | `/validations/:id` | Delete the rule, retaining the column and catalog entry. |

**Request key:** `validation`

| Field | Type | Requirement |
| --- | --- | --- |
| `column_id` | Integer | Required on create; an existing column. |
| `column_validator_id` | Integer | Required on create; an ID from `/column_validators`. |
| `input_json` | JSON value | Optional settings accepted by that validator's schema. Defaults to `{}` on create. |

All three fields can be supplied on update. Explicit null for `input_json` is preserved if the selected schema allows it.

For example, attach a required-value check with `POST /validations`:

```json
{
  "validation": {
    "column_id": 201,
    "column_validator_id": 1
  }
}
```

Returned fields are `id`, `column_id`, `column_validator_id`, and `input_json`. `RequiredValidator` needs no settings. Other validators will define their own settings through their catalog schemas.

## Transformation maps

A map connects an input file type to an output file type. Its transformations describe how to fill individual output columns.

| Method | Path | Result |
| --- | --- | --- |
| `GET` | `/transform_maps` | Array in ID order, including transformations. |
| `GET` | `/transform_maps/:id` | One map, including transformations. |
| `POST` | `/transform_maps` | Create a map, optionally with transformations; return its metadata. |
| `PATCH` / `PUT` | `/transform_maps/:id` | Update the map's metadata or file-type references. |
| `DELETE` | `/transform_maps/:id` | Delete the map and its transformations. |

**Request key:** `transform_map`

| Field | Type | Create | Update |
| --- | --- | --- | --- |
| `name` | String | Required, nonblank. | Optional; must remain nonblank. |
| `description` | String or null | Optional. | Optional; null clears it. |
| `input_file_type_id` | Integer | Required; an existing type. | Optional. |
| `output_file_type_id` | Integer | Required; an existing type. | Optional. |
| `transformations` | Array of transformation objects | Optional; omitted or empty is allowed. | Not accepted; use the transformation endpoints. |

Each nested transformation accepts `output_column_id`, `column_transformer_id`, and optional `input_json`. It belongs to the map being created; a supplied child `transform_map_id` cannot change that ownership.

For example, `POST /transform_maps` can copy `email` from source type `10` into column `201` of destination type `20`:

```json
{
  "transform_map": {
    "name": "Customer email mapping",
    "input_file_type_id": 10,
    "output_file_type_id": 20,
    "transformations": [
      {
        "output_column_id": 201,
        "column_transformer_id": 1,
        "input_json": { "name": "email" }
      }
    ]
  }
}
```

Use the returned file-type and output-column IDs, and the catalog ID for `CopyTransformer`. The map and all supplied transformations are saved together.

Create and update responses contain `id`, `name`, `description`, `input_file_type_id`, and `output_file_type_id`. Reads also include `transformations`, ordered by ID. Each item has the fields listed in [transformation rules](#transformation-rules).

Same-type maps, repeated names, and repeated input/output pairs are allowed. A map can leave output columns unmapped. Changing the output type is rejected while existing transformations target columns outside the proposed output type. Changing the input type does not rewrite existing source-column settings.

Deleting a map retains its file types, columns, and operation catalogs.

## Transformation rules

A transformation belongs to one map, selects an operation, and targets one output column. One map cannot have two transformations targeting the same output column.

| Method | Path | Result |
| --- | --- | --- |
| `GET` | `/transformations` | Array in ID order. Optional query: `transform_map_id`. |
| `GET` | `/transformations/:id` | One transformation. |
| `POST` | `/transformations` | Create a transformation. |
| `PATCH` / `PUT` | `/transformations/:id` | Update a transformation. |
| `DELETE` | `/transformations/:id` | Delete the transformation, retaining its map, column, and catalog entry. |

**Request key:** `transformation`

| Field | Type | Requirement |
| --- | --- | --- |
| `transform_map_id` | Integer | Required on create; an existing map. |
| `output_column_id` | Integer | Required on create; a column in the map's output file type. |
| `column_transformer_id` | Integer | Required on create; an ID from `/column_transformers`. |
| `input_json` | JSON value | Optional in the general request shape; the operation's schema determines required settings. Defaults to `{}` on create. |

All four fields can be supplied on update. For copy, `input_json` must be an object containing a nonempty string `name`. That name must identify a column in the map's input file type.

Example body for `POST /transformations`:

```json
{
  "transformation": {
    "transform_map_id": 30,
    "output_column_id": 201,
    "column_transformer_id": 1,
    "input_json": { "name": "email" }
  }
}
```

Returned fields are `id`, `transform_map_id`, `output_column_id`, `column_transformer_id`, and `input_json`.

## Operation catalogs

| Method | Path | Contents |
| --- | --- | --- |
| `GET` | `/column_validators` | Available validator types, currently `RequiredValidator`. |
| `GET` | `/column_transformers` | Available transformer types, currently `CopyTransformer`. |

Both return arrays in ID order. Each entry contains:

| Field | Meaning |
| --- | --- |
| `id` | The ID to supply when a validation or transformation selects this operation. |
| `processor_class` | The application-defined Ruby class name identifying the operation. |
| `description` | A description of its behavior. |
| `input_schema` | JSON Schema describing accepted `input_json` settings; null skips JSON Schema checks. |

Catalogs are read-only through the API and populated by application seeds. Select operations by their returned IDs. Do not assume the same IDs across installations. See [input schemas](input_schemas.md) for schema and null-handling details.

## Bulk edits

### Add and remove within one parent

Use these endpoints to edit several items within one file type or map:

| Method | Path | Fields accepted by each item in `add` |
| --- | --- | --- |
| `PATCH` | `/file_types/:file_type_id/columns` | `name`, `description`, `position` |
| `PATCH` | `/file_types/:file_type_id/validations` | `column_id`, `column_validator_id`, `input_json` |
| `PATCH` | `/transform_maps/:transform_map_id/transformations` | `output_column_id`, `column_transformer_id`, `input_json` |

These requests use top-level `add` and `remove_ids`, without a singular resource wrapper. For example, a transformation replacement has this shape:

```json
{
  "remove_ids": [41, 42],
  "add": [
    {
      "output_column_id": 201,
      "column_transformer_id": 1,
      "input_json": { "name": "email" }
    }
  ]
}
```

- Both arrays are optional; omitted or empty arrays perform no corresponding changes.
- `add` must be an array of objects. Each uses the same required fields as the resource's create request, except the parent ID supplied by the URL.
- `remove_ids` must contain distinct positive JSON integers belonging to that parent.
- Added validations must target columns in the requested file type. Added transformations must target columns in the map's output type.
- Removals happen first so replacements can reuse a position, name, or output target.
- All changes succeed together. Any failure restores earlier removals and discards earlier additions.

Successful requests return HTTP 200 with the parent's entire updated collection: columns in position order, or rules in ID order. A request with no changes returns the current collection.

### Create or update arrays of rules

These endpoints operate on explicit arrays of validation or transformation records:

| Method | Path | Top-level request key | Result |
| --- | --- | --- | --- |
| `POST` | `/validations/bulk` | `validations` | Create rules; return HTTP 201. |
| `PATCH` | `/validations/bulk` | `validations` | Update rules by ID; return HTTP 200. |
| `POST` | `/transformations/bulk` | `transformations` | Create rules; return HTTP 201. |
| `PATCH` | `/transformations/bulk` | `transformations` | Update rules by ID; return HTTP 200. |

The value must be a nonempty array of objects. Creates use the single-record create fields. Updates require an `id` per item and accept the fields to change; duplicate update IDs are rejected. Parent IDs must be supplied for creates because these paths have no parent in the URL.

Each request is transactional. Success returns only the affected records, in request order. These endpoints do not remove records.

## Errors

| Status | Meaning |
| --- | --- |
| `200` | Successful read or update. |
| `201` | Created a resource or rules. |
| `204` | Deleted successfully; the response has no body. |
| `400` | Missing required request wrapper or malformed payload, array, or removal-ID format. |
| `404` | Resource not found, including a record outside the parent of a scoped lookup. |
| `422` | Invalid field values, rule settings, references, or a deletion blocked by a dependency. |

For ordinary malformed requests and missing records, the body contains an `error` string. Messages describe the particular failure:

```json
{ "error": "Record not found" }
```

Single-record, nested-create, and scoped-bulk validation failures use an `errors` object whose keys identify fields:

```json
{ "errors": { "name": ["can't be blank"] } }
```

Nested creates identify items with paths such as `columns[1].validations[0].input_json` or `transformations[1].input_json`. Scoped bulk edits use paths such as `add[0].input_json`. Array indexes start at zero.

For validation failures, the four array-based rule endpoints return an array with the failing item's `index` and its field errors. Missing records within those batches also use an indexed entry, with an `error` string. Malformed requests still use the top-level `error` string described above.

```json
{
  "errors": [
    { "index": 1, "errors": { "column_validator": ["must exist"] } }
  ]
}
```

A failed write does not return a partially successful collection. Correct the failing input and resubmit the intended changes.
