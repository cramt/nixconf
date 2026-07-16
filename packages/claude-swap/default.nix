{
  lib,
  python3Packages,
  fetchurl,
}:
python3Packages.buildPythonApplication rec {
  pname = "claude-swap";
  version = "0.21.0";
  pyproject = true;

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/source/c/claude-swap/claude_swap-${version}.tar.gz";
    hash = "sha256-usBvZgHVpdvOzJE+yFQ0McU6qoSzQbbkkTCPAn7gVa4=";
  };

  build-system = [python3Packages.hatchling];

  dependencies = with python3Packages; [
    keyring
    textual
    truststore
  ];

  # sdist ships no test suite; exercised at runtime by the claude-swap-auto timer
  doCheck = false;
  pythonImportsCheck = ["claude_swap"];

  meta = {
    description = "Switch between multiple Claude Code accounts with automatic rate-limit rotation";
    homepage = "https://github.com/realiti4/claude-swap";
    license = lib.licenses.mit;
    mainProgram = "cswap";
  };
}
