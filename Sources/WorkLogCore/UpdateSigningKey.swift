extension UpdateArchive {
    /// Public half of the release signing key (Ed25519, base64). Each release publishes
    /// `<zip>.sig`, made in CI from the UPDATE_SIGNING_KEY secret by `scripts/sign_update.swift`,
    /// which refuses to sign unless that secret matches this key.
    public static let signingKey = "NKcGaR3Hu5Mj7NMAE7QNn0MLt1fsCu4LD+GZp3l6RB8="
}
