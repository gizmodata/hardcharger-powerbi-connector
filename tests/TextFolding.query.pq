let
    Source = Hardcharger.Contents("localhost", 31337, false, false),
    Data = Source{[Name="memory"]}[Data]{[Name="main"]}[Data]{[Name="test_data"]}[Data],
    Selected = Table.SelectRows(Data, each Text.StartsWith([name], "a") or Text.Contains([name], "ar")),
    Sorted = Table.Sort(Selected, {{"id", Order.Ascending}})
in
    if Sorted[name] = {"alice", "charlie"} then Sorted else error "Text predicate folding failed"
