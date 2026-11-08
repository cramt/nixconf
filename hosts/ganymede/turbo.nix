# Turbo on ganymede, only while the GPU is idle.
#
# The battery died and came out, and without it the firmware sets the
# turbo-disable bit (IA32_MISC_ENABLE bit 38), pinning the i5-8300H at 2.3 GHz.
# That isn't arbitrary: the battery used to absorb peaks the 90 W charger
# (19 V x 4.7 A) can't, and this Nitro shipped with a bigger one for its
# 1050 Ti. Measured on 2026-11-08, all 8 threads loaded, GPU idle:
#
#   no turbo (firmware)   14 W  2.3 GHz       57 C
#   turbo, 35 W cap       33 W  ~3.1 GHz      79 C
#   turbo, stock 45/56 W  ~50 W 3.6-3.8 GHz   96 C
#
# Everything gamed here so far ran next to that 14 W CPU, so that's the only
# CPU+GPU load proven to fit the charger. Turbo therefore only runs while the
# GPU has been idle for a while, capped at 35 W for temperature and to keep
# the window between a game starting and the gate noticing (~1 s) small.
# Builds get ~1.35x; a game gets exactly the box it had before.
#
# Fails safe: turbo starts off, and comes back off whenever the gate stops.
# Remove all of this if a battery goes back in or a >=135 W charger arrives;
# then turbo with stock limits is fine.
{
  config,
  pkgs,
  ...
}: let
  pstate = "/sys/devices/system/cpu/intel_pstate";
  rapl = "/sys/class/powercap/intel-rapl:0";
  capUw = toString 35000000;
  # GPU utilisation (%) at or above which turbo goes off. Idle on emrakul's
  # Home reads 0 %.
  busyPercent = 20;
  # Seconds of idle GPU before turbo comes back, so loading screens and menus
  # don't flap it.
  idleSeconds = 30;

  turbo-gate = pkgs.writeShellApplication {
    name = "turbo-gate";
    runtimeInputs = [pkgs.msr-tools config.hardware.nvidia.package.bin];
    text = ''
      # intel_pstate refuses no_turbo=0 while the firmware's bit is set, so
      # clear it per CPU (read-modify-write, the rest of the MSR is untouched).
      for cpu in /dev/cpu/[0-9]*; do
        n=''${cpu##*/}
        v=$(rdmsr -p "$n" -c 0x1a0)
        wrmsr -p "$n" 0x1a0 $(( v & ~(1 << 38) ))
      done

      echo ${capUw} > ${rapl}/constraint_0_power_limit_uw
      echo ${capUw} > ${rapl}/constraint_1_power_limit_uw

      state=off
      echo 1 > ${pstate}/no_turbo
      idle=0
      while read -r util; do
        if (( util >= ${toString busyPercent} )); then
          idle=0
          if [[ $state == on ]]; then
            echo 1 > ${pstate}/no_turbo
            state=off
            echo "GPU at $util %: turbo off"
          fi
        else
          idle=$(( idle + 1 ))
          if [[ $state == off ]] && (( idle >= ${toString idleSeconds} )); then
            echo 0 > ${pstate}/no_turbo
            state=on
            echo "GPU idle ${toString idleSeconds} s: turbo on"
          fi
        fi
      done < <(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits -lms 1000)

      # nvidia-smi went away, so we're blind to the GPU: fail, let systemd
      # turn turbo off and restart us.
      exit 1
    '';
  };
in {
  hardware.cpu.x86.msr.enable = true;

  systemd.services.turbo-gate = {
    description = "Turbo only while the GPU is idle (no battery, 90 W charger)";
    wantedBy = ["multi-user.target"];
    after = ["systemd-modules-load.service"];
    serviceConfig = {
      ExecStart = "${turbo-gate}/bin/turbo-gate";
      ExecStopPost = "${pkgs.runtimeShell} -c 'echo 1 > ${pstate}/no_turbo'";
      Restart = "always";
      RestartSec = 5;
    };
  };
}
