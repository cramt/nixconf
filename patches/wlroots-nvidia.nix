# stolen from https://aur.archlinux.org/packages/wlroots-nvidia
# and https://aur.archlinux.org/packages/wlroots-nvidia
final: prev: {
  wlroots = prev.wlroots.overrideAttrs
    (o: {
      patches = (o.patches or [ ]) ++ [ ./wlroots-nvidia.patch ];
    });
}
