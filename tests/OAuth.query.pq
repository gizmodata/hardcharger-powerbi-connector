// Exercise Warp SQL browser-flow HTTP contracts using PQTest's HTTP mock.
let
    Helpers = Hardcharger.TestHelpers(),
    Start = Helpers[StartLogin],
    Finish = Helpers[FinishLogin],
    Path = "{""server"":""oauth.example.test"",""port"":443,""useEncryption"":true}",
    Flow = Start(Path, "test-state", []),
    Token = Finish(Flow[Context], Flow[CallbackUri], "test-state"),
    Checks = {
        Flow[LoginUri] = "https://idp.example.test/authorize?flow=test-flow",
        Flow[CallbackUri] = "https://oauth.example.test:443/?powerbi_signin_complete=1",
        Flow[Context][PollSecret] = "test-poll-secret",
        Token[access_token] = "test-access-token",
        Token[token_type] = "bearer"
    }
in
    if List.AllTrue(Checks) then #table({"ChecksPassed"}, {{List.Count(Checks)}})
    else error "Warp SQL OAuth flow failed"
