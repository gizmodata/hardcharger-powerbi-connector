// Cross-table source identity must support a single folded JOIN query.
let
    LeftSource = Hardcharger.Contents("localhost", 31337, false, false),
    RightSource = Hardcharger.Contents("localhost", 31337, false, false),
    Emp = LeftSource{[Name="memory"]}[Data]{[Name="main"]}[Data]{[Name="emp"]}[Data],
    Dept = RightSource{[Name="memory"]}[Data]{[Name="main"]}[Data]{[Name="dept"]}[Data],
    Joined = Table.NestedJoin(Emp, {"dept_id"}, Dept, {"dept_id"}, "department", JoinKind.Inner),
    Expanded = Table.ExpandTableColumn(Joined, "department", {"dname"}),
    Sorted = Table.Sort(Expanded, {{"emp_id", Order.Ascending}})
in
    if Table.RowCount(Sorted) = 2 and Sorted[dname] = {"Accounting", "HR"} then Sorted
    else error "Cross-table join returned incorrect results"
