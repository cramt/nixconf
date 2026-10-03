# saturn as the LAN sees it, for the hosts that reach it (ganymede's
# Moonlight) and for its own Wake-on-LAN. Read off the box on 2026-10-03:
# enp6s0, an RTL8125B on r8169, is its only NIC.
#
# saturn.fritz.box also resolves to 192.168.178.22 (MAC 2c:f0:5d:a3:94:13),
# a different machine with its own SSH host key that calls itself saturn
# too, so this is the address rather than the name.
{
  name = "saturn";
  address = "192.168.178.23";
  macAddress = "2c:f0:5d:cf:62:1a";
}
