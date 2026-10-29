[Version = "1.0.1"]
section Hardcharger;

// Diagnostics module for trace logging (disable for release builds)
EnableTraceOutput = false;

Extension.LoadFunction = (fileName as text) =>
    let
        binary = Extension.Contents(fileName),
        asText = Text.FromBinary(binary)
    in
        Expression.Evaluate(asText, #shared);

Extension.LoadExpression = Extension.LoadFunction;

Diagnostics = Extension.LoadFunction("Diagnostics.pqm");
Diagnostics.LogValue = if EnableTraceOutput then Diagnostics[LogValue] else (prefix, value, optional delayed) => value;
Diagnostics.LogValue2 = if EnableTraceOutput then Diagnostics[LogValue2] else (prefix, value, result, optional delayed) => result;
Diagnostics.LogFailure = if EnableTraceOutput then Diagnostics[LogFailure] else (text, function) => function();

HardchargerGenerator = Extension.LoadExpression("SqlGenerator.pqm");

// Current Microsoft ADBC pattern: Adbc.Connection + SqlView.Generator.
// https://learn.microsoft.com/en-us/power-query/adbc
Adbc.Connection =
    try
        #shared[Adbc.Connection]
    otherwise
        (driver, databaseProperties, connectionProperties, options) =>
            error Error.Record("Expression.Error", "Adbc.Connection is not available in this Power BI Desktop version. Update to a recent build.");

SqlView.Generator =
    try
        #shared[SqlView.Generator]
    otherwise
        (uniqueIdentifier, sqlGenerator, getData) =>
            error Error.Record("Expression.Error", "SqlView.Generator is not available in this Power BI Desktop version. Update to a recent build.");

Driver = Extension.LoadExpression("HardchargerAdbcConfig.pqm");
PreRenameCompat = Extension.LoadExpression("PreRenameCompat.pqm");

// Full key of one of the native driver's own options, e.g. "auth.access_token".
DriverOption = (name as text) as text => PreRenameCompat[DriverOptionPrefix] & name;

// High-level Get Data dialog parameters. Credentials use the standard auth UI.
Hardcharger.ContentsType = type function (
    server as (type text meta [
        Documentation.FieldCaption = "Server",
        Documentation.FieldDescription = "Hostname or IP address of the Hardcharger server",
        Documentation.SampleValues = {"localhost"}
    ]),
    port as (type number meta [
        Documentation.FieldCaption = "Port",
        Documentation.FieldDescription = "Chargewire HTTP(S) port of the Hardcharger server",
        Documentation.SampleValues = {31337}
    ]),
    useEncryption as (type logical meta [
        Documentation.FieldCaption = "Use Encryption (TLS)",
        Documentation.FieldDescription = "Use HTTPS; disable for a plain HTTP development server",
        Documentation.AllowedValues = {true, false}
    ]),
    optional disableCertificateVerification as (type logical meta [
        Documentation.FieldCaption = "Disable Certificate Verification",
        Documentation.FieldDescription = "Skip TLS certificate verification (not recommended for production)",
        Documentation.AllowedValues = {true, false}
    ]),
    optional defaultCatalog as (type text meta [
        Documentation.FieldCaption = "Default Catalog",
        Documentation.FieldDescription = "Database/catalog to use (leave blank for the server default)",
        Documentation.SampleValues = {"my_database"}
    ])
) as table;

// TLS is a required data-source parameter so credential scopes and gateway
// TestConnection preserve the chosen transport. Credentials never enter the URI.
BuildUri = (server as text, port as number, useEncryption as nullable logical) as text =>
    let
        host = Text.Lower(Text.Trim(server)),
        validHost = host <> "" and not List.AnyTrue(List.Transform({"/", "?", "#", "@", " "}, each Text.Contains(host, _))),
        validPort = port >= 1 and port <= 65535 and Number.RoundDown(port) = port,
        authority = if validHost and validPort then host & ":" & Number.ToText(port, "0", "en-US")
            else error Error.Record("DataSource.Error", "Enter a hostname and a whole-number port between 1 and 65535.")
    in
        "hardcharger://" & authority & (if useEncryption = false then "?tls=false" else "");

// Standard Power Query credential storage; tokens use the driver's token option.
GetCredentialProperties = () as record => MapCredentialProperties(Extension.CurrentCredential());

MapCredentialProperties = (credential as record) as record =>
    let
        kind = credential[AuthenticationKind]?
    in
        if kind = "UsernamePassword" then
            [username = credential[Username], password = credential[Password]]
        else if kind = "Key" then
            Record.FromList({credential[Key]}, {DriverOption("auth.access_token")})
        else if kind = "OAuth" then
            Record.FromList({credential[access_token]}, {DriverOption("auth.access_token")})
        else error Error.Record("DataSource.Error", "Unsupported authentication kind.");

[DataSource.Kind = "Hardcharger", Publish = "Hardcharger.Publish"]
shared Hardcharger.Contents = Value.ReplaceType(HardchargerImpl, Hardcharger.ContentsType);

HardchargerImpl = (server as text, port as number, useEncryption as logical, optional disableCertificateVerification as logical, optional defaultCatalog as text) as table =>
    let
        context = HardchargerContext(server, port, useEncryption, disableCertificateVerification, defaultCatalog),
        result = GetDatabases(context)
    in
        Diagnostics.LogValue2(
            "Hardcharger/Connection",
            [ Server = server, Port = port, DefaultCatalog = defaultCatalog ],
            result
        );

HardchargerContext = (server as text, port as number, useEncryption as nullable logical, disableCertificateVerification as nullable logical, defaultCatalog as nullable text) =>
    let
        Uri = BuildUri(server, port, useEncryption),
        TlsProperties =
            if disableCertificateVerification = true then
                Record.FromList({"true"}, {DriverOption("tls.skip_verify")})
            else
                [],
        DatabaseProperties = [ uri = Uri ] & TlsProperties & GetCredentialProperties(),
        Catalog = if defaultCatalog <> null and defaultCatalog <> "" then defaultCatalog else null,
        ConnectionProperties = if Catalog <> null then [ adbc.connection.catalog = Catalog ] else [],
        Connection = Adbc.Connection(Driver, DatabaseProperties, ConnectionProperties, [ ConnectionPoolType = 2 ]),
        ExecuteQuery = (sql as text, optional opts as nullable record) =>
            let
                connectionProps =
                    if opts[Catalog]? <> null then [ adbc.connection.catalog = opts[Catalog] ] else ConnectionProperties,
                queryOptions = [
                    ConnectionProperties = connectionProps,
                    IsMetadata = opts[IsMetadata]?
                ]
            in
                Connection[ExecuteQuery](sql, null, queryOptions),
        GetData = (query as text, resultType as type, foldContext) => CreateDataTable(query, resultType, foldContext, ExecuteQuery),
        // Data-source identity for the SqlView engine: two tables can fold into
        // a single native query (e.g. a DirectQuery join) only if their
        // identifiers compare equal. Keyed on the connection target only —
        // never include credentials here.
        UniqueIdentifier = [ Module = ModuleIdentifier, Signature = [ Uri = Uri, Catalog = Catalog, SkipVerify = disableCertificateVerification = true ] ],
        SqlGenerator = SqlView.Generator(UniqueIdentifier, HardchargerGenerator, GetData)
    in
        [
            ExecuteQuery = ExecuteQuery,
            SqlGenerator = SqlGenerator,
            DefaultCatalog = Catalog
        ];

ModuleIdentifier = () => ...;

CreateDataTable = (query as text, resultType as type, foldContext, executeQuery) =>
    Table.View(null, [
        GetType = () => resultType,
        GetRows = () =>
            let
                data = executeQuery(query, foldContext[[Catalog], [IsMetadata]]?),
                oldNames = Table.ColumnNames(data),
                newNames = Table.ColumnNames(#table(resultType, {})),
                renamed = Table.RenameColumns(data, List.Zip({oldNames, newNames}))
            in
                renamed
    ]);

EscapeIdentifier = (identifier as text) as text => """" & Text.Replace(identifier, """", """""") & """";

EscapeStringLiteral = (value as text) as text => "'" & Text.Replace(value, "'", "''") & "'";

MakeNavTableType = (isLeaf) =>
    let
        dataType = type table meta [
            NavigationTable.ItemKind = "Table",
            Preview.Delay = "Table",
            NavigationTable.RowConfigurationColumn = "Kind"
        ],
        tableType = type table [
            Name = text,
            Description = nullable text,
            Data = dataType,
            Kind = text
        ],
        withKeys = Type.ReplaceTableKeys(tableType, {[Columns = {"Name", "Kind"}, Primary = true]}) meta [
            NavigationTable.NameColumn = "Name",
            NavigationTable.DataColumn = "Data",
            NavigationTable.KindColumn = "Kind"
        ]
    in
        withKeys;

GetDatabases = (context) =>
    let
        isLeaf = false,
        kind = "Database",
        catalogFilter =
            if context[DefaultCatalog] <> null then
                " WHERE catalog_name = " & EscapeStringLiteral(context[DefaultCatalog])
            else
                "",
        command = "SELECT DISTINCT catalog_name as name FROM information_schema.schemata" & catalogFilter,
        tables = context[ExecuteQuery](command, [IsMetadata = true]),
        getSchemas = (name) => GetSchemas(context, name),
        withData = Table.AddColumn(tables, "Data", each getSchemas([name]), type table),
        withDescription = Table.AddColumn(withData, "Description", each null, type nullable text),
        withKind = Table.AddColumn(withDescription, "Kind", each kind meta [NavigationTable.IsLeaf = isLeaf], type text),
        selected = Table.SelectColumns(withKind, {"name", "Description", "Data", "Kind"}),
        renamed = Table.RenameColumns(selected, {{"name", "Name"}}),
        withFolding = Table.View(null, [
            GetType = () => MakeNavTableType(isLeaf),
            GetRows = () => renamed,
            OnSelectRows = (selector) => FoldNavigationStep(selector, getSchemas, kind),
            ThrowFoldingFailures = false
        ])
    in
        withFolding;

GetSchemas = (context, catalog) =>
    let
        isLeaf = false,
        kind = "Schema",
        command = "SELECT schema_name as name FROM information_schema.schemata WHERE catalog_name = " & EscapeStringLiteral(catalog)
            & " AND schema_name NOT IN ('information_schema', 'pg_catalog')",
        schemas = context[ExecuteQuery](command, [IsMetadata = true]),
        getTables = (name) => GetTables(context, catalog, name),
        withData = Table.AddColumn(schemas, "Data", each getTables([name]), type table),
        withDescription = Table.AddColumn(withData, "Description", each null, type nullable text),
        withKind = Table.AddColumn(withDescription, "Kind", each kind meta [NavigationTable.IsLeaf = isLeaf], type text),
        selected = Table.SelectColumns(withKind, {"name", "Description", "Data", "Kind"}),
        renamed = Table.RenameColumns(selected, {{"name", "Name"}}),
        withFolding = Table.View(null, [
            GetType = () => MakeNavTableType(isLeaf),
            GetRows = () => renamed,
            OnSelectRows = (selector) => FoldNavigationStep(selector, getTables, kind),
            ThrowFoldingFailures = false
        ])
    in
        withFolding;

GetTables = (context, catalog, schema) =>
    let
        isLeaf = true,
        kind = {"Table", "View"},
        command = "SELECT table_name as name, table_type FROM information_schema.tables WHERE table_catalog = " & EscapeStringLiteral(catalog)
            & " AND table_schema = " & EscapeStringLiteral(schema),
        tables = context[ExecuteQuery](command, [IsMetadata = true]),
        getTable = (name) => GetTable(context, catalog, schema, name),
        withData = Table.AddColumn(tables, "Data", each getTable([name]), type table),
        withDescription = Table.AddColumn(withData, "Description", each null, type nullable text),
        withKind = Table.AddColumn(withDescription, "Kind",
            each (if [table_type] = "VIEW" then "View" else "Table") meta [NavigationTable.IsLeaf = isLeaf], type text),
        selected = Table.SelectColumns(withKind, {"name", "Description", "Data", "Kind"}),
        renamed = Table.RenameColumns(selected, {{"name", "Name"}}),
        withFolding = Table.View(null, [
            GetType = () => MakeNavTableType(isLeaf),
            GetRows = () => renamed,
            OnSelectRows = (selector) => FoldNavigationStep(selector, getTable, kind, true),
            ThrowFoldingFailures = false
        ])
    in
        withFolding;

GetTable = (context, catalog, schema, table) =>
    let
        tableType = GetTableType(context[ExecuteQuery], catalog, schema, table),
        tableReference = [Kind = "FromTable", Table = [Catalog = catalog, Schema = schema, Name = table]],
        withSqlView = context[SqlGenerator](tableReference, tableType, [])
    in
        withSqlView;

FoldNavigationStep = (selector, loader, kind, optional immediate) =>
    let
        reduceAnd = (ast) => if ast[Kind] = "Binary" and ast[Operator] = "And" then List.Combine({@reduceAnd(ast[Left]), @reduceAnd(ast[Right])}) else {ast},
        matchFieldAccess = (ast) => if ast[Kind] = "FieldAccess" and ast[Expression] = RowExpression.Row then ast[MemberName] else ...,
        matchConstant = (ast) => if ast[Kind] = "Constant" then ast[Value] else ...,
        matchIndex = (ast) => if ast[Kind] = "Binary" and ast[Operator] = "Equals"
            then
                if ast[Left][Kind] = "FieldAccess"
                    then Record.AddField([], matchFieldAccess(ast[Left]), matchConstant(ast[Right]))
                    else Record.AddField([], matchFieldAccess(ast[Right]), matchConstant(ast[Left]))
            else ...,
        predicate1 = Record.Combine(List.Transform(reduceAnd(RowExpression.From(selector)), matchIndex)),
        isKindList = kind is list,
        kindMatch = if isKindList then List.Contains(kind, predicate1[Kind]?) else predicate1[Kind]? = kind,
        predicate2 = if kindMatch then Record.RemoveFields(predicate1, {"Kind"}) else predicate1,
        pickKind = if isKindList then
                       if List.Contains(kind, predicate1[Kind]?) then predicate1[Kind]? else ...
                   else kind,
        name = if Record.FieldCount(predicate2) = 1 and predicate2[Name]? <> null then predicate2[Name] else ...,

        dataResult = loader(name),
        emptyResult = #table(type table [Name = text, Description = nullable text, Data = table, Kind = text], {}),
        // If the navigation predicate cannot fold, Table.View falls back to
        // normal metadata enumeration; preserve the original ADBC error.
        resultOrEmpty = dataResult
    in
        if resultOrEmpty = null
            then emptyResult
            else Table.FromRecords({[Name = name, Description = "", Data = resultOrEmpty, Kind = pickKind]});

GetTableType = (exec, catalog, schema, table) =>
    let
        qualifiedName = EscapeIdentifier(catalog) & "." & EscapeIdentifier(schema) & "." & EscapeIdentifier(table),
        command = "SELECT "
            & "name AS column_name, "
            & "type AS data_type, "
            & "CASE WHEN ""notnull"" THEN 'NO' ELSE 'YES' END AS is_nullable, "
            & "TRY_CAST(regexp_extract(type, '^DECIMAL\((\d+),\s*\d+\)$', 1) AS INTEGER) AS numeric_precision, "
            & "TRY_CAST(regexp_extract(type, '^DECIMAL\(\d+,\s*(\d+)\)$', 1) AS INTEGER) AS numeric_scale, "
            & "NULL::INTEGER AS character_maximum_length "
            & "FROM pragma_table_info(" & EscapeStringLiteral(qualifiedName) & ") "
            & "ORDER BY cid",
        columnInfo = Table.Buffer(exec(command, [IsMetadata = true])),
        columnNames = columnInfo[column_name],
        columnTypes = List.Transform(Table.ToRecords(columnInfo), each [
            Type = GetColumnType([data_type], [is_nullable], [numeric_precision], [numeric_scale], [character_maximum_length]),
            Optional = false
        ]),
        rowType = Type.ForRecord(Record.FromList(columnTypes, columnNames), false),
        primaryKeys = GetPrimaryKeys(exec, catalog, schema, table),
        tableType = type table rowType,
        tableTypeWithPrimaryKey = Type.ReplaceTableKeys(tableType, primaryKeys)
    in
        tableTypeWithPrimaryKey;

// Parse the base type from potentially parameterized data_type values like "DECIMAL(18,2)" or "INTEGER[]"
ParseBaseType = (dataType as text) as text =>
    let
        parenPos = Text.PositionOf(dataType, "("),
        bracketPos = Text.PositionOf(dataType, "["),
        endPos = List.Min(List.RemoveNulls({
            if parenPos >= 0 then parenPos else null,
            if bracketPos >= 0 then bracketPos else null,
            Text.Length(dataType)
        })),
        baseType = Text.Upper(Text.Trim(Text.Start(dataType, endPos)))
    in
        baseType;

AdjustType = (nullable as logical, mtype as type, nativeTypeName as text) =>
    let
        withNullable = if nullable then type nullable mtype else mtype,
        withFacets = Type.ReplaceFacets(withNullable, [NativeTypeName = nativeTypeName])
    in
        withFacets;

ColumnTypeMap = [
    BOOLEAN = type logical,
    TINYINT = Int32.Type,
    SMALLINT = Int32.Type,
    INTEGER = Int32.Type,
    BIGINT = Int64.Type,
    HUGEINT = Decimal.Type,
    UTINYINT = Int32.Type,
    USMALLINT = Int32.Type,
    UINTEGER = Int64.Type,
    UBIGINT = Decimal.Type,
    FLOAT = Double.Type,
    DOUBLE = Double.Type,
    DECIMAL = Decimal.Type,
    VARCHAR = type text,
    BLOB = type binary,
    DATE = type date,
    TIME = type time,
    TIMESTAMP = type datetime,
    #"TIMESTAMP WITH TIME ZONE" = type datetimezone,
    TIMESTAMPTZ = type datetimezone,
    TIMESTAMP_S = type datetime,
    TIMESTAMP_MS = type datetime,
    TIMESTAMP_NS = type datetime,
    INTERVAL = type text,
    UUID = type text,
    JSON = type text,
    BIT = type text,
    ENUM = type text,
    LIST = type text,
    STRUCT = type text,
    MAP = type text,
    UNION = type text,
    ARRAY = type text
];

GetColumnType = (dataType as text, isNullableText as text, numericPrecision, numericScale, charMaxLength) =>
    let
        baseType = ParseBaseType(dataType),
        isNullable = isNullableText = "YES",
        mtype = Record.FieldOrDefault(ColumnTypeMap, baseType, type text),
        adjustedType = if baseType = "DECIMAL" and numericPrecision <> null then
            Type.ReplaceFacets(
                AdjustType(isNullable, Decimal.Type, "DECIMAL"),
                [NativeTypeName = "DECIMAL", NumericPrecisionBase = 10, NumericPrecision = numericPrecision, NumericScale = numericScale ?? 0])
        else if baseType = "VARCHAR" and charMaxLength <> null then
            Type.ReplaceFacets(
                AdjustType(isNullable, type text, "VARCHAR"),
                [NativeTypeName = "VARCHAR", MaxLength = charMaxLength, IsVariableLength = true])
        else
            AdjustType(isNullable, mtype, baseType)
    in
        adjustedType;

GetPrimaryKeys = (exec, catalog, schema, table) =>
    let
        command = "SELECT column_name FROM information_schema.table_constraints tc "
            & "JOIN information_schema.key_column_usage kcu "
            & "ON tc.constraint_name = kcu.constraint_name "
            & "AND tc.table_catalog = kcu.table_catalog "
            & "AND tc.table_schema = kcu.table_schema "
            & "AND tc.table_name = kcu.table_name "
            & "WHERE tc.constraint_type = 'PRIMARY KEY' "
            & "AND tc.table_catalog = " & EscapeStringLiteral(catalog) & " "
            & "AND tc.table_schema = " & EscapeStringLiteral(schema) & " "
            & "AND tc.table_name = " & EscapeStringLiteral(table) & " "
            & "ORDER BY kcu.ordinal_position",
        result = try exec(command, [IsMetadata = true]) otherwise #table({"column_name"}, {}),
        primaryKeyColumns = result[column_name]
    in
        if List.IsEmpty(primaryKeyColumns) then {} else {[Columns = primaryKeyColumns, Primary = true]};

// Chargewire browser sign-in (v1 §4.3). The browser returns to a same-origin
// completion URL after the server processes the IdP callback. Poll secrets travel
// only in POST bodies, and the resulting server token goes to the native driver.

// Base path of the protocol on the server at base: "/chargewire", or the earlier
// root on a Hardcharger server released before the rename, whose discovery at
// /chargewire answers 404.
ProtocolRoot = (base as text) as text =>
    let
        DiscoveredProtocol = (root as text) as nullable text =>
            let
                response = Web.Contents(base & root, [
                    Headers = [Accept = "application/json"],
                    ManualStatusHandling = {404},
                    IsRetry = true
                ]),
                status = Value.Metadata(response)[Response.Status]
            in
                if status = 404 then null else (try Json.Document(response)[protocol]? otherwise null),
        current = DiscoveredProtocol("/chargewire")
    in
        if current = "chargewire" then "/chargewire"
        else if DiscoveredProtocol(PreRenameCompat[Root]) = PreRenameCompat[Protocol] then PreRenameCompat[Root]
        else error Error.Record("DataSource.Error", "The server at " & base & " is not a Hardcharger server.");

OAuthBaseUrl = (dataSourcePath as text) as text =>
    let p = Json.Document(dataSourcePath)
    in (if p[useEncryption] = false then "http://" else "https://")
        & p[server] & ":" & Number.ToText(p[port], "0", "en-US");

OAuthPost = (url as text, body as record) =>
    Json.Document(Web.Contents(url, [
        Content = Json.FromValue(body),
        Headers = [#"Content-Type" = "application/json"],
        IsRetry = true
    ]));

StartLogin = (resourceUrl, state, display) =>
    let
        base = OAuthBaseUrl(resourceUrl),
        done = base & "/?powerbi_signin_complete=1",
        root = ProtocolRoot(base),
        flow = OAuthPost(base & root & "/v1/auth/oauth/flows", [return_to = "/?powerbi_signin_complete=1"])
    in [
        LoginUri = flow[authorize_url], CallbackUri = done,
        WindowHeight = 800, WindowWidth = 1024,
        Context = [BaseUrl = base, Root = root, FlowId = flow[flow_id], PollSecret = flow[poll_secret],
            Interval = List.Max({1, flow[poll_interval_s]? ?? 1})]
    ];

FinishLogin = (context, callbackUri, state) => PollForToken(context, 300);

PollForToken = (context as record, secondsLeft as number) =>
    let
        response = OAuthPost(context[BaseUrl] & context[Root] & "/v1/auth/oauth/flows/" & Uri.EscapeDataString(context[FlowId]),
            [poll_secret = context[PollSecret]]),
        status = response[state]?
    in
        if status = "complete" then
            [access_token = response[access_token], token_type = "bearer", expires_in = response[expires_in]?]
        else if status = "failed" then
            error Error.Record("DataSource.Error", "Browser sign-in failed. Please sign in again.")
        else if secondsLeft <= 0 then
            error Error.Record("DataSource.Error", "Browser sign-in timed out. Please sign in again.")
        else Function.InvokeAfter(() => @PollForToken(context, secondsLeft - context[Interval]), #duration(0, 0, 0, context[Interval]));

// Data source definition
Hardcharger = [
    TestConnection = (dataSourcePath) =>
        let
            json = Json.Document(dataSourcePath)
        in
            { "Hardcharger.Contents", json[server], json[port], json[useEncryption], json[disableCertificateVerification]?, json[defaultCatalog]? },
    Authentication = [
        UsernamePassword = [],
        Key = [Label = "Bearer token", KeyLabel = "Token"],
        OAuth = [
            StartLogin = StartLogin,
            FinishLogin = FinishLogin,
            Label = "OAuth (Browser)"
        ]
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

// Publish to Power BI "Get Data" dialog
Hardcharger.Publish = [
    Beta = false,
    Category = "Database",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://github.com/gizmodata/hardcharger-powerbi-connector",
    SupportsDirectQuery = true,
    SourceImage = Hardcharger.Icons,
    SourceTypeImage = Hardcharger.Icons
];

Hardcharger.Icons = [
    Icon16 = { Extension.Contents("Hardcharger16.png"), Extension.Contents("Hardcharger20.png"), Extension.Contents("Hardcharger24.png"), Extension.Contents("Hardcharger32.png") },
    Icon32 = { Extension.Contents("Hardcharger32.png"), Extension.Contents("Hardcharger40.png"), Extension.Contents("Hardcharger48.png"), Extension.Contents("Hardcharger64.png") }
];
