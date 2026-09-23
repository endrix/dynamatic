// RUN: rm -rf %t && mkdir %t
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n ndwire_data -o %t/ndwire_data.vhd -t ndwire -p bitwidth=32 'extra_signals={}'
// RUN: python3 %dynamatic_src_root/tools/unit-generators/vhdl/vhdl-unit-generator.py -n ndwire_ctrl -o %t/ndwire_ctrl.vhd -t ndwire -p bitwidth=0 'extra_signals={}'
// RUN: FileCheck %s -input-file %t/ndwire_data.vhd --check-prefix=DATA
// RUN: FileCheck %s -input-file %t/ndwire_ctrl.vhd --check-prefix=CTRL

// The non-deterministic wire. With data, the output's data port sat after
// outs_ready without a separator and left a ';' before the closing ')';
// without data, the handshake anded a std_logic with the boolean
// (state = RUNNING). Neither parsed. The data port now comes before
// outs_valid, the last port has no ';', and the state reaches the
// handshake as a std_logic.

// DATA: entity ndwire_data is
// DATA: outs       : out std_logic_vector(32 - 1 downto 0);
// DATA-NEXT: outs_valid : out std_logic;
// DATA-NEXT: outs_ready : in  std_logic
// DATA-NEXT: );
// DATA: elsif (ins_valid and outs_ready) = '1' then
// DATA: is_running <= '1' when state = RUNNING else '0';
// DATA: ins_ready <= outs_ready and is_running;
// DATA: outs_valid <= ins_valid and is_running;
// DATA: outs <= ins;

// CTRL: entity ndwire_ctrl is
// CTRL-NOT: outs  {{.*}}std_logic_vector
// CTRL: ins_ready <= outs_ready and is_running;
// CTRL: outs_valid <= ins_valid and is_running;
