# Signing setup

Both artifacts use the existing GizmoData EV code-signing certificate in Azure
Key Vault. The signer uses certificate GET and key SIGN permissions; no PFX or
private key is downloaded. Authentication uses azure/login with GitHub OIDC in
the production environment, and DefaultAzureCredential in the PQX signing tool.

The configured Azure application is `github-actions-codesigning-gizmo-edge-prd`.
The federated credential added for this repository is
`github-actions-codesigning-hardcharger-powerbi`, issuer
`https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange`,
subject:

```text
repo:gizmodata@181902052/hardcharger-powerbi-connector@1431158132:environment:production
```

GitHub now uses immutable subjects on new repositories. Query the setting before
recreating federation: `gh api repos/gizmodata/hardcharger-powerbi-connector/actions/oidc/customization/sub`.
The older GizmoSQL subject was name-based, so simply replacing its repo name
would fail authentication. Existing federated credentials remain untouched.

Environment secrets: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_KEY_VAULT_URI,
AZURE_CERT_NAME. Signing runs only for version tags after tests pass. Ordinary
pushes and pull requests do not receive signing credentials. MSI signatures use
RFC3161 SHA256 timestamps; PQX uses Power Query's OPC signature format and is
verified before packaging. The MSI checks the exact same signer thumbprint.

UpgradeCode `D7F4B2AA-139E-49D1-8AA4-C575F690CFB7` and component GUIDs are permanent
Hardcharger identities. Never reuse GizmoSQL installer GUIDs. Power BI's trusted
certificate policy is appended to rather than replaced; the release job checks
that an unrelated entry survives install, repair and removal.
