let
    Source = Hardcharger.Contents("localhost", 31337, false, false),
    Data = Source{[Name="memory"]}[Data]{[Name="main"]}[Data]{[Name="extended_types"]}[Data],
    Sorted = Table.Sort(Data, {{"id", Order.Ascending}}),
    First = Sorted{0}, Second = Sorted{1},
    Checks = {First[amount] = 12345.67, First[d] = #date(2024,6,15),
        First[ts] = #datetime(2024,6,15,14,30,45), First[flag] = true,
        First[note] = "O'Brien", Second[amount] = null, Second[d] = null, Second[note] = null}
in
    if List.AllTrue(Checks) then #table({"ChecksPassed"}, {{List.Count(Checks)}})
    else error "Decimal, date, timestamp, boolean or null round-trip failed"
