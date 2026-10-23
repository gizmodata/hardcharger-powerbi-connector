// Value assertions augment the nine original GizmoSQL tests (which mostly
// only checked successful evaluation). Force each assertion despite M laziness.
let
    Source = Hardcharger.Contents("localhost", 31337, false, false),
    Schema = Source{[Name="memory"]}[Data]{[Name="main"]}[Data],
    Data = Schema{[Name="test_data"]}[Data],
    Sorted = Table.Sort(Data, {{"id", Order.Ascending}}),
    Checks = {
        Table.RowCount(Data) = 3,
        Sorted[id] = {1, 2, 3}, Sorted[name] = {"alice", "bob", "charlie"},
        Table.RowCount(Table.SelectRows(Data, each [id] = 1)) = 1,
        Table.ColumnNames(Table.SelectColumns(Data, {"id", "name"})) = {"id", "name"},
        Table.Sort(Data, {{"value", Order.Descending}}){0}[name] = "alice",
        Table.RowCount(Table.FirstN(Data, 2)) = 2,
        Number.Abs(List.Sum(Data[value]) - 7.27) < 0.000001
    }
in
    if List.AllTrue(Checks) then #table({"ChecksPassed"}, {{List.Count(Checks)}})
    else error "Original-suite value assertions failed"
