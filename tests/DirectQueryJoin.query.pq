// A relational query only: correctness assertions live in Join.query.pq.
// Strict DirectQuery must fold this entire table expression into server SQL.
let
    EmpSource = Hardcharger.Contents("localhost", 31337, false, false),
    DeptSource = Hardcharger.Contents("localhost", 31337, false, false),
    Emp = EmpSource{[Name="memory"]}[Data]{[Name="main"]}[Data]{[Name="emp"]}[Data],
    Dept = DeptSource{[Name="memory"]}[Data]{[Name="main"]}[Data]{[Name="dept"]}[Data],
    Joined = Table.NestedJoin(Emp, {"dept_id"}, Dept, {"dept_id"}, "department", JoinKind.Inner),
    Expanded = Table.ExpandTableColumn(Joined, "department", {"dname"})
in
    Table.Sort(Expanded, {{"emp_id", Order.Ascending}})
