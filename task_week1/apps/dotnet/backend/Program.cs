// Notes API with ASP.NET Core (Minimal API) + DynamoDB. Same contract as every other backend: ../../../API.md
//
// DynamoDB is AWS's managed NoSQL database. One table "notes", key = "id" (string).
//   Local dev + CI : DynamoDB Local container  (DYNAMODB_ENDPOINT=http://dynamodb:8000)
//   Production     : the REAL DynamoDB on AWS (no endpoint -> the SDK talks to AWS, credentials from the EC2 role)
// Same code in both: only environment variables change.
using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.Model;
using Amazon.Runtime;

var builder = WebApplication.CreateBuilder(args);

string tableName = Environment.GetEnvironmentVariable("TABLE_NAME") ?? "notes";
string? endpoint = Environment.GetEnvironmentVariable("DYNAMODB_ENDPOINT");

// Register ONE DynamoDB client for the whole app (dependency injection: handlers ask for IAmazonDynamoDB).
builder.Services.AddSingleton<IAmazonDynamoDB>(_ => string.IsNullOrEmpty(endpoint)
    // AWS: region from AWS_REGION, credentials found automatically (env vars, ~/.aws, or the EC2 instance role)
    ? new AmazonDynamoDBClient()
    // DynamoDB Local accepts any credentials, but the SDK still needs some
    : new AmazonDynamoDBClient(new BasicAWSCredentials("local", "local"),
        new AmazonDynamoDBConfig { ServiceURL = endpoint, AuthenticationRegion = "us-east-1" }));

var app = builder.Build();

// Any unexpected exception -> 500 JSON (details only in the logs, never to the client)
app.UseExceptionHandler(errorApp => errorApp.Run(ctx =>
    Error(500, "INTERNAL_ERROR", "Unexpected server error").ExecuteAsync(ctx)));

// ---- Routes ----

app.MapGet("/api/health", () => Results.Json(new { status = "ok", backend = ".NET + ASP.NET Core + DynamoDB" }));

app.MapGet("/api/notes", async (IAmazonDynamoDB db) =>
{
    // Scan = read the WHOLE table (DynamoDB has no "ORDER BY"). Fine for a small table; big tables need Query + an index.
    var notes = new List<Note>();
    Dictionary<string, AttributeValue>? next = null;
    do // DynamoDB returns at most 1 MB per call: keep asking while it says "there is more" (LastEvaluatedKey)
    {
        var page = await db.ScanAsync(new ScanRequest { TableName = tableName, ExclusiveStartKey = next });
        notes.AddRange(page.Items.Select(ToNote));
        next = page.LastEvaluatedKey is { Count: > 0 } ? page.LastEvaluatedKey : null;
    } while (next != null);
    // ids are UUID version 7: they start with the creation time, so sorting the ids = sorting by creation
    return Results.Json(notes.OrderByDescending(n => n.Id, StringComparer.Ordinal));
});

app.MapGet("/api/notes/{id}", async (string id, IAmazonDynamoDB db) =>
{
    if (!Guid.TryParse(id, out _)) return NotFound(id); // malformed id = not found, like every backend
    var res = await db.GetItemAsync(new GetItemRequest { TableName = tableName, Key = Key(id) });
    return res.Item is { Count: > 0 } ? Results.Json(ToNote(res.Item)) : NotFound(id);
});

app.MapPost("/api/notes", async (HttpRequest req, IAmazonDynamoDB db) =>
{
    var (input, error) = await ReadInput(req);
    if (error != null) return error;
    var note = new Note(Guid.CreateVersion7().ToString(), input!.Text, input.Done, input.DueDate,
        DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture));
    await db.PutItemAsync(new PutItemRequest { TableName = tableName, Item = ToItem(note) });
    return Results.Json(note, statusCode: 201);
});

app.MapPut("/api/notes/{id}", async (string id, HttpRequest req, IAmazonDynamoDB db) =>
{
    if (!Guid.TryParse(id, out _)) return NotFound(id);
    var (input, error) = await ReadInput(req);
    if (error != null) return error;
    // Full replace (PUT): dueDate left out -> REMOVE the attribute (= null). createdAt is kept.
    // "#t"/"#d"/"#due" = placeholders for attribute names ("text" is a DynamoDB reserved word).
    var update = "SET #t = :t, #d = :d" + (input!.DueDate == null ? " REMOVE #due" : ", #due = :due");
    var values = new Dictionary<string, AttributeValue> { [":t"] = new() { S = input.Text }, [":d"] = new() { BOOL = input.Done } };
    if (input.DueDate != null) values[":due"] = new() { S = input.DueDate };
    try
    {
        var res = await db.UpdateItemAsync(new UpdateItemRequest
        {
            TableName = tableName,
            Key = Key(id),
            UpdateExpression = update,
            // Without this condition, UpdateItem would CREATE the note if it did not exist
            ConditionExpression = "attribute_exists(id)",
            ExpressionAttributeNames = new() { ["#t"] = "text", ["#d"] = "done", ["#due"] = "dueDate" },
            ExpressionAttributeValues = values,
            ReturnValues = ReturnValue.ALL_NEW, // answer with the note after the change
        });
        return Results.Json(ToNote(res.Attributes));
    }
    catch (ConditionalCheckFailedException)
    {
        return NotFound(id);
    }
});

app.MapDelete("/api/notes/{id}", async (string id, IAmazonDynamoDB db) =>
{
    if (!Guid.TryParse(id, out _)) return NotFound(id);
    try
    {
        await db.DeleteItemAsync(new DeleteItemRequest
        {
            TableName = tableName,
            Key = Key(id),
            ConditionExpression = "attribute_exists(id)", // fail (-> 404) instead of silently deleting nothing
        });
        return Results.NoContent(); // 204
    }
    catch (ConditionalCheckFailedException)
    {
        return NotFound(id);
    }
});

// Unknown route OR known route with a wrong method -> 404 JSON, like the other backends
app.MapFallback((HttpRequest req) => Error(404, "NOT_FOUND", $"Route {req.Path} not found"));

app.Run(); // listens on port 8080 (ASPNETCORE_HTTP_PORTS, set by the official image)

// ---- Helpers ----

static IResult Error(int status, string code, string message) =>
    Results.Json(new { error = new { code, message } }, statusCode: status);

static IResult NotFound(string id) => Error(404, "NOT_FOUND", $"Note {id} not found");

static IResult Invalid(string message) => Error(400, "VALIDATION_ERROR", message);

static Dictionary<string, AttributeValue> Key(string id) => new() { ["id"] = new AttributeValue { S = id } };

// DynamoDB item (each attribute has a type: S = string, BOOL = boolean...) <-> API JSON
static Note ToNote(Dictionary<string, AttributeValue> item) => new(
    item["id"].S,
    item["text"].S,
    item.TryGetValue("done", out var d) && d.BOOL == true,
    item.TryGetValue("dueDate", out var due) ? due.S : null,
    item["createdAt"].S);

static Dictionary<string, AttributeValue> ToItem(Note n)
{
    var item = new Dictionary<string, AttributeValue>
    {
        ["id"] = new() { S = n.Id },
        ["text"] = new() { S = n.Text },
        ["done"] = new() { BOOL = n.Done },
        ["createdAt"] = new() { S = n.CreatedAt },
    };
    if (n.DueDate != null) item["dueDate"] = new() { S = n.DueDate }; // no deadline = no attribute
    return item;
}

// We read the body ourselves (instead of a typed parameter, the usual Minimal API way) to return exactly
// the codes of API.md: INVALID_JSON vs VALIDATION_ERROR, "done must be a boolean"...
static async Task<(Input?, IResult?)> ReadInput(HttpRequest req)
{
    string raw = await new StreamReader(req.Body).ReadToEndAsync();
    JsonElement body;
    try
    {
        body = JsonDocument.Parse(raw).RootElement;
    }
    catch (JsonException)
    {
        return (null, Error(400, "INVALID_JSON", "Request body is not valid JSON"));
    }
    bool isObject = body.ValueKind == JsonValueKind.Object;

    string text = isObject && body.TryGetProperty("text", out var t) && t.ValueKind == JsonValueKind.String
        ? t.GetString()!.Trim() : "";
    if (text.Length == 0) return (null, Invalid("text is required"));
    if (text.EnumerateRunes().Count() > 200) return (null, Invalid("text must be at most 200 characters"));

    bool done = false;
    if (isObject && body.TryGetProperty("done", out var d))
    {
        if (d.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) return (null, Invalid("done must be a boolean"));
        done = d.GetBoolean();
    }

    string? dueDate = null;
    if (isObject && body.TryGetProperty("dueDate", out var due) && due.ValueKind != JsonValueKind.Null)
    {
        // TryParseExact checks the calendar too: "2026-02-30" -> false
        if (due.ValueKind != JsonValueKind.String || !Regex.IsMatch(due.GetString()!, "^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
            || !DateOnly.TryParseExact(due.GetString(), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _))
            return (null, Invalid("dueDate must be a date in YYYY-MM-DD format or null"));
        dueDate = due.GetString();
    }
    return (new Input(text, done, dueDate), null);
}

record Note(string Id, string Text, bool Done, string? DueDate, string CreatedAt); // JSON: id, text, done, dueDate, createdAt
record Input(string Text, bool Done, string? DueDate);
