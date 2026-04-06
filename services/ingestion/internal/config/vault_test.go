package config

import "testing"

func TestLoadVaultSecretsNotFound(t *testing.T) {
    // dev mode — يجب أن يُرجع nil مع warning
    t.Setenv("APP_ENV", "dev")
    err := LoadVaultSecrets("/nonexistent/path/vault/secrets/db")
    if err != nil {
        t.Errorf("expected nil in dev, got: %v", err)
    }
}

func TestLoadVaultSecretsProductionError(t *testing.T) {
    // production mode — يجب أن يُرجع error
    t.Setenv("APP_ENV", "production")
    err := LoadVaultSecrets("/nonexistent/path/vault/secrets/db")
    if err == nil {
        t.Error("expected error in production, got nil")
    }
}
