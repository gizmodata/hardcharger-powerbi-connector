// Validate endpoint and credential-scope helpers without network activity. The
// bundled native driver reads its options under the PreRenameCompat.pqm prefix.
let
    Helpers = Hardcharger.TestHelpers(),
    BuildUri = Helpers[BuildUri],
    OAuthBase = Helpers[OAuthBaseUrl],
    MapCredential = Helpers[MapCredentialProperties],
    Checks = {
        MapCredential([AuthenticationKind="Key", Key="test-token"])[#"adbc.warp.auth.access_token"] = "test-token",
        MapCredential([AuthenticationKind="OAuth", access_token="test-oauth"])[#"adbc.warp.auth.access_token"] = "test-oauth",
        MapCredential([AuthenticationKind="UsernamePassword", Username="test-user", Password="test-password"])[username] = "test-user",
        (try MapCredential([AuthenticationKind="Anonymous"]))[HasError],
        BuildUri(" DB.EXAMPLE.COM ", 31337, true) = "hardcharger://db.example.com:31337",
        BuildUri("localhost", 31337, false) = "hardcharger://localhost:31337?tls=false",
        (try BuildUri("host/path", 31337, true))[HasError],
        (try BuildUri("user@host", 31337, true))[HasError],
        (try BuildUri("host", 0, true))[HasError],
        (try BuildUri("host", 65536, true))[HasError],
        (try BuildUri("host", 1.5, true))[HasError],
        OAuthBase("{""server"":""localhost"",""port"":31337,""useEncryption"":false}") = "http://localhost:31337",
        OAuthBase("{""server"":""db.example.com"",""port"":443,""useEncryption"":true}") = "https://db.example.com:443"
    }
in
    if List.AllTrue(Checks) then #table({"ChecksPassed"}, {{List.Count(Checks)}})
    else error "Connection endpoint validation failed"
