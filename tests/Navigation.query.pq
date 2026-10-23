// Test navigation table: verify the connector can connect, authenticate,
// and enumerate tables from the Hardcharger server.
let
    Nav = Hardcharger.Contents("localhost", 31337, false, false)
in
    Nav
