# hdl-read.sh -- how an exported design is read into yosys. Sourced, never run.
#
# report-timing.sh maps a whole exported design to a cell library and times
# it; report-lut6.sh maps the same design to 6-input lookup tables and counts
# them. Both read the export the same way, from here, so that the two reports
# are about one design: a Verilog export (*.v) as is; a VHDL export (*.vhd)
# through the GHDL plugin for yosys, the way the VHDL flow's designs are
# simulated, the shared types package first and the top last.
#
# hdl_read_design <tool> <hdl-dir> <top>
#   sets READ, the yosys commands that read the design and pick the top, and
#   YOSYS, the command to run them with (the GHDL plugin loaded for VHDL).
#   Returns 1 when the directory holds no design, 2 when the export is VHDL
#   and the plugin is not installed; <tool> names the caller in the message.
hdl_read_design() {
  local tool="$1" dir="$2" top="$3"
  local verilog vhdl files f
  verilog=$(ls "$dir"/*.v 2>/dev/null | tr '\n' ' ')
  vhdl=$(ls "$dir"/*.vhd 2>/dev/null | tr '\n' ' ')
  if [[ -n "$verilog" ]]; then
    READ="read_verilog -sv -noassert $verilog; hierarchy -top $top"
    YOSYS=(yosys)
  elif [[ -n "$vhdl" ]]; then
    if ! yosys -q -m ghdl -p "" >/dev/null 2>&1; then
      echo "$tool: the GHDL plugin for yosys is not installed; VHDL not read" >&2
      return 2
    fi
    files="$(ls "$dir"/types.vhd 2>/dev/null || true)"
    for f in $vhdl; do
      case "$(basename "$f")" in
        types.vhd|"$top.vhd") continue ;;
      esac
      files="$files $f"
    done
    files="$files $dir/$top.vhd"
    READ="ghdl --std=08 -fsynopsys $files -e $top; hierarchy -top $top"
    YOSYS=(yosys -m ghdl)
  else
    echo "$tool: no Verilog or VHDL file in $dir" >&2
    return 1
  fi
}
