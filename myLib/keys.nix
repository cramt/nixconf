# SSH public keys with user + root access across the fleet. Root's
# authorized_keys is derived from these (modules/bundles/nixos-users.nix), which
# is what lets `just deploy` activate over SSH on every host.
{
  alex = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwaPHqAJyayzLGfkEhwoDskUUyTr0aEovcc1Nzg2zXH alex.cramt@gmail.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWPMez5MadLlJ+NbdUJBDpd3MWCYI28gvA4Ddi5wD8I alex.cramt@gmail.com"
  ];
}
