// Exercise Chargewire browser-flow HTTP contracts against loopback HTTP fixtures:
// a current server (31338) and one released before the rename (31339).
let
    Helpers = Hardcharger.TestHelpers(),
    Start = Helpers[StartLogin],
    Finish = Helpers[FinishLogin],
    SignIn = (port as number) =>
        let
            Path = "{""server"":""127.0.0.1"",""port"":" & Number.ToText(port, "0", "en-US") & ",""useEncryption"":false}",
            Flow = Start(Path, "test-state", []),
            Token = Finish(Flow[Context], Flow[CallbackUri], "test-state")
        in {
            Flow[LoginUri] = "https://idp.example.test/authorize?flow=test-flow",
            Flow[CallbackUri] = "http://127.0.0.1:" & Number.ToText(port, "0", "en-US") & "/?powerbi_signin_complete=1",
            Flow[Context][PollSecret] = "test-poll-secret",
            Token[access_token] = "test-access-token",
            Token[token_type] = "bearer"
        },
    Checks = SignIn(31338) & SignIn(31339)
in
    if List.AllTrue(Checks) then #table({"ChecksPassed"}, {{List.Count(Checks)}})
    else error "Chargewire OAuth flow failed"
