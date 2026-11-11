"""Generates CSVWeave.postman_collection.json next to this script.

Usage (from anywhere): python3 e2e/postman/generate_collection.py

Expected counts, output headers, first rows, and error stages are read from
e2e/fixtures/*/expected/, so regenerate after changing a fixture or a seeded rule.
Scenario definitions here mirror e2e/support/configuration_seeder.rb; keep them in sync.
Hand edits to the JSON are overwritten on the next run.
"""
import json, re, pathlib
root = pathlib.Path(__file__).resolve().parents[2]
FIX = root / "e2e/fixtures"

def script(kind, code):
    return [{"listen": kind, "script": {"type": "text/javascript", "exec": code.strip("\n").split("\n")}}]

def unquote_ids(raw):
    # Numeric IDs come from variables; drop the JSON quotes so they are sent as integers.
    return re.sub(r'"(\{\{[a-zA-Z_]+\}\})"', r"\1", raw)

def req(name, method, path, tests="", body=None, form=None, pre=""):
    r = {"method": method, "header": [], "url": "{{baseUrl}}" + path}
    if body is not None:
        r["header"] = [{"key": "Content-Type", "value": "application/json"}]
        r["body"] = {"mode": "raw", "raw": unquote_ids(json.dumps(body, indent=2))}
    if form is not None:
        r["body"] = {"mode": "formdata", "formdata": form}
    item = {"name": name, "request": r, "event": []}
    if pre: item["event"] += script("prerequest", pre)
    if tests: item["event"] += script("test", tests)
    return item

def folder(name, desc, items):
    return {"name": name, "description": desc, "item": items}

def lines_of(path):
    return [l for l in path.read_text().split("\n") if l]

def stages(path):
    return [json.loads(l)["stage"] for l in lines_of(path)]

class Scenario:
    def __init__(self, p, label):
        self.p, self.label = p, label
    def v(self, name):
        return "{{" + self.p + name + "}}"
    def setvar(self, name, expr):
        return f'pm.collectionVariables.set("{self.p}{name}", {expr});'

    def started(self, var):
        return f"""
pm.test("run started or reused", () => pm.expect(pm.response.code).to.be.oneOf([200, 202]));
{self.setvar(var, "pm.response.json().id")}
"""

    def poll(self, name, path, expect_js):
        # Re-runs itself (Collection Runner / Newman only) until the run leaves queued/running.
        return req(name, "GET", path, tests="""
const body = pm.response.json();
const attempts = Number(pm.collectionVariables.get("pollAttempts") || 0);
if (["queued", "running"].includes(body.status) && attempts < 30) {
  pm.collectionVariables.set("pollAttempts", attempts + 1);
  setTimeout(() => {}, 1000);
  postman.setNextRequest(pm.info.requestName);
} else {
  pm.collectionVariables.set("pollAttempts", 0);
  pm.test("run finished within 30 polls", () => pm.expect(body.status).to.be.oneOf(["succeeded", "rejected", "failed"]));
""" + expect_js + """
}
""")

    def upload(self, name, fixture, var, ft="inputFileTypeId"):
        return req(name, "POST", "/data_files", form=[
            {"key": "data_file[file_type_id]", "value": self.v(ft), "type": "text"},
            {"key": "data_file[file]", "src": fixture, "type": "file"},
        ], tests=f"""
pm.test("uploaded", () => pm.response.to.have.status(201));
{self.setvar(var, "pm.response.json().id")}
""")

    def catalogs(self, validators, transformers):
        return [
            req("List validators", "GET", "/column_validators", tests=f"""
pm.test("catalog loaded", () => pm.response.to.have.status(200));
{json.dumps(validators)}.forEach((name) => {{
  const entry = pm.response.json().find((item) => item.processor_class === name);
  pm.test(`${{name}} present`, () => pm.expect(entry).to.exist);
  pm.collectionVariables.set(`v_${{name.replace("Validator", "")}}`, entry.id);
}});
"""),
            req("List transformers", "GET", "/column_transformers", tests=f"""
pm.test("catalog loaded", () => pm.response.to.have.status(200));
{json.dumps(transformers)}.forEach((name) => {{
  const entry = pm.response.json().find((item) => item.processor_class === name);
  pm.test(`${{name}} present`, () => pm.expect(entry).to.exist);
  pm.collectionVariables.set(`t_${{name.replace("Transformer", "")}}`, entry.id);
}});
"""),
        ]

    def create_type(self, name, type_name, columns, var, pre=""):
        body = {"file_type": {"name": type_name + " {{runTag}}", "columns": [
            {"name": col, "position": i, **({"validations": [
                {"column_validator_id": "{{v_" + cls.replace("Validator", "") + "}}", **({"input_json": js} if js else {})}
                for cls, js in vals]} if vals else {})}
            for i, (col, vals) in enumerate(columns)]}}
        return req(name, "POST", "/file_types", body=body, pre=pre, tests=f"""
pm.test("created", () => pm.response.to.have.status(201));
{self.setvar(var, "pm.response.json().id")}
""")

    def read_columns(self, count):
        return req("Read output columns", "GET", "/file_types/" + self.v("outputFileTypeId"), tests=f"""
pm.test("found", () => pm.response.to.have.status(200));
const columns = pm.response.json().columns;
pm.test("{count} columns", () => pm.expect(columns.length).to.eql({count}));
columns.forEach((column) => pm.collectionVariables.set(`{self.p}col_${{column.name}}`, column.id));
""")

    def create_map(self, map_name, transformations):
        body = {"transform_map": {
            "name": map_name + " {{runTag}}",
            "input_file_type_id": self.v("inputFileTypeId"), "output_file_type_id": self.v("outputFileTypeId"),
            "transformations": [{"output_column_id": self.v("col_" + col),
                                 "column_transformer_id": "{{t_" + cls.replace("Transformer", "") + "}}",
                                 "input_json": js} for col, cls, js in transformations]}}
        return req("Create transform map", "POST", "/transform_maps", body=body, tests=f"""
pm.test("created", () => pm.response.to.have.status(201));
{self.setvar("transformMapId", "pm.response.json().id")}
""")

    def counts(self, status, a, r, e):
        return f"""
  pm.test("status {status}, counts {a}/{r}/{e}", () => {{
    pm.expect(body.status).to.eql("{status}");
    pm.expect([body.accepted_rows, body.rejected_rows, body.error_count]).to.eql([{a}, {r}, {e}]);
  }});"""

    def jsonl(self, name, path, expected_file):
        st = stages(expected_file)
        t = f"""
pm.test("downloaded", () => pm.response.to.have.status(200));
const lines = pm.response.text().split("\\n").filter((line) => line.length > 0);
pm.test("{len(st)} error line(s)", () => pm.expect(lines.length).to.eql({len(st)}));"""
        if st:
            t += f"""
pm.test("errors per stage", () => pm.expect(lines.map((line) => JSON.parse(line).stage)).to.eql({json.dumps(st)}));"""
        return req(name, "GET", path, tests=t)

    def csv_out(self, name, path, expected_file):
        rows = lines_of(expected_file)
        return req(name, "GET", path, tests=f"""
pm.test("downloaded", () => pm.response.to.have.status(200));
const lines = pm.response.text().trim().split("\\n");
pm.test("output header", () => pm.expect(lines[0]).to.eql({json.dumps(rows[0])}));
pm.test("{len(rows) - 1} converted row(s)", () => pm.expect(lines.length - 1).to.eql({len(rows) - 1}));
pm.test("first row converted", () => pm.expect(lines[1]).to.eql({json.dumps(rows[1])}));
""")

    def file_flow(self, kind, key, label, fixture_prefix, exp_dir, outcome):
        """Start a run for one uploaded file, poll it, and download its results.
        kind: validation | conversion; outcome: (status, counts or failure_reason)."""
        run_var = f"{key}{kind.capitalize()}RunId"
        verb, base = ("validate", "validation_runs") if kind == "validation" else ("convert", "conversion_runs")
        body = {"conversion_run": {"transform_map_id": self.v("transformMapId")}} if kind == "conversion" else None
        status, detail = outcome
        if isinstance(detail, tuple):
            check = self.counts(status, *detail)
        else:
            check = f"""
  pm.test("rejected: {detail.replace('"', "'")}", () => {{
    pm.expect(body.status).to.eql("rejected");
    pm.expect(body.failure_reason).to.eql({json.dumps(detail)});{'''
    pm.expect(body.output_url).to.eql(null);''' if kind == "conversion" else ""}
  }});"""
        title = "Validate" if kind == "validation" else "Convert"
        items = [
            req(f"{title} {label}", "POST", f"/data_files/{self.v(key + 'FileId')}/{verb}", body=body,
                tests=self.started(run_var)),
            self.poll(f"Poll {label} {kind}", f"/{base}/{self.v(run_var)}", check),
        ]
        if kind == "conversion":
            converted = exp_dir / f"{fixture_prefix}_converted.csv"
            if converted.exists():
                items.append(self.csv_out(f"Download {label} output", f"/{base}/{self.v(run_var)}/output", converted))
            else:
                items.append(req(f"{label.capitalize()} output is not available", "GET",
                                 f"/{base}/{self.v(run_var)}/output", tests="""
pm.test("404 for a rejected run's output", () => pm.response.to.have.status(404));
"""))
        items.append(self.jsonl(f"Download {label} {kind} errors", f"/{base}/{self.v(run_var)}/error_report",
                                exp_dir / f"{fixture_prefix}_{kind}_errors.jsonl"))
        return items

RUN_TAG = 'pm.collectionVariables.set("runTag", new Date().toISOString());'

# ---------------- Basic ----------------
b = Scenario("basic_", "Basic")
bdir = FIX / "basic/expected"
basic = folder("Basic", "Supplier orders -> warehouse orders: the README example.", [
    folder("00 Setup", "Read the catalogs and create the input/output file types and map through the API.",
        b.catalogs(["RequiredValidator", "DateValidator", "RegexValidator", "NumericRangeValidator"],
                   ["CopyTransformer", "ConcatenateTransformer", "DateParseTransformer", "SubstringTransformer",
                    "IntegerParseTransformer", "ArithmeticTransformer"]) + [
        b.create_type("Create input file type", "E2E-TEST Postman supplier orders", [
            ("order_ref", [("RequiredValidator", None)]), ("first", []), ("last", []),
            ("ordered_on", [("DateValidator", {"format": "%d %b %Y"})]),
            ("product_code", [("RegexValidator", {"pattern": "\\ASKU-"})]), ("qty", []), ("unit_price", [])],
            "inputFileTypeId", pre=RUN_TAG),
        b.create_type("Create output file type", "E2E-TEST Postman warehouse orders", [
            ("order_id", []), ("customer_name", []), ("order_date", []), ("sku", []),
            ("quantity", [("NumericRangeValidator", {"min": 1})]),
            ("line_total", [("NumericRangeValidator", {"min": 0})])], "outputFileTypeId"),
        b.read_columns(6),
        b.create_map("E2E-TEST Postman supplier to warehouse", [
            ("order_id", "CopyTransformer", {"source_column": "order_ref"}),
            ("customer_name", "ConcatenateTransformer", {"source_columns": ["first", "last"], "separator": " "}),
            ("order_date", "DateParseTransformer", {"source_column": "ordered_on", "format": "%d %b %Y", "output_format": "%Y-%m-%d"}),
            ("sku", "SubstringTransformer", {"source_column": "product_code", "start": 4, "length": 20}),
            ("quantity", "IntegerParseTransformer", {"source_column": "qty"}),
            ("line_total", "ArithmeticTransformer", {"source_columns": ["qty", "unit_price"], "operator": "*"})]),
    ]),
    folder("01 Upload", "Upload the basic fixture CSVs.", [
        b.upload("Upload valid orders", "basic/e2e_test_orders_valid.csv", "validFileId"),
        b.upload("Upload mixed orders", "basic/e2e_test_orders_mixed.csv", "mixedFileId"),
        b.upload("Upload bad-header orders", "basic/e2e_test_orders_bad_header.csv", "badHeaderFileId"),
        b.upload("Upload Latin-1 orders", "basic/e2e_test_orders_latin1.csv", "latin1FileId"),
    ]),
    folder("02 Validate", "Validate uploads, poll, and check counts and error reports.",
        b.file_flow("validation", "valid", "valid orders", "orders_valid", bdir, ("succeeded", (5, 0, 0)))
        + b.file_flow("validation", "mixed", "mixed orders", "orders_mixed", bdir, ("succeeded", (4, 4, 4)))
        + b.file_flow("validation", "latin1", "Latin-1 orders", "orders_latin1", bdir, ("rejected", "input contains invalid UTF-8"))),
    folder("03 Convert", "Convert uploads with the map, poll, and check outputs and error reports.",
        b.file_flow("conversion", "valid", "valid orders", "orders_valid", bdir, ("succeeded", (5, 0, 0)))
        + b.file_flow("conversion", "mixed", "mixed orders", "orders_mixed", bdir, ("succeeded", (2, 6, 7)))
        + b.file_flow("conversion", "badHeader", "bad-header orders", "orders_bad_header", bdir,
                      ("rejected", 'missing headers: "unit_price"'))),
])

# ---------------- Comprehensive ----------------
c = Scenario("full_", "Comprehensive")
cdir = FIX / "comprehensive/expected"
comprehensive = folder("Comprehensive",
    "Event registrations -> attendee badges: every cataloged validator and transformer, plus an unmapped output column.", [
    folder("00 Setup", "Read the catalogs and create the input/output file types and map through the API.",
        c.catalogs(["RequiredValidator", "LengthValidator", "RegexValidator", "NumericRangeValidator", "DateValidator",
                    "StringComparisonValidator", "NumericComparisonValidator"],
                   ["CopyTransformer", "IntegerParseTransformer", "DecimalParseTransformer", "ConcatenateTransformer",
                    "FormatStringTransformer", "ArithmeticTransformer", "SubstringTransformer", "TruncateTransformer",
                    "DateParseTransformer"]) + [
        c.create_type("Create input file type", "E2E-TEST Postman event registrations", [
            ("reg_id", [("RequiredValidator", None), ("RegexValidator", {"pattern": "\\AREG-T[0-9]{4}\\z"})]),
            ("given_name", [("RequiredValidator", None), ("LengthValidator", {"max": 20})]),
            ("family_name", [("LengthValidator", {"min": 0, "max": 30})]),
            ("email", [("RegexValidator", {"pattern": "@example\\.test\\z"})]),
            ("confirm_email", [("StringComparisonValidator", {"other_column": "email", "operator": "=="})]),
            ("registered_on", [("DateValidator", {"format": "%Y-%m-%d", "min": "2026-01-01", "max": "2026-12-31"})]),
            ("event_on", [("DateValidator", {"format": "%d/%m/%Y"})]),
            ("tickets", [("NumericComparisonValidator", {"other_column": "group_size", "operator": "<="})]),
            ("ticket_price", []), ("discount", []), ("booking_fee", []), ("group_size", []), ("notes", [])],
            "inputFileTypeId", pre=RUN_TAG),
        c.create_type("Create output file type", "E2E-TEST Postman attendee badges", [
            ("badge_id", [("RegexValidator", {"pattern": "\\AT[0-9]{4}\\z"})]),
            ("full_name", []),
            ("display_name", [("LengthValidator", {"max": 40})]),
            ("badge_label", []), ("email", []),
            ("event_date", [("DateValidator", {"format": "%Y-%m-%d", "min": "2026-01-01"})]),
            ("tickets", [("NumericRangeValidator", {"min": 1, "max": 10})]),
            ("ticket_price", [("NumericRangeValidator", {"min": 0})]),
            ("subtotal", []), ("net_price", []), ("price_with_fee", []),
            ("price_per_person", [("NumericRangeValidator", {"min": 0})]),
            ("notes_short", []), ("internal_ref", [])], "outputFileTypeId"),
        c.read_columns(14),
        c.create_map("E2E-TEST Postman registrations to badges", [
            ("badge_id", "SubstringTransformer", {"source_column": "reg_id", "start": 4, "length": 5}),
            ("full_name", "ConcatenateTransformer", {"source_columns": ["given_name", "family_name"], "separator": " "}),
            ("display_name", "FormatStringTransformer", {"source_columns": ["given_name", "family_name"], "format": "%{family_name}, %{given_name}"}),
            ("badge_label", "FormatStringTransformer", {"source_columns": ["given_name"], "format": "%{given_name} - 100%% fake"}),
            ("email", "CopyTransformer", {"source_column": "email"}),
            ("event_date", "DateParseTransformer", {"source_column": "event_on", "format": "%d/%m/%Y"}),
            ("tickets", "IntegerParseTransformer", {"source_column": "tickets"}),
            ("ticket_price", "DecimalParseTransformer", {"source_column": "ticket_price"}),
            ("subtotal", "ArithmeticTransformer", {"source_columns": ["tickets", "ticket_price"], "operator": "*"}),
            ("net_price", "ArithmeticTransformer", {"source_columns": ["ticket_price", "discount"], "operator": "-"}),
            ("price_with_fee", "ArithmeticTransformer", {"source_columns": ["ticket_price", "booking_fee"], "operator": "+"}),
            ("price_per_person", "ArithmeticTransformer", {"source_columns": ["ticket_price", "group_size"], "operator": "/", "scale": 2}),
            ("notes_short", "TruncateTransformer", {"source_column": "notes", "length": 15})]),
    ]),
    folder("01 Upload", "Upload the comprehensive fixture CSVs.", [
        c.upload("Upload valid registrations", "comprehensive/e2e_test_registrations_valid.csv", "validFileId"),
        c.upload("Upload mixed registrations", "comprehensive/e2e_test_registrations_mixed.csv", "mixedFileId"),
    ]),
    folder("02 Validate", "Validate uploads, poll, and check counts and error reports.",
        c.file_flow("validation", "valid", "valid registrations", "registrations_valid", cdir, ("succeeded", (4, 0, 0)))
        + c.file_flow("validation", "mixed", "mixed registrations", "registrations_mixed", cdir, ("succeeded", (8, 9, 13)))),
    folder("03 Convert", "Convert uploads with the map, poll, and check outputs and error reports.",
        c.file_flow("conversion", "valid", "valid registrations", "registrations_valid", cdir, ("succeeded", (4, 0, 0)))
        + c.file_flow("conversion", "mixed", "mixed registrations", "registrations_mixed", cdir, ("succeeded", (2, 15, 24)))),
])

# ---------------- Edge cases (uses Basic's records) ----------------
CONVERT = {"conversion_run": {"transform_map_id": b.v("transformMapId")}}
edge = folder("Edge cases", "Run reuse, file-type mismatch, and unknown IDs. Requires the Basic folder to have run first.", [
    req("Reuse finished validation run", "POST", f"/data_files/{b.v('validFileId')}/validate", tests="""
pm.test("200 with the same run", () => {
  pm.response.to.have.status(200);
  pm.expect(pm.response.json().id).to.eql(Number(pm.collectionVariables.get("basic_validValidationRunId")));
});
"""),
    req("Reuse finished conversion run", "POST", f"/data_files/{b.v('validFileId')}/convert", body=CONVERT, tests="""
pm.test("200 with the same run", () => {
  pm.response.to.have.status(200);
  pm.expect(pm.response.json().id).to.eql(Number(pm.collectionVariables.get("basic_validConversionRunId")));
});
"""),
    b.upload("Upload valid orders as the output file type", "basic/e2e_test_orders_valid.csv", "mismatchFileId", ft="outputFileTypeId"),
    req("Convert with a mismatched file type", "POST", f"/data_files/{b.v('mismatchFileId')}/convert", body=CONVERT, tests="""
pm.test("422 with a rejected run", () => {
  pm.response.to.have.status(422);
  pm.expect(pm.response.json().status).to.eql("rejected");
});
"""),
    req("Validate an unknown data file", "POST", "/data_files/999999999/validate", tests="""
pm.test("404", () => pm.response.to.have.status(404));
"""),
    req("Convert with an unknown map", "POST", f"/data_files/{b.v('validFileId')}/convert",
        body={"conversion_run": {"transform_map_id": 999999999}}, tests="""
pm.test("422 with a transform_map error", () => {
  pm.response.to.have.status(422);
  pm.expect(pm.response.json().errors).to.have.property("transform_map");
});
"""),
])

collection = {
    "info": {
        "name": "CSVWeave E2E",
        "description": "End-to-end flows with E2E-TEST data. Run with the Collection Runner or `bin/rails e2e:newman` "
                       "(FOLDER=Basic or FOLDER=Comprehensive for one scenario). Set the working directory to "
                       "e2e/fixtures for uploads. See e2e/README.md.",
        "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
    },
    "variable": [{"key": "baseUrl", "value": "http://localhost:3000"}],
    "item": [basic, comprehensive, edge],
}
(root / "e2e/postman/CSVWeave.postman_collection.json").write_text(json.dumps(collection, indent=2, ensure_ascii=False) + "\n")
