{ inputs, ... }:
{
  _module.args.myLib = import ../myLib { inherit inputs; };
}
