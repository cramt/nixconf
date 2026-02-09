{...}: {
  environment.etc."1password/custom_allowed_browsers" = {
    text = ''
      zen
    '';
    mode = "0755";
  };
  programs._1password.enable = true;

  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = ["cramt"];
  };
}
