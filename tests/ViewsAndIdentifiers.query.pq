let
    Source = Hardcharger.Contents("localhost", 31337, false, false),
    Schema = Source{[Name="memory"]}[Data]{[Name="main"]}[Data],
    View = Schema{[Name="test_view",Kind="View"]}[Data],
    Quoted = Schema{[Name="quoted'table"]}[Data],
    Other = Source{[Name="other"]}[Data]{[Name="main"]}[Data]{[Name="test_data"]}[Data]
in
    if Table.RowCount(View) = 2 and Table.First(Quoted)[#"a""b"] = 42 and Other{0}[id] = 99
    then #table({"ChecksPassed"}, {{3}}) else error "View, quoted identifier or catalog navigation failed"
